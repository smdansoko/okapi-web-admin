"""Shared helpers for building "one row per champs/structure/menage record"
listings, used both by the contract PDF export (app.py) and the
indemnification Excel export (excel_export.py). Extracted to its own module
to avoid a circular import between those two files.
"""


def chef_of(menage: dict):
    for ind in menage.get("individus", []):
        if ind.get("relationCdm") == "Chef de menage":
            return ind
    if menage.get("individus"):
        return menage["individus"][0]
    return None


def individu_lookup(menages, code_menage, code_individu):
    for m in menages:
        if m.get("codeMenage") == code_menage or m.get("id") == code_menage:
            for ind in m.get("individus", []):
                if ind.get("id") == code_individu:
                    return ind
    return None


def code_enquete_for_champ(champ: dict) -> str:
    """Computes the "code de l'enquête" survey code for a champs record:
    concat(code_proprietaire, '-', num_enquete_champ). Falls back to the
    bare code_proprietaire if numEnqueteChamp is missing (older records)."""
    code_prop = champ.get("codeProprietaire", "") or ""
    num_enquete = champ.get("numEnqueteChamp")
    if num_enquete is None or num_enquete == "":
        return code_prop
    return f"{code_prop}-{num_enquete}"


def distinct_batches(champs, structures):
    batches = set()
    for c in champs:
        if c.get("numBatch"):
            batches.add(c["numBatch"])
    for s in structures:
        if s.get("numBatch"):
            batches.add(s["numBatch"])
    return sorted(batches)


def contract_rows_for_batch(menages, champs, structures, num_batch=""):
    """Returns a list of contract-row dicts, ONE ROW PER CHAMPS RECORD.

    IMPORTANT (per user requirement): when the same PAP (propriétaire) has
    several distinct "enquêtes champs" records, each record must produce
    its OWN separate contract - they must NOT be merged into a single
    combined contract. So unlike a plain "distinct owners" list, this
    function may return several rows sharing the same owner `code`, one
    per champs record (`champ_id` distinguishes them), meaning:
        number of champs-based rows for a PAP == number of contracts for
        that PAP.

    Each row dict has: code, champ_id ("" if not champ-based), nom,
    type_contrat, village, numBatch, codeMenage, source, num_enquete
    (the numEnqueteChamp value, or None), code_enquete (the computed
    "code de l'enquête" survey code, or "" if not champ-based), and
    include_structures (True only for the FIRST row belonging to a given
    owner code, so that a PAP's structures/habitation are billed on
    exactly ONE of their contracts, never duplicated across multiple
    contracts nor omitted).
    """
    rows = []
    codes_with_champ_rows = set()
    for c in champs:
        if num_batch and c.get("numBatch", "") != num_batch:
            continue
        code = c.get("codeProprietaire", "")
        if not code:
            continue
        ind = individu_lookup(menages, c.get("codeMenage", ""), code) or {}
        rows.append({
            "code": code,
            "champ_id": c.get("id", ""),
            "nom": ind.get("nomPrenom") or c.get("proprietaireNom", ""),
            "type_contrat": c.get("typeDePropriete", ""),
            "village": c.get("village", ""),
            "numBatch": c.get("numBatch", ""),
            "codeMenage": c.get("codeMenage", ""),
            "source": "champ",
            "num_enquete": c.get("numEnqueteChamp", 1),
            "code_enquete": code_enquete_for_champ(c),
        })
        codes_with_champ_rows.add(code)

    existing_codes_no_champ = set()
    for s in structures:
        if num_batch and s.get("numBatch", "") != num_batch:
            continue
        code = s.get("proprietaireStructure", "")
        if not code:
            continue
        if code in codes_with_champ_rows:
            # This owner already has at least one champs-based contract row
            # - their structures/habitation will be billed on that record
            # (see include_structures below), so no separate row is added
            # here to avoid a duplicate/second contract for the same PAP.
            continue
        if code in existing_codes_no_champ:
            continue
        ind = individu_lookup(menages, s.get("codeMenage", ""), code) or {}
        rows.append({
            "code": code,
            "champ_id": "",
            "nom": ind.get("nomPrenom") or s.get("proprietaireNom", ""),
            "type_contrat": "Propriétaire",
            "village": s.get("village", ""),
            "numBatch": s.get("numBatch", ""),
            "codeMenage": s.get("codeMenage", ""),
            "source": "structure",
            "num_enquete": None,
            "code_enquete": "",
        })
        existing_codes_no_champ.add(code)

    if not num_batch:
        known_codes = codes_with_champ_rows | existing_codes_no_champ
        for m in menages:
            chef = chef_of(m)
            if chef and chef.get("id") not in known_codes:
                rows.append({
                    "code": chef.get("id"),
                    "champ_id": "",
                    "nom": chef.get("nomPrenom", ""),
                    "type_contrat": "Propriétaire",
                    "village": m.get("village", ""),
                    "numBatch": m.get("codeMenage", ""),
                    "codeMenage": m.get("codeMenage", ""),
                    "source": "menage",
                    "num_enquete": None,
                    "code_enquete": "",
                })
                known_codes.add(chef.get("id"))

    # Mark, per owner code, which row is the FIRST one encountered so that
    # exactly one contract per PAP carries their structures/habitation.
    seen_for_structures = set()
    for r in rows:
        r["include_structures"] = r["code"] not in seen_for_structures
        seen_for_structures.add(r["code"])

    return rows


def distinct_owner_count(rows):
    return len({r["code"] for r in rows})
