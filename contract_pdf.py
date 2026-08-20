"""Python port of lib/services/contract_pdf_generator.dart (Flutter) for the
web admin app. Reproduces the same "Accord de compensation" PDF structure
(ménage / lignage / communautaire variants), including photo embedding on
page 1 and the consolidated ANNEXE 1 (all asset categories on one page,
overflow allowed to next page).
"""
import io
import base64
import os
from datetime import datetime

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    Image as RLImage,
    PageBreak,
    KeepTogether,
    Frame,
    PageTemplate,
    BaseDocTemplate,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader

from compensation import compute_for_owner, CompensationSummary

_FONT_DIR = os.path.join(os.path.dirname(__file__), "fonts")
_IMG_DIR = os.path.join(os.path.dirname(__file__), "static", "img")
_FONTS_REGISTERED = False

# NOTE: Per client request, contracts no longer use branded colors (maroon /
# dark green) anywhere except the two header logo images and the applicant's
# photos. MAROON/DARK_GREEN are kept only as unused legacy aliases; all
# styling below uses black / grey (achromatic) instead.
MAROON = colors.black
DARK_GREEN = colors.black
GREY_LIGHT = colors.HexColor("#EDEDED")
GREY_DARKER = colors.HexColor("#D9D9D9")
GREY_BORDER = colors.HexColor("#BBBBBB")

# Full usable page width (A4 width minus left/right margins used in
# generate_contract_pdf: 210mm - 2*32pt). Tables use this so ANNEXE 1 and
# other tables stretch left-aligned up to the page margins.
FULL_WIDTH_MM = 186.0

OKAPI_LOGO_PATH = os.path.join(_IMG_DIR, "okapi_header_logo.png")
WCAG_LOGO_PATH = os.path.join(_IMG_DIR, "wcag_header_logo.png")
# Hardcoded aspect ratios (width/height) of the trimmed logo assets, avoiding
# a runtime image-library dependency just to measure them.
OKAPI_LOGO_ASPECT = 644.0 / 324.0
WCAG_LOGO_ASPECT = 1023.0 / 784.0


def _scale_widths(widths_mm, total_mm=FULL_WIDTH_MM):
    """Scales a list of column widths (in mm) proportionally so they sum to
    `total_mm`, used to stretch ANNEXE 1 tables to the full page width."""
    s = sum(widths_mm)
    if s <= 0:
        return widths_mm
    factor = total_mm / s
    return [w * factor for w in widths_mm]


def _ensure_fonts():
    global _FONTS_REGISTERED
    if _FONTS_REGISTERED:
        return
    pdfmetrics.registerFont(TTFont("DejaVu", os.path.join(_FONT_DIR, "DejaVuSans.ttf")))
    pdfmetrics.registerFont(
        TTFont("DejaVu-Bold", os.path.join(_FONT_DIR, "DejaVuSans-Bold.ttf"))
    )
    pdfmetrics.registerFont(
        TTFont("DejaVu-Italic", os.path.join(_FONT_DIR, "DejaVuSans-Oblique.ttf"))
    )
    _FONTS_REGISTERED = True


def fmt_number(v):
    v = v or 0
    neg = v < 0
    i = int(round(abs(v)))
    s = str(i)
    out = []
    n = len(s)
    for idx, ch in enumerate(s):
        if idx > 0 and (n - idx) % 3 == 0:
            out.append(" ")
        out.append(ch)
    return ("-" if neg else "") + "".join(out)


def fmt_gnf(v):
    return f"{fmt_number(v)} GNF"


def fmt_date(iso_str):
    if not iso_str:
        return ""
    try:
        d = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return d.strftime("%d/%m/%Y")
    except Exception:
        return ""


TITLE_SUFFIX = {
    "proprietaire": "LE MÉNAGE AFFECTÉ",
    "lignage": "LE LIGNAGE AFFECTÉ",
    "communautaire": "LA COMMUNAUTÉ AFFECTÉE",
}
PARTY_LABEL = {
    "proprietaire": "Ménage affecté",
    "lignage": "Lignage affecté",
    "communautaire": "Communauté affectée",
}
CHEF_LABEL = {
    "proprietaire": "Chef du Ménage affecté",
    "lignage": "Chef du Lignage affecté",
    "communautaire": "représentant de la Communauté Affectée",
}
FOOTER_LABEL = {
    "proprietaire": "Accord Ménage",
    "lignage": "Accord Lignage",
    "communautaire": "Accord collectif",
}
IDENT_SECTION_TITLE = {
    "proprietaire": "1. Identification du Représentant du ménage",
    "lignage": "1. Identification du Représentant du lignage",
    "communautaire": "1. Identification du Représentant",
}
TEMOINS_LABEL = {
    "proprietaire": "Témoins (Autres membres adultes du Ménage affecté présents, ou personnes de confiance choisies par le Ménage affecté)",
    "lignage": "Témoins (Autres membres adultes du Lignage affecté présents, représentants des autorités coutumières ou locales, personnes de confiance)",
    "communautaire": "Témoins (Autres membres adultes de la Communauté Affectée présents, représentants des autorités coutumières ou locales, personnes de confiance)",
}


def has_identity_document(type_de_piece):
    return bool(type_de_piece) and type_de_piece != "Pas de document"


