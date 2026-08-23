"""Aggregation layer for the "Rapport" tab, producing all data needed to
populate the 14 "Tableaux" described in the uploaded reference report
(OKAPI_AMCP_PARC..._Rapport_provisoire...docx), but computed LIVE from the
app's actual database (menages/champs/structures) instead of being a static
document. This lets the Rapport docx/PDF exports always reflect the current
state of the synced survey data.

Reference mapping (see docx analysis):
  Tableau 1 : Accords signés / Localisation par type et nombre de responsables
  Tableau 2 : Récapitulatif des compensations (nb PAP, superficie, montant)
  Tableau 3 : Récapitulatif des compensations par village
  Tableau 4 : Récapitulatif des compensations des cultures annuelles
  Tableau 5 : Récapitulatif des compensations des arbres / lot
  Tableau 6 : Montants et superficie par type de terrain / village
  Tableaux 7-14 : Tableau d'indemnisation des PAP (paginated)

Tableaux 5-14 in the uploaded docx are embedded as unreadable EMF images
(no libreoffice/soffice available in this sandbox to convert them), so
their content is *regenerated from live data* here using the exact same
computation logic already used elsewhere in the app (compensation.py /
contract_rows.py / excel_export.py), rather than being copied from the
(unreadable) images.
"""
from datetime import datetime

from compensation import compute_global, compute_for_owner, compute_for_champ_record, terrain_price
from contract_rows import (
    code_enquete_for_champ,
    distinct_batches,
    contract_rows_for_batch,
    individu_lookup,
)


def _summary_for_row(champs, structures, row):
    if row.get("champ_id"):
        champ = next((c for c in champs if c.get("id") == row["champ_id"]), None)
        if champ is None:
            from compensation import CompensationSummary
            return CompensationSummary()
        return compute_for_champ_record(
            champ, structures, row["code"],
            include_structures=row.get("include_structures", False),
        )
    structs = structures if row.get("include_structures", True) else []
    return compute_for_owner([], structs, row["code"])


def _contrat_type_bucket(type_contrat: str) -> str:
    tt = (type_contrat or "").lower()
    if "ligna" in tt:
        return "lignage"
    if "communaut" in tt:
        return "collectif"
    return "menage"


def build_tableau1(menages, champs, structures, num_batch=""):
    """Tableau 1 : Accords signés / Localisation par type et nombre de
    responsables. One row per lot (num_batch), columns: Ménage / Lignage /
    Collectif (contract-type counts) + Masculin / Féminin (representative's
    sexe, one per contract row). If num_batch is given, restrict to that
    single lot."""
    batches = [num_batch] if num_batch else distinct_batches(champs, structures)
    rows = []
    tot = {"menage": 0, "lignage": 0, "collectif": 0, "masculin": 0, "feminin": 0}
    for b in batches:
        contract_rows = contract_rows_for_batch(menages, champs, structures, b)
        counts = {"menage": 0, "lignage": 0, "collectif": 0, "masculin": 0, "feminin": 0}
        for r in contract_rows:
            counts[_contrat_type_bucket(r.get("type_contrat", ""))] += 1
            ind = individu_lookup(menages, r.get("codeMenage", ""), r["code"]) or {}
            sexe = (ind.get("sexe") or "").strip().lower()
            if sexe.startswith("m"):
                counts["masculin"] += 1
            elif sexe.startswith("f"):
                counts["feminin"] += 1
        rows.append({"lot": b, **counts, "total": len(contract_rows)})
        for k in tot:
            tot[k] += counts[k]
    tot["total"] = sum(r["total"] for r in rows)
    return {"rows": rows, "total": tot}


def build_tableau2(menages, champs, structures, num_batch=""):
    """Tableau 2 : Récapitulatif des compensations (nb PAP distincts,
    superficie totale des parcelles en m², montant total) — une ligne par
    lot + une ligne Total. If num_batch is given, restrict to that single
    lot."""
    batches = [num_batch] if num_batch else distinct_batches(champs, structures)
    rows = []
    tot_pap = 0
    tot_sup = 0.0
    tot_montant = 0.0
    for b in batches:
        contract_rows = contract_rows_for_batch(menages, champs, structures, b)
        nb_pap = len({r["code"] for r in contract_rows})
        sup = 0.0
        montant = 0.0
        for r in contract_rows:
            s = _summary_for_row(champs, structures, r)
            sup += sum(p["superficie"] for p in s.parcelle_details)
            montant += s.total
        rows.append({"lot": b, "nb_pap": nb_pap, "superficie": sup, "montant": montant})
        tot_pap += nb_pap
        tot_sup += sup
        tot_montant += montant
    return {
        "rows": rows,
        "total": {"nb_pap": tot_pap, "superficie": tot_sup, "montant": tot_montant},
    }


