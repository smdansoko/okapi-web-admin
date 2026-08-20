"""Compensation table Excel export, matching the format of
OKAPI_WCAG_Tableau d'indemnisation_WCAG2613.xlsm:

Row 8 (merged A:M): title "OKAPI -- WCAG -- TABLEAU D'INDEMNISATION (en date
du <today>) / <villages> (<batch_code>)"
Row 11: headers N°, num_lot, Prénom et Nom, Code PAP, Téléphone,
        Date de naissance, N° ID, Genre, District/village, Statut PAP,
        Statut Contrat, Superficie (m²), Montant de Compensation (GNF)
Row 12+: data rows, one per PAP/owner
Row after data: Total row (SUM formula for Superficie + Montant)
Signature lines below.
"""
import io
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

from compensation import compute_for_owner

HEADER = [
    "N°",
    "num_lot",
    "Prénom et Nom",
    "Code PAP",
    "Téléphone",
    "Date de naissance",
    "N° ID",
    "Genre",
    "District/village",
    "Statut PAP",
    "Statut Contrat",
    "Superficie (m²)",
    "Montant de Compensation (GNF)",
]

COL_WIDTHS = [4.9, 19.8, 31.0, 25.3, 19.7, 19.8, 19.7, 19.8, 25.0, 20.0, 20.5, 19.8, 25.5]

THIN = Side(style="thin")
BORDER_ALL = Border(top=THIN, bottom=THIN, left=THIN, right=THIN)
TITLE_FONT = Font(name="Century Gothic", size=10, bold=True)
HEADER_FONT = Font(name="Century Gothic", size=10, bold=True)
CELL_FONT = Font(name="Century Gothic", size=10)


def _fmt_date(iso_str):
    if not iso_str:
        return ""
    try:
        d = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return d.strftime("%d/%m/%Y")
    except Exception:
        return iso_str


def _statut_contrat_label(champ_type):
    return {
        "Propriétaire": "Ménage",
        "Lignage": "Lignage",
        "Communautaire": "Communautaire",
    }.get(champ_type, champ_type or "")