def build_contract_data(menage=None, champ=None, individu=None, contract_type="proprietaire"):
    """Builds a normalized dict of contract fields, mirroring ContractData.
    Either pass `menage` (Propriétaire contract, chef de ménage) or pass
    `champ` + `individu` (Lignage/Communautaire contract, owner of the champ).
    """
    if menage is not None:
        individus = menage.get("individus", [])
        chef = None
        for ind in individus:
            if ind.get("relationCdm") == "Chef de menage":
                chef = ind
                break
        if chef is None and individus:
            chef = individus[0]
        chef = chef or {}
        return {
            "type": "proprietaire",
            "numeroLot": menage.get("codeMenage", ""),
            "region": menage.get("region", ""),
            "prefecture": menage.get("prefecture", ""),
            "sousPrefecture": menage.get("sousPrefecture", ""),
            "district": menage.get("district", ""),
            "village": menage.get("village", ""),
            "codeMenage": menage.get("codeMenage", ""),
            "codeIndividu": chef.get("id", menage.get("codeMenage", "")),
            "nomPrenom": chef.get("nomPrenom", ""),
            "sexe": chef.get("sexe", ""),
            "dateNaissance": fmt_date(chef.get("dateNaissance")),
            "typeDePiece": chef.get("typeDePiece", ""),
            "numeroPiece": chef.get("numeroPiece", ""),
            "dateEtablissementPiece": fmt_date(chef.get("dateEtablissementPiece")),
            "telephone": chef.get("telephone", ""),
            "dateEnquete": menage.get("dateEnquete", ""),
            "photoProfilBase64": chef.get("photoProfilBase64"),
            "photoCniRectoBase64": chef.get("photoCniRectoBase64"),
            "photoCniVersoBase64": chef.get("photoCniVersoBase64"),
        }
    else:
        proprietaire = individu or {}
        return {
            "type": contract_type,
            "numeroLot": champ.get("numBatch") or champ.get("codeMenage", ""),
            "region": champ.get("region", ""),
            "prefecture": champ.get("prefecture", ""),
            "sousPrefecture": champ.get("sousPrefecture", ""),
            "district": champ.get("district", ""),
            "village": champ.get("village", ""),
            "codeMenage": champ.get("codeMenage", ""),
            "codeIndividu": proprietaire.get("id", ""),
            "nomPrenom": proprietaire.get("nomPrenom", ""),
            "sexe": proprietaire.get("sexe", ""),
            "dateNaissance": fmt_date(proprietaire.get("dateNaissance")),
            "typeDePiece": proprietaire.get("typeDePiece", ""),
            "numeroPiece": proprietaire.get("numeroPiece", ""),
            "dateEtablissementPiece": fmt_date(proprietaire.get("dateEtablissementPiece")),
            "telephone": proprietaire.get("telephone", ""),
            "dateEnquete": champ.get("dateEnquete", ""),
            "photoProfilBase64": proprietaire.get("photoProfilBase64"),
            "photoCniRectoBase64": proprietaire.get("photoCniRectoBase64"),
            "photoCniVersoBase64": proprietaire.get("photoCniVersoBase64"),
        }


def _decode_photo(b64data, max_w=90, max_h=110):
    if not b64data:
        return None
    try:
        raw = base64.b64decode(b64data)
        img = RLImage(io.BytesIO(raw), width=max_w, height=max_h)
        return img
    except Exception:
        return None


def _placeholder_box(label, w, h):
    t = Table([[label]], colWidths=[w], rowHeights=[h])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), GREY_LIGHT),
                ("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("FONTNAME", (0, 0), (-1, -1), "DejaVu"),
                ("TEXTCOLOR", (0, 0), (-1, -1), colors.grey),
            ]
        )
    )
    return t


def _styles():
    _ensure_fonts()
    return {
        "title": ParagraphStyle(
            "title", fontName="DejaVu-Bold", fontSize=13, textColor=MAROON,
            alignment=TA_CENTER, leading=16,
        ),
        "section": ParagraphStyle(
            "section", fontName="DejaVu-Bold", fontSize=11, textColor=DARK_GREEN,
            spaceBefore=10, spaceAfter=6,
        ),
        "para": ParagraphStyle(
            "para", fontName="DejaVu", fontSize=9.5, alignment=TA_JUSTIFY,
            spaceAfter=6, leading=12,
        ),
        "article": ParagraphStyle(
            "article", fontName="DejaVu-Bold", fontSize=10.5, spaceBefore=8, spaceAfter=4,
        ),
        "small": ParagraphStyle("small", fontName="DejaVu", fontSize=9),
        "small_bold": ParagraphStyle("small_bold", fontName="DejaVu-Bold", fontSize=9),
        "field_label": ParagraphStyle(
            "field_label", fontName="DejaVu-Bold", fontSize=7.8, leading=9.5,
        ),
        "field_value": ParagraphStyle(
            "field_value", fontName="DejaVu", fontSize=9, leading=10.5,
        ),
        "caption": ParagraphStyle(
            "caption", fontName="DejaVu-Bold", fontSize=7.5, alignment=TA_CENTER,
        ),
        "annex_sub": ParagraphStyle(
            "annex_sub", fontName="DejaVu-Bold", fontSize=9.5, textColor=MAROON, spaceAfter=4,
        ),
        "empty_note": ParagraphStyle(
            "empty_note", fontName="DejaVu", fontSize=8.5, textColor=colors.grey,
        ),
        "footer": ParagraphStyle("footer", fontName="DejaVu", fontSize=7, textColor=colors.HexColor("#555555")),
    }


