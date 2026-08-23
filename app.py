"""OKAPI Survey - Web Admin Application.

A standalone Flask web application (separate from the Flutter mobile app)
that:
  1) Receives synced data from the OKAPI Survey mobile app via /api/sync
  2) Exports contracts (same PDF format as the mobile app, ported to Python)
  3) Exports compensation/indemnification tables (.xlsx, matching the
     OKAPI_WCAG_Tableau d'indemnisation_WCAG2613.xlsm reference format)
  4) Provides a complete, well-structured dashboard.
"""
import io
import json
import os
import sqlite3
import uuid
from datetime import datetime

from flask import Flask, render_template, request, jsonify, send_file, abort
from werkzeug.security import generate_password_hash, check_password_hash

import db
from compensation import (
    compute_for_owner,
    compute_for_champ_record,
    compute_global,
    CompensationSummary,
)
from contract_pdf import build_contract_data, generate_contract_pdf
from excel_export import build_compensation_table
from contract_rows import (
    chef_of as _chef_of,
    individu_lookup as _individu_lookup,
    code_enquete_for_champ,
    distinct_batches as _distinct_batches,
    contract_rows_for_batch as _contract_rows_for_batch,
    distinct_owner_count as _distinct_owner_count,
)

app = Flask(__name__)
app.config["JSON_AS_ASCII"] = False

db.init_db()


@app.after_request
def _add_cors_headers(response):
    """Allow the OKAPI Survey mobile app (incl. its Flutter Web preview,
    served from a different origin/port) to call /api/sync and other
    endpoints via cross-origin requests."""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = (
        "Content-Type, X-Device-Id, X-Device-Name"
    )
    return response


@app.route("/api/sync", methods=["OPTIONS"])
@app.route("/api/status", methods=["OPTIONS"])
def _cors_preflight():
    return ("", 204)


@app.template_filter("fromjson")
def _fromjson_filter(s):
    try:
        return json.loads(s) if s else {}
    except Exception:
        return {}


@app.context_processor
def _inject_pending_users_count():
    try:
        return {"pending_users_count": db.users_counts().get("pending", 0)}
    except Exception:
        return {"pending_users_count": 0}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _compute_age(date_naissance_iso):
    """Computes age in whole years from an ISO date string, or None."""
    if not date_naissance_iso:
        return None
    try:
        dob = datetime.fromisoformat(date_naissance_iso.replace("Z", ""))
        today = datetime.now()
        age = today.year - dob.year - (
            (today.month, today.day) < (dob.month, dob.day)
        )
        return age if age >= 0 else None
    except Exception:
        return None


# _distinct_batches, _contract_rows_for_batch and _distinct_owner_count are
# implemented in contract_rows.py (shared with excel_export.py, so the
# "code de l'enquête" formula stays in exactly one place) and imported
# above.


def _summary_for_row(champs, structures, row):
    """Computes the compensation summary for a single contract row,
    respecting the non-merge rule: a champs-based row only accounts for
    ITS OWN champs record (never other records belonging to the same
    owner), and structures are only added on the row flagged
    include_structures=True."""
    if row.get("champ_id"):
        champ = next((c for c in champs if c.get("id") == row["champ_id"]), None)
        if champ is None:
            return CompensationSummary()
        return compute_for_champ_record(
            champ, structures, row["code"],
            include_structures=row.get("include_structures", False),
        )
    structs = structures if row.get("include_structures", True) else []
    return compute_for_owner([], structs, row["code"])


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

def _total_montant_for_rows(champs, structures, rows):
    total = 0.0
    for r in rows:
        total += _summary_for_row(champs, structures, r).total
    return round(total)


@app.route("/")
def dashboard():
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    c = db.counts()

    total_individus = sum(len(m.get("individus", [])) for m in menages)
    total_superficie = 0.0
    for ch in champs:
        for p in ch.get("parcelles", []):
            total_superficie += p.get("superficieParcelle", 0) or 0

    global_summary = compute_global(champs, structures)
    batches = _distinct_batches(champs, structures)

    recent_syncs = db.recent_syncs(10)

    # Batch breakdown for a quick table
    batch_rows = []
    for b in batches:
        rows = _contract_rows_for_batch(menages, champs, structures, b)
        total_montant = _total_montant_for_rows(champs, structures, rows)
        batch_rows.append({
            "num_batch": b,
            "owners_count": _distinct_owner_count(rows),
            "contracts_count": len(rows),
            "total_montant": total_montant,
        })

    return render_template(
        "dashboard.html",
        counts=c,
        total_individus=total_individus,
        total_superficie=round(total_superficie, 2),
        total_montant=round(global_summary.total),
        batches=batches,
        batch_rows=batch_rows,
        recent_syncs=recent_syncs,
        now=datetime.now(),
    )


