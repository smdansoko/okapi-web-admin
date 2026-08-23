"""Import legacy KoboToolbox/ODK "Enquête ménage" Excel exports into the
per-project SQLite databases, producing records in the exact JSON shape
the Flutter mobile app / db.upsert_menage() already expect.

Sources:
  - /home/user/uploaded_files/Enquête_des_ménages (WCAG).xlsx      -> project "wcag"
  - /home/user/uploaded_files/Enquête_ménage (SIMANDOU).xlsx       -> project "simandou"

Each source file has 2 sheets:
  - "Enquête ménage"   : one row per ménage (household)
  - "info_individus"   : one row per individu (household member), linked to
                          its parent ménage row via _parent_index == the
                          ménage row's _index (both are KoboToolbox/ODK
                          export bookkeeping columns).

Both sheets contain trailing EMPTY rows (an ODK/KoboToolbox export quirk) -
these are skipped by requiring the key column (code_menage / id_individu)
to be non-empty.

Village names: the legacy "village" column stores short internal Kobo
choice-list VALUES (e.g. "WI", "KT"), not the full village name.
  - For WCAG, the original XLSForm ("WCAG_Enquête des ménages.xlsx",
    'choices' sheet) provides a complete code->name lookup table, embedded
    below as WCAG_VILLAGE_MAP (100% coverage verified against the 3
    communes present in the WCAG legacy export: Boké-centre, Kanfarandé,
    Dabis).
  - For SIMANDOU, the user provided "Liste_village.xlsx" (code/village
    columns), embedded below as SIMANDOU_VILLAGE_MAP (100% coverage
    verified against the 15 village codes present in the SIMANDOU legacy
    export).

Region/Préfecture: derived from the `commune` column via
backend/../data/guinea_admin.json, using a normalization+prefix match
first (handles accent/spacing/"-centre" variants), then difflib fuzzy
matching as a last resort.

Run with:  python3 import_legacy_excel.py [--dry-run]
"""

import argparse
import difflib
import json
import os
import re
import unicodedata
from datetime import datetime

import openpyxl

import db

BASE_DIR = os.path.dirname(__file__)
UPLOADED_DIR = "/home/user/uploaded_files"

WCAG_XLSX = os.path.join(UPLOADED_DIR, "Enquête_des_ménages (WCAG).xlsx")
SIMANDOU_XLSX = os.path.join(UPLOADED_DIR, "Enquête_ménage (SIMANDOU).xlsx")

GUINEA_ADMIN_PATH = os.path.join(BASE_DIR, "data", "guinea_admin.json")

# ---------------------------------------------------------------------------
# WCAG village code -> full village name (extracted from the original
# XLSForm "WCAG_Enquête des ménages.xlsx" -> 'choices' sheet -> list_name
# == 'village'). 100% coverage verified for the codes actually present in
# the legacy WCAG ménage export.
# ---------------------------------------------------------------------------
WCAG_VILLAGE_MAP = {
    "BM": "Biramou",
    "BI": "Bitonko",
    "BS": "Bissitè",
    "BY1": "Bonya I",
    "BY2": "Bonyia II",
    "CF": "Carrefour",
    "DA": "Dabon",
    "DF": "Diafaré",
    "DB": "Dobali",
    "DS": "Dossolon",
    "DK": "Doukounkou",
    "KK": "Kakourounty",
    "KL": "Kalounka",
    "KM": "Kamlack",
    "KN": "Kangugu",
    "KR": "Karagbo",
    "KS": "Kassampa",
    "KT": "Katchafn",
    "KW": "Kaweswes",
    "KB": "Kambilam",
    "KI": "Kissaki",
    "KD": "Kouda",
    "MR": "Marao",
    "SL": "Silikonko",
    "SS": "Sinsourou",
    "TL": "Taloukhouré",
    "TD": "Taloukhouré Daranta",
    "TG": "Togomayé",
    "TO": "Togossam",
    "TN": "Tomboya",
    "TK": "Tonkima",
    "CU": "Boké-centre",
    "CRK": "Kanfarandé",
    "CRD": "Dabis",
    "CRT": "Tanènè",
    "CRS": "Sansalé",
    "CRKB": "Kaboyé",
    "CRW": "Wendou-N'Bour",
    "WI": "Weissin",
    "ND": "N'Diarédi",
    "NY": "N'Yamayara",
}

