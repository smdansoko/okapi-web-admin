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
            "codePap": chef.get("codePap", ""),
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
            "codePap": proprietaire.get("codePap", ""),
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


def _annex_table_grouped(row0_labels, row0_spans, row1_labels, rows, total_row, col_widths, font_size=6.3):
    """Renders an ANNEXE 1 table with a 2-row header where groups of
    sub-columns share a merged top-level label (row0), e.g. "Plantules"
    spanning "Nombre / Prix unitaire (GNF) / Montant (GNF)". `row0_spans` is
    a list of (start_col, end_col) inclusive column indices to merge on row
    0. Columns whose row0 label is "" (e.g. the leading "Type d'arbre" and
    trailing "Montant (GNF)" columns) are automatically vertically merged
    across both header rows."""
    styles = _styles()
    data = [row0_labels, row1_labels] + rows + [total_row]
    scaled_widths = [w * mm for w in _scale_widths(col_widths)]
    t = Table(data, colWidths=scaled_widths, repeatRows=2, hAlign="LEFT")
    style = [
        ("GRID", (0, 0), (-1, -1), 0.5, GREY_BORDER),
        ("BACKGROUND", (0, 0), (-1, 1), GREY_LIGHT),
        ("BACKGROUND", (0, -1), (-1, -1), GREY_LIGHT),
        ("FONTNAME", (0, 0), (-1, 1), "DejaVu-Bold"),
        ("FONTNAME", (0, -1), (-1, -1), "DejaVu-Bold"),
        ("FONTNAME", (0, 2), (-1, -2), "DejaVu"),
        ("FONTSIZE", (0, 0), (-1, -1), font_size),
        ("ALIGN", (0, 0), (-1, 1), "CENTER"),
        ("ALIGN", (1, 2), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 2), (0, -1), "LEFT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 2),
        ("RIGHTPADDING", (0, 0), (-1, -1), 2),
    ]
    grouped_cols = set()
    for (c0, c1) in row0_spans:
        style.append(("SPAN", (c0, 0), (c1, 0)))
        grouped_cols.update(range(c0, c1 + 1))
    for col_idx, label in enumerate(row0_labels):
        if label == "" and col_idx not in grouped_cols:
            style.append(("SPAN", (col_idx, 0), (col_idx, 1)))
    t.setStyle(TableStyle(style))
    return t


