"""SQLite storage layer for OKAPI Survey Web Admin.

Stores the same JSON structures produced by the Flutter mobile app
(Menage, EnqueteChamp, EnqueteStructure — as sent by the /api/sync endpoint)
as raw JSON blobs, plus a few indexed columns for fast querying/sorting.

--- Multi-project data isolation (Option B) --------------------------------
Each project (WCAG, SIMANDOU, SMB) has its own, completely separate SQLite
database file under data/<project>.db. The "active" project for the current
request is tracked via a contextvar (set by app.py's before_request hook
from the Flask session, or forced to "wcag" for the mobile /api/* routes
since the mobile app only ever targets the WCAG project for now). Every
get_conn() call transparently opens the correct file for whichever project
is currently active - no other function in this module needs to change.
"""
import sqlite3
import json
import os
import shutil
import threading
import contextvars

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
LEGACY_DB_PATH = os.path.join(DATA_DIR, "okapi.db")

PROJECTS = ["wcag", "simandou", "smb"]
DEFAULT_PROJECT = "wcag"

_lock = threading.Lock()
_current_project = contextvars.ContextVar("current_project", default=DEFAULT_PROJECT)


def set_current_project(project: str):
    """Sets the active project (db file) for the current request/thread."""
    if project not in PROJECTS:
        project = DEFAULT_PROJECT
    _current_project.set(project)


def get_current_project() -> str:
    return _current_project.get()


def _db_path_for(project: str) -> str:
    return os.path.join(DATA_DIR, f"{project}.db")


def migrate_legacy_db():
    """One-time migration: the original single-project database was named
    data/okapi.db. All mobile survey data collected so far belongs to the
    WCAG project, so on first run with the new multi-project layout we copy
    it (never move, to keep the original as a safety backup) to
    data/wcag.db if that file doesn't exist yet."""
    os.makedirs(DATA_DIR, exist_ok=True)
    wcag_path = _db_path_for("wcag")
    if os.path.exists(LEGACY_DB_PATH) and not os.path.exists(wcag_path):
        shutil.copyfile(LEGACY_DB_PATH, wcag_path)


def get_conn():
    project = get_current_project()
    conn = sqlite3.connect(_db_path_for(project))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    """Initializes (creates tables in) EVERY project's database, so
    SIMANDOU and SMB start with the correct empty schema even before any
    data is synced/imported into them."""
    migrate_legacy_db()
    for project in PROJECTS:
        _init_db_for_project(project)


def _init_db_for_project(project: str):
    os.makedirs(DATA_DIR, exist_ok=True)
    prev = get_current_project()
    set_current_project(project)
    try:
        _create_tables()
    finally:
        set_current_project(prev)