# ---------------------------------------------------------------------------
# SIMANDOU village code -> full village name, provided by the user as
# "Liste_village.xlsx" (single sheet 'Feuil1', columns N°/code/village).
# 100% coverage verified against the 15 distinct village codes actually
# present in the legacy SIMANDOU ménage export.
# ---------------------------------------------------------------------------
SIMANDOU_VILLAGE_MAP = {
    "KS": "Kosseno",
    "GB": "Gbaranokoro",
    "GK": "Gbaranokoura",
    "FR": "Férédou",
    "BK": "Banankoro",
    "FE": "Fréssédou",
    "TW": "Ténémawoussoudou",
    "FB": "Foyer-Barry",
    "FK": "Founounkouroudou",
    "MR": "Mamaridou",
    "BF": "Bafouro",
    "DJ": "Djeridou",
    "MT": "Matenin-moridou",
    "NB": "Nabaladou",
    "NF": "Naniferedou",
    "SM": "Semissadou",
    "DF": "Djaforodou",
    "FG": "Famougnedou",
    "FD": "Foudou",
    "MN": "Manabri",
    "SG": "Samiédou",
    "TM": "Tary-moussoudou",
    "WR": "Waradala",
    "WS": "Worosoukoro",
    "KY": "Koyola",
    "FF": "Farafina",
    "SK": "Sokodou",
    "CU": "Damaro-cu",
    "Dk": "Djarakedou",
    "KK": "Konsankoro",
    "CUK": "Kérouané Centre",
}


# ---------------------------------------------------------------------------
# Commune -> (region, prefecture) resolver, backed by data/guinea_admin.json
# ---------------------------------------------------------------------------
def _normalize(s: str) -> str:
    s = (s or "").strip()
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = re.sub(r"[^a-z0-9]", "", s)
    return s


class CommuneResolver:
    def __init__(self, guinea_admin_path):
        with open(guinea_admin_path, encoding="utf-8") as f:
            data = json.load(f)
        self._flat = {}
        self._prefectures = []  # (region, prefecture, communes)
        for region, prefs in data.items():
            for pref, communes in prefs.items():
                self._prefectures.append((region, pref, communes))
                for c in communes:
                    self._flat[c] = (region, pref)
        self._norm_flat = {_normalize(k): (k, v) for k, v in self._flat.items()}
        self.unresolved = set()

    def resolve(self, commune):
        commune = (commune or "").strip()
        if not commune:
            return None, None, "empty"
        if commune in self._flat:
            r, p = self._flat[commune]
            return r, p, "exact"
        norm_q = _normalize(commune)
        if norm_q in self._norm_flat:
            name, (r, p) = self._norm_flat[norm_q]
            return r, p, f"norm-exact->{name}"
        # prefix containment (handles "Boké-centre" vs "Boké Centre",
        # "Dabis" vs "Dabiss", "Kérouané" vs "Kérouane Centre")
        candidates = []
        for nk, (name, (r, p)) in self._norm_flat.items():
            if nk.startswith(norm_q) or norm_q.startswith(nk):
                candidates.append((abs(len(nk) - len(norm_q)), name, r, p))
        if candidates:
            candidates.sort()
            _, name, r, p = candidates[0]
            return r, p, f"prefix->{name}"
        # commune name matches a PREFECTURE name (chef-lieu case)
        for region, pref, communes in self._prefectures:
            npref = _normalize(pref)
            if npref == norm_q or npref.startswith(norm_q) or norm_q.startswith(npref):
                for c in communes:
                    if "centre" in _normalize(c):
                        return region, pref, f"prefecture-centre->{c}"
                return region, pref, f"prefecture-match->{pref}"
        # last resort: difflib fuzzy match
        matches = difflib.get_close_matches(commune, list(self._flat.keys()), n=1, cutoff=0.5)
        if matches:
            r, p = self._flat[matches[0]]
            return r, p, f"fuzzy->{matches[0]}"
        self.unresolved.add(commune)
        return "", "", "NO MATCH"


