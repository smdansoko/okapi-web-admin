"""Python port of lib/services/compensation_calculator.dart.

Computes the same compensation breakdown (per PAP / owner) as the Flutter
mobile app, using the same price_matrix.json reference data, so that the
web admin's compensation table export exactly matches the mobile app's
contract PDF figures.
"""
import json
import math
import os

_DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

with open(os.path.join(_DATA_DIR, "price_matrix.json"), encoding="utf-8") as f:
    PRICE_MATRIX = json.load(f)

_TERRAINS = PRICE_MATRIX.get("terrains", [])
_CULTURES_ANNUELLES = PRICE_MATRIX.get("cultures_annuelles", [])
_CULTURES_PERENNES = PRICE_MATRIX.get("cultures_perennes", [])
_ESPECES_SAUVAGES = PRICE_MATRIX.get("especes_sauvages", [])
_BOIS_DOEUVRE = PRICE_MATRIX.get("bois_doeuvre", [])
_STRUCTURES = PRICE_MATRIX.get("structures", [])

_AUTRES_STRUCTURES_MAP = {
    "Douche Moderne (Piece)": ("Douche moderne", "piece"),
    "WC traditionnel": ("WC traditionnel", "piece"),
    "WC modeme": ("WC moderne (avec ciment)", "piece"),
    "Fosse septique étayée mètre cube": ("Fosse septique étayée", "sol"),
    "Dalle de fosse en béton armé (avec ou sans trappe métallique m2)": (
        "Dalle de fosse en béton armé (avec ou sans trappe métallique)",
        "sol",
    ),
    "Puits traditionnel étayé mètre linéaire": (
        "Puits traditionnel / Fosse septique étayée",
        "longueur",
    ),
    "Puits moderne busé avec pompe manuelle pièce": (
        "Puits moderne busé avec pompe manuelle",
        "piece",
    ),
    "Abris pour animaux en tôles et planches m2": (
        "Abris pour animaux en tôles et planches",
        "sol",
    ),
    "Poulailler en brique creuse et toles piece": (
        "Poulailler en briques creuses et toles",
        "piece",
    ),
    "Hutte temporaire - abris dans les champs paille et bois": (
        "Hutte temporaire - abris dans les champs paille et bois",
        "piece",
    ),
}


def _find(lst, key, value):
    for e in lst:
        if e.get(key) == value:
            return e
    return None


class CompensationSummary:
    def __init__(self):
        self.parcelles = 0.0
        self.champs_cultures_annuelles = 0.0
        self.cultures_perennes = 0.0
        self.especes_sauvages = 0.0
        self.bois_doeuvre = 0.0
        self.ressources = 0.0
        self.structures = 0.0
        self.parcelle_details = []
        self.culture_annuelle_details = []
        self.culture_perenne_details = []
        self.espece_sauvage_details = []
        self.bois_doeuvre_details = []
        self.structure_details = []

    @property
    def total(self):
        return (
            self.parcelles
            + self.champs_cultures_annuelles
            + self.cultures_perennes
            + self.especes_sauvages
            + self.bois_doeuvre
            + self.ressources
            + self.structures
        )


def _accumulate_champs_enquete(summary: CompensationSummary, enquete: dict):
    for parcelle in enquete.get("parcelles", []):
        terrain = _find(_TERRAINS, "type", parcelle.get("typeDeTerrain"))
        cout_m2 = (terrain or {}).get("prix_compensation", 0) or 0
        superficie = parcelle.get("superficieParcelle", 0) or 0
        montant_parcelle = cout_m2 * superficie
        summary.parcelles += montant_parcelle
        if superficie > 0:
            summary.parcelle_details.append(
                {
                    "typeDeTerrain": parcelle.get("typeDeTerrain", ""),
                    "superficie": superficie,
                    "coutM2": cout_m2,
                    "montant": montant_parcelle,
                }
            )

        for champ in parcelle.get("champs", []):
            culture = _find(_CULTURES_ANNUELLES, "culture", champ.get("culture"))
            if culture:
                revenu_ha = culture.get("revenu_annuel_ha", 0) or 0
                superficie_champ = champ.get("superficieChamps", 0) or 0
                montant = revenu_ha * superficie_champ
                summary.champs_cultures_annuelles += montant
                if montant > 0:
                    summary.culture_annuelle_details.append(
                        {
                            "culture": champ.get("culture", ""),
                            "superficieHa": superficie_champ,
                            "revenuHa": revenu_ha,
                            "montant": montant,
                        }
                    )

        for arbre in parcelle.get("arbres", []):
            t = arbre.get("typeArbre")
            if t == "cultures_perennes":
                _accumulate_culture_perenne(summary, arbre.get("especeArbre"), arbre)
            elif t == "especes_sauvages":
                _accumulate_espece_sauvage(summary, arbre.get("especeArbre"), arbre)
            elif t == "bois_doeuvre":
                _accumulate_bois_doeuvre(summary, arbre.get("especeArbre"), arbre)