def _create_tables():
    conn = get_conn()
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS menages (
            id TEXT PRIMARY KEY,
            code_menage TEXT,
            village TEXT,
            district TEXT,
            sous_prefecture TEXT,
            prefecture TEXT,
            region TEXT,
            nom_chef TEXT,
            data_json TEXT NOT NULL,
            updated_at TEXT,
            synced_at TEXT DEFAULT (datetime('now')),
            device_id TEXT
        );

        CREATE TABLE IF NOT EXISTS champs (
            id TEXT PRIMARY KEY,
            code_menage TEXT,
            code_proprietaire TEXT,
            proprietaire_nom TEXT,
            num_batch TEXT,
            type_de_propriete TEXT,
            village TEXT,
            data_json TEXT NOT NULL,
            updated_at TEXT,
            synced_at TEXT DEFAULT (datetime('now')),
            device_id TEXT
        );

        CREATE TABLE IF NOT EXISTS structures (
            id TEXT PRIMARY KEY,
            code_menage TEXT,
            proprietaire_structure TEXT,
            proprietaire_nom TEXT,
            num_batch TEXT,
            village TEXT,
            data_json TEXT NOT NULL,
            updated_at TEXT,
            synced_at TEXT DEFAULT (datetime('now')),
            device_id TEXT
        );

        CREATE TABLE IF NOT EXISTS survey_records (
            id TEXT PRIMARY KEY,
            form_key TEXT NOT NULL,
            region TEXT,
            prefecture TEXT,
            sous_prefecture TEXT,
            data_json TEXT NOT NULL,
            updated_at TEXT,
            synced_at TEXT DEFAULT (datetime('now')),
            device_id TEXT
        );

        CREATE TABLE IF NOT EXISTS sync_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT,
            device_name TEXT,
            counts_json TEXT,
            synced_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS deleted_records (
            record_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            tablette TEXT,
            device_id TEXT,
            deleted_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (record_type, record_id)
        );

        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            nom_prenom TEXT NOT NULL,
            telephone TEXT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            sexe TEXT,
            statut TEXT,
            tablette TEXT,
            approval_status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT DEFAULT (datetime('now')),
            approved_at TEXT,
            approved_by TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_champs_batch ON champs(num_batch);
        CREATE INDEX IF NOT EXISTS idx_structures_batch ON structures(num_batch);
        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        CREATE INDEX IF NOT EXISTS idx_users_status ON users(approval_status);
        CREATE INDEX IF NOT EXISTS idx_survey_records_form_key ON survey_records(form_key);
        CREATE INDEX IF NOT EXISTS idx_survey_records_region ON survey_records(region);
        """
    )
    conn.commit()

    # Migration-safe: add the `tablette` column to a pre-existing `users`
    # table created before this field existed (CREATE TABLE IF NOT EXISTS
    # does not retroactively add columns to an already-existing table).
    try:
        conn.execute("ALTER TABLE users ADD COLUMN tablette TEXT")
        conn.commit()
    except sqlite3.OperationalError:
        pass  # column already exists

    conn.close()


# ---------------------------------------------------------------------------
# Users (mobile app authentication + admin approval workflow)
# ---------------------------------------------------------------------------

def create_user(user_id: str, nom_prenom: str, telephone: str, username: str,
                 password_hash: str, sexe: str, statut: str, tablette: str = ""):
    """Inserts a new pending registration. Raises sqlite3.IntegrityError if the
    username is already taken. `tablette` identifies which physical tablet
    this account (typically a "Chef d'équipe") is assigned to, used to
    restrict mobile sync to that tablet's own survey records."""
    with _lock:
        conn = get_conn()
        conn.execute(
            """INSERT INTO users
               (id, nom_prenom, telephone, username, password_hash, sexe, statut, tablette, approval_status)
               VALUES (?,?,?,?,?,?,?,?, 'pending')""",
            (user_id, nom_prenom, telephone, username, password_hash, sexe, statut, tablette),
        )
        conn.commit()
        conn.close()


def get_user_by_username(username: str):
    conn = get_conn()
    row = conn.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_user_by_id(user_id: str):
    conn = get_conn()
    row = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def all_users():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM users ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


def set_user_approval(user_id: str, status: str, approved_by: str = ""):
    """status must be 'approved' or 'rejected'."""
    with _lock:
        conn = get_conn()
        conn.execute(
            """UPDATE users SET approval_status=?, approved_at=datetime('now'), approved_by=?
               WHERE id=?""",
            (status, approved_by, user_id),
        )
        conn.commit()
        conn.close()


def delete_user(user_id: str):
    with _lock:
        conn = get_conn()
        conn.execute("DELETE FROM users WHERE id=?", (user_id,))
        conn.commit()
        conn.close()


def users_counts():
    conn = get_conn()
    rows = conn.execute(
        "SELECT approval_status, COUNT(*) c FROM users GROUP BY approval_status"
    ).fetchall()
    conn.close()
    out = {"pending": 0, "approved": 0, "rejected": 0}
    for r in rows:
        out[r["approval_status"]] = r["c"]
    return out


TOMBSTONE_TABLES = {
    "menage": "menages",
    "champ": "champs",
    "structure": "structures",
}


def is_deleted(record_type: str, record_id: str) -> bool:
    conn = get_conn()
    row = conn.execute(
        "SELECT 1 FROM deleted_records WHERE record_type=? AND record_id=?",
        (record_type, record_id),
    ).fetchone()
    conn.close()
    return row is not None


def record_deletion(record_type: str, record_id: str, tablette: str = "",
                     device_id: str = ""):
    """Deletes the record from its data table (if present) and records a
    tombstone so the deletion is propagated to every other tablet on their
    next 'Actualiser' (pull), and so the record is never re-created by a
    later, out-of-order upsert of stale data for the same id."""
    table = TOMBSTONE_TABLES.get(record_type)
    with _lock:
        conn = get_conn()
        if table:
            conn.execute(f"DELETE FROM {table} WHERE id=?", (record_id,))
        conn.execute(
            """INSERT INTO deleted_records (record_type, record_id, tablette, device_id, deleted_at)
               VALUES (?,?,?,?,datetime('now'))
               ON CONFLICT(record_type, record_id) DO UPDATE SET
                 tablette=excluded.tablette,
                 device_id=excluded.device_id,
                 deleted_at=excluded.deleted_at
            """,
            (record_type, record_id, tablette, device_id),
        )
        conn.commit()
        conn.close()


