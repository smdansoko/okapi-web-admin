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


# `image`-type field names per form, extracted from the Flutter app's
# lib/data/survey_schema.json (see SurveySchema.imageFields in
# lib/models/survey_field.dart, which this mirrors). Each entry is either
# a top-level field name (found directly in a record's `values` dict) or a
# tuple (repeat_name, field_name) for fields nested inside a repeat
# section's instances (found in a record's `repeats[repeat_name][i]` dict).
# Used by form_records.html to detect which values are base64-encoded JPEG
# photos and render them as <img> tags instead of raw text.
IMAGE_FIELDS_BY_FORM = {
    "pose_cameras": {
        "top": ["photo_dispositive"],
        "repeats": {},
    },
    "chimpanzes_recce": {
        "top": [],
        "repeats": {},
    },
    "poisson": {
        "top": [],
        "repeats": {"identification_espece": ["photo_habitat", "photo_espece"]},
    },
    "flore": {
        "top": [],
        "repeats": {"identification_espece": ["photo_espece", "photo_habitat"]},
    },
    "oiseaux": {
        "top": [],
        "repeats": {"identificatin_espece": ["photo_habitat", "photo_espece"]},
    },
    "reptiles": {
        "top": [],
        "repeats": {"identification_espece": ["photo_habitat", "photo_especee"]},
    },
    "amphibiens": {
        "top": [],
        "repeats": {"identification_espece": ["photo_especee", "photo_habitat"]},
    },
    "mammiferes": {
        "top": [],
        "repeats": {"identification_espece": ["photo_habitat", "photo_espece"]},
    },
    "infrastructures": {
        "top": [],
        "repeats": {"infrastructures": ["photo"]},
    },
    "patrimoine_culturel": {
        "top": ["num_photo_site"],
        "repeats": {},
    },
    "socioeconomique": {
        "top": [],
        "repeats": {},
    },
}


def image_fields_for(form_key: str):
    """Returns the IMAGE_FIELDS_BY_FORM entry for form_key, defaulting to
    an empty (no images) definition for unknown/legacy forms."""
    return IMAGE_FIELDS_BY_FORM.get(form_key, {"top": [], "repeats": {}})