@app.route("/statistiques")
def dashboard_stats():
    """Second dashboard screen: as many additional statistics as possible
    (breakdowns by contract type, région/préfecture/village, structure
    types, culture/espèce totals, sync activity over time, etc.)."""
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    c = db.counts()

    # --- Répartition par type de contrat (Propriétaire / Lignage / Communautaire) ---
    type_contrat_counts = {"Propriétaire": 0, "Lignage": 0, "Communautaire": 0, "Autre": 0}
    for ch in champs:
        tt = (ch.get("typeDePropriete") or "").lower()
        if "ligna" in tt:
            type_contrat_counts["Lignage"] += 1
        elif "communaut" in tt:
            type_contrat_counts["Communautaire"] += 1
        elif "propri" in tt:
            type_contrat_counts["Propriétaire"] += 1
        else:
            type_contrat_counts["Autre"] += 1

    # --- Répartition géographique ---
    def _geo_counts(items, field):
        counts = {}
        for it in items:
            key = it.get(field) or "Non spécifié"
            counts[key] = counts.get(key, 0) + 1
        return sorted(counts.items(), key=lambda kv: -kv[1])

    par_region = _geo_counts(menages, "region")
    par_prefecture = _geo_counts(menages, "prefecture")
    par_village = _geo_counts(menages, "village")[:15]  # top 15

    # --- Sexe / démographie des individus ---
    sexe_counts = {"Masculin": 0, "Féminin": 0, "Non spécifié": 0}
    age_buckets = {"0-17": 0, "18-35": 0, "36-60": 0, "61+": 0, "Non spécifié": 0}
    total_individus = 0
    for m in menages:
        for ind in m.get("individus", []):
            total_individus += 1
            sexe = (ind.get("sexe") or "").strip()
            if sexe.lower().startswith("m"):
                sexe_counts["Masculin"] += 1
            elif sexe.lower().startswith("f"):
                sexe_counts["Féminin"] += 1
            else:
                sexe_counts["Non spécifié"] += 1
            age = _compute_age(ind.get("dateNaissance"))
            if age is not None:
                if age < 18:
                    age_buckets["0-17"] += 1
                elif age < 36:
                    age_buckets["18-35"] += 1
                elif age <= 60:
                    age_buckets["36-60"] += 1
                else:
                    age_buckets["61+"] += 1
            else:
                age_buckets["Non spécifié"] += 1

    # --- Types de terrain / cultures / structures (top items by frequency) ---
    def _top(counter_dict, n=10):
        return sorted(counter_dict.items(), key=lambda kv: -kv[1])[:n]

    type_terrain_counts = {}
    culture_annuelle_counts = {}
    culture_perenne_counts = {}
    espece_sauvage_counts = {}
    bois_doeuvre_counts = {}
    total_parcelles = 0
    total_arbres = 0
    for ch in champs:
        for p in ch.get("parcelles", []):
            total_parcelles += 1
            tdt = p.get("typeDeTerrain") or "Non spécifié"
            type_terrain_counts[tdt] = type_terrain_counts.get(tdt, 0) + 1
            for champ_agr in p.get("champs", []):
                cu = champ_agr.get("culture") or "Non spécifié"
                culture_annuelle_counts[cu] = culture_annuelle_counts.get(cu, 0) + 1
            for arbre in p.get("arbres", []):
                total_arbres += 1
                t = arbre.get("typeArbre")
                esp = arbre.get("especeArbre") or "Non spécifié"
                if t == "cultures_perennes":
                    culture_perenne_counts[esp] = culture_perenne_counts.get(esp, 0) + 1
                elif t == "especes_sauvages":
                    espece_sauvage_counts[esp] = espece_sauvage_counts.get(esp, 0) + 1
                elif t == "bois_doeuvre":
                    bois_doeuvre_counts[esp] = bois_doeuvre_counts.get(esp, 0) + 1

    type_structure_counts = {}
    for s in structures:
        for st in s.get("structures", []):
            t = st.get("typeDeStructure") or "Non spécifié"
            type_structure_counts[t] = type_structure_counts.get(t, 0) + 1

    # --- Montant total détaillé par catégorie (across all PAP, no merging
    #     needed here since this is a GLOBAL sum, not per-contract) ---
    global_summary = compute_global(champs, structures)
    montant_par_categorie = [
        ("Parcelles (terrain)", round(global_summary.parcelles)),
        ("Cultures annuelles", round(global_summary.champs_cultures_annuelles)),
        ("Cultures pérennes", round(global_summary.cultures_perennes)),
        ("Espèces sauvages", round(global_summary.especes_sauvages)),
        ("Bois d'œuvre", round(global_summary.bois_doeuvre)),
        ("Ressources naturelles", round(global_summary.ressources)),
        ("Structures / habitations", round(global_summary.structures)),
    ]

    # --- Activité de synchronisation dans le temps (par jour, 14 derniers) ---
    sync_by_day = {}
    for row in db.recent_syncs(200):
        day = (row.get("synced_at") or "")[:10]
        if not day:
            continue
        sync_by_day[day] = sync_by_day.get(day, 0) + 1
    sync_timeline = sorted(sync_by_day.items())[-14:]

    # --- Répartition par lot (nombre de contrats, PAS de PAP fusionnés) ---
    batches = _distinct_batches(champs, structures)
    contracts_per_batch = []
    for b in batches:
        rows = _contract_rows_for_batch(menages, champs, structures, b)
        contracts_per_batch.append({
            "num_batch": b,
            "owners_count": _distinct_owner_count(rows),
            "contracts_count": len(rows),
        })

    # --- PAP avec plusieurs enquêtes champs (contrats non fusionnés) ---
    # Each champs record now carries its own auto-generated "code de
    # l'enquête" = concat(code_proprietaire, '-', num_enquete_champ), so a
    # PAP with N champs records has N distinct code_enquete values (one per
    # future contract). We surface those codes explicitly here.
    per_owner_champ_count = {}
    per_owner_codes_enquete = {}
    for ch in champs:
        code = ch.get("codeProprietaire", "")
        if code:
            per_owner_champ_count[code] = per_owner_champ_count.get(code, 0) + 1
            per_owner_codes_enquete.setdefault(code, []).append(
                code_enquete_for_champ(ch)
            )
    multi_record_owners = [
        {
            "code": code,
            "nom": next(
                (ch.get("proprietaireNom", "") for ch in champs if ch.get("codeProprietaire") == code),
                "",
            ),
            "count": cnt,
            "codes_enquete": per_owner_codes_enquete.get(code, []),
        }
        for code, cnt in per_owner_champ_count.items() if cnt > 1
    ]
    multi_record_owners.sort(key=lambda o: -o["count"])

    # --- Statistiques sur les nouveaux codes auto-générés ---
    # code_enquete: un par enquête champs (concat codeProprietaire-numEnqueteChamp)
    # code_parcelle: un par parcelle (concat code_enquete-numOrdreParcelle)
    # code_champ: un par champ cultivé (concat code_parcelle-numOrdreChamps)
    codes_enquete_set = set()
    codes_parcelle_set = set()
    codes_champ_set = set()
    total_parcelles_sans_code = 0
    total_champs_sans_code = 0
    for ch in champs:
        ce = code_enquete_for_champ(ch)
        if ce:
            codes_enquete_set.add(ce)
        for p in ch.get("parcelles", []):
            cp = p.get("codeParcelle", "")
            if cp:
                codes_parcelle_set.add(cp)
            else:
                total_parcelles_sans_code += 1
            for champ_agr in p.get("champs", []):
                cc = champ_agr.get("codeChamp", "")
                if cc:
                    codes_champ_set.add(cc)
                else:
                    total_champs_sans_code += 1

    distinct_owner_codes = {ch.get("codeProprietaire", "") for ch in champs if ch.get("codeProprietaire")}
    codes_summary = {
        "distinct_pap": len(distinct_owner_codes),
        "distinct_codes_enquete": len(codes_enquete_set),
        "total_enquetes_champs": len(champs),
        "distinct_codes_parcelle": len(codes_parcelle_set),
        "total_parcelles_sans_code": total_parcelles_sans_code,
        "distinct_codes_champ": len(codes_champ_set),
        "total_champs_sans_code": total_champs_sans_code,
    }

    return render_template(
        "dashboard_stats.html",
        counts=c,
        total_individus=total_individus,
        total_parcelles=total_parcelles,
        total_arbres=total_arbres,
        type_contrat_counts=type_contrat_counts,
        par_region=par_region,
        par_prefecture=par_prefecture,
        par_village=par_village,
        sexe_counts=sexe_counts,
        age_buckets=age_buckets,
        type_terrain_counts=_top(type_terrain_counts),
        culture_annuelle_counts=_top(culture_annuelle_counts),
        culture_perenne_counts=_top(culture_perenne_counts),
        espece_sauvage_counts=_top(espece_sauvage_counts),
        bois_doeuvre_counts=_top(bois_doeuvre_counts),
        type_structure_counts=_top(type_structure_counts, 15),
        montant_par_categorie=montant_par_categorie,
        total_montant=round(global_summary.total),
        sync_timeline=sync_timeline,
        contracts_per_batch=contracts_per_batch,
        multi_record_owners=multi_record_owners,
        codes_summary=codes_summary,
        now=datetime.now(),
    )


