"""Generates the "Rapport" PDF export, modeled after the uploaded reference
document (OKAPI_AMCP_PARC_..._Rapport_provisoire_...docx): title page,
contrôle qualité roster, préambule narrative, résultats narrative, and all
14 "Tableaux" (built live from the app's synced data via rapport_data.py).

Reuses the same ReportLab fonts/helpers/table-building conventions as
contract_pdf.py (DejaVu fonts, _annex_table-style grid tables, fmt_number).
"""
import io
import os

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

from contract_pdf import fmt_number, fmt_gnf, _ensure_fonts, GREY_LIGHT, GREY_BORDER, FULL_WIDTH_MM, _scale_widths

_IMG_DIR = os.path.join(os.path.dirname(__file__), "static", "img")
OKAPI_LOGO_PATH = os.path.join(_IMG_DIR, "okapi_header_logo.png")
WCAG_LOGO_PATH = os.path.join(_IMG_DIR, "wcag_header_logo.png")
OKAPI_LOGO_ASPECT = 644.0 / 324.0
WCAG_LOGO_ASPECT = 1023.0 / 784.0

EQUIPE_PARC = [
    ("Thierno Adama SOW", "Cheffe de projet"),
    ("Sékou Cyril BAMBA", "Spécialiste PARC (LARAP)"),
    ("Souleymane DANSOKO", "Expert Database/SIG"),
    ("Amadou Ciré CAMARA", "Chef d'équipe"),
    ("Ibrahima Fily TRAORÉ", "Chef d'équipe"),
    ("Pépé René LAMAH", "Chef d'équipe"),
    ("Adeline Vassy GBATOMA", "Cheffe d'équipe"),
    ("Fatoumata Baïlo BAH", "Cheffe d'équipe"),
    ("Roger KÉITA", "Chef d'équipe"),
]
PREPARE_PAR = [
    ("Thierno Adama SOW", "Cheffe de projet"),
    ("Souleymane DANSOKO", "Expert Database et SIG"),
    ("Malick SAMBY", "Assistant Database"),
    ("Rouguiatou CONDÉ", "Assistante Database"),
    ("Mamoudou SIDIBÉ", "Rédacteur accords d'indemnisation"),
    ("Mohamed Lamine CISSÉ", "Rédacteur accords d'indemnisation"),
]


def _styles():
    _ensure_fonts()
    return {
        "title": ParagraphStyle("title", fontName="DejaVu-Bold", fontSize=16, alignment=TA_CENTER, leading=20),
        "subtitle": ParagraphStyle("subtitle", fontName="DejaVu-Bold", fontSize=12, alignment=TA_CENTER, leading=16, spaceAfter=6),
        "section": ParagraphStyle("section", fontName="DejaVu-Bold", fontSize=13, spaceBefore=12, spaceAfter=8),
        "subsection": ParagraphStyle("subsection", fontName="DejaVu-Bold", fontSize=10.5, spaceBefore=8, spaceAfter=4),
        "para": ParagraphStyle("para", fontName="DejaVu", fontSize=9.5, alignment=TA_JUSTIFY, spaceAfter=6, leading=13),
        "small": ParagraphStyle("small", fontName="DejaVu", fontSize=9, leading=12),
        "small_bold": ParagraphStyle("small_bold", fontName="DejaVu-Bold", fontSize=9, leading=12),
        "caption": ParagraphStyle("caption", fontName="DejaVu-Bold", fontSize=10, spaceBefore=10, spaceAfter=4),
        "footer": ParagraphStyle("footer", fontName="DejaVu", fontSize=7, textColor=colors.HexColor("#555555")),
        "center": ParagraphStyle("center", fontName="DejaVu", fontSize=9.5, alignment=TA_CENTER),
    }