def purge_champs_and_structures():
    """Deletes ALL 'Enquêtes Champs' and 'Enquêtes Structures' records
    synced from the tablets for the CURRENTLY ACTIVE PROJECT ONLY (see
    get_conn()/set_current_project() - each project has its own database
    file, so this never touches another project's data).

    This is what actually makes the old "contrats à générer" disappear
    from the Contrats page / dashboard batch table, since those are
    entirely computed on the fly from the champs/structures records (see
    contract_rows.py) - there is no separate "contracts" table to clear.

    Ménages are INTENTIONALLY left completely untouched, per explicit
    requirement ("supprime les données synchronisées des tablettes sans
    toucher aux ménages").

    A deletion tombstone is recorded for every purged record so that
    every tablet also purges its own local copy on its next "Actualiser"
    pull (mirrors record_deletion()'s tombstone behaviour), keeping the
    web admin and every mobile device in sync after the purge.

    Returns (champs_count, structures_count) - the number of records
    deleted of each kind, for the confirmation message shown to the
    admin.
    """
    with _lock:
        conn = get_conn()
        champ_ids = [r["id"] for r in conn.execute("SELECT id FROM champs").fetchall()]
        structure_ids = [
            r["id"] for r in conn.execute("SELECT id FROM structures").fetchall()
        ]
        for cid in champ_ids:
            conn.execute(
                """INSERT INTO deleted_records (record_type, record_id, tablette, device_id, deleted_at)
                   VALUES ('champ', ?, '', '', datetime('now'))
                   ON CONFLICT(record_type, record_id) DO UPDATE SET
                     deleted_at=excluded.deleted_at
                """,
                (cid,),
            )
        for sid in structure_ids:
            conn.execute(
                """INSERT INTO deleted_records (record_type, record_id, tablette, device_id, deleted_at)
                   VALUES ('structure', ?, '', '', datetime('now'))
                   ON CONFLICT(record_type, record_id) DO UPDATE SET
                     deleted_at=excluded.deleted_at
                """,
                (sid,),
            )
        conn.execute("DELETE FROM champs")
        conn.execute("DELETE FROM structures")
        conn.commit()
        conn.close()
        return len(champ_ids), len(structure_ids)


def all_deletions(since: str = None):
    """Returns all deletion tombstones (optionally only those recorded
    after [since], an ISO datetime string) as a list of
    {recordType, recordId, deletedAt} dicts, for the mobile /api/pull
    response so every tablet can purge its own local copy of records
    deleted elsewhere."""
    conn = get_conn()
    if since:
        rows = conn.execute(
            "SELECT * FROM deleted_records WHERE deleted_at > ? ORDER BY deleted_at",
            (since,),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM deleted_records ORDER BY deleted_at"
        ).fetchall()
    conn.close()
    return [
        {
            "recordType": r["record_type"],
            "recordId": r["record_id"],
            "tablette": r["tablette"] or "",
            "deletedAt": r["deleted_at"],
        }
        for r in rows
    ]


def upsert_menage(m: dict, device_id: str = ""):
    if is_deleted("menage", m.get("id", "")):
        return
    with _lock:
        conn = get_conn()
        chef = None
        for ind in m.get("individus", []):
            if ind.get("relationCdm") == "Chef de menage":
                chef = ind
                break
        if chef is None and m.get("individus"):
            chef = m["individus"][0]
        conn.execute(
            """INSERT INTO menages
               (id, code_menage, village, district, sous_prefecture, prefecture,
                region, nom_chef, data_json, updated_at, device_id)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET
                 code_menage=excluded.code_menage,
                 village=excluded.village,
                 district=excluded.district,
                 sous_prefecture=excluded.sous_prefecture,
                 prefecture=excluded.prefecture,
                 region=excluded.region,
                 nom_chef=excluded.nom_chef,
                 data_json=excluded.data_json,
                 updated_at=excluded.updated_at,
                 synced_at=datetime('now'),
                 device_id=excluded.device_id
               WHERE excluded.updated_at IS NULL
                  OR menages.updated_at IS NULL
                  OR menages.updated_at = ''
                  OR excluded.updated_at >= menages.updated_at
            """,
            (
                m.get("id"),
                m.get("codeMenage", ""),
                m.get("village", ""),
                m.get("district", ""),
                m.get("sousPrefecture", ""),
                m.get("prefecture", ""),
                m.get("region", ""),
                (chef or {}).get("nomPrenom", m.get("nomChefMenage", "") or ""),
                json.dumps(m, ensure_ascii=False),
                m.get("updatedAt", ""),
                device_id,
            ),
        )
        conn.commit()
        conn.close()


