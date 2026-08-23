"""SQLite storage layer for OKAPI Survey Web Admin.

Stores the same JSON structures produced by the Flutter mobile app
(Menage, EnqueteChamp, EnqueteStructure — as sent by the /api/sync endpoint)
as raw JSON blobs, plus a few indexed columns for fast querying/sorting.
"""
import sqlite3
import json
import os
import threading

DB_PATH = os.path.join(os.path.dirname(__file__), "data", "okapi.db")
_lock = threading.Lock()


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
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

        CREATE TABLE IF NOT EXISTS sync_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT,
            device_name TEXT,
            counts_json TEXT,
            synced_at TEXT DEFAULT (datetime('now'))
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


def upsert_menage(m: dict, device_id: str = ""):
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


def menage_by_id(mid: str):
    conn = get_conn()
    row = conn.execute("SELECT * FROM menages WHERE id=?", (mid,)).fetchone()
    conn.close()
    return json.loads(row["data_json"]) if row else None


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
    conn.close()
    return {"menages": m, "champs": c, "structures": s}


def recent_syncs(limit=20):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM sync_log ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]