def _grid_table(header, rows, total_row, col_widths_mm, font_size=8.0, right_cols=None):
    scaled = [w * mm for w in _scale_widths(col_widths_mm)]
    data = [header] + rows + ([total_row] if total_row else [])
    t = Table(data, colWidths=scaled, repeatRows=1, hAlign="LEFT")
    style = [
        ("GRID", (0, 0), (-1, -1), 0.5, GREY_BORDER),
        ("BACKGROUND", (0, 0), (-1, 0), GREY_LIGHT),
        ("FONTNAME", (0, 0), (-1, 0), "DejaVu-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "DejaVu"),
        ("FONTSIZE", (0, 0), (-1, -1), font_size),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    if total_row:
        style.append(("BACKGROUND", (0, -1), (-1, -1), GREY_LIGHT))
        style.append(("FONTNAME", (0, -1), (-1, -1), "DejaVu-Bold"))
    if right_cols:
        for c in right_cols:
            style.append(("ALIGN", (c, 0), (c, -1), "RIGHT"))
    t.setStyle(TableStyle(style))
    return t


def _title_page(data, styles):
    story = [
        Spacer(1, 40),
        Paragraph("L'ENVIRONNEMENT AU SERVICE DU DÉVELOPPEMENT DURABLE", styles["small_bold"]),
        Spacer(1, 30),
        Paragraph("PLAN D'ACTION DE RÉINSTALLATION ET DE COMPENSATION (PARC)", styles["title"]),
        Spacer(1, 10),
        Paragraph("RAPPORT PROVISOIRE", styles["subtitle"]),
        Spacer(1, 30),
        Paragraph(f"Lot(s) : {', '.join(data['batches']) if data['batches'] else '—'}", styles["center"]),
        Spacer(1, 8),
        Paragraph(f"Généré le {data['generated_at'].strftime('%d %B %Y à %H:%M')}", styles["center"]),
        PageBreak(),
    ]
    return story


def _controle_qualite(styles):
    def roster_table(rows):
        data = [[Paragraph(f"<b>{n}</b>", styles["small"]), Paragraph(f, styles["small"])] for n, f in rows]
        t = Table(data, colWidths=[70 * mm, 100 * mm], hAlign="LEFT")
        t.setStyle(TableStyle([
            ("TOPPADDING", (0, 0), (-1, -1), 2),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ]))
        return t

    story = [
        Paragraph("CONTRÔLE QUALITÉ", styles["section"]),
        Paragraph("Préparé par", styles["subsection"]),
        roster_table(PREPARE_PAR),
        Spacer(1, 8),
        Paragraph("Vérifié et approuvé par", styles["subsection"]),
        roster_table([("Guy RONDEAU", "Expert environnementaliste international, Directeur général")]),
        Spacer(1, 8),
        Paragraph("Équipe PARC", styles["subsection"]),
        roster_table(EQUIPE_PARC),
        PageBreak(),
    ]
    return story


def _preambule(data, styles):
    total_indemnises = data["indemnisation_count"]
    story = [
        Paragraph("PRÉAMBULE", styles["section"]),
        Paragraph(
            "Le Plan d'Action de Réinstallation et de Compensation (PARC) a été préparé par OKAPI Environnement "
            "Conseil SARL, un cabinet spécialisé dans l'accompagnement environnemental et social des projets "
            "d'infrastructure et d'exploitation minière en République de Guinée.",
            styles["para"],
        ),
        Paragraph(
            "Ce document porte sur le dispositif de compensation lié aux emprises du Projet, permettant "
            "l'indemnisation des Personnes Affectées par le Projet (PAP) pour la perte de leurs terres et de "
            "leurs biens.",
            styles["para"],
        ),
        Paragraph(
            "Le présent rapport présente l'ensemble des mesures techniques, sociales et financières mises en "
            "œuvre dans le cadre du processus de compensation, sur la base des données synchronisées à ce jour "
            f"dans l'application OKAPI Survey, soit {total_indemnises} enregistrement(s) d'indemnisation.",
            styles["para"],
        ),
        Paragraph(
            "Ce rapport constitue également un état d'avancement de la mise en œuvre du PARC.",
            styles["para"],
        ),
        PageBreak(),
    ]
    return story


def _tableau1_section(data, styles):
    t1 = data["tableau1"]
    header = ["Lot", "Ménage", "Lignage", "Collectif", "Masculin", "Féminin", "Total"]
    rows = [[r["lot"], r["menage"], r["lignage"], r["collectif"], r["masculin"], r["feminin"], r["total"]] for r in t1["rows"]]
    tot = t1["total"]
    total_row = ["TOTAL", tot["menage"], tot["lignage"], tot["collectif"], tot["masculin"], tot["feminin"], tot["total"]]
    story = [
        Paragraph("Tableau 1 : Accords signés / Localisation par type et nombre de responsables", styles["caption"]),
        _grid_table(header, rows, total_row, [40, 22, 22, 22, 22, 22, 20], right_cols=[1, 2, 3, 4, 5, 6]),
        Spacer(1, 10),
    ]
    return story


def _tableau2_section(data, styles):
    t2 = data["tableau2"]
    header = ["Lot", "Nombre de PAP", "Superficie (m²)", "Compensation (GNF)"]
    rows = [
        [r["lot"], r["nb_pap"], f"{r['superficie']:,.2f}".replace(",", " "), fmt_number(r["montant"])]
        for r in t2["rows"]
    ]
    tot = t2["total"]
    total_row = ["TOTAL", tot["nb_pap"], f"{tot['superficie']:,.2f}".replace(",", " "), fmt_number(tot["montant"])]
    story = [
        Paragraph("Tableau 2 : Récapitulatif des compensations", styles["caption"]),
        _grid_table(header, rows, total_row, [45, 30, 40, 45], right_cols=[1, 2, 3]),
        Spacer(1, 10),
    ]
    return story


def _tableau3_section(data, styles):
    t3 = data["tableau3"]
    header = ["Lot", "Village", "Nombre de PAP", "Superficie (m²)", "Compensation (GNF)"]
    rows = [
        [r["lot"], r["village"], r["nb_pap"], f"{r['superficie']:,.2f}".replace(",", " "), fmt_number(r["montant"])]
        for r in t3["rows"]
    ]
    tot = t3["total"]
    total_row = ["", "TOTAL", tot["nb_pap"], f"{tot['superficie']:,.2f}".replace(",", " "), fmt_number(tot["montant"])]
    story = [
        Paragraph("Tableau 3 : Récapitulatif des compensations par village", styles["caption"]),
        _grid_table(header, rows, total_row, [30, 40, 28, 40, 42], right_cols=[2, 3, 4]),
        Spacer(1, 10),
    ]
    return story


def _tableau4_section(data, styles):
    t4 = data["tableau4"]
    header = ["Culture", "Superficie (ha)", "Compensation (GNF)"]
    rows = [
        [r["culture"], f"{r['superficie']:,.4f}".replace(",", " "), fmt_number(r["montant"])]
        for r in t4["rows"]
    ]
    tot = t4["total"]
    total_row = ["TOTAL", f"{tot['superficie']:,.4f}".replace(",", " "), fmt_number(tot["montant"])]
    story = [
        Paragraph("Tableau 4 : Récapitulatif des compensations des cultures annuelles", styles["caption"]),
        _grid_table(header, rows, total_row, [60, 45, 45], right_cols=[1, 2]),
        Spacer(1, 10),
    ]
    return story


def _tableau5_section(data, styles):
    t5 = data["tableau5"]
    header = ["Lot", "Cultures pérennes (GNF)", "Espèces sauvages (GNF)", "Bois d'œuvre (GNF)", "Total (GNF)"]
    rows = [
        [
            r["lot"],
            fmt_number(r["cultures_perennes"]),
            fmt_number(r["especes_sauvages"]),
            fmt_number(r["bois_doeuvre"]),
            fmt_number(r["total"]),
        ]
        for r in t5["rows"]
    ]
    tb = t5["totals_by_cat"]
    total_row = ["TOTAL", fmt_number(tb["cultures_perennes"]), fmt_number(tb["especes_sauvages"]), fmt_number(tb["bois_doeuvre"]), fmt_number(t5["grand_total"])]
    story = [
        Paragraph("Tableau 5 : Récapitulatif des compensations des arbres / lot", styles["caption"]),
        _grid_table(header, rows, total_row, [28, 38, 38, 38, 32], font_size=7.3, right_cols=[1, 2, 3, 4]),
        Spacer(1, 10),
    ]
    return story


def _tableau6_section(data, styles):
    t6 = data["tableau6"]
    header = ["Type de terrain", "Village", "Superficie (m²)", "Montant (GNF)"]
    rows = [
        [r["type_terrain"], r["village"], f"{r['superficie']:,.2f}".replace(",", " "), fmt_number(r["montant"])]
        for r in t6["rows"]
    ]
    tot = t6["total"]
    total_row = ["TOTAL", "", f"{tot['superficie']:,.2f}".replace(",", " "), fmt_number(tot["montant"])]
    story = [
        Paragraph("Tableau 6 : Récapitulatif des montants et superficie relatif au type de terrain / localisation par village", styles["caption"]),
        _grid_table(header, rows, total_row, [55, 45, 40, 46], font_size=7.5, right_cols=[2, 3]),
        Spacer(1, 10),
    ]
    return story


def _fmt_date_short(iso_str):
    if not iso_str:
        return ""
    try:
        from datetime import datetime as _dt
        d = _dt.fromisoformat(iso_str.replace("Z", "+00:00"))
        return d.strftime("%d/%m/%Y")
    except Exception:
        return ""


def _indemnisation_sections(data, styles, tableau_start=7):
    """Renders Tableaux 7+ : paginated per-PAP indemnisation table."""
    pages = data["indemnisation_pages"]
    story = []
    header = [
        "N°", "Lot", "Prénom et Nom", "Code de l'enquête", "Genre",
        "Village", "Statut contrat", "Superficie (m²)", "Montant (GNF)",
    ]
    total_num = len(pages) + tableau_start - 1
    for idx, page_rows in enumerate(pages):
        n_tab = tableau_start + idx
        suffix = "" if idx == 0 else (" (suite et fin)" if idx == len(pages) - 1 else " (suite)")
        rows = [
            [
                r["n"], r["num_lot"], r["nom"], r["code_enquete"], r["genre"],
                r["village"], r["statut_contrat"],
                f"{r['superficie']:,.2f}".replace(",", " "), fmt_number(r["montant"]),
            ]
            for r in page_rows
        ]
        tot_sup = sum(r["superficie"] for r in page_rows)
        tot_montant = sum(r["montant"] for r in page_rows)
        total_row = ["", "", "", "", "", "", "TOTAL", f"{tot_sup:,.2f}".replace(",", " "), fmt_number(tot_montant)]
        story.append(Paragraph(
            f"Tableau {n_tab} : Tableau d'indemnisation des {data['indemnisation_count']} PAP{suffix}",
            styles["caption"],
        ))
        story.append(_grid_table(
            header, rows, total_row,
            [10, 22, 45, 32, 16, 30, 26, 26, 30],
            font_size=6.8, right_cols=[7, 8],
        ))
        story.append(PageBreak())
    return story


def _header_footer(canvas, doc):
    canvas.saveState()
    w, h = A4
    logo_h = 13 * mm
    top_y = h - 22
    try:
        if os.path.exists(OKAPI_LOGO_PATH):
            okapi_w = logo_h * OKAPI_LOGO_ASPECT
            canvas.drawImage(OKAPI_LOGO_PATH, 32, top_y - logo_h, width=okapi_w, height=logo_h, preserveAspectRatio=True, mask="auto")
    except Exception:
        pass
    try:
        if os.path.exists(WCAG_LOGO_PATH):
            wcag_w = logo_h * WCAG_LOGO_ASPECT
            canvas.drawImage(WCAG_LOGO_PATH, w - 32 - wcag_w, top_y - logo_h, width=wcag_w, height=logo_h, preserveAspectRatio=True, mask="auto")
    except Exception:
        pass
    canvas.setStrokeColor(GREY_BORDER)
    canvas.line(32, h - 62, w - 32, h - 62)
    canvas.line(32, 40, w - 32, 40)
    canvas.setFont("DejaVu", 7)
    canvas.setFillColor(colors.HexColor("#555555"))
    canvas.drawString(32, 30, "OKAPI Environnement Conseil — Rapport PARC")
    canvas.drawRightString(w - 32, 30, f"Page {doc.page}")
    canvas.restoreState()


def generate_rapport_pdf(menages, champs, structures, report_data=None):
    """Generates the Rapport PDF as bytes. `report_data` may be a
    pre-computed dict from rapport_data.build_full_report_data (to avoid
    recomputation when also needed by the docx export in the same
    request); computed on the fly otherwise."""
    if report_data is None:
        from rapport_data import build_full_report_data
        report_data = build_full_report_data(menages, champs, structures)

    styles = _styles()
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4, leftMargin=32, rightMargin=32, topMargin=68, bottomMargin=48,
    )
    story = []
    story += _title_page(report_data, styles)
    story += _controle_qualite(styles)
    story += _preambule(report_data, styles)

    story.append(Paragraph("RÉSULTATS", styles["section"]))
    story.append(Paragraph(
        "Ce rapport présente les activités d'acquisition foncière menées sur l'ensemble des lots synchronisés "
        "à ce jour dans l'application OKAPI Survey.",
        styles["para"],
    ))
    story += _tableau1_section(report_data, styles)
    story += _tableau2_section(report_data, styles)
    story += _tableau3_section(report_data, styles)
    story += _tableau4_section(report_data, styles)
    story.append(PageBreak())
    story += _tableau5_section(report_data, styles)
    story += _tableau6_section(report_data, styles)
    story.append(PageBreak())
    story += _indemnisation_sections(report_data, styles)

    doc.build(story, onFirstPage=_header_footer, onLaterPages=_header_footer)
    return buf.getvalue()