# ---------------------------------------------------------------------------
# Excel helpers
# ---------------------------------------------------------------------------
def _iso(value):
    """Converts an Excel cell value (datetime/date/str/None) to an ISO
    string, or None."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _read_sheet(ws):
    headers = [c.value for c in ws[1]]
    idx = {h: i for i, h in enumerate(headers) if h is not None}
    rows = list(ws.iter_rows(min_row=2, values_only=True))
    return idx, rows


def load_menage_workbook(xlsx_path):
    """Reads both sheets of a legacy ménage Excel export and returns a list
    of dicts, each shaped exactly like the app's Menage.toMap() output
    (including a nested 'individus' list of Individu.toMap()-shaped
    dicts)."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws_m = wb["Enquête ménage"]
    ws_i = wb["info_individus"]

    midx, mrows = _read_sheet(ws_m)
    iidx, irows = _read_sheet(ws_i)

    mreal = [r for r in mrows if r[midx["code_menage"]]]
    ireal = [r for r in irows if r[iidx["id_individu"]]]

    # Detect duplicate menage _index values (rare KoboToolbox export
    # anomaly: two unrelated ménage rows sharing the same _index). If left
    # unhandled, individus grouped by _parent_index would be incorrectly
    # attached to BOTH households. When this happens, we instead re-derive
    # each individu's parent using the `code_menage` prefix embedded in
    # its own `id_individu` (id_individu = "{code_menage}-{numOrdre}"),
    # which is a reliable, collision-free join key.
    from collections import Counter

    index_counts = Counter(r[midx["_index"]] for r in mreal)
    duplicate_indices = {idx for idx, c in index_counts.items() if c > 1}
    if duplicate_indices:
        print(
            f"  ⚠️  Duplicate ménage _index values detected: {sorted(duplicate_indices)} "
            f"- falling back to id_individu-prefix matching for affected groups."
        )

    # Group individus by their parent ménage's _index (KoboToolbox/ODK
    # export bookkeeping column) - verified reliable except for the
    # duplicate-_index case handled above.
    individus_by_parent_index = {}
    for r in ireal:
        pidx = r[iidx["_parent_index"]]
        individus_by_parent_index.setdefault(pidx, []).append(r)

    menages = []
    for mr in mreal:
        m_index = mr[midx["_index"]]
        code_menage = mr[midx["code_menage"]]
        ind_rows = individus_by_parent_index.get(m_index, [])
        if m_index in duplicate_indices:
            # Disambiguate via id_individu prefix instead of _parent_index.
            ind_rows = [
                r for r in ind_rows if str(r[iidx["id_individu"]]).startswith(code_menage + "-")
            ]

        individus = []
        for ir in ind_rows:
            num_ordre = ir[iidx["num_ordre_individu"]]
            individus.append(
                {
                    "id": ir[iidx["id_individu"]],
                    "numOrdreIndividu": num_ordre if num_ordre is not None else 1,
                    "nomPrenom": ir[iidx["nom_prenom"]] or "",
                    "sexe": ir[iidx["sexe"]] or "",
                    "relationCdm": ir[iidx["relation_cdm"]] or "",
                    "typeDePiece": ir[iidx["type_de_piece"]] or "",
                    "numeroPiece": ir[iidx["numero_piece"]] or "",
                    "dateEtablissementPiece": _iso(ir[iidx["date_etablissement_piece"]]),
                    "dateNaissance": _iso(ir[iidx["date_naissance"]]),
                    "telephone": ir[iidx["telephone"]] or "",
                    "situationMatrimoniale": ir[iidx["situation_matrimoniale"]] or "",
                    "nombreFemmes": ir[iidx["nombre_femmes"]],
                    "groupeEthnique": ir[iidx["groupe_ethnique"]] or "",
                    "autreGroupeEthnique": ir[iidx["autre_groupe_ethnique"]],
                    "nationalite": ir[iidx["nationalite"]] or "",
                    "autreNationalite": ir[iidx["autre_nationalite"]],
                    "handicap": ir[iidx["handicap"]] or "Non",
                    "handicapPrecis": ir[iidx["handicap_precis"]],
                    "photoProfilBase64": None,
                    "photoCniRectoBase64": None,
                    "photoCniVersoBase64": None,
                    "codePap": None,
                    # Legacy filename kept for the future Phase 4 photo
                    # directory linkage (photo_membre tracking column).
                    # NOT part of the Flutter Individu model - harmlessly
                    # ignored by Individu.fromMap(), preserved in data_json
                    # for later use. photo_membre_URL is intentionally NOT
                    # stored (dead KoboToolbox links, per user instruction).
                    "photoMembreFilenameLegacy": ir[iidx["photo_membre"]],
                }
            )

        yield_menage = {
            "mr": mr,
            "midx": midx,
            "individus": individus,
            "n_individus_expected": len(ind_rows),
        }
        menages.append(yield_menage)

    return menages


