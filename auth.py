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
    {"code": "social", "label": "SOCIAL", "available": False},
    {"code": "biodiversite", "label": "BIODIVERSITÉ", "available": False},
]

PROJECT_LABELS = {p["code"]: p["label"] for p in PROJECTS}
MODULE_LABELS = {m["code"]: m["label"] for m in MODULES}

# Routes that must remain reachable WITHOUT a session (login page, static
# assets, and the mobile app's JSON API which authenticates its own way and
# always operates on the WCAG project regardless of any web-admin session).
_PUBLIC_ENDPOINTS = {
    "login", "logout", "static",
}
_MOBILE_API_PREFIXES = ("/api/",)


def is_mobile_api_request() -> bool:
    return request.path.startswith(_MOBILE_API_PREFIXES)


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
            # Mobile app always syncs to WCAG for now, regardless of any
            # concurrent web-admin session/project selection.
            db.set_current_project("wcag")
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
            # Only the PARC module is implemented today - SOCIAL/
            # BIODIVERSITÉ must never reach the main app pages (which are
            # all PARC-specific), even if a project+module are both set.
            if session.get("module") != "parc":
                return redirect(url_for("module_coming_soon"))

        return None

    @app.context_processor
    def _inject_nav_context():
        return {
            "auth_user": current_user(),
            "current_project_label": PROJECT_LABELS.get(session.get("project"), ""),
            "current_module_label": MODULE_LABELS.get(session.get("module"), ""),
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
                return redirect(url_for("dashboard"))
            elif chosen:
                # Not yet available (SOCIAL / BIODIVERSITÉ) - show a
                # "coming soon" placeholder instead of the main app.
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
