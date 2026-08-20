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
from datetime import datetime

from flask import Flask, render_template, request, jsonify, send_file, abort

import db
from compensation import compute_for_owner, compute_global
from contract_pdf import build_contract_data, generate_contract_pdf
from excel_export import build_compensation_table

app = Flask(__name__)
app.config["JSON_AS_ASCII"] = False

db.init_db()


@app.template_filter("fromjson")
def _fromjson_filter(s):
    try:
        return json.loads(s) if s else {}
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _chef_of(menage: dict):
    for ind in menage.get("individus", []):
        if ind.get("relationCdm") == "Chef de menage":
            return ind
    if menage.get("individus"):
        return menage["individus"][0]
    return None


def _individu_lookup(menages, code_menage, code_individu):
    for m in menages:
        if m.get("codeMenage") == code_menage or m.get("id") == code_menage:
            for ind in m.get("individus", []):
                if ind.get("id") == code_individu:
                    return ind
    return None


def _distinct_batches(champs, structures):
    batches = set()
    for c in champs:
        if c.get("numBatch"):
            batches.add(c["numBatch"])
    for s in structures:
        if s.get("numBatch"):
            batches.add(s["numBatch"])
    return sorted(batches)


def _owners_for_batch(menages, champs, structures, num_batch=""):
    """Returns a list of owner dicts: code, nom, type_contrat, village, numBatch."""
    owners = {}
    for c in champs:
        if num_batch and c.get("numBatch", "") != num_batch:
            continue
        code = c.get("codeProprietaire", "")
        if not code:
            continue
        ind = _individu_lookup(menages, c.get("codeMenage", ""), code) or {}
        owners.setdefault(code, {
            "code": code,
            "nom": ind.get("nomPrenom") or c.get("proprietaireNom", ""),
            "type_contrat": c.get("typeDePropriete", ""),
            "village": c.get("village", ""),
            "numBatch": c.get("numBatch", ""),
            "codeMenage": c.get("codeMenage", ""),
            "source": "champ",
        })
    for s in structures:
        if num_batch and s.get("numBatch", "") != num_batch:
            continue
        code = s.get("proprietaireStructure", "")
        if not code:
            continue
        ind = _individu_lookup(menages, s.get("codeMenage", ""), code) or {}
        owners.setdefault(code, {
            "code": code,
            "nom": ind.get("nomPrenom") or s.get("proprietaireNom", ""),
            "type_contrat": "Propriétaire",
            "village": s.get("village", ""),
            "numBatch": s.get("numBatch", ""),
            "codeMenage": s.get("codeMenage", ""),
            "source": "structure",
        })
    if not num_batch:
        for m in menages:
            chef = _chef_of(m)
            if chef and chef.get("id") not in owners:
                owners[chef.get("id")] = {
                    "code": chef.get("id"),
                    "nom": chef.get("nomPrenom", ""),
                    "type_contrat": "Propriétaire",
                    "village": m.get("village", ""),
                    "numBatch": m.get("codeMenage", ""),
                    "codeMenage": m.get("codeMenage", ""),
                    "source": "menage",
                }
    return list(owners.values())


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

def _total_montant_for_owners(champs, structures, owners):
    total = 0.0
    for o in owners:
        s = compute_for_owner(champs, structures, o["code"])
        total += s.total
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
        owners = _owners_for_batch(menages, champs, structures, b)
        total_montant = _total_montant_for_owners(champs, structures, owners)
        batch_rows.append({
            "num_batch": b,
            "owners_count": len(owners),
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

    owners = _owners_for_batch(menages, champs, structures, batch_filter)
    # Sort by numBatch then nom
    owners.sort(key=lambda o: (o.get("numBatch", ""), o.get("nom", "")))

    return render_template(
        "contracts.html",
        owners=owners,
        batches=batches,
        selected_batch=batch_filter,
    )


@app.route("/contracts/export/<code_individu>")
def export_contract(code_individu):
    menages = db.all_menages()
    champs = db.all_champs()
    structures = db.all_structures()

    contract_type = request.args.get("type", "")

    # Try to find as a chef de menage first
    menage_match = None
    for m in menages:
        chef = _chef_of(m)
        if chef and chef.get("id") == code_individu:
            menage_match = m
            break

    if menage_match is not None:
        d = build_contract_data(menage=menage_match)
    else:
        # Find via champ owner
        champ_match = None
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
        if champ_match is None:
            abort(404, description="Owner not found")
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

    summary = compute_for_owner(champs, structures, code_individu)
    pdf_bytes = generate_contract_pdf(d, summary)

    filename = f"Contrat_{d.get('numeroLot', code_individu)}_{code_individu}.pdf"
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


@app.route("/api/status")
def api_status():
    return jsonify({
        "status": "online",
        "app": "OKAPI Survey Web Admin",
        "totals": db.counts(),
        "time": datetime.now().isoformat(),
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5070, debug=False)
