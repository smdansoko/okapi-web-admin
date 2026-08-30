"""Authentication + Project/Module navigation for OKAPI Survey Web Admin.

Two hardcoded web-admin accounts (distinct from the mobile app's
self-registration `users` table in db.py, which is a completely separate
concept - mobile field-agent accounts vs. these 2 web-admin operator
accounts):

  - dsmariame / TinaDans10@   -> role "admin"        (full access)
  - okapisurvey / OAKPI2026@  -> role "gestionnaire"  (no access to /users)

After login, the user must pick a PROJECT (SIMANDOU / WCAG / SMB) and then
a MODULE (PARC / SOCIAL / BIODIVERSITÉ). Only PARC is implemented today
(routes to the existing dashboard/ménages/contrats/... app, scoped to the
selected project's own SQLite database - see db.py). SOCIAL and
BIODIVERSITÉ show a "coming soon" placeholder.
"""
from functools import wraps

from flask import session, redirect, url_for, request, render_template

import db

# ---------------------------------------------------------------------------
# Hardcoded web-admin accounts
# ---------------------------------------------------------------------------

USERS = {
    "dsmariame": {"password": "TinaDans10@", "role": "admin", "label": "Administrateur principal"},
    "okapisurvey": {"password": "OAKPI2026@", "role": "gestionnaire", "label": "Gestionnaire"},
}

PROJECTS = [
    {"code": "simandou", "label": "SIMANDOU"},
    {"code": "wcag", "label": "WCAG"},
    {"code": "smb", "label": "SMB"},
]

MODULES = [
    {"code": "parc", "label": "PARC", "available": True},
    {"code": "social", "label": "SOCIAL", "available": True},
    {"code": "biodiversite", "label": "BIODIVERSITÉ", "available": True},
]

PROJECT_LABELS = {p["code"]: p["label"] for p in PROJECTS}
MODULE_LABELS = {m["code"]: m["label"] for m in MODULES}

# Endpoints that belong to each module. Contracts/compensation/facturation/
# rapport/ménages/photos are ALL compensation-contract-related and must
# stay exclusively under PARC (per user requirement: "tout ce qui est lié
# aux contrats de compensation doivent rester dans PARC"). BIODIVERSITÉ and
# SOCIAL each only expose their own dashboard + form record browsing.
_PARC_ENDPOINTS = {
    "dashboard", "dashboard_stats", "menages_list", "menage_detail",
    "contracts_list", "export_contract", "preview_contract",
    "photos_directory", "photos_directory_upload", "individu_photo",
    "individu_photo_field", "individu_photos_manage", "individu_photo_crop",
    "compensation_page", "compensation_export",
    "facturation_page", "facturation_export_superficie", "facturation_export",
    "rapport_page", "rapport_export_pdf", "rapport_export_docx",
}
_BIODIVERSITE_ENDPOINTS = {
    "biodiversite_dashboard", "biodiversite_form_records",
    "biodiversite_export", "biodiversite_form_export",
}
_SOCIAL_ENDPOINTS = {
    "social_dashboard", "social_form_records",
    "social_export", "social_form_export",
    "rapport_patrimoine_page", "rapport_patrimoine_export_docx",
}
# Endpoints reachable regardless of the selected module (admin user mgmt).
_SHARED_ENDPOINTS = {"users_list", "user_approve", "user_reject", "user_delete"}

_MODULE_ENDPOINTS = {
    "parc": _PARC_ENDPOINTS,
    "biodiversite": _BIODIVERSITE_ENDPOINTS,
    "social": _SOCIAL_ENDPOINTS,
}

_MODULE_HOME_ENDPOINT = {
    "parc": "dashboard",
    "biodiversite": "biodiversite_dashboard",
    "social": "social_dashboard",
}

# Routes that must remain reachable WITHOUT a session (login page, static
# assets, and the mobile app's JSON API which authenticates its own way and
# always operates on the WCAG project regardless of any web-admin session).
_PUBLIC_ENDPOINTS = {
    "login", "logout", "static",
}
_MOBILE_API_PREFIXES = ("/api/",)


def is_mobile_api_request() -> bool:
    return request.path.startswith(_MOBILE_API_PREFIXES)


# Mobile endpoints that deal with USER ACCOUNTS (register/login/status
# checks) always operate on the shared "wcag" database, regardless of
# which project the user later chooses to survey - the `users` table is
# effectively a single shared directory of field agents, independent of
# project. Only DATA endpoints (/api/sync, /api/pull, /api/status) are
# project-aware and read the target project from the mobile app's request.
_MOBILE_USER_ACCOUNT_PATHS = ("/api/register", "/api/login", "/api/users/")


def mobile_request_project() -> str:
    """Determines which project's database a mobile /api/* data request
    (sync/pull/status) should be bound to. The Flutter app sends the
    user-selected project (SIMANDOU/WCAG/SMB) either as a `project` field
    in the JSON body (POST /api/sync), a `project` query string parameter
    (GET /api/pull, /api/status), or an `X-Project` header. Falls back to
    "wcag" for older app builds that don't send it yet, so nothing breaks
    for already-deployed APKs."""
    project = request.args.get("project") or request.headers.get("X-Project")
    if not project:
        payload = request.get_json(silent=True) or {}
        if isinstance(payload, dict):
            project = payload.get("project")
    project = (project or "").strip().lower()
    if project not in db.PROJECTS:
        project = db.DEFAULT_PROJECT
    return project


def current_user():
    username = session.get("username")
    if not username:
        return None
    return {
        "username": username,
        "role": session.get("role", ""),
        "label": USERS.get(username, {}).get("label", username),
    }


def is_logged_in() -> bool:
    return bool(session.get("username"))