def _field_row_table(rows, styles, label_width_mm=58, value_width_mm=76):
    """Renders the PAP identification fields as a compact, left-aligned
    two-column table. Labels use a slightly smaller font + wider column so
    that long labels like "Numéro de la pièce d'identité" or "Date
    d'établissement de la PI" always fit on a single line without wrapping.
    Vertical spacing (row padding) is intentionally tight to reduce the
    overall block height."""
    data = []
    for label, value in rows:
        data.append(
            [
                Paragraph(label, styles["field_label"]),
                Paragraph(value if value else "-", styles["field_value"]),
            ]
        )
    t = Table(data, colWidths=[label_width_mm * mm, value_width_mm * mm], hAlign="LEFT")
    t.setStyle(
        TableStyle(
            [
                ("LINEBELOW", (0, 0), (-1, -2), 0.5, colors.HexColor("#DDDDDD")),
                ("TOPPADDING", (0, 0), (-1, -1), 1.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (0, 0), (-1, -1), "LEFT"),
            ]
        )
    )
    return t


def _annex_table(header, rows, total_row, col_widths):
    """Renders an ANNEXE 1 asset-category table. `col_widths` (in mm) are
    proportionally rescaled to always fill the full usable page width
    (FULL_WIDTH_MM), and the table is explicitly left-aligned (hAlign) so it
    sits flush against the left margin like the rest of the page content."""
    styles = _styles()
    data = [header] + rows + [total_row]
    scaled_widths = [w * mm for w in _scale_widths(col_widths)]
    t = Table(data, colWidths=scaled_widths, repeatRows=1, hAlign="LEFT")
    style = [
        ("GRID", (0, 0), (-1, -1), 0.5, GREY_BORDER),
        ("BACKGROUND", (0, 0), (-1, 0), GREY_LIGHT),
        ("BACKGROUND", (0, -1), (-1, -1), GREY_LIGHT),
        ("FONTNAME", (0, 0), (-1, 0), "DejaVu-Bold"),
        ("FONTNAME", (0, -1), (-1, -1), "DejaVu-Bold"),
        ("FONTNAME", (0, 1), (-1, -2), "DejaVu"),
        ("FONTSIZE", (0, 0), (-1, -1), 7.5),
        ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 0), (0, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    t.setStyle(TableStyle(style))
    return t


def _page1(d, styles):
    story = []
    story.append(Paragraph(
        f"ACCORD DE COMPENSATION CONCLU ENTRE AMC ET {TITLE_SUFFIX[d['type']]}",
        styles["title"],
    ))
    story.append(Spacer(1, 4))

    fields = [
        ("Numéro de lot", d["numeroLot"]),
        ("Région", d["region"]),
        ("Préfecture", d["prefecture"]),
        ("Sous préfecture", d["sousPrefecture"]),
        ("District", d["district"]),
        ("Localité", d["village"]),
        ("Code du ménage", d["codeMenage"]),
        ("Code de l'individu", d["codeIndividu"]),
        ("Prénom et NOM", d["nomPrenom"]),
        ("Sexe", d["sexe"]),
        ("Date de naissance", d["dateNaissance"]),
        ("Type de pièce d'identité", d["typeDePiece"]),
        ("Numéro de la pièce d'identité", d["numeroPiece"]),
        ("Date d'établissement de la PI", d["dateEtablissementPiece"]),
        ("Numéro de téléphone", d["telephone"]),
    ]
    ident_table = _field_row_table(fields, styles)

    profile_img = _decode_photo(d.get("photoProfilBase64"), 90, 110)
    photo_cell = profile_img if profile_img else _placeholder_box("PHOTO", 90, 110)

    # hAlign="LEFT" is required here: ReportLab Tables default to centering
    # themselves horizontally on the page, which was causing the whole PAP
    # identification block (région, préfecture, etc.) to appear centered
    # instead of flush against the left margin.
    top = Table(
        [[ident_table, photo_cell]],
        colWidths=[134 * mm, 32 * mm],
        hAlign="LEFT",
    )
    top.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
    ]))

    story.append(Paragraph(f"<b>{IDENT_SECTION_TITLE[d['type']]}</b>", styles["small_bold"]))
    story.append(Spacer(1, 4))
    story.append(top)
    story.append(Spacer(1, 10))

    if has_identity_document(d.get("typeDePiece")):
        recto = _decode_photo(d.get("photoCniRectoBase64"), 78 * mm, 46 * mm) or _placeholder_box(
            "CNI - RECTO", 78 * mm, 46 * mm
        )
        verso = _decode_photo(d.get("photoCniVersoBase64"), 78 * mm, 46 * mm) or _placeholder_box(
            "CNI - VERSO", 78 * mm, 46 * mm
        )
        # Extra empty spacer column between recto/verso to add breathing room
        # between the two ID photos, per client request.
        cni_table = Table(
            [
                [recto, "", verso],
                [
                    Paragraph("Pièce d'identité (recto)", styles["caption"]),
                    "",
                    Paragraph("Pièce d'identité (verso)", styles["caption"]),
                ],
            ],
            colWidths=[78 * mm, 10 * mm, 78 * mm],
            hAlign="LEFT",
        )
        cni_table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ]))
        story.append(cni_table)
        story.append(Spacer(1, 10))

    chef_name = d["nomPrenom"] or "..........................."
    party_word = {
        "proprietaire": ("MÉNAGE AFFECTÉ", "Ménage affecté", "Ménage"),
        "lignage": ("LIGNAGE AFFECTÉ", "Lignage affecté", "Lignage"),
        "communautaire": ("COMMUNAUTÉ AFFECTÉE", "Communauté affectée", "Communauté"),
    }[d["type"]]

    story.append(Paragraph("ENTRE LES SOUSSIGNÉS :", styles["para"]))
    story.append(Paragraph(
        "LA SOCIÉTÉ Winning Consortium Alumina Guinea (WCAG), société de droit guinéen immatriculée au Registre du "
        "Commerce et du Crédit Mobilier, ayant son siège social en République de Guinée, valablement représentée par "
        "son Directeur Général, Monsieur WU QIONG, agissant tant en son nom personnel qu'au nom et pour le compte de "
        "sa filiale Alumina Minérale Compagnie (AMC), ci-après désignée « AMC » ou « la Société » ;",
        styles["para"],
    ))
    story.append(Paragraph("ET :", styles["para"]))
    if d["type"] == "communautaire":
        story.append(Paragraph(
            f"La {party_word[0]} identifiée ci-dessus, valablement représentée à l'effet des présentes par son Chef, "
            f"Monsieur {chef_name}, agissant d'un commun accord avec et pour le compte de l'ensemble des personnes "
            f"composant ladite {party_word[2]} affectée, ci-après désignée « la {party_word[2]} affectée » ;",
            styles["para"],
        ))
    else:
        story.append(Paragraph(
            f"Le {party_word[0]} identifié ci-dessus, valablement représenté à l'effet des présentes par son Chef, "
            f"Monsieur {chef_name}, agissant d'un commun accord avec et pour le compte de l'ensemble des personnes "
            f"physiques composant ledit {party_word[2]} affecté, ci-après désigné « le {party_word[2]} affecté » ;",
            styles["para"],
        ))
    return story