# ---------------------------------------------------------------------------
# Contracts listing + PDF export
# ---------------------------------------------------------------------------

@app.route("/contracts")
def contracts_list():
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    batch_filter = request.args.get("batch", "")
    batches = _distinct_batches(champs, structures)

    rows = _contract_rows_for_batch(menages, champs, structures, batch_filter)
    # Sort by numBatch then nom then num_enquete (so multi-record PAP appear
    # grouped together, in survey order)
    rows.sort(
        key=lambda o: (
            o.get("numBatch", ""),
            o.get("nom", ""),
            o.get("num_enquete") or 0,
        )
    )

    distinct_owners = _distinct_owner_count(rows)

    return render_template(
        "contracts.html",
        owners=rows,
        batches=batches,
        selected_batch=batch_filter,
        distinct_owners=distinct_owners,
        contracts_count=len(rows),
    )


@app.route("/contracts/export/<code_individu>")
def export_contract(code_individu):
    """Exports a contract PDF.

    IMPORTANT: contracts are generated PER CHAMPS RECORD, not per owner.
    When a PAP (propriétaire) has several distinct "enquêtes champs"
    records, pass ``champ_id`` in the query string to select exactly which
    record's contract to generate; each record produces its own separate,
    non-merged contract. If ``champ_id`` is omitted, the first matching
    champs record for that owner is used (kept for backward compatibility
    with old links / structure-only or ménage-only owners).
    """
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()

    contract_type = request.args.get("type", "")
    champ_id = request.args.get("champ_id", "")

    # Try to find as a chef de menage first (ménage-based contract, no
    # champs record involved at all)
    menage_match = None
    for m in menages:
        chef = _chef_of(m)
        if chef and chef.get("id") == code_individu:
            menage_match = m
            break

    champ_match = None
    if menage_match is None:
        # Find via champ owner - if champ_id was given, match that EXACT
        # record (required for the non-merged, per-record contract
        # behaviour); otherwise fall back to the first matching record.
        if champ_id:
            champ_match = next(
                (c for c in champs if c.get("id") == champ_id
                 and c.get("codeProprietaire") == code_individu),
                None,
            )
        if champ_match is None:
            for c in champs:
                if c.get("codeProprietaire") == code_individu:
                    champ_match = c
                    break
        if champ_match is None:
            for s in structures:
                if s.get("proprietaireStructure") == code_individu:
                    # Build a minimal champ-like dict from structure for header fields
                    champ_match = {
                        "numBatch": s.get("numBatch", ""),
                        "codeMenage": s.get("codeMenage", ""),
                        "region": s.get("region", ""),
                        "prefecture": s.get("prefecture", ""),
                        "sousPrefecture": s.get("sousPrefecture", ""),
                        "district": s.get("district", ""),
                        "village": s.get("village", ""),
                        "dateEnquete": s.get("dateEnquete", ""),
                    }
                    break

    if menage_match is None and champ_match is None:
        abort(404, description="Owner not found")

    if menage_match is not None:
        d = build_contract_data(menage=menage_match)
        summary = compute_for_owner(champs, structures, code_individu)
        out_suffix = code_individu
    else:
        individu = _individu_lookup(menages, champ_match.get("codeMenage", ""), code_individu) or {
            "id": code_individu,
            "nomPrenom": "",
        }
        if not contract_type:
            tt = (champ_match.get("typeDePropriete", "") or "").lower()
            if "ligna" in tt:
                contract_type = "lignage"
            elif "communaut" in tt:
                contract_type = "communautaire"
            else:
                contract_type = "proprietaire"
        d = build_contract_data(champ=champ_match, individu=individu, contract_type=contract_type)

        # Non-merge rule: this contract accounts ONLY for champ_match's own
        # champs record. Structures are only included if this is the
        # first/only champs record for this owner (avoids double-billing a
        # PAP's habitation across multiple separate contracts) - detected
        # by checking whether this is the earliest-created champs record
        # for that owner among all of that owner's records.
        owner_champs = [c for c in champs if c.get("codeProprietaire") == code_individu]
        is_first_record = True
        if len(owner_champs) > 1 and champ_match.get("id"):
            owner_champs_sorted = sorted(
                owner_champs,
                key=lambda c: (c.get("numEnqueteChamp", 1), c.get("createdAt", "")),
            )
            is_first_record = owner_champs_sorted[0].get("id") == champ_match.get("id")

        if champ_match.get("id"):
            summary = compute_for_champ_record(
                champ_match, structures, code_individu,
                include_structures=is_first_record,
            )
            out_suffix = f"{code_individu}_{champ_match.get('numEnqueteChamp', 1)}"
        else:
            # Structure-only or ménage-fallback owner (no actual champs
            # record) - keep the previous merged/global behaviour since
            # there is only ever one contract for this PAP in that case.
            summary = compute_for_owner(champs, structures, code_individu)
            out_suffix = code_individu

    pdf_bytes = generate_contract_pdf(d, summary)

    filename = f"Contrat_{d.get('numeroLot', code_individu)}_{out_suffix}.pdf"
    return send_file(
        io.BytesIO(pdf_bytes),
        mimetype="application/pdf",
        as_attachment=True,
        download_name=filename,
    )