def upsert_champ(c: dict, device_id: str = ""):
    if is_deleted("champ", c.get("id", "")):
        return
    with _lock:
        conn = get_conn()
        conn.execute(
            """INSERT INTO champs
               (id, code_menage, code_proprietaire, proprietaire_nom, num_batch,
                type_de_propriete, village, data_json, updated_at, device_id)
               VALUES (?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET
                 code_menage=excluded.code_menage,
                 code_proprietaire=excluded.code_proprietaire,
                 proprietaire_nom=excluded.proprietaire_nom,
                 num_batch=excluded.num_batch,
                 type_de_propriete=excluded.type_de_propriete,
                 village=excluded.village,
                 data_json=excluded.data_json,
                 updated_at=excluded.updated_at,
                 synced_at=datetime('now'),
                 device_id=excluded.device_id
               WHERE excluded.updated_at IS NULL
                  OR champs.updated_at IS NULL
                  OR champs.updated_at = ''
                  OR excluded.updated_at >= champs.updated_at
            """,
            (
                c.get("id"),
                c.get("codeMenage", ""),
                c.get("codeProprietaire", ""),
                c.get("proprietaireNom", ""),
                c.get("numBatch", ""),
                c.get("typeDePropriete", ""),
                c.get("village", ""),
                json.dumps(c, ensure_ascii=False),
                c.get("updatedAt", ""),
                device_id,
            ),
        )
        conn.commit()
        conn.close()


def upsert_structure(s: dict, device_id: str = ""):
    if is_deleted("structure", s.get("id", "")):
        return
    with _lock:
        conn = get_conn()
        conn.execute(
            """INSERT INTO structures
               (id, code_menage, proprietaire_structure, proprietaire_nom, num_batch,
                village, data_json, updated_at, device_id)
               VALUES (?,?,?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET
                 code_menage=excluded.code_menage,
                 proprietaire_structure=excluded.proprietaire_structure,
                 proprietaire_nom=excluded.proprietaire_nom,
                 num_batch=excluded.num_batch,
                 village=excluded.village,
                 data_json=excluded.data_json,
                 updated_at=excluded.updated_at,
                 synced_at=datetime('now'),
                 device_id=excluded.device_id
               WHERE excluded.updated_at IS NULL
                  OR structures.updated_at IS NULL
                  OR structures.updated_at = ''
                  OR excluded.updated_at >= structures.updated_at
            """,
            (
                s.get("id"),
                s.get("codeMenage", ""),
                s.get("proprietaireStructure", ""),
                s.get("proprietaireNom", ""),
                s.get("numBatch", ""),
                s.get("village", ""),
                json.dumps(s, ensure_ascii=False),
                s.get("updatedAt", ""),
                device_id,
            ),
        )
        conn.commit()
        conn.close()


def upsert_survey_record(r: dict, device_id: str = ""):
    """Upserts a single generic BIODIVERSITE/SOCIAL survey record. `r` is
    the exact dict produced by the Flutter app's SurveyRecord.toMap():
    {id, formKey, values: {...}, repeats: {...}, createdAt, updatedAt}."""
    with _lock:
        conn = get_conn()
        values = r.get("values", {}) or {}
        conn.execute(
            """INSERT INTO survey_records
               (id, form_key, region, prefecture, sous_prefecture,
                data_json, updated_at, device_id)
               VALUES (?,?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET
                 form_key=excluded.form_key,
                 region=excluded.region,
                 prefecture=excluded.prefecture,
                 sous_prefecture=excluded.sous_prefecture,
                 data_json=excluded.data_json,
                 updated_at=excluded.updated_at,
                 synced_at=datetime('now'),
                 device_id=excluded.device_id
            """,
            (
                r.get("id"),
                r.get("formKey", ""),
                values.get("region", ""),
                values.get("prefecture", ""),
                values.get("sous_prefecture", ""),
                json.dumps(r, ensure_ascii=False),
                r.get("updatedAt", ""),
                device_id,
            ),
        )
        conn.commit()
        conn.close()


def log_sync(device_id: str, device_name: str, counts: dict):
    with _lock:
        conn = get_conn()
        conn.execute(
            "INSERT INTO sync_log (device_id, device_name, counts_json) VALUES (?,?,?)",
            (device_id, device_name, json.dumps(counts)),
        )
        conn.commit()
        conn.close()