def _page2(d, styles):
    party = PARTY_LABEL[d["type"]]
    story = [
        Paragraph("IL EST PRÉALABLEMENT EXPOSÉ CE QUI SUIT :", styles["para"]),
        Paragraph(
            f"- AMC construit et exploite une raffinerie d'alumine ainsi que les infrastructures connexes (« le Projet ») "
            f"dans la zone couvrant notamment la localité de {d['village']} ;",
            styles["para"],
        ),
        Paragraph(
            f"- Dans ce cadre, un recensement des ménages, biens et actifs affectés par le Projet a été mené à partir du "
            f"21/11/2025, incluant celui du {party} identifié ci-dessus ;",
            styles["para"],
        ),
        Paragraph(
            f"- De ces études, il ressort que le {party} détient des droits dans la zone visée par le Projet, dont le détail "
            f"figure en Annexe 1 du présent Accord ;",
            styles["para"],
        ),
        Paragraph(
            "- Conformément au Plan d'Action de Réinstallation et de Compensation (PARC) applicable au Projet, ces droits "
            "donnent lieu à une compensation au titre de l'occupation permanente des terres et des actifs concernés ;",
            styles["para"],
        ),
        Paragraph(
            f"- En application du PARC, une proposition de compensation personnalisée a été développée par WCAG, et "
            f"communiquée, présentée et expliquée au {party} et aux personnes le composant ;",
            styles["para"],
        ),
        Paragraph(
            f"- Après avoir pris le temps nécessaire à la réflexion et à la consultation de l'ensemble des personnes le "
            f"constituant, le Chef du {party} consent librement et en toute connaissance de cause aux termes du présent "
            "Accord.",
            styles["para"],
        ),
        Spacer(1, 6),
        Paragraph("IL A ÉTÉ CONVENU ET ARRÊTÉ CE QUI SUIT :", styles["small_bold"]),
        Paragraph("Article 1 – Principe d'indemnisation", styles["article"]),
        Paragraph(
            f"Les Parties conviennent des termes et conditions de l'indemnisation, pour la perte des terres et des biens "
            f"du {party} figurant en Annexe 1 du présent Accord. Le {party} considère ces termes et conditions comme étant "
            "pleinement suffisants et satisfaisants, et de nature à compenser intégralement les conséquences de son "
            "déplacement physique et/ou économique du fait du Projet.",
            styles["para"],
        ),
    ]
    return story


def _page3(d, styles):
    party = PARTY_LABEL[d["type"]]
    return [
        Paragraph("Article 2 – Principe de non-contestation", styles["article"]),
        Paragraph(
            f"Le {party} déclare expressément renoncer à réclamer à WCAG, ainsi qu'à ses sous-traitants intervenant dans le "
            "cadre du Projet, toute indemnisation additionnelle liée à la perte des parcelles listées en Annexe 1 du "
            "présent Accord, ainsi que des actifs (cultures, arbres, structures) qui y sont implantés.",
            styles["para"],
        ),
        Paragraph("Article 3 – Dispositions diverses", styles["article"]),
        Paragraph(
            "Le préambule et les annexes du présent Accord en font partie intégrante. Le présent Accord est régi par le "
            "droit guinéen. Tout différend relatif à sa validité, son interprétation ou son exécution sera réglé à "
            "l'amiable et, à défaut, conformément à la réglementation guinéenne en vigueur.",
            styles["para"],
        ),
        Paragraph(f"Article 4 – Intégrité du consentement du {party}", styles["article"]),
        Paragraph("Le représentant des autorités locales présent lors de la signature certifie :", styles["para"]),
        Paragraph(
            f"- Que l'Accord a fait l'objet d'une traduction orale en soussou, langue parlée par le {party} ;",
            styles["para"],
        ),
        Paragraph(
            f"- Qu'il a informé tous les membres présents, adultes et capables, du {party} de l'ensemble de leurs droits et "
            "obligations au titre du présent Accord ;",
            styles["para"],
        ),
        Paragraph(
            f"- Que le {party} a disposé du temps de réflexion nécessaire avant de donner son consentement final aux termes "
            "du présent Accord.",
            styles["para"],
        ),
    ]