# ---------------------------------------------------------------------------
# Compensation table export (.xlsx)
# ---------------------------------------------------------------------------

@app.route("/compensation")
def compensation_page():
    champs = db.all_champs()
    structures = db.all_structures()
    batches = _distinct_batches(champs, structures)
    return render_template("compensation.html", batches=batches)


@app.route("/compensation/export")
def compensation_export():
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    num_batch = request.args.get("batch", "")
    villages_label = request.args.get("village", "")

    excel_bytes, meta = build_compensation_table(
        menages, champs, structures,
        num_batch=num_batch, villages_label=villages_label,
    )
    filename = f"Tableau_Indemnisation_{num_batch or 'GLOBAL'}.xlsx"
    return send_file(
        io.BytesIO(excel_bytes),
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        as_attachment=True,
        download_name=filename,
    )


# ---------------------------------------------------------------------------
# Ménages (household list, including members)
# ---------------------------------------------------------------------------

@app.route("/menages")
def menages_list():
    menages = db.all_menages()
    search = (request.args.get("q", "") or "").strip().lower()
    village_filter = request.args.get("village", "")

    villages = sorted({m.get("village", "") for m in menages if m.get("village")})

    rows = []
    for m in menages:
        chef = _chef_of(m) or {}
        if village_filter and m.get("village", "") != village_filter:
            continue
        if search:
            haystack = " ".join([
                m.get("codeMenage", ""),
                chef.get("nomPrenom", ""),
                m.get("village", ""),
                m.get("district", ""),
            ]).lower()
            if search not in haystack:
                continue
        rows.append({
            "id": m.get("id"),
            "codeMenage": m.get("codeMenage", ""),
            "chef_nom": chef.get("nomPrenom", ""),
            "nb_individus": len(m.get("individus", [])),
            "village": m.get("village", ""),
            "district": m.get("district", ""),
            "sousPrefecture": m.get("sousPrefecture", ""),
            "prefecture": m.get("prefecture", ""),
            "region": m.get("region", ""),
            "dateEnquete": (m.get("dateEnquete") or "")[:10],
        })

    rows.sort(key=lambda r: (r["village"], r["chef_nom"]))

    return render_template(
        "menages.html",
        rows=rows,
        villages=villages,
        search=search,
        selected_village=village_filter,
        total_menages=len(menages),
    )