def build_menage_record(entry, village_map, commune_resolver, log):
    mr = entry["mr"]
    midx = entry["midx"]

    commune = mr[midx["commune"]] or ""
    village_code = mr[midx["village"]] or ""
    village_full = village_map.get(village_code, village_code) if village_map else village_code
    if village_map is not None and village_code not in village_map:
        log["village_unmapped"].add(village_code)

    region, prefecture, how = commune_resolver.resolve(commune)
    if how == "NO MATCH":
        log["commune_unmapped"].add(commune)

    date_enquete = _iso(mr[midx["date_enquete"]]) or datetime.now().isoformat()
    repondant_cdm = mr[midx["repondant_cdm"]] or "Oui"

    record = {
        "id": mr[midx["code_menage"]],
        "dateEnquete": date_enquete,
        "enqueteurs": mr[midx["enqueteurs"]] or "",
        "tablette": str(mr[midx["tablette"]] or ""),
        "numOrdreMenage": mr[midx["num_ordre_menage"]] or 1,
        "region": region or "",
        "prefecture": prefecture or "",
        "sousPrefecture": commune,
        "district": village_full,
        "village": village_full,
        "codeMenage": mr[midx["code_menage"]],
        "residencePrincipale": mr[midx["residence_principale"]] or "Oui",
        "statutMenage": mr[midx["statut_menage"]] or "",
        "latitude": mr[midx.get("_coord_menage_latitude", -1)] if "_coord_menage_latitude" in midx else None,
        "longitude": mr[midx.get("_coord_menage_longitude", -1)] if "_coord_menage_longitude" in midx else None,
        "repondantCdm": repondant_cdm,
        "nomPrenomRepondant": mr[midx["nom_prenom_repondant"]] if "nom_prenom_repondant" in midx else None,
        "lienRepondantCdc": mr[midx["lien_repondant_cdc"]] if "lien_repondant_cdc" in midx else None,
        "telephoneRepondant": mr[midx["telephone_repondant"]] if "telephone_repondant" in midx else None,
        "typeDePieceRepondant": mr[midx["type_de_piece_repondant"]] if "type_de_piece_repondant" in midx else None,
        "numeroPieceRepondant": mr[midx["numero_piece_repondant"]] if "numero_piece_repondant" in midx else None,
        "datePieceRepondant": _iso(mr[midx["date_piece_repondant"]]) if "date_piece_repondant" in midx else None,
        "individus": entry["individus"],
        "createdAt": date_enquete,
        "updatedAt": date_enquete,
    }
    return record


def import_project(project, xlsx_path, village_map, commune_resolver, dry_run=False):
    print(f"\n=== Importing legacy data into project '{project}' from {xlsx_path} ===")
    entries = load_menage_workbook(xlsx_path)
    print(f"  Ménages found (real rows): {len(entries)}")
    total_individus = sum(len(e["individus"]) for e in entries)
    print(f"  Individus found (real rows, grouped): {total_individus}")

    log = {"village_unmapped": set(), "commune_unmapped": set()}

    db.set_current_project(project)
    existing_ids = {m["id"] for m in db.all_menages()}
    print(f"  Existing menages already in {project}.db before import: {len(existing_ids)}")

    records = []
    collisions = []
    for entry in entries:
        rec = build_menage_record(entry, village_map, commune_resolver, log)
        if rec["id"] in existing_ids:
            collisions.append(rec["id"])
        records.append(rec)

    print(f"  codeMenage collisions with existing data: {len(collisions)}")
    if collisions[:5]:
        print(f"    e.g. {collisions[:5]}")

    if log["village_unmapped"]:
        print(f"  ⚠️  Village codes with NO name mapping (kept as raw code): "
              f"{sorted(log['village_unmapped'])}")
    if log["commune_unmapped"]:
        print(f"  ⚠️  Communes that could NOT be resolved to region/préfecture: "
              f"{sorted(log['commune_unmapped'])}")

    if dry_run:
        print("  --dry-run: no data written.")
        return {
            "menages": len(records),
            "individus": total_individus,
            "collisions": len(collisions),
        }

    inserted = 0
    for rec in records:
        db.upsert_menage(rec, device_id="legacy-import")
        inserted += 1

    counts = db.counts()
    print(f"  Done. {inserted} menages upserted. {project}.db now has: {counts}")
    return {
        "menages": inserted,
        "individus": total_individus,
        "collisions": len(collisions),
        "counts_after": counts,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only", choices=["wcag", "simandou"], default=None)
    args = parser.parse_args()

    db.init_db()
    resolver = CommuneResolver(GUINEA_ADMIN_PATH)

    results = {}
    if args.only in (None, "wcag"):
        results["wcag"] = import_project(
            "wcag", WCAG_XLSX, WCAG_VILLAGE_MAP, resolver, dry_run=args.dry_run
        )
    if args.only in (None, "simandou"):
        results["simandou"] = import_project(
            "simandou", SIMANDOU_XLSX, SIMANDOU_VILLAGE_MAP, resolver, dry_run=args.dry_run
        )

    print("\n=== Summary ===")
    print(json.dumps(results, indent=2, ensure_ascii=False))
    if resolver.unresolved:
        print(f"\n⚠️  Globally unresolved communes: {sorted(resolver.unresolved)}")


if __name__ == "__main__":
    main()