def _page4(d, summary, styles):
    rows = [
        ["Type de biens", "Montants (GNF)"],
        ["Compensation des parcelles (foncier)", fmt_number(summary.parcelles)],
        ["Compensation des champs (cultures annuelles)", fmt_number(summary.champs_cultures_annuelles)],
        ["Compensation des cultures pérennes", fmt_number(summary.cultures_perennes)],
        ["Compensation des espèces sauvages", fmt_number(summary.especes_sauvages)],
        ["Compensation des bois d'œuvre", fmt_number(summary.bois_doeuvre)],
        ["Compensation des ressources", fmt_number(summary.ressources)],
        ["Compensation des structures", fmt_number(summary.structures)],
        ["Total des compensations", fmt_number(summary.total)],
    ]
    # Colour has been removed from the recap table's title/header row per
    # client request (contracts are now achromatic except logos/photos):
    # the header row uses a light grey background + black bold text and a
    # bottom border instead of a solid maroon fill with white text.
    t = Table(rows, colWidths=[110 * mm, 50 * mm], hAlign="LEFT")
    t.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, GREY_BORDER),
                ("BACKGROUND", (0, 0), (-1, 0), GREY_DARKER),
                ("LINEBELOW", (0, 0), (-1, 0), 1, colors.black),
                ("BACKGROUND", (0, -1), (-1, -1), GREY_LIGHT),
                ("FONTNAME", (0, 0), (-1, 0), "DejaVu-Bold"),
                ("FONTNAME", (0, -1), (-1, -1), "DejaVu-Bold"),
                ("FONTNAME", (0, 1), (-1, -2), "DejaVu"),
                ("FONTSIZE", (0, 0), (-1, -1), 9.5),
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    # NOTE: the SIGNATURE / EMPREINTE POUCE GAUCHE box that used to sit here
    # has been moved to the top of page 5, so that ALL signature-related
    # boxes are consolidated on a single page (page 5), per client request.
    story = [
        Paragraph("RÉCAPITULATIF DES COMPENSATIONS", styles["section"]),
        t,
    ]
    return story


def _page5(d, summary, styles):
    chef_name = d["nomPrenom"] or "..........................."
    party = PARTY_LABEL[d["type"]]
    consent = (
        f"Je, soussigné, {'Monsieur ' if d['type'] != 'communautaire' else ''}{chef_name}, en ma qualité de "
        f"{CHEF_LABEL[d['type']]}, certifie, en plein accord avec les membres du{'e' if d['type']=='communautaire' else ''} "
        f"{party.split()[0]}, donner mon consentement à l'ensemble des termes et conditions du présent Accord qui m'ont "
        "été traduits oralement du français en sousou, et ce, en présence d'un représentant des autorités locales dont "
        "la fonction est ............................................................................"
    )
    dt = fmt_date(d.get("dateEnquete")) or ""

    # SIGNATURE / EMPREINTE POUCE GAUCHE box, moved here from page 4 so that
    # ALL signature-related boxes appear together on a single page (page 5).
    # Height increased (24mm -> 34mm) to leave enough room for an actual
    # thumbprint, per client request. Colour removed from the header cell
    # (light grey instead of a solid brand colour).
    sig_thumb_box = Table(
        [["SIGNATURE", "EMPREINTE POUCE GAUCHE"], ["", ""]],
        colWidths=[80 * mm, 80 * mm],
        rowHeights=[7 * mm, 34 * mm],
        hAlign="LEFT",
    )
    sig_thumb_box.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER),
                ("GRID", (0, 0), (-1, -1), 0.75, GREY_BORDER),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (0, 0), (-1, 0), GREY_LIGHT),
                ("FONTNAME", (0, 0), (-1, 0), "DejaVu-Bold"),
                ("FONTSIZE", (0, 0), (-1, 0), 8.5),
                ("ALIGN", (0, 0), (-1, 0), "CENTER"),
                ("TOPPADDING", (0, 0), (-1, 0), 3),
            ]
        )
    )

    story = [
        sig_thumb_box,
        Spacer(1, 8),
        Paragraph(
            f"Fait en deux (2) exemplaires originaux, un étant remis à chacune des Parties.<br/>"
            f"À ........................, le {dt}",
            styles["para"],
        ),
        Spacer(1, 6),
    ]
    box_content = [
        [Paragraph(f"<b>{TITLE_SUFFIX[d['type']] if d['type']!='proprietaire' else 'Le Ménage affecté'}</b>", styles["small_bold"])],
        [Paragraph(consent, styles["para"])],
        [Paragraph("Signature :", styles["small"])],
    ]
    box = Table(box_content, colWidths=[FULL_WIDTH_MM * mm], hAlign="LEFT")
    box.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.75, colors.black),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]
        )
    )
    story.append(box)
    story.append(Spacer(1, 8))

    def sig_lines(*labels):
        return [Paragraph(f"{lbl} : ......................................................................", styles["small"]) for lbl in labels]

    _half_mm = (FULL_WIDTH_MM - 2) / 2.0

    amc_box = Table(
        [[Paragraph("<b>AMC</b>", styles["small_bold"])]] + [[l] for l in sig_lines("Nom", "Fonction", "Signature")],
        colWidths=[_half_mm * mm],
    )
    amc_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))

    aut_box = Table(
        [[Paragraph("<b>Autorités</b>", styles["small_bold"])]]
        + [[l] for l in sig_lines("Nom", "Institution/Fonction", "Signature", "Nom", "Institution/Fonction")],
        colWidths=[_half_mm * mm],
    )
    aut_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))

    row1 = Table([[amc_box, aut_box]], colWidths=[(_half_mm + 1) * mm, (_half_mm + 1) * mm], hAlign="LEFT")
    story.append(row1)
    story.append(Spacer(1, 6))

    temoins_lines = []
    for _ in range(4):
        temoins_lines += sig_lines("Nom", "Relation", "Signature")
        temoins_lines.append(Spacer(1, 2))
    temoins_box = Table(
        [[Paragraph(f"<b>{TEMOINS_LABEL[d['type']]}</b>", styles["small_bold"])]] + [[l] for l in temoins_lines],
        colWidths=[_half_mm * mm],
    )
    temoins_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 1.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5)]))

    autorites_lines = []
    for _ in range(4):
        autorites_lines += sig_lines("Nom", "Fonction", "Signature")
        autorites_lines.append(Spacer(1, 2))
    autorites_box = Table(
        [[Paragraph("<b>Autorités locales (Chef du village, Chef du district ou Autres.......)</b>", styles["small_bold"])]]
        + [[l] for l in autorites_lines],
        colWidths=[_half_mm * mm],
    )
    autorites_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 1.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.5)]))

    row2 = Table([[temoins_box, autorites_box]], colWidths=[(_half_mm + 1) * mm, (_half_mm + 1) * mm], hAlign="LEFT")
    story.append(row2)
    return story