@app.route("/menages/<menage_id>")
def menage_detail(menage_id):
    menage = db.menage_by_id(menage_id)
    if not menage:
        abort(404, description="Ménage introuvable")

    champs = db.all_champs()
    structures = db.all_structures()

    individus = []
    for ind in menage.get("individus", []):
        age = _compute_age(ind.get("dateNaissance"))
        nb_enquetes_champ = sum(
            1 for c in champs if c.get("codeProprietaire") == ind.get("id")
        )
        nb_enquetes_structure = sum(
            1 for s in structures if s.get("proprietaireStructure") == ind.get("id")
        )
        individus.append({
            **ind,
            "age": age,
            "nb_enquetes_champ": nb_enquetes_champ,
            "nb_enquetes_structure": nb_enquetes_structure,
        })

    return render_template(
        "menage_detail.html",
        menage=menage,
        individus=individus,
    )


# ---------------------------------------------------------------------------
# Rapport (synthèse imprimable de l'état d'avancement de l'enquête)
# ---------------------------------------------------------------------------

@app.route("/rapport")
def rapport_page():
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()

    total_individus = sum(len(m.get("individus", [])) for m in menages)
    total_superficie = 0.0
    for ch in champs:
        for p in ch.get("parcelles", []):
            total_superficie += p.get("superficieParcelle", 0) or 0

    global_summary = compute_global(champs, structures)
    batches = _distinct_batches(champs, structures)

    batch_report_rows = []
    for b in batches:
        rows = _contract_rows_for_batch(menages, champs, structures, b)
        total_montant = _total_montant_for_rows(champs, structures, rows)
        villages = sorted({r["village"] for r in rows if r.get("village")})
        batch_report_rows.append({
            "num_batch": b,
            "owners_count": _distinct_owner_count(rows),
            "contracts_count": len(rows),
            "total_montant": total_montant,
            "villages": ", ".join(villages) if villages else "—",
        })

    recent_syncs = db.recent_syncs(15)

    return render_template(
        "rapport.html",
        menages_count=len(menages),
        total_individus=total_individus,
        champs_count=len(champs),
        structures_count=len(structures),
        total_superficie=round(total_superficie, 2),
        total_montant=round(global_summary.total),
        montant_par_categorie=[
            ("Parcelles (terrain)", round(global_summary.parcelles)),
            ("Cultures annuelles", round(global_summary.champs_cultures_annuelles)),
            ("Cultures pérennes", round(global_summary.cultures_perennes)),
            ("Espèces sauvages", round(global_summary.especes_sauvages)),
            ("Bois d'œuvre", round(global_summary.bois_doeuvre)),
            ("Ressources naturelles", round(global_summary.ressources)),
            ("Structures / habitations", round(global_summary.structures)),
        ],
        batch_report_rows=batch_report_rows,
        recent_syncs=recent_syncs,
        now=datetime.now(),
    )


