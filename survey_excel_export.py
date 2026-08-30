"""Generic Excel (.xlsx) export for BIODIVERSITÉ / SOCIAL survey records
(the generic Survey Engine forms - pose_cameras, chimpanzes_recce, poisson,
flore, oiseaux, reptiles, amphibiens, mammiferes, infrastructures,
patrimoine_culturel, socioeconomique).

Unlike the PARC compensation export (excel_export.py), these forms don't
have a fixed Python-side schema, so columns are derived dynamically from the
union of keys present in the records' `values` dict (sorted for a stable,
predictable column order, with a few well-known identifying columns pinned
first). Repeat groups (if any) are exported as a compact JSON-ish summary
column, plus an additional sheet per repeat group with one row per repeat
item, linked back to the parent record via its `record_id`.
"""
import io
import json
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

from survey_forms import FORM_TITLES, forms_for_module
import db

THIN = Side(style="thin")
BORDER_ALL = Border(top=THIN, bottom=THIN, left=THIN, right=THIN)
TITLE_FONT = Font(name="Century Gothic", size=12, bold=True)
HEADER_FONT = Font(name="Century Gothic", size=10, bold=True, color="FFFFFF")
HEADER_FILL_COLOR = "6B4F3B"
CELL_FONT = Font(name="Century Gothic", size=10)

# Well-known columns pinned first (when present), in this order.
_PINNED_KEYS = [
    "region", "prefecture", "sous_prefecture", "localite", "composante",
    "enqueteurs", "equipe_enquete", "date", "identifiant", "nom_site",
]


def _fmt_dt(iso_str):
    if not iso_str:
        return ""
    try:
        d = datetime.fromisoformat(str(iso_str).replace("Z", "+00:00"))
        return d.strftime("%d/%m/%Y %H:%M")
    except Exception:
        return str(iso_str)


def _scalar(val):
    if val is None:
        return ""
    if isinstance(val, (list, dict)):
        try:
            return json.dumps(val, ensure_ascii=False)
        except Exception:
            return str(val)
    return val


def _ordered_value_keys(records):
    """Union of all `values` keys across records, with well-known keys
    pinned first (in _PINNED_KEYS order), then the rest alphabetically."""
    seen = set()
    for r in records:
        seen.update((r.get("values") or {}).keys())
    pinned = [k for k in _PINNED_KEYS if k in seen]
    rest = sorted(k for k in seen if k not in _PINNED_KEYS)
    return pinned + rest


def _style_header_row(ws, row_idx, headers):
    from openpyxl.styles import PatternFill
    fill = PatternFill(start_color=HEADER_FILL_COLOR, end_color=HEADER_FILL_COLOR, fill_type="solid")
    for col_idx, label in enumerate(headers, start=1):
        cell = ws.cell(row=row_idx, column=col_idx, value=label)
        cell.font = HEADER_FONT
        cell.fill = fill
        cell.border = BORDER_ALL
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)


def _write_form_sheet(wb, form_key, records, sheet_title=None):
    ws = wb.create_sheet(title=(sheet_title or form_key)[:31])

    title = FORM_TITLES.get(form_key, form_key)
    ws.merge_cells("A1:F1")
    c = ws["A1"]
    c.value = f"OKAPI Survey — {title} ({len(records)} fiche(s))"
    c.font = TITLE_FONT
    c.alignment = Alignment(horizontal="left", vertical="center")

    value_keys = _ordered_value_keys(records)
    repeat_keys = set()
    for r in records:
        repeat_keys.update((r.get("repeats") or {}).keys())
    repeat_keys = sorted(repeat_keys)

    headers = ["ID fiche", "Créé le", "Mis à jour le"] + value_keys
    for rk in repeat_keys:
        headers.append(f"{rk} (nb)")

    header_row_idx = 3
    _style_header_row(ws, header_row_idx, headers)

    row_idx = header_row_idx + 1
    for r in records:
        v = r.get("values") or {}
        reps = r.get("repeats") or {}
        row = [
            (r.get("id") or "")[:36],
            _fmt_dt(r.get("createdAt")),
            _fmt_dt(r.get("updatedAt")),
        ]
        for k in value_keys:
            row.append(_scalar(v.get(k)))
        for rk in repeat_keys:
            row.append(len(reps.get(rk) or []))
        for col_idx, val in enumerate(row, start=1):
            cell = ws.cell(row=row_idx, column=col_idx, value=val)
            cell.font = CELL_FONT
            cell.border = BORDER_ALL
            cell.alignment = Alignment(vertical="top", wrap_text=False)
        row_idx += 1

    # Column widths: narrower for id/dates, generous for text fields.
    ws.column_dimensions["A"].width = 20
    ws.column_dimensions["B"].width = 16
    ws.column_dimensions["C"].width = 16
    for idx in range(4, 4 + len(value_keys) + len(repeat_keys)):
        ws.column_dimensions[get_column_letter(idx)].width = 22

    ws.freeze_panes = ws.cell(row=header_row_idx + 1, column=1)

    # One additional sheet per repeat group, flattened.
    for rk in repeat_keys:
        _write_repeat_sheet(wb, form_key, rk, records)

    return ws


def _write_repeat_sheet(wb, form_key, repeat_key, records):
    sheet_title = f"{form_key}_{repeat_key}"[:31]
    ws = wb.create_sheet(title=sheet_title)

    item_keys = set()
    for r in records:
        for item in (r.get("repeats") or {}).get(repeat_key, []):
            item_keys.update(item.keys())
    item_keys = sorted(item_keys)

    headers = ["ID fiche parente"] + item_keys
    _style_header_row(ws, 1, headers)

    row_idx = 2
    for r in records:
        rid = (r.get("id") or "")[:36]
        for item in (r.get("repeats") or {}).get(repeat_key, []):
            row = [rid] + [_scalar(item.get(k)) for k in item_keys]
            for col_idx, val in enumerate(row, start=1):
                cell = ws.cell(row=row_idx, column=col_idx, value=val)
                cell.font = CELL_FONT
                cell.border = BORDER_ALL
            row_idx += 1

    ws.column_dimensions["A"].width = 20
    for idx in range(2, 2 + len(item_keys)):
        ws.column_dimensions[get_column_letter(idx)].width = 20


def build_survey_form_workbook(form_key: str):
    """Builds a workbook containing a single form's records (+ any repeat
    group sheets). Returns raw .xlsx bytes."""
    by_form = db.all_survey_records(form_key)
    records = by_form.get(form_key, [])

    wb = Workbook()
    wb.remove(wb.active)
    _write_form_sheet(wb, form_key, records, sheet_title=form_key)

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue(), len(records)


def build_survey_module_workbook(module: str):
    """Builds a single workbook containing ALL forms of a module
    (biodiversite or social), one sheet per form (+ repeat sheets).
    Returns raw .xlsx bytes."""
    forms = forms_for_module(module)
    by_form = db.all_survey_records()

    wb = Workbook()
    wb.remove(wb.active)
    total = 0
    for f in forms:
        records = by_form.get(f["key"], [])
        total += len(records)
        _write_form_sheet(wb, f["key"], records, sheet_title=f["key"])

    if not forms:
        wb.create_sheet(title="Vide")

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue(), total