def _accumulate_culture_perenne(summary, espece, arbre):
    data = _find(_CULTURES_PERENNES, "nom_usuel", espece)
    if not data:
        return
    prix_plante = data.get("prix_plante", 0) or 0
    prix_jeune_np = data.get("prix_jeune_non_prod", 0) or 0
    prix_jeune_p = data.get("prix_jeune_prod", 0) or 0
    prix_adulte = data.get("prix_adulte", 0) or 0
    prix_adulte_decl = data.get("prix_adulte_declinant", 0) or 0

    plantules = arbre.get("nombrePlante") or 0
    jeunes_np = arbre.get("nombreJeuneNp") or 0
    jeunes_p = arbre.get("nombreJeuneP") or 0
    matures = arbre.get("nombreMature") or 0
    adulte_decl = arbre.get("nombreAdulteDeclinant") or 0

    montant = (
        plantules * prix_plante
        + jeunes_np * prix_jeune_np
        + jeunes_p * prix_jeune_p
        + matures * prix_adulte
        + adulte_decl * prix_adulte_decl
    )
    summary.cultures_perennes += montant
    if montant > 0:
        summary.culture_perenne_details.append(
            {
                "espece": espece,
                "plantules": plantules,
                "jeunesNp": jeunes_np,
                "jeunesP": jeunes_p,
                "matures": matures,
                "adulteDeclinant": adulte_decl,
                "prixPlante": prix_plante,
                "prixJeuneNp": prix_jeune_np,
                "prixJeuneP": prix_jeune_p,
                "prixAdulte": prix_adulte,
                "prixAdulteDeclinant": prix_adulte_decl,
                "montant": montant,
            }
        )


def _accumulate_espece_sauvage(summary, espece, arbre):
    data = _find(_ESPECES_SAUVAGES, "nom_usuel", espece)
    if not data:
        return
    prix_np = data.get("indemnisation_plant_non_productif", 0) or 0
    prix_p = data.get("revenu_brut_annuel_plant_productif", 0) or 0
    jeunes_np = arbre.get("nombreJeuneNp") or 0
    jeunes_p = arbre.get("nombreJeuneP") or 0
    montant = jeunes_np * prix_np + jeunes_p * prix_p
    summary.especes_sauvages += montant
    if montant > 0:
        summary.espece_sauvage_details.append(
            {
                "espece": espece,
                "jeunesNp": jeunes_np,
                "jeunesP": jeunes_p,
                "prixNp": prix_np,
                "prixP": prix_p,
                "montant": montant,
            }
        )


def _accumulate_bois_doeuvre(summary, espece, arbre):
    data = _find(_BOIS_DOEUVRE, "nom_usuel", espece)
    if not data:
        return
    valeur_m3 = data.get("valeur_bois_m3", 0) or 0
    hauteur = arbre.get("hauteur") or 0
    circonference = arbre.get("circonference") or 0
    nombre_pieds = arbre.get("nombreDePieds") or 0
    if hauteur <= 0 or circonference <= 0 or nombre_pieds <= 0:
        return
    rayon_equiv = circonference / math.pi
    volume_unitaire = (math.pi / 4) * (rayon_equiv * rayon_equiv) * hauteur
    volume_total = volume_unitaire * nombre_pieds
    montant = volume_total * valeur_m3
    summary.bois_doeuvre += montant
    summary.bois_doeuvre_details.append(
        {
            "espece": espece,
            "circonference": circonference,
            "hauteur": hauteur,
            "volumeUnitaire": volume_unitaire,
            "nombrePieds": nombre_pieds,
            "volumeTotal": volume_total,
            "prixUnitaire": valeur_m3,
            "montant": montant,
        }
    )