# ---------------------------------------------------------------------------
# Facturation (tableau de facturation par lot / par PAP)
# ---------------------------------------------------------------------------

@app.route("/facturation")
def facturation_page():
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    batch_filter = request.args.get("batch", "")
    batches = _distinct_batches(champs, structures)

    rows = _contract_rows_for_batch(menages, champs, structures, batch_filter)
    rows.sort(key=lambda o: (o.get("numBatch", ""), o.get("nom", "")))

    facture_rows = []
    grand_total = 0.0
    for r in rows:
        summary = _summary_for_row(champs, structures, r)
        montant = summary.total
        grand_total += montant
        facture_rows.append({
            **r,
            "montant_parcelles": round(summary.parcelles),
            "montant_cultures_annuelles": round(summary.champs_cultures_annuelles),
            "montant_cultures_perennes": round(summary.cultures_perennes),
            "montant_especes_sauvages": round(summary.especes_sauvages),
            "montant_bois_doeuvre": round(summary.bois_doeuvre),
            "montant_structures": round(summary.structures),
            "montant_total": round(montant),
        })

    return render_template(
        "facturation.html",
        rows=facture_rows,
        batches=batches,
        selected_batch=batch_filter,
        grand_total=round(grand_total),
        contracts_count=len(facture_rows),
    )