def build_compensation_table(
    menages: list,
    champs: list,
    structures: list,
    num_batch: str = "",
    villages_label: str = "",
):
    """Builds the compensation/indemnification workbook for all PAPs
    belonging to [num_batch] (or all if num_batch is empty), aggregating
    compensation from champs+structures per owner, matching the .xlsm
    reference format exactly.
    """
    wb = Workbook()
    ws = wb.active
    ws.title = num_batch if num_batch else "WCAG"

    for idx, w in enumerate(COL_WIDTHS, start=1):
        ws.column_dimensions[get_column_letter(idx)].width = w

    # ---- Title row (merged A8:M10) ----
    today_str = datetime.now().strftime("%d %B %Y")
    title = (
        f"OKAPI --  WCAG -- TABLEAU D'INDEMNISATION (en date du {today_str})\n"
        f"{villages_label} ({num_batch})" if num_batch else
        f"OKAPI --  WCAG -- TABLEAU D'INDEMNISATION (en date du {today_str})"
    )
    ws.merge_cells("A8:M10")
    c = ws["A8"]
    c.value = title
    c.font = TITLE_FONT
    c.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)

    # ---- Header row 11 ----
    header_row_idx = 11
    for col_idx, label in enumerate(HEADER, start=1):
        cell = ws.cell(row=header_row_idx, column=col_idx, value=label)
        cell.font = HEADER_FONT
        cell.border = BORDER_ALL
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

    # ---- Build PAP rows: group champs+structures by owner (code_proprietaire) ----
    # Gather all distinct owners across champs (Lignage/Communautaire/foncier)
    # and menages (Propriétaire households), filtered by num_batch if given.
    owners = {}  # code -> dict(nom, telephone, date_naissance, num_id, genre, village, statut_pap, type_contrat)

    def _individu_lookup(code_menage, code_individu):
        for m in menages:
            if m.get("codeMenage") == code_menage or m.get("id") == code_menage:
                for ind in m.get("individus", []):
                    if ind.get("id") == code_individu:
                        return ind
        return None

    for champ in champs:
        if num_batch and champ.get("numBatch", "") != num_batch:
            continue
        code_prop = champ.get("codeProprietaire", "")
        if not code_prop:
            continue
        ind = _individu_lookup(champ.get("codeMenage", ""), code_prop) or {}
        owners.setdefault(
            code_prop,
            {
                "nom": ind.get("nomPrenom") or champ.get("proprietaireNom", ""),
                "telephone": ind.get("telephone", ""),
                "date_naissance": ind.get("dateNaissance"),
                "num_id": ind.get("numeroPiece", ""),
                "genre": ind.get("sexe", ""),
                "village": champ.get("village", ""),
                "statut_pap": "Propriétaire" if champ.get("typeDePropriete") == "Propriétaire" else champ.get("typeDePropriete", ""),
                "statut_contrat": _statut_contrat_label(champ.get("typeDePropriete", "")),
                "superficie": 0.0,
            },
        )

    for s in structures:
        if num_batch and s.get("numBatch", "") != num_batch:
            continue
        code_prop = s.get("proprietaireStructure", "")
        if not code_prop:
            continue
        ind = _individu_lookup(s.get("codeMenage", ""), code_prop) or {}
        owners.setdefault(
            code_prop,
            {
                "nom": ind.get("nomPrenom") or s.get("proprietaireNom", ""),
                "telephone": ind.get("telephone", ""),
                "date_naissance": ind.get("dateNaissance"),
                "num_id": ind.get("numeroPiece", ""),
                "genre": ind.get("sexe", ""),
                "village": s.get("village", ""),
                "statut_pap": "Propriétaire",
                "statut_contrat": "Ménage",
                "superficie": 0.0,
            },
        )

    # Fallback: households with no Champs/Structures survey but matching batch
    # (their compensation would be 0, but they should still appear if the
    # caller wants a complete PAP roster — only add when no batch filter or
    # if no owners found yet, to avoid double counting typical batch exports).
    if not num_batch:
        for m in menages:
            chef = None
            for ind in m.get("individus", []):
                if ind.get("relationCdm") == "Chef de menage":
                    chef = ind
                    break
            if chef is None and m.get("individus"):
                chef = m["individus"][0]
            if chef and chef.get("id") not in owners:
                owners[chef.get("id")] = {
                    "nom": chef.get("nomPrenom", ""),
                    "telephone": chef.get("telephone", ""),
                    "date_naissance": chef.get("dateNaissance"),
                    "num_id": chef.get("numeroPiece", ""),
                    "genre": chef.get("sexe", ""),
                    "village": m.get("village", ""),
                    "statut_pap": "Propriétaire",
                    "statut_contrat": "Ménage",
                    "superficie": 0.0,
                }

    # ---- Compute compensation + superficie totals per owner ----
    row_idx = header_row_idx + 1
    n = 1
    total_superficie = 0.0
    total_montant = 0.0
    first_data_row = row_idx
    for code_prop, info in owners.items():
        summary = compute_for_owner(champs, structures, code_prop)
        superficie = sum(p["superficie"] for p in summary.parcelle_details)
        montant = summary.total
        total_superficie += superficie
        total_montant += montant

        values = [
            n,
            num_batch,
            info["nom"],
            code_prop,
            info["telephone"],
            _fmt_date(info["date_naissance"]),
            info["num_id"],
            info["genre"],
            info["village"],
            info["statut_pap"],
            info["statut_contrat"],
            round(superficie, 2),
            round(montant),
        ]
        for col_idx, val in enumerate(values, start=1):
            cell = ws.cell(row=row_idx, column=col_idx, value=val)
            cell.font = CELL_FONT
            cell.border = BORDER_ALL
            if col_idx in (12, 13):
                cell.number_format = "#,##0.00" if col_idx == 12 else "#,##0"
                cell.alignment = Alignment(horizontal="right")
        n += 1
        row_idx += 1

    last_data_row = row_idx - 1

    # ---- Total row ----
    total_row_idx = row_idx
    ws.merge_cells(start_row=total_row_idx, start_column=1, end_row=total_row_idx, end_column=11)
    tot_label = ws.cell(row=total_row_idx, column=1, value="Total")
    tot_label.font = Font(name="Century Gothic", size=10, bold=True)
    tot_label.border = BORDER_ALL

    if last_data_row >= first_data_row:
        sup_cell = ws.cell(
            row=total_row_idx, column=12,
            value=f"=SUM(L{first_data_row}:L{last_data_row})",
        )
        mont_cell = ws.cell(
            row=total_row_idx, column=13,
            value=f"=SUM(M{first_data_row}:M{last_data_row})",
        )
    else:
        sup_cell = ws.cell(row=total_row_idx, column=12, value=0)
        mont_cell = ws.cell(row=total_row_idx, column=13, value=0)
    for c in (sup_cell, mont_cell):
        c.font = Font(name="Century Gothic", size=10, bold=True)
        c.border = BORDER_ALL
        c.number_format = "#,##0.00" if c is sup_cell else "#,##0"
        c.alignment = Alignment(horizontal="right")

    # ---- Signature block ----
    sig_row = total_row_idx + 4
    ws.cell(row=sig_row, column=1, value=f"Fait à Boké, le {datetime.now().strftime('%d %B %Y')}").font = CELL_FONT
    ws.cell(
        row=sig_row + 2, column=1,
        value="Signé : Guy RONDEAU, Directeur Général, Gérant, OKAPI Environnement Conseil SARL",
    ).font = CELL_FONT

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue(), {
        "count": n - 1,
        "total_superficie": round(total_superficie, 2),
        "total_montant": round(total_montant),
    }