def build_tableau3(menages, champs, structures, num_batch=""):
    """Tableau 3 : Récapitulatif des compensations par village (nb PAP,
    superficie, montant), regroupé par lot puis par village. If num_batch
    is given, restrict to that single lot."""
    batches = [num_batch] if num_batch else distinct_batches(champs, structures)
    rows = []
    tot_pap = 0
    tot_sup = 0.0
    tot_montant = 0.0
    for b in batches:
        contract_rows = contract_rows_for_batch(menages, champs, structures, b)
        by_village = {}
        for r in contract_rows:
            village = r.get("village") or "Non spécifié"
            entry = by_village.setdefault(village, {"codes": set(), "sup": 0.0, "montant": 0.0})
            entry["codes"].add(r["code"])
            s = _summary_for_row(champs, structures, r)
            entry["sup"] += sum(p["superficie"] for p in s.parcelle_details)
            entry["montant"] += s.total
        for village in sorted(by_village.keys()):
            e = by_village[village]
            rows.append({
                "lot": b,
                "village": village,
                "nb_pap": len(e["codes"]),
                "superficie": e["sup"],
                "montant": e["montant"],
            })
            tot_pap += len(e["codes"])
            tot_sup += e["sup"]
            tot_montant += e["montant"]
    return {
        "rows": rows,
        "total": {"nb_pap": tot_pap, "superficie": tot_sup, "montant": tot_montant},
    }


def build_tableau4(champs, num_batch=""):
    """Tableau 4 : Récapitulatif des compensations des cultures annuelles
    (superficie en ha, montant en GNF), regroupé par culture. If num_batch
    is given, restrict to champs belonging to that single lot."""
    from compensation import _find, _CULTURES_ANNUELLES  # noqa: reuse price lookup

    by_culture = {}
    for ch in champs:
        if num_batch and ch.get("numBatch", "") != num_batch:
            continue
        for p in ch.get("parcelles", []):
            for champ_agr in p.get("champs", []):
                culture = champ_agr.get("culture") or "Non spécifié"
                data = _find(_CULTURES_ANNUELLES, "culture", culture)
                revenu_ha = (data or {}).get("revenu_annuel_ha", 0) or 0
                superficie_ha = champ_agr.get("superficieChamps", 0) or 0
                montant = revenu_ha * superficie_ha
                entry = by_culture.setdefault(culture, {"superficie": 0.0, "montant": 0.0})
                entry["superficie"] += superficie_ha
                entry["montant"] += montant

    rows = [
        {"culture": k, "superficie": v["superficie"], "montant": v["montant"]}
        for k, v in sorted(by_culture.items(), key=lambda kv: -kv[1]["montant"])
        if v["montant"] > 0 or v["superficie"] > 0
    ]
    tot_sup = sum(r["superficie"] for r in rows)
    tot_montant = sum(r["montant"] for r in rows)
    return {"rows": rows, "total": {"superficie": tot_sup, "montant": tot_montant}}


_ARBRE_CATEGORY_LABEL = {
    "cultures_perennes": "Cultures pérennes",
    "especes_sauvages": "Espèces sauvages",
    "bois_doeuvre": "Bois d'œuvre",
}


def build_tableau5(champs, structures, num_batch=""):
    """Tableau 5 : Récapitulatif des compensations des arbres / lot —
    regroupé par lot (num_batch) puis par catégorie d'arbre (cultures
    pérennes / espèces sauvages / bois d'œuvre), montant en GNF. If
    num_batch is given, restrict to that single lot."""
    batches = [num_batch] if num_batch else distinct_batches(champs, structures)
    rows = []
    totals_by_cat = {"cultures_perennes": 0.0, "especes_sauvages": 0.0, "bois_doeuvre": 0.0}
    grand_total = 0.0
    for b in batches:
        batch_champs = [c for c in champs if c.get("numBatch", "") == b]
        summary = compute_global(batch_champs, [])
        cat_amounts = {
            "cultures_perennes": summary.cultures_perennes,
            "especes_sauvages": summary.especes_sauvages,
            "bois_doeuvre": summary.bois_doeuvre,
        }
        row_total = sum(cat_amounts.values())
        if row_total <= 0:
            continue
        rows.append({"lot": b, **cat_amounts, "total": row_total})
        for k, v in cat_amounts.items():
            totals_by_cat[k] += v
        grand_total += row_total
    return {"rows": rows, "totals_by_cat": totals_by_cat, "grand_total": grand_total}