def _annexe1(d, summary: CompensationSummary, styles):
    story = [Paragraph("ANNEXE 1 – LISTE DES BIENS AFFECTÉS ET COMPENSATIONS", styles["section"])]

    # Parcelles
    story.append(Paragraph("PARCELLES AGRICOLES (FONCIER)", styles["annex_sub"]))
    if not summary.parcelle_details:
        story.append(Paragraph("Aucun bien de cette catégorie n'a été recensé.", styles["empty_note"]))
    else:
        rows = []
        tot_sup = tot_m = 0
        for p in summary.parcelle_details:
            tot_sup += p["superficie"]
            tot_m += p["montant"]
            rows.append([p["typeDeTerrain"], fmt_number(p["coutM2"]), f"{p['superficie']:.2f}", fmt_number(p["montant"])])
        total_row = ["TOTAL", "", f"{tot_sup:.2f}", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Type de terrain", "Coût/m² (GNF)", "Superficie (m²)", "Montant (GNF)"],
            rows, total_row, [60 * mm, 33 * mm, 33 * mm, 34 * mm],
        ))
    story.append(Spacer(1, 10))

    # Cultures annuelles
    story.append(Paragraph("CULTURES ANNUELLES (CHAMPS)", styles["annex_sub"]))
    if not summary.culture_annuelle_details:
        story.append(Paragraph("Aucun bien de cette catégorie n'a été recensé.", styles["empty_note"]))
    else:
        rows = []
        tot_sup = tot_m = 0
        for c in summary.culture_annuelle_details:
            tot_sup += c["superficieHa"]
            tot_m += c["montant"]
            rows.append([c["culture"], f"{c['superficieHa']:.2f}", fmt_number(c["revenuHa"]), fmt_number(c["montant"])])
        total_row = ["TOTAL", f"{tot_sup:.2f}", "", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Culture", "Superficie (ha)", "Revenu/ha (GNF)", "Montant (GNF)"],
            rows, total_row, [60 * mm, 33 * mm, 33 * mm, 34 * mm],
        ))
    story.append(Spacer(1, 10))

    # Bois d'oeuvre
    story.append(Paragraph("BOIS D'ŒUVRE", styles["annex_sub"]))
    if not summary.bois_doeuvre_details:
        story.append(Paragraph("Aucun bien de cette catégorie n'a été recensé.", styles["empty_note"]))
    else:
        rows = []
        tot_m = 0
        for b in summary.bois_doeuvre_details:
            tot_m += b["montant"]
            rows.append([
                b["espece"], f"{b['circonference']:.2f}", f"{b['hauteur']:.2f}",
                str(b["nombrePieds"]), f"{b['volumeTotal']:.2f}", fmt_number(b["montant"]),
            ])
        total_row = ["TOTAL", "", "", "", "", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Espèce", "Circ. DHP (m)", "Hauteur (m)", "Nb pieds", "Vol. total (m³)", "Montant (GNF)"],
            rows, total_row, [40 * mm, 22 * mm, 22 * mm, 20 * mm, 25 * mm, 31 * mm],
        ))
    story.append(Spacer(1, 10))

    # Cultures pérennes
    if summary.culture_perenne_details:
        story.append(Paragraph("CULTURES PÉRENNES", styles["annex_sub"]))
        rows = []
        tot_m = 0
        for c in summary.culture_perenne_details:
            tot_m += c["montant"]
            rows.append([
                c["espece"], str(c["plantules"]), str(c["jeunesNp"]), str(c["jeunesP"]),
                str(c["matures"]), str(c["adulteDeclinant"]), fmt_number(c["montant"]),
            ])
        total_row = ["TOTAUX", "", "", "", "", "", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Type d'arbre", "Plantules", "Jeunes NP", "Jeunes P", "Matures", "Adulte décl.", "Montant (GNF)"],
            rows, total_row, [32 * mm, 20 * mm, 20 * mm, 18 * mm, 18 * mm, 20 * mm, 32 * mm],
        ))
        story.append(Spacer(1, 10))

    # Especes sauvages
    if summary.espece_sauvage_details:
        story.append(Paragraph("ESPÈCES SAUVAGES", styles["annex_sub"]))
        rows = []
        tot_m = 0
        for e in summary.espece_sauvage_details:
            tot_m += e["montant"]
            rows.append([e["espece"], str(e["jeunesNp"]), str(e["jeunesP"]), fmt_number(e["montant"])])
        total_row = ["TOTAUX", "", "", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Type d'arbre", "Nombre NP", "Nombre P", "Montant (GNF)"],
            rows, total_row, [60 * mm, 33 * mm, 33 * mm, 34 * mm],
        ))
        story.append(Spacer(1, 10))

    # Structures
    if summary.structure_details:
        story.append(Paragraph("STRUCTURES", styles["annex_sub"]))
        rows = []
        tot_m = 0
        for s in summary.structure_details:
            tot_m += s["montant"]
            rows.append([
                s["designation"], s["unite"], f"{s['quantite']:.2f}",
                fmt_number(s["prixUnitaire"]), fmt_number(s["montant"]),
            ])
        total_row = ["TOTAL", "", "", "", fmt_number(tot_m)]
        story.append(_annex_table(
            ["Désignation", "Unité", "Quantité", "Prix unitaire (GNF)", "Montant (GNF)"],
            rows, total_row, [55 * mm, 20 * mm, 25 * mm, 33 * mm, 27 * mm],
        ))
        story.append(Spacer(1, 10))

    if (
        not summary.parcelle_details
        and not summary.culture_annuelle_details
        and not summary.bois_doeuvre_details
        and not summary.culture_perenne_details
        and not summary.espece_sauvage_details
        and not summary.structure_details
    ):
        story.append(Paragraph("Aucun bien de cette catégorie n'a été recensé.", styles["empty_note"]))

    return story