@app.route("/facturation/export")
def facturation_export():
    """Exports the billing table as .xlsx (same figures as /facturation,
    one row per contract - i.e. per champs record, not merged per PAP)."""
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment

    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()
    batch_filter = request.args.get("batch", "")

    rows = _contract_rows_for_batch(menages, champs, structures, batch_filter)
    rows.sort(key=lambda o: (o.get("numBatch", ""), o.get("nom", "")))

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Facturation"

    headers = [
        "N° de lot", "Nom et prénom", "Code individu", "N° enquête",
        "Type de contrat", "Village",
        "Parcelles (GNF)", "Cultures annuelles (GNF)", "Cultures pérennes (GNF)",
        "Espèces sauvages (GNF)", "Bois d'œuvre (GNF)", "Structures (GNF)",
        "Montant total (GNF)",
    ]
    ws.append(headers)
    header_fill = PatternFill(start_color="6B1F1F", end_color="6B1F1F", fill_type="solid")
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")

    grand_total = 0.0
    for r in rows:
        summary = _summary_for_row(champs, structures, r)
        grand_total += summary.total
        ws.append([
            r.get("numBatch") or r.get("codeMenage", ""),
            r.get("nom", ""),
            r.get("code", ""),
            r.get("num_enquete") or "",
            r.get("type_contrat", ""),
            r.get("village", ""),
            round(summary.parcelles),
            round(summary.champs_cultures_annuelles),
            round(summary.cultures_perennes),
            round(summary.especes_sauvages),
            round(summary.bois_doeuvre),
            round(summary.structures),
            round(summary.total),
        ])

    ws.append([])
    total_row = ["", "", "", "", "", "TOTAL GÉNÉRAL", "", "", "", "", "", "", round(grand_total)]
    ws.append(total_row)
    for cell in ws[ws.max_row]:
        cell.font = Font(bold=True)

    for col_idx, width in enumerate(
        [14, 24, 16, 10, 16, 16, 16, 18, 18, 18, 16, 16, 16], start=1
    ):
        ws.column_dimensions[ws.cell(row=1, column=col_idx).column_letter].width = width

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    filename = f"Facturation_{batch_filter or 'GLOBAL'}.xlsx"
    return send_file(
        buf,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        as_attachment=True,
        download_name=filename,
    )


# ---------------------------------------------------------------------------
# Sync API (receives data from the OKAPI Survey mobile app)
# ---------------------------------------------------------------------------

@app.route("/api/sync", methods=["POST"])
def api_sync():
    payload = request.get_json(force=True, silent=True) or {}
    device_id = payload.get("deviceId", "") or request.headers.get("X-Device-Id", "")
    device_name = payload.get("deviceName", "") or request.headers.get("X-Device-Name", "")

    menages = payload.get("menages", [])
    champs = payload.get("champs", [])
    structures = payload.get("structures", [])

    for m in menages:
        db.upsert_menage(m, device_id)
    for c in champs:
        db.upsert_champ(c, device_id)
    for s in structures:
        db.upsert_structure(s, device_id)

    counts = {
        "menages": len(menages),
        "champs": len(champs),
        "structures": len(structures),
    }
    db.log_sync(device_id, device_name, counts)

    return jsonify({
        "status": "ok",
        "received": counts,
        "server_totals": db.counts(),
        "synced_at": datetime.now().isoformat(),
    })


@app.route("/api/pull", methods=["GET", "OPTIONS"])
def api_pull():
    """Cross-tablet sync (pull side): lets a tablet fetch ALL menages,
    champs and structures currently stored on the server - including ones
    pushed there by OTHER tablets - so that pressing "Actualiser" on one
    tablet immediately makes households registered on another tablet
    available in its own local Champs/Structures survey forms."""
    if request.method == "OPTIONS":
        return ("", 204)
    return jsonify({
        "status": "ok",
        "menages": db.all_menages(),
        "champs": db.all_champs(),
        "structures": db.all_structures(),
        "totals": db.counts(),
        "pulled_at": datetime.now().isoformat(),
    })


@app.route("/api/status")
def api_status():
    return jsonify({
        "status": "online",
        "app": "OKAPI Survey Web Admin",
        "totals": db.counts(),
        "time": datetime.now().isoformat(),
    })


# ---------------------------------------------------------------------------
# Authentication API (mobile app self-registration + login + admin approval)
# ---------------------------------------------------------------------------