def all_menages():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM menages ORDER BY updated_at DESC").fetchall()
    conn.close()
    return [json.loads(r["data_json"]) for r in rows]


def all_champs():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM champs ORDER BY num_batch, updated_at DESC").fetchall()
    conn.close()
    return [json.loads(r["data_json"]) for r in rows]


def all_structures():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM structures ORDER BY num_batch, updated_at DESC").fetchall()
    conn.close()
    return [json.loads(r["data_json"]) for r in rows]


def all_survey_records(form_key: str = None):
    """Returns survey records grouped by formKey: {formKey: [record_dict,...]}
    matching the shape SurveyRecord.fromMap() expects on the Flutter side.
    If `form_key` is given, restricts to that single form (still returned
    as a {formKey: [...]} dict for API-shape consistency)."""
    conn = get_conn()
    if form_key:
        rows = conn.execute(
            "SELECT * FROM survey_records WHERE form_key=? ORDER BY updated_at DESC",
            (form_key,),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM survey_records ORDER BY form_key, updated_at DESC"
        ).fetchall()
    conn.close()
    out: dict = {}
    for row in rows:
        record = json.loads(row["data_json"])
        out.setdefault(row["form_key"], []).append(record)
    return out


def survey_records_count():
    conn = get_conn()
    rows = conn.execute(
        "SELECT form_key, COUNT(*) c FROM survey_records GROUP BY form_key"
    ).fetchall()
    conn.close()
    return {r["form_key"]: r["c"] for r in rows}


def menage_by_id(mid: str):
    conn = get_conn()
    row = conn.execute("SELECT * FROM menages WHERE id=?", (mid,)).fetchone()
    conn.close()
    return json.loads(row["data_json"]) if row else None


def find_individu(individu_id: str):
    """Searches every ménage for an individu with this id. Returns
    (menage_dict, individu_dict) or (None, None) if not found. Used by the
    web admin's photo view/crop endpoints (Req #4: photos "directement
    liées aux individus correspondants dans le ménage")."""
    conn = get_conn()
    rows = conn.execute("SELECT * FROM menages").fetchall()
    conn.close()
    for row in rows:
        m = json.loads(row["data_json"])
        for ind in m.get("individus", []):
            if ind.get("id") == individu_id:
                return m, ind
    return None, None


def update_individu_photo(menage_id: str, individu_id: str, field: str, base64_data: str):
    """Updates one of an individu's 3 photo fields (photoProfilBase64 /
    photoCniRectoBase64 / photoCniVersoBase64) directly on the ménage's
    stored JSON, e.g. after cropping in the web admin UI. Bumps the
    ménage's updatedAt so the change propagates to every mobile tablet on
    their next 'Actualiser' (Req #3's last-write-wins pull-merge), and is
    immediately reflected wherever this individu's photo is displayed
    (ménage detail page, generated contract PDFs).

    Returns True if the individu was found and updated, False otherwise.
    """
    if field not in ("photoProfilBase64", "photoCniRectoBase64", "photoCniVersoBase64"):
        raise ValueError(f"Unknown photo field: {field}")
    m = menage_by_id(menage_id)
    if not m:
        return False
    found = False
    for ind in m.get("individus", []):
        if ind.get("id") == individu_id:
            ind[field] = base64_data
            found = True
            break
    if not found:
        return False
    from datetime import datetime as _dt
    m["updatedAt"] = _dt.now().isoformat()
    upsert_menage(m, device_id="webadmin")
    return True


def champs_by_owner(code_proprietaire: str):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM champs WHERE code_proprietaire=?", (code_proprietaire,)
    ).fetchall()
    conn.close()
    return [json.loads(r["data_json"]) for r in rows]


def structures_by_owner(proprietaire_structure: str):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM structures WHERE proprietaire_structure=?",
        (proprietaire_structure,),
    ).fetchall()
    conn.close()
    return [json.loads(r["data_json"]) for r in rows]


def counts():
    conn = get_conn()
    m = conn.execute("SELECT COUNT(*) c FROM menages").fetchone()["c"]
    c = conn.execute("SELECT COUNT(*) c FROM champs").fetchone()["c"]
    s = conn.execute("SELECT COUNT(*) c FROM structures").fetchone()["c"]
    sr = conn.execute("SELECT COUNT(*) c FROM survey_records").fetchone()["c"]
    conn.close()
    return {"menages": m, "champs": c, "structures": s, "survey_records": sr}


def recent_syncs(limit=20):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM sync_log ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]