def _page1(d, styles):
    story = []
    story.append(Paragraph(
        f"ACCORD DE COMPENSATION CONCLU ENTRE WCAG ET {TITLE_SUFFIX[d['type']]}",
        styles["title"],
    ))
    story.append(Spacer(1, 4))

    # Field order matches the official reference contracts exactly (no
    # "District", no "Code du ménage" — replaced by "Code de l'individu"
    # followed by the new "Code PAP" identifier).
    fields = [
        ("Numéro de lot", d["numeroLot"]),
        ("Région", d["region"]),
        ("Préfecture", d["prefecture"]),
        ("Sous préfecture", d["sousPrefecture"]),
        ("Localité", d["village"]),
        ("Code de l'individu", d["codeIndividu"]),
        ("Code PAP", d.get("codePap", "")),
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
    is_communautaire = d["type"] == "communautaire"

    story.append(Paragraph(
        "LA SOCIÉTÉ Winning Consortium Alumina Guinea (WCAG), société de droit guinéen enregistrée au Registre de "
        "commerce sous le numéro RCCM/GN-KAL/2018.B.086411/2018 dont le siège social se situe à Camayenne, Corniche "
        "Nord, BP : 435, C/Dixinnn, Conakry, République de Guinée, représentée par son Directeur Général M. WU QIONG, "
        "dûment habilité aux fins des présentes,",
        styles["para"],
    ))
    story.append(Paragraph("Ci-après dénommée «WCAG».", styles["para"]))
    story.append(Paragraph("Et", styles["para"]))
    if is_communautaire:
        story.append(Paragraph(
            f"La COMMUNAUTÉ AFFECTÉE identifiée ci-dessus, valablement représentée à l'effet des présentes par son "
            f"Chef, Monsieur {chef_name}, agissant d'un commun accord avec et pour le compte de l'ensemble des "
            "personnes physiques composant ladite Communauté affectée, lesquelles lui ont reconnu et conféré "
            "l'ensemble des pouvoirs nécessaires, en ce compris le pouvoir de représentation, pour conclure le "
            "présent accord.",
            styles["para"],
        ))
    else:
        party_word = {
            "proprietaire": ("MÉNAGE AFFECTÉ", "Ménage"),
            "lignage": ("LIGNAGE AFFECTÉ", "Lignage"),
        }[d["type"]]
        story.append(Paragraph(
            f"Le {party_word[0]} identifié ci-dessus, valablement représenté à l'effet des présentes par son Chef, "
            f"Monsieur {chef_name}, agissant d'un commun accord avec et pour le compte de l'ensemble des personnes "
            f"physiques composant ledit {party_word[1]} affecté, lesquelles lui ont reconnu et conféré l'ensemble "
            "des pouvoirs nécessaires, en ce compris le pouvoir de représentation, pour conclure le présent accord.",
            styles["para"],
        ))
    return story


def _page2(d, styles):
    t = d["type"]
    is_communautaire = t == "communautaire"
    party = PARTY_LABEL[t]  # "Ménage affecté" / "Lignage affecté" / "Communauté affectée"
    party_lower = party[0].lower() + party[1:]
    chef_of = {
        "proprietaire": "Chef du Ménage affecté",
        "lignage": "Chef du Lignage affecté",
        "communautaire": "Chef de la Communauté affectée",
    }[t]
    chef_designe = {
        "proprietaire": "Chef désigné du Ménage affecté",
        "lignage": "Chef désigné du Lignage affecté",
        "communautaire": "Chef désigné de la Communauté affectée",
    }[t]
    art = "le" if not is_communautaire else "la"

    # "AMC" only ever appears in the Collectif reference contract; per client
    # request every such occurrence in that specific type is replaced by
    # "WCAG" here (the other two types already use WCAG throughout).
    story = [
        Paragraph(f"Ci-après dénommé{'e' if is_communautaire else ''} « {party} ».", styles["para"]),
        Paragraph(
            f"WCAG et {'la' if is_communautaire else 'le'} {party_lower} étant également désignés ci-après "
            "collectivement « les Parties » et individuellement « la Partie ».",
            styles["para"],
        ),
        Spacer(1, 6),
        Paragraph("APRÈS AVOIR PRÉALABLEMENT RAPPELÉ QUE :", styles["small_bold"]),
        Paragraph(
            "- En vue de la construction et de l'exploitation de la raffinerie d'alumine par WCAG, un recensement des "
            "ayants droit et un inventaire de l'ensemble de leurs biens affectés ont été entrepris depuis le "
            "21/11/2025, dans l'emprise concernée du Projet ;",
            styles["para"],
        ),
        Paragraph(
            f"- De ces études, il ressort que {art} {party_lower} détient des droits dans la zone visée par le Projet. "
            f"Ces droits, dûment énumérés dans une fiche récapitulative signée par le {chef_designe}, sont "
            "détaillés en Annexe 1 ;",
            styles["para"],
        ),
        Paragraph(
            "- Conformément à ses principes et à ses engagements vis-à-vis de l'État guinéen, WCAG a élaboré un Plan "
            "d'action de Réinstallation et de Compensation (PARC) afin d'assurer la compensation de tous les ayants "
            "droits affectés par le Projet. Le PARC prévoit la compensation pour une occupation permanente.",
            styles["para"],
        ),
        Paragraph(
            f"- En application du PARC, une proposition de compensation personnalisée a été développée par WCAG, et "
            f"communiquée, présentée et expliquée {'à la' if is_communautaire else 'au'} {party_lower} et aux "
            "personnes le composant ;",
            styles["para"],
        ),
        Paragraph(
            f"- Après avoir pris le temps nécessaire à la réflexion et à la consultation de l'ensemble des personnes "
            f"le constituant, le {chef_of} consent librement et en toute connaissance de cause à l'offre de "
            "compensation proposée par WCAG telle que décrite en Annexe 2 ;",
            styles["para"],
        ),
        Paragraph(
            "Dans ce contexte, les Parties ont conclu le présent accord de compensation (ci-après dénommé l'« "
            "Accord »).",
            styles["para"],
        ),
        Spacer(1, 6),
        Paragraph("IL A ÉTÉ CONVENU ET ARRÊTÉ CE QUI SUIT :", styles["small_bold"]),
        Paragraph("Article 1 – Principe d'indemnisation", styles["article"]),
        Paragraph(
            f"Les Parties conviennent des termes et conditions de l'indemnisation, pour la perte des terres et des "
            f"biens {'de la' if is_communautaire else 'du'} {party_lower} figurant en Annexe 1. "
            f"{'La' if is_communautaire else 'Le'} {party_lower} considère ces termes et conditions comme étant "
            "pleinement suffisants, satisfaisants et de nature à compenser intégralement tout préjudice causé par "
            "son déplacement physique et/ou économique ainsi que les éventuelles conséquences sur ses conditions de "
            f"vie, y compris tous les dommages et pertes subis par {'elle' if is_communautaire else 'lui'} du fait "
            "de ce déplacement.",
            styles["para"],
        ),
    ]
    return story


def _page3(d, styles):
    t = d["type"]
    is_communautaire = t == "communautaire"
    party = PARTY_LABEL[t]
    party_lower = party[0].lower() + party[1:]
    de_party = f"{'de la' if is_communautaire else 'du'} {party_lower}"
    art_le_la = "la" if is_communautaire else "le"
    membres_de = "de la Communauté affectée" if is_communautaire else f"du {party_lower}"

    return [
        Paragraph("Article 2 – Principe de non-contestation", styles["article"]),
        Paragraph(
            f"{'La' if is_communautaire else 'Le'} {party_lower} déclare expressément renoncer à réclamer à WCAG, "
            "ainsi qu'à ses sous-traitants intervenant dans le cadre de la mise en œuvre du Projet, une quelconque "
            "indemnisation supplémentaire, de quelque nature que ce soit, à raison des faits cités en préambule et "
            "autres que les indemnisations prévues dans le cadre du présent Accord.",
            styles["para"],
        ),
        Paragraph(
            f"{'La' if is_communautaire else 'Le'} {party_lower} s'engage ainsi dans les conditions prévues dans "
            "l'Annexe 2 à renoncer :",
            styles["para"],
        ),
        Paragraph(
            "- À tous droits de quelque nature que ce soit, formels, informels ou coutumiers, sur les parcelles "
            "listées en Annexe 1 pour la durée prévue à cet accord ;",
            styles["para"],
        ),
        Paragraph(
            "- À tous droits sur les actifs de quelque nature que ce soit qui y sont implantés ou édifiés, "
            "(ci-après les « Actifs ») pour la durée prévue à cet accord.",
            styles["para"],
        ),
        Paragraph(
            f"Les Parties s'engagent à conclure, à cet effet, une attestation de reconnaissance de compensation au "
            f"plus tard à la date à laquelle l'indemnisation aura été effectivement mise à la disposition {de_party}. "
            "Cette attestation prendra la forme d'un acte de rétrocession.",
            styles["para"],
        ),
        Paragraph("Article 3 – Dispositions diverses", styles["article"]),
        Paragraph(
            "Les Parties reconnaissent que le préambule ainsi que les annexes font partie intégrante du présent "
            "Accord.",
            styles["para"],
        ),
        Paragraph("L'Accord est régi et interprété conformément aux dispositions du droit guinéen.", styles["para"]),
        Paragraph(
            f"Tous différends qui surviendraient entre {art_le_la} {party_lower} ou l'un quelconque de ses membres "
            "et les autres Parties découlant de l'Accord ou en relation avec celui-ci seront réglés conformément "
            "aux dispositions légales en vigueur en République de Guinée.",
            styles["para"],
        ),
        Paragraph(f"Article 4 – Intégrité du consentement {de_party}", styles["article"]),
        Paragraph(
            "Les Parties reconnaissent qu'un représentant des autorités locales a assisté à la présentation du "
            "présent Accord. En apposant sa signature au bas du présent Accord, ledit représentant confirme :",
            styles["para"],
        ),
        Paragraph(
            "- Que l'Accord a fait l'objet d'une traduction orale en soussou, langue parlée par la Communauté "
            "affectée ;",
            styles["para"],
        ),
        Paragraph(
            f"- Qu'il a informé tous les membres présents, adultes et capables {membres_de} de l'ensemble de leurs "
            "droits et obligations au titre de l'Accord et de ses annexes ; et",
            styles["para"],
        ),
        Paragraph(
            "- Qu'il a répondu à toutes leurs interrogations et leur a communiqué l'ensemble des éléments de "
            "réponse propres à leur permettre de se déterminer eux-mêmes.",
            styles["para"],
        ),
        Paragraph(
            "Le représentant des autorités locales s'engage en outre expressément à assurer un suivi de "
            "l'exécution du présent Accord, selon les termes et dans les conditions qui y sont définis.",
            styles["para"],
        ),
        Paragraph(
            f"Les membres {membres_de}, qui ont disposé du temps de réflexion nécessaire, déclarent ainsi avoir "
            "pleinement compris et accepté de leur plein gré, l'ensemble de leurs droits et obligations au titre "
            "de l'Accord.",
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
    # SIGNATURE / EMPREINTE POUCE GAUCHE box: belongs on the SAME page as the
    # récapitulatif table in all 3 reference contracts (Ménage page 4,
    # Lignage page 4, Collectif page 4) — moved back here from page 5.
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
        Paragraph("RÉCAPITULATIF DES COMPENSATIONS", styles["section"]),
        t,
        Spacer(1, 10),
        sig_thumb_box,
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
    is_lignage = d["type"] == "lignage"

    # Consent-box header: all 3 reference documents literally read "Le
    # Ménage affecté"/"Le Ménage Affecté" here regardless of type (a
    # template copy-paste artifact present even in the Lignage/Collectif
    # source docs) — corrected here per-type instead of replicating the
    # artifact, for professionalism.
    consent_header = {
        "proprietaire": "Le Ménage affecté",
        "lignage": "Le Lignage affecté",
        "communautaire": "La Communauté affectée",
    }[d["type"]]

    story = [
        Paragraph(
            f"Fait en deux (2) exemplaires originaux, un étant remis à chacune des Parties.<br/>"
            f"À ........................, le {dt}",
            styles["para"],
        ),
        Spacer(1, 6),
    ]
    box_content = [
        [Paragraph(f"<b>{consent_header}</b>", styles["small_bold"])],
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

    wcag_box = Table(
        [[Paragraph("<b>WCAG</b>", styles["small_bold"])]] + [[l] for l in sig_lines("Nom", "Fonction", "Signature")],
        colWidths=[_half_mm * mm],
    )
    wcag_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))

    if is_lignage:
        # Lignage: row 1 = WCAG box | single-slot "Autorités locales" box
        # (NOT the 2-slot "Autorités" box used by Ménage/Collectif).
        autloc_box = Table(
            [[Paragraph("<b>Autorités locales</b>", styles["small_bold"])]]
            + [[l] for l in sig_lines("Nom", "Fonction", "Signature")],
            colWidths=[_half_mm * mm],
        )
        autloc_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))
        row1 = Table([[wcag_box, autloc_box]], colWidths=[(_half_mm + 1) * mm, (_half_mm + 1) * mm], hAlign="LEFT")
        story.append(row1)
        story.append(Spacer(1, 6))

        # Full-width Témoins section with a 2-column x 3-row grid of slots
        # (6 total), matching the Lignage reference's distinct layout — no
        # separate "Autorités locales" box here since it already appeared
        # in row 1 above.
        story.append(Paragraph(f"<b>{TEMOINS_LABEL['lignage']}</b>", styles["small_bold"]))
        story.append(Spacer(1, 3))

        def temoin_cell():
            return Table(
                [[l] for l in sig_lines("Nom", "Fonction", "Signature")],
                colWidths=[_half_mm * mm],
            )

        grid_rows = []
        for _ in range(3):
            c1 = temoin_cell()
            c2 = temoin_cell()
            grid_rows.append([c1, c2])
        grid = Table(grid_rows, colWidths=[(_half_mm + 1) * mm, (_half_mm + 1) * mm], hAlign="LEFT")
        grid.setStyle(TableStyle([
            ("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER),
            ("GRID", (0, 0), (-1, -1), 0.75, GREY_BORDER),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ]))
        story.append(grid)
        return story

    # Ménage / Collectif: row 1 = WCAG box | 2-slot "Autorités" box; row 2 =
    # Témoins (4 slots) | Autorités locales (4 slots).
    aut_box = Table(
        [[Paragraph("<b>Autorités</b>", styles["small_bold"])]]
        + [[l] for l in sig_lines("Nom", "Institution/Fonction", "Signature", "Nom", "Institution/Fonction")],
        colWidths=[_half_mm * mm],
    )
    aut_box.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.75, GREY_BORDER), ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))

    row1 = Table([[wcag_box, aut_box]], colWidths=[(_half_mm + 1) * mm, (_half_mm + 1) * mm], hAlign="LEFT")
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

    # Bois d'oeuvre — column order matches the reference contracts: Espèce,
    # Circonférence, Hauteur, Volume unitaire, Nombre de pieds, Coût/m³,
    # Volume total, Montant (GNF).
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
                f"{b['volumeUnitaire']:.3f}", str(b["nombrePieds"]),
                fmt_number(b["prixUnitaire"]), f"{b['volumeTotal']:.3f}",
                fmt_number(b["montant"]),
            ])
        total_row = ["TOTAL", "", "", "", "", "", "", fmt_number(tot_m)]
        story.append(_annex_table(
            [
                "Espèce", "Circonférence\nau DHP (m)", "Hauteur (m)",
                "Volume\nunitaire (m³)", "Nombre\nde pieds", "Coût/m³ (GNF)",
                "Volume\ntotal (m³)", "Montant (GNF)",
            ],
            rows, total_row,
            [26 * mm, 22 * mm, 18 * mm, 20 * mm, 18 * mm, 24 * mm, 20 * mm, 28 * mm],
        ))
    story.append(Spacer(1, 10))

    # Cultures pérennes — multi-level headers: Type d'arbre | Plantules
    # {Nombre, Prix unitaire, Montant} | Jeunes pousses non productives
    # {...} | Jeunes pousses productives {...} | Adultes {...} | Montant
    # (GNF) total, matching the reference contracts exactly.
    if summary.culture_perenne_details:
        story.append(Paragraph("CULTURES PÉRENNES", styles["annex_sub"]))
        rows = []
        tot_m = 0
        for c in summary.culture_perenne_details:
            tot_m += c["montant"]
            m_plantules = c["plantules"] * c["prixPlante"]
            m_jnp = c["jeunesNp"] * c["prixJeuneNp"]
            m_jp = c["jeunesP"] * c["prixJeuneP"]
            m_adultes = (c["matures"] + c["adulteDeclinant"]) * c["prixAdulte"]
            rows.append([
                c["espece"],
                str(c["plantules"]), fmt_number(c["prixPlante"]), fmt_number(m_plantules),
                str(c["jeunesNp"]), fmt_number(c["prixJeuneNp"]), fmt_number(m_jnp),
                str(c["jeunesP"]), fmt_number(c["prixJeuneP"]), fmt_number(m_jp),
                str(c["matures"] + c["adulteDeclinant"]), fmt_number(c["prixAdulte"]), fmt_number(m_adultes),
                fmt_number(c["montant"]),
            ])
        total_row = ["TOTAUX", "", "", "", "", "", "", "", "", "", "", "", fmt_number(tot_m)]
        row0 = ["Type d'arbre", "Plantules", "", "", "Jeunes pousses non productives", "", "", "Jeunes pousses productives", "", "", "Adultes", "", "", "Montant (GNF)"]
        row1 = [
            "",
            "Nombre", "Prix unitaire\n(GNF)", "Montant\n(GNF)",
            "Nombre", "Prix unitaire\n(GNF)", "Montant\n(GNF)",
            "Nombre", "Prix unitaire\n(GNF)", "Montant\n(GNF)",
            "Nombre", "Prix unitaire\n(GNF)", "Montant\n(GNF)",
            "",
        ]
        col_widths = [16] + [10, 13, 13] * 4 + [16]
        story.append(_annex_table_grouped(
            row0, [(1, 3), (4, 6), (7, 9), (10, 12)], row1, rows, total_row,
            col_widths,
        ))
        story.append(Spacer(1, 10))

    # Especes sauvages — multi-level headers: Type d'arbre | Jeunes pousses
    # non productives {Prix unitaire, Nombre, Montant} | Jeunes pousses
    # productives {Prix unitaire, Nombre, Montant} | Montant (GNF) total.
    if summary.espece_sauvage_details:
        story.append(Paragraph("ESPÈCES SAUVAGES", styles["annex_sub"]))
        rows = []
        tot_m = 0
        for e in summary.espece_sauvage_details:
            tot_m += e["montant"]
            m_np = e["jeunesNp"] * e["prixNp"]
            m_p = e["jeunesP"] * e["prixP"]
            rows.append([
                e["espece"],
                fmt_number(e["prixNp"]), str(e["jeunesNp"]), fmt_number(m_np),
                fmt_number(e["prixP"]), str(e["jeunesP"]), fmt_number(m_p),
                fmt_number(e["montant"]),
            ])
        total_row = ["TOTAUX", "", "", "", "", "", "", fmt_number(tot_m)]
        row0 = ["Type d'arbre", "Jeunes pousses non productives", "", "", "Jeunes pousses productives", "", "", "Montant (GNF)"]
        row1 = [
            "",
            "Prix unitaire\n(GNF)", "Nombre", "Montant\n(GNF)",
            "Prix unitaire\n(GNF)", "Nombre", "Montant\n(GNF)",
            "",
        ]
        story.append(_annex_table_grouped(
            row0, [(1, 3), (4, 6)], row1, rows, total_row,
            [34, 24, 18, 24, 24, 18, 24, 30],
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
            Paragraph(
                "La Communauté Affectée, signataire de l'Accord, accepte de quitter la ou les parcelles dont la liste "
                "figure en Annexe 1 au plus tard quinze (15) jours après la signature du présent Accord. Il appartient "
                "donc à la Communauté Affectée de prendre toutes les dispositions utiles afin de retirer les éléments "
                "meubles et immeubles qui s'y trouvent avant cette échéance.",
                styles["para"],
            ),
            Paragraph(
                "En contrepartie, WCAG s'engage, conformément au PARC, à indemniser la Communauté Affectée des "
                "conséquences du Projet sur ses conditions de vie, y compris tous les dommages et pertes subis par lui "
                "du fait de ce Projet, de la manière et dans les conditions décrites ci-après :",
                styles["para"],
            ),
            Paragraph("1. CONSTITUTION D'UN BUDGET PROJET", styles["article"]),
            Paragraph(
                "Conformément aux modalités d'indemnisation prévues dans le PARC, les biens détenus par la Communauté "
                "Affectée seront compensés par le biais d'un ou plusieurs projets d'intérêt général réalisés au profit "
                "de la Communauté Affectée.",
                styles["para"],
            ),
            Paragraph(
                "Le budget dévolu à ce ou ces projets est fonction de la superficie totale des parcelles impactées par "
                "le projet et des biens qui s'y trouvent, tel qu'énumérés en Annexe 1.",
                styles["para"],
            ),
            Paragraph(
                "La Communauté Affectée considère ce budget comme étant suffisant, satisfaisant et de nature à "
                "compenser intégralement les pertes occasionnées par le Projet.",
                styles["para"],
            ),
            Paragraph(
                f"Sur cette base, le budget total disponible s'élève ainsi à {fmt_gnf(summary.total)}.",
                styles["para"],
            ),
            Paragraph("2. IDENTIFICATION DES PROJETS COLLECTIFS", styles["article"]),
            Paragraph(
                "Conformément aux dispositions du PARC, les projets communautaires seront identifiés conjointement "
                "par :",
                styles["para"],
            ),
            Paragraph(
                "- La Communauté Affectée, représentée par un comité constitué à cet effet ; et<br/>"
                "- WCAG ou son représentant désigné,",
                styles["para"],
            ),
            Paragraph(
                "L'appui des Services Techniques Déconcentrés compétents en la matière sera également sollicité, et "
                "une cohérence recherchée avec le Plan de Développement Local et le Plan Annuel d'Investissement de la "
                "Commune concernée.",
                styles["para"],
            ),
            Paragraph(
                "Les Parties s'engagent à prendre toutes les mesures requises afin que le ou les projets soient "
                "identifiés et démarrés dans un délai maximum de trois (3) mois à compter de la signature du présent "
                "Accord.",
                styles["para"],
            ),
            Paragraph(
                "Les projets seront sélectionnés parmi la liste de projets-types proposés ci-dessous :",
                styles["para"],
            ),
            Paragraph(
                "- Aménagement agricole collectif ;<br/>"
                "- Puits (pastoral, maraîcher, ou domestique) ;<br/>"
                "- Marché (amélioration d'une structure existante) ;<br/>"
                "- École, centre de santé (amélioration et équipement d'une structure existante) ;<br/>"
                "- Voies d'accès à partir de la voie nouvellement créée ou en direction des axes principaux existants "
                "(cette création ne pourra pas donner lieu à de nouvelle compensation et leur tracé doit donc faire "
                "l'objet d'un consentement mutuel avec les parties concernées) ;<br/>"
                "- Autre projet identifié par la communauté et dans les limites du budget disponible.",
                styles["para"],
            ),
            Paragraph(
                "À l'issue de ce processus de concertation, une fiche d'identification sommaire sera corédigée par "
                "WCAG et le comité établi par la Communauté Affectée en vue de leur mise en œuvre. La fiche comprendra "
                "la sélection des projets à mettre en œuvre (plusieurs peuvent être prévus), et une estimation "
                "budgétaire par composante ainsi que le montant total.",
                styles["para"],
            ),
            Paragraph(
                "Seuls les projets pouvant être exécutés intégralement dans les limites du budget défini au point 1 "
                "ci-dessus pourront être entrepris dans le cadre du présent Accord.",
                styles["para"],
            ),
            Paragraph("3. MISE EN ŒUVRE DES PROJETS", styles["article"]),
            Paragraph(
                "Conformément aux dispositions du PARC, les projets seront mis en œuvre par des prestataires "
                "sélectionnés par appel d'offres ou directement par leur soin (cas des voies d'accès notamment), selon "
                "leurs capacités techniques, leurs expériences et les prix proposés. À qualité et à prix comparables, "
                "la préférence sera accordée aux prestataires installés dans la préfecture d'implantation du projet.",
                styles["para"],
            ),
            Paragraph("À cet effet :", styles["para"]),
            Paragraph(
                "- Un dossier d'appel d'offres sera développé par le maître d'œuvre, sur base de la fiche "
                "d'identification sommaire ;<br/>"
                "- Les offres seront ouvertes à l'occasion d'une réunion convoquée par le maître d'œuvre, en présence "
                "du comité constitué par la Communauté Affectée.",
                styles["para"],
            ),
            Paragraph(
                "Les marchés seront attribués par WCAG, qui reste seule responsable de la sélection finale du ou des "
                "prestataires, sur base des critères énoncés dans le dossier d'appel d'offres, puis de la réalisation "
                "des travaux.",
                styles["para"],
            ),
            Paragraph(
                "Les travaux seront réalisés sous la supervision du maître d'œuvre et du comité constitué par la "
                "Communauté Affectée. La réception provisoire du projet sera accordée à l'achèvement des travaux, "
                "moyennant l'accord du maître d'œuvre et dudit comité.",
                styles["para"],
            ),
            Paragraph("4. RÉTROCESSION DES PROJETS", styles["article"]),
            Paragraph(
                "À la suite de la réception provisoire des projets, il sera procédé à leur rétrocession formelle à la "
                "Communauté Affectée. À cet effet, un acte de rétrocession sera dressé dans lequel la Communauté "
                "Affectée s'engage à utiliser le projet selon sa destination convenue jusqu'à l'achèvement de la "
                "période de garantie et le versement, par WCAG, de la retenue de garantie.",
                styles["para"],
            ),
            Paragraph(
                "La signature de l'acte de rétrocession marque également la fin du processus de compensation.",
                styles["para"],
            ),
            Paragraph("5. GESTION DES FONDS", styles["article"]),
            Paragraph(
                "Le budget défini au point 1 ci-dessus sera provisionné sur les livres de WCAG en vue de son "
                "décaissement progressif, au bénéfice des prestataires désignés pour assurer l'exécution des projets.",
                styles["para"],
            ),
            Paragraph(
                "Une situation financière détaillée sera dressée par WCAG à la fin de chaque trimestre et transmise "
                "au comité constitué par la Communauté Affectée, avec copie au Préfet, afin qu'à tout moment, la "
                "Communauté Affectée dispose d'une information complète quant à la gestion des fonds.",
                styles["para"],
            ),
            Paragraph(
                "Conformément au PARC, les reliquats éventuels seront soit mis à la disposition de la Communauté "
                "Affectée, soit engagés sur un nouveau projet au bénéfice de la Communauté Affectée, selon leur "
                "montant. Dans tous les cas, ces reliquats éventuels restent acquis à la Communauté Affectée.",
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
