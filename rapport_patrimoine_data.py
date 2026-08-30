"""Aggregation layer for the "Annuaire des sites de patrimoine culturel"
report, modeled after the uploaded reference document
(OKAPI_Annuaire des sites Patrimoine culturel.docx): a summary table
(VILLAGE / ZONE / NOM DU SITE / TYPE / SOUS-TYPE / IMPORTANCE) followed by
one detailed label/value table per site.

Computed LIVE from the `patrimoine_culturel` survey records synced from the
mobile app (SOCIAL module), via db.all_survey_records('patrimoine_culturel').
No schema changes are needed - the `patrimoine_culturel` XLSForm already
collects every field used below (see the uploaded
"Patrimoine culturel (SOCIAL).xlsx" reference).
"""
from datetime import datetime

import db


def _val(v, key, default="—"):
    x = v.get(key)
    if x is None:
        return default
    s = str(x).strip()
    return s if s else default


def _combine(v, keys, sep=" — "):
    parts = []
    for k in keys:
        val = v.get(k)
        if val is None:
            continue
        s = str(val).strip()
        if s:
            parts.append(s)
    return sep.join(parts) if parts else "—"


def _coord_str(v):
    coord = v.get("coord")
    if not coord:
        return "—", "—"
    try:
        parts = str(coord).split()
        lat = parts[0] if len(parts) > 0 else "—"
        lon = parts[1] if len(parts) > 1 else "—"
        return f"Latitude : {lat}", f"Longitude : {lon}"
    except Exception:
        return str(coord), "—"


def _sous_type(v):
    st = (v.get("sous_type_site") or "").strip()
    autre = (v.get("autre_sous_type_site") or "").strip()
    if st and "autre" in st.lower() and autre:
        return autre
    return st or "—"


def _liens_autres_sites(v):
    if (v.get("liens_autres_sites") or "").strip().lower() == "oui":
        return _val(v, "autres_sites_lies")
    return "Non"


def _tensions(v):
    if (v.get("tensions_conflits") or "").strip().lower() == "oui":
        return _val(v, "tensions_conflits_description")
    return "Non"


def _usage_site(v):
    us = (v.get("usage_site") or "").strip()
    autre = (v.get("autre_usage_site") or "").strip()
    if us and "autre" in us.lower() and autre:
        return autre
    return us or "—"


def _site_from_record(r):
    v = r.get("values") or {}
    lat, lon = _coord_str(v)
    nom_site = _val(v, "nom_site")
    identifiant = (v.get("identifiant") or "").strip()
    type_site = _val(v, "type_site")
    sous_type = _sous_type(v)

    detail_rows = [
        ("Signification du nom", _val(v, "signification_nom")),
        ("Type de site", f"{type_site} / {sous_type}" if sous_type != "—" else type_site),
        ("Degré d'importance", _val(v, "degre_importance")),
        ("Qualification du patrimoine", _val(v, "qualification_patrimoine")),
        ("Description / Artefacts", _combine(v, ["description", "artefacts"])),
        ("Histoire et pratiques socioculturelles", _val(v, "histoire")),
        ("Usages / Évolution / Fréquence", _combine(v, ["usages", "evolution", "frequence"])),
        ("Propriétaires / Officiants", _combine(v, ["proprietaires", "officiants"])),
        ("Usagers / Rayonnement", _combine(v, ["usagers", "rayonnement"])),
        ("Liens à autres sites", _liens_autres_sites(v)),
        ("Interdits / Accès", _combine(v, ["interdits", "acces"])),
        ("Impact hors mitigation", _val(v, "impact_hors_mitigation")),
        ("Destructible / Reproductible", _combine(v, ["destructible", "reproductible"])),
        ("Traitement", _val(v, "traitement")),
        ("Mitigation effets", _val(v, "mitigation_effets")),
        ("Temps avant traitement", _val(v, "temps_avant_traitement")),
        ("Durée de traitement", _val(v, "duree_traitement")),
        ("Prochaines étapes", _val(v, "prochaines_etapes")),
        ("Réaction de la communauté", _val(v, "reaction_communaute")),
        ("Tensions et conflits", _tensions(v)),
        ("Responsables du site", _val(v, "responsables_site")),
        ("Coordonnées GPS", f"{lat}    {lon}"),
    ]

    village = v.get("localite") or v.get("sous_prefecture") or "—"
    zone = v.get("composante") or _usage_site(v) or "—"

    return {
        "id": r.get("id"),
        "identifiant": identifiant,
        "nom_site": nom_site,
        "heading": f"{nom_site} – Id : {identifiant}" if identifiant and identifiant != "—" else nom_site,
        "village": village,
        "zone": zone,
        "type_site": type_site,
        "sous_type_site": sous_type,
        "importance": _val(v, "degre_importance"),
        "region": v.get("region") or "—",
        "prefecture": v.get("prefecture") or "—",
        "sous_prefecture": v.get("sous_prefecture") or "—",
        "detail_rows": detail_rows,
    }


def build_patrimoine_report_data():
    by_form = db.all_survey_records("patrimoine_culturel")
    records = by_form.get("patrimoine_culturel", [])
    sites = [_site_from_record(r) for r in records]
    sites.sort(key=lambda s: (s["village"] or "", s["nom_site"] or ""))

    summary_rows = [
        (s["village"], s["zone"], s["nom_site"], s["type_site"], s["sous_type_site"], s["importance"])
        for s in sites
    ]

    return {
        "sites": sites,
        "summary_rows": summary_rows,
        "count": len(sites),
        "generated_at": datetime.now(),
    }
