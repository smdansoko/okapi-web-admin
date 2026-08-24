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