def _annexe2(d, summary, styles):
    if d["type"] == "communautaire":
        return [
            Paragraph("ANNEXE 2 : MODALITÉS D'INDEMNISATION", styles["section"]),
            Paragraph("1. CONSTITUTION D'UN BUDGET PROJET", styles["article"]),
            Paragraph(
                f"Conformément au PARC, le montant total de l'indemnisation due à la Communauté Affectée, indiqué en Annexe "
                f"1 du présent Accord (soit {fmt_gnf(summary.total)}), est affecté à la constitution d'un budget "
                "destiné au financement de projets collectifs au bénéfice de la Communauté Affectée.",
                styles["para"],
            ),
            Paragraph("2. IDENTIFICATION DES PROJETS COLLECTIFS", styles["article"]),
            Paragraph(
                "Les projets collectifs financés par ce budget sont co-identifiés par la Communauté Affectée, représentée par "
                "un comité désigné à cet effet, et par AMC. Les catégories de projets éligibles incluent notamment : les "
                "aménagements agricoles collectifs, les puits communautaires, l'amélioration des marchés, les écoles et "
                "centres de santé, ainsi que les pistes d'accès.",
                styles["para"],
            ),
            Paragraph("3. MISE EN ŒUVRE DES PROJETS", styles["article"]),
            Paragraph(
                "Les projets retenus sont mis en œuvre par des prestataires tiers sélectionnés par appel d'offres, en "
                "coopération avec le comité communautaire désigné par la Communauté Affectée.",
                styles["para"],
            ),
            Paragraph("4. RÉTROCESSION DES PROJETS", styles["article"]),
            Paragraph(
                "À l'achèvement de chaque projet, celui-ci fait l'objet d'une rétrocession formelle à la Communauté "
                "Affectée, matérialisée par un procès-verbal de remise signé par les représentants des deux Parties.",
                styles["para"],
            ),
            Paragraph("5. GESTION DES FONDS", styles["article"]),
            Paragraph(
                "Le budget alloué est provisionné dans la comptabilité d'AMC et décaissé progressivement au fur et à mesure "
                "de l'avancement des projets. Des points d'étape financiers sont partagés trimestriellement avec le comité "
                "formé par la Communauté Affectée.",
                styles["para"],
            ),
        ]

    party = PARTY_LABEL[d["type"]]
    return [
        Paragraph("ANNEXE 2 : MODALITÉS D'INDEMNISATION EN NUMÉRAIRE", styles["section"]),
        Paragraph(
            f"Le {party}, signataire de l'Accord, accepte de quitter définitivement et irrévocablement la ou les parcelles "
            "dont la liste figure sur sa fiche d'indemnisation, au plus tard sept (7) jours après la mise en œuvre des "
            f"dispositions décrites ci-dessous. Il appartient donc au {party} de prendre toutes les dispositions utiles afin "
            "de retirer les éléments meubles et immeubles qui s'y trouvent avant cette échéance.",
            styles["para"],
        ),
        Paragraph(
            f"En contrepartie, AMC s'engage, conformément au PARC, à indemniser le {party} des conséquences du Projet sur "
            "ses conditions de vie, y compris tous les dommages et pertes subis par lui du fait du Projet, de la manière et "
            "dans les conditions décrites ci-après :",
            styles["para"],
        ),
        Paragraph("1. INDEMNISATION FINANCIÈRE", styles["article"]),
        Paragraph(
            f"Conformément aux modalités d'indemnisation prévues dans le PARC, les Parties conviennent que le montant total "
            f"des indemnisations financières devant être payées au {party} sera celui indiqué sur la fiche individuelle de "
            f"compensation qui a été remise au Chef de Ménage, soit {fmt_gnf(summary.total)}. Le {party} considère "
            "le montant total de l'indemnisation comme étant suffisant, satisfaisant et de nature à compenser intégralement "
            "ses pertes du fait du Projet.",
            styles["para"],
        ),
        Paragraph("2. MODALITÉS DE PAIEMENT", styles["article"]),
        Paragraph(
            f"AMC portera assistance au {party} pour l'ouverture d'un compte bancaire afin de recevoir les paiements dus par "
            "AMC au titre de l'indemnisation financière.",
            styles["para"],
        ),
        Paragraph(
            "En cas de retard toutefois dans l'ouverture de ce compte bancaire, le paiement de l'indemnisation financière "
            "pourra s'effectuer selon les modalités suivantes :",
            styles["para"],
        ),
        Paragraph(
            "- Tous les montants seront réglés par chèque, établi en francs guinéens à l'ordre de la PAP.",
            styles["para"],
        ),
        Paragraph(
            "Dans tous les cas, les paiements seront effectués dans un délai maximal de vingt (20) jours après la signature "
            "du présent Accord.",
            styles["para"],
        ),
        Paragraph(
            "Le paiement, selon les modalités prévues ici, des sommes indiquées ci-dessus libère AMC de toute obligation au "
            "titre du paiement de l'indemnisation.",
            styles["para"],
        ),
        Paragraph(
            f"Pour faire valoir ses droits et être payé, le {party} devra obligatoirement se munir de l'Annexe 1 (montant et "
            "désignation du bénéficiaire) signée et validée par toutes les parties lors des inventaires des biens et de la "
            "carte d'identité nationale à son nom renseignée sur l'accord de compensation.",
            styles["para"],
        ),
    ]