def _accumulate_structure_enquete(summary, enquete):
    for s in enquete.get("structures", []):
        type_structure = s.get("typeDeStructure", "")
        uses_materiaux = type_structure in (
            "Habitation et bien immobiliers",
            "Case Traditionnelle",
            "Batiment rectangulaire",
        )
        if uses_materiaux:
            _accumulate_habitation(summary, s)
        else:
            mapping = _AUTRES_STRUCTURES_MAP.get(type_structure)
            if not mapping:
                continue
            designation, qty_kind = mapping
            price_row = _find(_STRUCTURES, "designation", designation)
            if not price_row:
                continue
            prix_unitaire = price_row.get("prix_unitaire", 0) or 0
            if qty_kind == "piece":
                quantite = 1
            elif qty_kind == "sol":
                quantite = s.get("superficieSol", 0) or 0
            else:
                quantite = s.get("longueurProfondeur", 0) or 0
            montant = prix_unitaire * quantite
            summary.structures += montant
            if montant > 0:
                summary.structure_details.append(
                    {
                        "designation": designation,
                        "unite": price_row.get("unite", ""),
                        "quantite": quantite,
                        "prixUnitaire": prix_unitaire,
                        "montant": montant,
                    }
                )


def _accumulate_habitation(summary, s):
    def add_line(materiau_label, superficie):
        if not materiau_label or materiau_label == "Aucun":
            return
        price_row = _find(_STRUCTURES, "designation", materiau_label)
        if not price_row:
            return
        prix_unitaire = price_row.get("prix_unitaire", 0) or 0
        montant = prix_unitaire * superficie
        summary.structures_temp_total += montant
        if montant > 0:
            summary.structure_details.append(
                {
                    "designation": materiau_label,
                    "unite": price_row.get("unite", "m²"),
                    "quantite": superficie,
                    "prixUnitaire": prix_unitaire,
                    "montant": montant,
                }
            )

    summary.structures_temp_total = 0.0
    add_line(s.get("materiauxToit"), s.get("superficieToit", 0) or 0)
    add_line(s.get("materiauxMur"), s.get("superficieMur", 0) or 0)
    add_line(s.get("materiauxSol"), s.get("superficieSol", 0) or 0)
    add_line(s.get("materiauxCarrelage"), s.get("superficieSol", 0) or 0)
    add_line(s.get("materiauxFermeture"), s.get("superficieOuvertures", 0) or 0)
    add_line(s.get("materiauxPeinture"), s.get("superficieMur", 0) or 0)
    summary.structures += summary.structures_temp_total


def compute_for_owner(champs_enquetes, structure_enquetes, code_proprietaire):
    summary = CompensationSummary()
    for enquete in champs_enquetes:
        if enquete.get("codeProprietaire") == code_proprietaire:
            _accumulate_champs_enquete(summary, enquete)
    for enquete in structure_enquetes:
        if enquete.get("proprietaireStructure") == code_proprietaire:
            _accumulate_structure_enquete(summary, enquete)
    return summary


def compute_for_champ_record(champ_enquete, structure_enquetes, code_proprietaire,
                              include_structures=False):
    """Computes a compensation summary for a SINGLE champs-survey record.

    Unlike ``compute_for_owner`` (which merges *every* champs record
    belonging to the same PAP/owner into one combined summary), this
    function only accumulates the items found in ``champ_enquete`` itself.

    This supports the requirement that when the same PAP (propriétaire) has
    several distinct field-survey records ("enquêtes champs"), each record
    must produce its OWN separate contract rather than being fused into a
    single merged contract (number of contracts == number of records).

    ``include_structures`` should be True only for the first champs record
    of a given owner (so structures are billed exactly once across all of
    that owner's contracts, never duplicated nor omitted).
    """
    summary = CompensationSummary()
    _accumulate_champs_enquete(summary, champ_enquete)
    if include_structures:
        for enquete in structure_enquetes:
            if enquete.get("proprietaireStructure") == code_proprietaire:
                _accumulate_structure_enquete(summary, enquete)
    return summary


def compute_global(champs_enquetes, structure_enquetes):
    summary = CompensationSummary()
    for enquete in champs_enquetes:
        _accumulate_champs_enquete(summary, enquete)
    for enquete in structure_enquetes:
        _accumulate_structure_enquete(summary, enquete)
    return summary