def build_tableau6(champs, num_batch=""):
    """Tableau 6 : Montants et superficie relatifs au type de terrain,
    localisés par village — regroupé par (type_de_terrain, village). If
    num_batch is given, restrict to champs belonging to that single lot."""
    by_key = {}
    for ch in champs:
        if num_batch and ch.get("numBatch", "") != num_batch:
            continue
        village = ch.get("village") or "Non spécifié"
        for p in ch.get("parcelles", []):
            tdt = p.get("typeDeTerrain") or "Non spécifié"
            superficie = p.get("superficieParcelle", 0) or 0
            prix_m2 = terrain_price(tdt)
            montant = prix_m2 * superficie
            entry = by_key.setdefault((tdt, village), {"superficie": 0.0, "montant": 0.0})
            entry["superficie"] += superficie
            entry["montant"] += montant

    rows = [
        {"type_terrain": k[0], "village": k[1], "superficie": v["superficie"], "montant": v["montant"]}
        for k, v in sorted(by_key.items(), key=lambda kv: (kv[0][0], kv[0][1]))
    ]
    tot_sup = sum(r["superficie"] for r in rows)
    tot_montant = sum(r["montant"] for r in rows)
    return {"rows": rows, "total": {"superficie": tot_sup, "montant": tot_montant}}


_STATUT_CONTRAT_LABEL = {
    "Propriétaire": "Ménage",
    "Lignage": "Lignage",
    "Communautaire": "Communautaire",
}


def build_indemnisation_rows(menages, champs, structures, num_batch=""):
    """Builds the full per-PAP indemnisation listing (one row per contract
    row, matching the non-merge architecture used across the app), the same
    data source as excel_export.build_compensation_table's rows. Used to
    populate Tableaux 7+ (paginated) in the Rapport docx/PDF export. If
    num_batch is given, restrict to that single lot (N° de lot)."""
    contract_rows = contract_rows_for_batch(menages, champs, structures, num_batch or "")
    contract_rows.sort(key=lambda o: (o.get("numBatch", ""), o.get("nom", "")))

    out = []
    n = 1
    for r in contract_rows:
        ind = individu_lookup(menages, r.get("codeMenage", ""), r["code"]) or {}
        summary = _summary_for_row(champs, structures, r)
        superficie = sum(p["superficie"] for p in summary.parcelle_details)
        code_enquete = r.get("code_enquete") or r["code"]
        out.append({
            "n": n,
            "num_lot": r.get("numBatch", ""),
            "nom": ind.get("nomPrenom") or r.get("nom", ""),
            "code_enquete": code_enquete,
            "telephone": ind.get("telephone", ""),
            "date_naissance": ind.get("dateNaissance"),
            "num_id": ind.get("numeroPiece", ""),
            "genre": ind.get("sexe", ""),
            "village": r.get("village", ""),
            "statut_pap": r.get("type_contrat") or "Propriétaire",
            "statut_contrat": _STATUT_CONTRAT_LABEL.get(r.get("type_contrat", ""), r.get("type_contrat", "")),
            "superficie": superficie,
            "montant": summary.total,
        })
        n += 1
    return out


def paginate(rows, page_size=40):
    """Splits a flat list of rows into pages of at most `page_size` rows,
    matching the reference report's pagination of the big indemnisation
    table across Tableaux 7 to 14 (8 pages for 391 PAP ≈ 49/page there;
    we use a configurable, slightly smaller default page size for
    readability in both DOCX and PDF renderers)."""
    if not rows:
        return []
    return [rows[i:i + page_size] for i in range(0, len(rows), page_size)]


def build_full_report_data(menages, champs, structures, page_size=40, num_batch=""):
    """Builds the complete data dict consumed by both the DOCX and PDF
    Rapport generators. If num_batch is given (a specific N° de lot), all
    tableaux and the indemnisation listing are restricted to that single
    lot instead of aggregating every lot."""
    t1 = build_tableau1(menages, champs, structures, num_batch)
    t2 = build_tableau2(menages, champs, structures, num_batch)
    t3 = build_tableau3(menages, champs, structures, num_batch)
    t4 = build_tableau4(champs, num_batch)
    t5 = build_tableau5(champs, structures, num_batch)
    t6 = build_tableau6(champs, num_batch)
    indemnisation_rows = build_indemnisation_rows(menages, champs, structures, num_batch)
    pages = paginate(indemnisation_rows, page_size=page_size)

    filtered_champs = [c for c in champs if not num_batch or c.get("numBatch", "") == num_batch]
    filtered_structures = [s for s in structures if not num_batch or s.get("numBatch", "") == num_batch]
    global_summary = compute_global(filtered_champs, filtered_structures)
    batches = distinct_batches(champs, structures)

    return {
        "generated_at": datetime.now(),
        "batches": batches,
        "selected_batch": num_batch,
        "tableau1": t1,
        "tableau2": t2,
        "tableau3": t3,
        "tableau4": t4,
        "tableau5": t5,
        "tableau6": t6,
        "indemnisation_pages": pages,
        "indemnisation_count": len(indemnisation_rows),
        "global_summary": global_summary,
        "menages_count": len(menages),
        "total_individus": sum(len(m.get("individus", [])) for m in menages),
        "champs_count": len(filtered_champs),
        "structures_count": len(filtered_structures),
    }