def _header_footer(canvas, doc, d):
    canvas.saveState()
    w, h = A4
    # Header: brand logos (replaces the former text-based OKAPI / WCAG header)
    logo_h = 13 * mm
    top_y = h - 22
    try:
        if os.path.exists(OKAPI_LOGO_PATH):
            okapi_w = logo_h * OKAPI_LOGO_ASPECT
            canvas.drawImage(
                OKAPI_LOGO_PATH, 32, top_y - logo_h, width=okapi_w, height=logo_h,
                preserveAspectRatio=True, mask="auto",
            )
    except Exception:
        pass
    try:
        if os.path.exists(WCAG_LOGO_PATH):
            wcag_w = logo_h * WCAG_LOGO_ASPECT
            canvas.drawImage(
                WCAG_LOGO_PATH, w - 32 - wcag_w, top_y - logo_h, width=wcag_w, height=logo_h,
                preserveAspectRatio=True, mask="auto",
            )
    except Exception:
        pass

    canvas.setStrokeColor(GREY_BORDER)
    canvas.line(32, h - 62, w - 32, h - 62)

    # Footer
    canvas.setStrokeColor(GREY_BORDER)
    canvas.line(32, 40, w - 32, 40)
    canvas.setFont("DejaVu", 7)
    canvas.setFillColor(colors.HexColor("#555555"))
    canvas.drawString(32, 30, f"Winning Consortium Alumina Guinea (WCAG) {FOOTER_LABEL[d['type']]}")
    ref = d["codeMenage"] or d["codeIndividu"]
    canvas.drawCentredString(w / 2, 30, ref)
    canvas.drawRightString(w - 32, 30, f"Page {doc.page}")
    canvas.restoreState()


def generate_contract_pdf(d, summary: CompensationSummary):
    """Generates the contract PDF as bytes."""
    _ensure_fonts()
    styles = _styles()
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=32,
        rightMargin=32,
        topMargin=68,
        bottomMargin=48,
    )
    story = []
    story += _page1(d, styles)
    story.append(PageBreak())
    story += _page2(d, styles)
    story.append(PageBreak())
    story += _page3(d, styles)
    story.append(PageBreak())
    story += _page4(d, summary, styles)
    story.append(PageBreak())
    story += _page5(d, summary, styles)
    story.append(PageBreak())
    story += _annexe1(d, summary, styles)
    story.append(PageBreak())
    story += _annexe2(d, summary, styles)

    doc.build(
        story,
        onFirstPage=lambda c, dd: _header_footer(c, dd, d),
        onLaterPages=lambda c, dd: _header_footer(c, dd, d),
    )
    return buf.getvalue()