def has_project_and_module() -> bool:
    return bool(session.get("project")) and bool(session.get("module"))


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not is_logged_in():
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapped


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not is_logged_in():
            return redirect(url_for("login", next=request.path))
        if session.get("role") != "admin":
            return render_template(
                "error_403.html",
                message="Cette page est réservée à l'administrateur principal.",
            ), 403
        return view(*args, **kwargs)
    return wrapped


def project_module_required(view):
    """Ensures the user is logged in AND has already picked a project +
    module (PARC) before reaching the main app pages (dashboard, ménages,
    contrats, etc.)."""
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not is_logged_in():
            return redirect(url_for("login", next=request.path))
        if not has_project_and_module():
            return redirect(url_for("select_project"))
        return view(*args, **kwargs)
    return wrapped


def register_auth_routes(app):
    """Registers /login, /logout, /select-project, /select-module and wires
    a before_request hook that (a) lets the mobile /api/* endpoints through
    unauthenticated and always bound to the WCAG project, and (b) points
    db.get_conn() at the correct project database for every other request
    based on the current web-admin session."""

    @app.before_request
    def _route_project_and_enforce_auth():
        if is_mobile_api_request():
            # User-account endpoints (register/login/status) always use the
            # shared "wcag" database (single directory of field agents).
            # Data endpoints (sync/pull/status) are project-aware: they use
            # whichever project the mobile app says it is currently
            # operating on (falls back to "wcag" for older app builds).
            if request.path.startswith(_MOBILE_USER_ACCOUNT_PATHS):
                db.set_current_project("wcag")
            else:
                db.set_current_project(mobile_request_project())
            return None

        # Web-admin pages: bind the active database to whatever project is
        # currently selected in the session (defaults to wcag if none yet,
        # harmless since project_module_required will redirect anyway).
        db.set_current_project(session.get("project") or db.DEFAULT_PROJECT)

        if request.endpoint in _PUBLIC_ENDPOINTS or request.endpoint is None:
            return None

        if not is_logged_in():
            return redirect(url_for("login", next=request.path))

        # Once logged in, force the project/module selection flow before
        # letting the user reach any other page (except the selection
        # pages themselves).
        _selection_endpoints = ("select_project", "select_module", "module_coming_soon",
                                 "switch_project", "switch_module")
        if request.endpoint not in _selection_endpoints:
            if not has_project_and_module():
                return redirect(url_for("select_project"))
            module = session.get("module")
            # Total separation between modules: PARC endpoints are ALL
            # compensation-contract related and must never be reachable
            # from BIODIVERSITÉ/SOCIAL sessions, and vice-versa. Any
            # endpoint not explicitly listed for the CURRENT module (and
            # not in the always-shared set) is redirected to that
            # module's own home page.
            if request.endpoint not in _SHARED_ENDPOINTS:
                allowed = _MODULE_ENDPOINTS.get(module, set())
                if request.endpoint not in allowed:
                    home = _MODULE_HOME_ENDPOINT.get(module, "select_project")
                    return redirect(url_for(home))

        return None

    @app.context_processor
    def _inject_nav_context():
        return {
            "auth_user": current_user(),
            "current_project_label": PROJECT_LABELS.get(session.get("project"), ""),
            "current_module_label": MODULE_LABELS.get(session.get("module"), ""),
            "current_module": session.get("module") or "",
        }

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if is_logged_in():
            return redirect(url_for("select_project"))

        error = None
        if request.method == "POST":
            username = (request.form.get("username") or "").strip().lower()
            password = request.form.get("password") or ""
            account = USERS.get(username)
            if account and account["password"] == password:
                session.clear()
                session["username"] = username
                session["role"] = account["role"]
                return redirect(url_for("select_project"))
            error = "Nom d'utilisateur ou mot de passe incorrect."

        return render_template("login.html", error=error)

    @app.route("/logout", methods=["POST", "GET"])
    def logout():
        session.clear()
        return redirect(url_for("login"))

    @app.route("/select-project", methods=["GET", "POST"])
    @login_required
    def select_project():
        if request.method == "POST":
            project = request.form.get("project", "")
            if project in db.PROJECTS:
                session["project"] = project
                session.pop("module", None)
                return redirect(url_for("select_module"))
        return render_template("select_project.html", projects=PROJECTS)

    @app.route("/select-module", methods=["GET", "POST"])
    @login_required
    def select_module():
        if not session.get("project"):
            return redirect(url_for("select_project"))

        if request.method == "POST":
            module = request.form.get("module", "")
            chosen = next((m for m in MODULES if m["code"] == module), None)
            if chosen and chosen["available"]:
                session["module"] = module
                return redirect(url_for(_MODULE_HOME_ENDPOINT.get(module, "dashboard")))
            elif chosen:
                # Not yet available - show a "coming soon" placeholder
                # instead of the main app.
                session["module"] = module
                return redirect(url_for("module_coming_soon"))

        return render_template(
            "select_module.html",
            modules=MODULES,
            project_label=PROJECT_LABELS.get(session.get("project"), ""),
        )

    @app.route("/module-a-venir")
    @login_required
    def module_coming_soon():
        if not session.get("project"):
            return redirect(url_for("select_project"))
        return render_template(
            "module_coming_soon.html",
            project_label=PROJECT_LABELS.get(session.get("project"), ""),
            module_label=MODULE_LABELS.get(session.get("module"), ""),
        )

    @app.route("/switch-project")
    @login_required
    def switch_project():
        session.pop("project", None)
        session.pop("module", None)
        return redirect(url_for("select_project"))

    @app.route("/switch-module")
    @login_required
    def switch_module():
        session.pop("module", None)
        return redirect(url_for("select_module"))
