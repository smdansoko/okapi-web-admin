"""Per-project photo directory management (Phase 4).

Each project (WCAG, SIMANDOU, SMB) has its own photo directory under
``data/photos/<project>/``, storing member profile photos whose filenames
match the ``photoMembreFilenameLegacy`` value stored on each individu
(captured during the Phase 2 legacy Excel import, from the original
household survey's ``photo_membre`` column - itself the original
KoboToolbox/ODK photo attachment filename, e.g. "1779771979385.jpg").

Since the original KoboToolbox photo URLs are dead (source server
decommissioned, per explicit user instruction to forget them), these images
must be re-supplied by the admin from field archives (backed-up SD
card / tablet storage / USB drive), then uploaded here in bulk - either as
a single ZIP archive or as a batch of individual image files. Only the
filename needs to match; matching is case- and whitespace-tolerant, and
folder structure inside an uploaded ZIP is ignored (flattened).

Once a photo is present in a project's directory, it is automatically:
  - picked up by contract_pdf.py's build_contract_data() as a fallback
    profile photo (page 1 of the "Accord de compensation") for any
    legacy-imported ménage/individu that has no photoProfilBase64 of its
    own (which is the case for ALL legacy-imported records, since the
    mobile app's own base64 capture only applies to new field surveys);
  - shown as a thumbnail on the ménage detail page in the web admin.
"""
import os
import re
import shutil
import zipfile

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
PHOTOS_ROOT = os.path.join(DATA_DIR, "photos")

ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp"}


def _safe_filename(name: str) -> str:
    """Keeps only the base filename (no path traversal), sanitized to a
    filesystem-safe form while keeping legacy numeric filenames intact."""
    name = os.path.basename(name or "").strip()
    name = re.sub(r"[^A-Za-z0-9._\-]", "_", name)
    return name


def _norm_key(filename: str) -> str:
    """Normalizes a filename for matching: lowercase + stripped, so that
    extension-case differences (.jpg vs .JPG) don't cause false negatives."""
    return (filename or "").strip().lower()


def photos_dir_for(project: str) -> str:
    d = os.path.join(PHOTOS_ROOT, project)
    os.makedirs(d, exist_ok=True)
    return d


def _index_existing(project: str) -> dict:
    """Returns {normalized_filename: actual_filename_on_disk} for every
    photo currently uploaded for this project."""
    d = photos_dir_for(project)
    index = {}
    for fn in os.listdir(d):
        if fn.startswith("."):
            continue  # skip .gitkeep and other dotfiles
        full = os.path.join(d, fn)
        if os.path.isfile(full):
            index[_norm_key(fn)] = fn
    return index


def photo_path_for(project: str, legacy_filename: str):
    """Returns the absolute path to the matching uploaded photo for this
    project + legacy filename, or None if not yet uploaded."""
    if not legacy_filename:
        return None
    actual = _index_existing(project).get(_norm_key(legacy_filename))
    if not actual:
        return None
    return os.path.join(photos_dir_for(project), actual)


def get_photo_bytes(project: str, legacy_filename: str):
    path = photo_path_for(project, legacy_filename)
    if not path:
        return None
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def save_individual_files(project: str, file_storages) -> dict:
    """Saves a batch of individually-selected image files (werkzeug
    FileStorage objects) directly into the project's photo directory.
    Returns {"saved": [...], "skipped": [...]}."""
    d = photos_dir_for(project)
    saved, skipped = [], []
    for fs in file_storages:
        raw_name = (fs.filename or "").strip()
        if not raw_name:
            continue
        ext = os.path.splitext(raw_name)[1].lower()
        safe = _safe_filename(raw_name)
        if ext not in ALLOWED_EXT or not safe:
            skipped.append(raw_name)
            continue
        fs.save(os.path.join(d, safe))
        saved.append(safe)
    return {"saved": saved, "skipped": skipped}


def save_zip_archive(project: str, file_storage) -> dict:
    """Extracts every image file found inside a ZIP archive (at any depth)
    into the project's photo directory, flattened (only the basename is
    kept - folder structure inside the zip is irrelevant for matching).
    Returns {"saved": [...], "skipped": [...], "error": str|None}."""
    d = photos_dir_for(project)
    saved, skipped = [], []
    try:
        with zipfile.ZipFile(file_storage, "r") as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                raw_name = os.path.basename(info.filename)
                if not raw_name:
                    continue
                ext = os.path.splitext(raw_name)[1].lower()
                safe = _safe_filename(raw_name)
                if ext not in ALLOWED_EXT or not safe:
                    skipped.append(raw_name)
                    continue
                with zf.open(info) as src, open(os.path.join(d, safe), "wb") as dst:
                    shutil.copyfileobj(src, dst)
                saved.append(safe)
    except zipfile.BadZipFile:
        return {"saved": [], "skipped": [], "error": "Fichier ZIP invalide ou corrompu."}
    return {"saved": saved, "skipped": skipped, "error": None}


def manifest_for_project(project: str) -> list:
    """Returns [{"filename", "size", "mtime"}, ...] for every photo
    currently uploaded for this project. Used by the mobile app (Req:
    "photos téléversées dans le web synchronisées automatiquement dans
    l'application mobile") to compute which files it is still missing
    locally, without having to download anything it already cached."""
    d = photos_dir_for(project)
    out = []
    for fn in sorted(os.listdir(d)):
        if fn.startswith("."):
            continue
        full = os.path.join(d, fn)
        if os.path.isfile(full):
            try:
                st = os.stat(full)
            except OSError:
                continue
            out.append({"filename": fn, "size": st.st_size, "mtime": int(st.st_mtime)})
    return out


def build_zip_bytes(project: str, filenames=None):
    """Builds an in-memory ZIP archive containing the requested photo
    filenames for a project (or ALL uploaded photos when `filenames` is
    falsy). Unknown/missing filenames are silently skipped. Returns
    (bytes_io, included_count)."""
    import io as _io
    index = _index_existing(project)
    if filenames:
        wanted = [index[_norm_key(fn)] for fn in filenames if _norm_key(fn) in index]
    else:
        wanted = list(index.values())
    buf = _io.BytesIO()
    d = photos_dir_for(project)
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as zf:
        for fn in wanted:
            zf.write(os.path.join(d, fn), arcname=fn)
    buf.seek(0)
    return buf, len(wanted)


def stats_for_project(project: str, menages: list) -> dict:
    """Computes photo coverage stats for every individu across all
    ménages of a project: how many carry a photo_membre legacy reference
    at all, and how many of those are actually matched to an uploaded
    file. Also returns the detailed list of still-missing photos so the
    admin knows exactly which ones still need to be collected/uploaded."""
    index = _index_existing(project)
    total_individus = 0
    with_legacy_ref = 0
    matched = 0
    missing = []
    for m in menages:
        for ind in m.get("individus", []):
            total_individus += 1
            fn = ind.get("photoMembreFilenameLegacy")
            if fn:
                with_legacy_ref += 1
                if _norm_key(fn) in index:
                    matched += 1
                else:
                    missing.append({
                        "codeMenage": m.get("codeMenage", ""),
                        "village": m.get("village", ""),
                        "nomPrenom": ind.get("nomPrenom", ""),
                        "codeIndividu": ind.get("id", ""),
                        "filename": fn,
                    })
    return {
        "total_individus": total_individus,
        "with_legacy_ref": with_legacy_ref,
        "matched": matched,
        "missing_count": with_legacy_ref - matched,
        "missing": missing,
        "uploaded_total": len(index),
    }
