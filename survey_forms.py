"""Shared metadata for the 11 BIODIVERSITE/SOCIAL survey forms collected by
the OKAPI Survey mobile app (see the Flutter app's lib/data/survey_schema.json,
which this list mirrors exactly - formKey/title/module/icon).

Used by the web admin's BIODIVERSITE and SOCIAL dashboards to show per-form
record counts without needing to parse the full ODK schema on the Python
side (the web admin only needs to LIST records, not render/edit forms).
"""

FORM_DEFS = [
    {"key": "pose_cameras", "title": "Pose caméras", "module": "biodiversite", "emoji": "📷"},
    {"key": "chimpanzes_recce", "title": "Chimpanzés Recce", "module": "biodiversite", "emoji": "🐒"},
    {"key": "poisson", "title": "Poisson", "module": "biodiversite", "emoji": "🐟"},
    {"key": "flore", "title": "Flore", "module": "biodiversite", "emoji": "🌿"},
    {"key": "oiseaux", "title": "Oiseaux", "module": "biodiversite", "emoji": "🐦"},
    {"key": "reptiles", "title": "Reptiles", "module": "biodiversite", "emoji": "🦎"},
    {"key": "amphibiens", "title": "Amphibiens", "module": "biodiversite", "emoji": "💧"},
    {"key": "mammiferes", "title": "Mammifères", "module": "biodiversite", "emoji": "🐾"},
    {"key": "infrastructures", "title": "Infrastructures de base", "module": "social", "emoji": "🏢"},
    {"key": "patrimoine_culturel", "title": "Patrimoine culturel", "module": "social", "emoji": "🛕"},
    {"key": "socioeconomique", "title": "Socioéconomique", "module": "social", "emoji": "📊"},
]

FORMS_BY_MODULE = {
    "biodiversite": [f for f in FORM_DEFS if f["module"] == "biodiversite"],
    "social": [f for f in FORM_DEFS if f["module"] == "social"],
}

FORM_TITLES = {f["key"]: f["title"] for f in FORM_DEFS}


def forms_for_module(module: str):
    return FORMS_BY_MODULE.get(module, [])


# Key categorical fields worth breaking down ("Top N") per form, for the
# BIODIVERSITÉ / SOCIAL dashboard statistics panels. Each entry is
# (field_name_in_values, display_label). Field names match the
# `patrimoine_culturel`/etc. XLSForm `name` columns (see the Flutter app's
# lib/data/survey_schema.json, which this list is derived from).
STAT_FIELDS_BY_FORM = {
    "pose_cameras": [
        ("habitat2", "Type d'habitat"),
        ("local2", "Espèce observée (nom commun)"),
        ("type_observation2", "Type d'observation"),
    ],
    "chimpanzes_recce": [
        ("habitat", "Type d'habitat"),
        ("local", "Espèce observée (nom commun)"),
        ("type_observation", "Type d'observation"),
    ],
    "poisson": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("habitat", "Habitat"),
        ("espece_migratrice", "Espèce migratrice"),
    ],
    "flore": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("type_espece", "Type d'espèce"),
        ("habitat", "Habitat"),
    ],
    "oiseaux": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("habitat", "Habitat"),
        ("espece_migratrice", "Espèce migratrice"),
    ],
    "reptiles": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("habitat", "Habitat"),
    ],
    "amphibiens": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("habitat", "Habitat"),
    ],
    "mammiferes": [
        ("nom_scientifique", "Espèce (nom scientifique)"),
        ("habitat", "Habitat"),
        ("espece_migratrice", "Espèce migratrice"),
    ],
    "infrastructures": [
        ("type_infras", "Type d'infrastructure"),
        ("etats_actuels", "État actuel"),
    ],
    "patrimoine_culturel": [
        ("type_site", "Type de site"),
        ("degre_importance", "Degré d'importance"),
        ("usage_site", "Usage du site"),
    ],
    "socioeconomique": [
        ("activite_principale", "Activité principale (chef de ménage)"),
        ("type_logement", "Type de logement"),
        ("sexe_chef_menage", "Sexe du chef de ménage"),
    ],
}