def _user_public(u: dict):
    """Returns the user dict WITHOUT the password hash, for API responses."""
    return {
        "id": u.get("id"),
        "nomPrenom": u.get("nom_prenom"),
        "telephone": u.get("telephone"),
        "username": u.get("username"),
        "sexe": u.get("sexe"),
        "statut": u.get("statut"),
        "approvalStatus": u.get("approval_status"),
        "createdAt": u.get("created_at"),
        "approvedAt": u.get("approved_at"),
    }


@app.route("/api/register", methods=["POST", "OPTIONS"])
def api_register():
    if request.method == "OPTIONS":
        return ("", 204)
    payload = request.get_json(force=True, silent=True) or {}
    nom_prenom = (payload.get("nomPrenom") or "").strip()
    telephone = (payload.get("telephone") or "").strip()
    username = (payload.get("username") or "").strip().lower()
    password = payload.get("password") or ""
    sexe = (payload.get("sexe") or "").strip()
    statut = (payload.get("statut") or "").strip()

    if not nom_prenom or not username or not password:
        return jsonify({
            "status": "error",
            "message": "Nom/prénom, nom d'utilisateur et mot de passe sont obligatoires.",
        }), 400

    if len(password) < 4:
        return jsonify({
            "status": "error",
            "message": "Le mot de passe doit contenir au moins 4 caractères.",
        }), 400

    if db.get_user_by_username(username):
        return jsonify({
            "status": "error",
            "message": "Ce nom d'utilisateur est déjà utilisé.",
        }), 409

    user_id = str(uuid.uuid4())
    password_hash = generate_password_hash(password)
    try:
        db.create_user(user_id, nom_prenom, telephone, username, password_hash, sexe, statut)
    except sqlite3.IntegrityError:
        return jsonify({
            "status": "error",
            "message": "Ce nom d'utilisateur est déjà utilisé.",
        }), 409

    return jsonify({
        "status": "ok",
        "message": "Compte créé. En attente de validation par un administrateur.",
        "user": _user_public(db.get_user_by_id(user_id)),
    })


@app.route("/api/login", methods=["POST", "OPTIONS"])
def api_login():
    if request.method == "OPTIONS":
        return ("", 204)
    payload = request.get_json(force=True, silent=True) or {}
    username = (payload.get("username") or "").strip().lower()
    password = payload.get("password") or ""

    user = db.get_user_by_username(username)
    if not user or not check_password_hash(user["password_hash"], password):
        return jsonify({
            "status": "error",
            "message": "Nom d'utilisateur ou mot de passe incorrect.",
        }), 401

    if user["approval_status"] == "pending":
        return jsonify({
            "status": "pending",
            "message": "Votre compte est en attente de validation par un administrateur.",
        }), 403

    if user["approval_status"] == "rejected":
        return jsonify({
            "status": "rejected",
            "message": "Votre demande de compte a été refusée. Contactez un administrateur.",
        }), 403

    return jsonify({
        "status": "ok",
        "message": "Connexion réussie.",
        "user": _user_public(user),
    })


@app.route("/api/users/<user_id>/status", methods=["GET", "OPTIONS"])
def api_user_status(user_id):
    """Lets the mobile app re-check whether a still-pending account has since
    been approved/rejected, without requiring the password again."""
    if request.method == "OPTIONS":
        return ("", 204)
    user = db.get_user_by_id(user_id)
    if not user:
        return jsonify({"status": "error", "message": "Utilisateur introuvable."}), 404
    return jsonify({"status": "ok", "user": _user_public(user)})


# ---------------------------------------------------------------------------
# Admin: user management (approve / reject registrations)
# ---------------------------------------------------------------------------

@app.route("/users")
def users_list():
    users = db.all_users()
    counts = db.users_counts()
    return render_template("users.html", users=users, counts=counts)


@app.route("/users/<user_id>/approve", methods=["POST"])
def user_approve(user_id):
    db.set_user_approval(user_id, "approved", approved_by="admin")
    return ("", 204) if request.args.get("ajax") else _redirect_users()


@app.route("/users/<user_id>/reject", methods=["POST"])
def user_reject(user_id):
    db.set_user_approval(user_id, "rejected", approved_by="admin")
    return ("", 204) if request.args.get("ajax") else _redirect_users()


@app.route("/users/<user_id>/delete", methods=["POST"])
def user_delete(user_id):
    db.delete_user(user_id)
    return ("", 204) if request.args.get("ajax") else _redirect_users()


def _redirect_users():
    from flask import redirect, url_for
    return redirect(url_for("users_list"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5070, debug=False)
