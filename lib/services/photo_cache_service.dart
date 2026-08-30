import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'session_service.dart';
import 'sync_service.dart';

/// Downloads and caches, ON THE DEVICE FILESYSTEM, the legacy member
/// photos uploaded by the admin in the OKAPI Web Admin ("Répertoire
/// photos"), so they remain available for display in generated contracts
/// even with NO internet connection afterwards.
///
/// Each project (wcag/simandou/smb) has its own on-server photo directory
/// (see okapi_web_admin/photos.py) and its own local cache sub-folder here,
/// mirroring the same strict per-project isolation used for
/// ménages/champs/structures (a SIMANDOU photo must never be used while
/// the WCAG project is active, and vice-versa).
///
/// NOT supported on Web (no real filesystem) — on Web, contracts simply
/// fall back to showing no photo for legacy (non re-photographed) members,
/// same as before this feature existed.
class PhotoCacheService {
  PhotoCacheService._();
  static final PhotoCacheService instance = PhotoCacheService._();

  Directory? _rootDir;

  Future<Directory> _projectDir(String project) async {
    if (kIsWeb) {
      throw UnsupportedError('Photo cache is not available on Web.');
    }
    _rootDir ??= await getApplicationSupportDirectory();
    final dir = Directory('${_rootDir!.path}/legacy_photos/$project');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns the local file for [legacyFilename] under [project], or null
  /// if it hasn't been downloaded yet.
  Future<File?> localFile(String project, String? legacyFilename) async {
    if (kIsWeb || legacyFilename == null || legacyFilename.isEmpty) {
      return null;
    }
    try {
      final dir = await _projectDir(project);
      final f = File('${dir.path}/$legacyFilename');
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the cached photo (if any) and returns it as a base64 string,
  /// ready to be dropped straight into ContractData.photoProfilBase64 —
  /// same shape as a live photoProfilBase64 capture.
  Future<String?> localPhotoBase64(String project, String? legacyFilename) async {
    final f = await localFile(project, legacyFilename);
    if (f == null) return null;
    try {
      final bytes = await f.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Downloads every legacy photo currently available on the server for
  /// [project] (or only the ones not already cached, when
  /// [onlyMissing] is true — the default, for fast incremental syncs) and
  /// stores them under the device's app-support directory for fully
  /// offline later use. Returns the number of newly downloaded files, or
  /// throws on network/parsing failure (caller should surface a friendly
  /// error to the user, mirroring SyncResult's pattern).
  Future<int> downloadProjectPhotos(
    String project, {
    bool onlyMissing = true,
    void Function(int done, int total)? onProgress,
  }) async {
    if (kIsWeb) return 0;
    final serverUrl = await SyncService.instance.serverUrl;
    if (serverUrl.isEmpty) return 0;

    // 1) Fetch manifest of what's available server-side for this project.
    final manifestUri = Uri.parse('$serverUrl/api/photos/manifest?project=$project');
    final manifestResp = await http.get(manifestUri).timeout(const Duration(seconds: 30));
    if (manifestResp.statusCode != 200) {
      throw Exception('Impossible de récupérer la liste des photos (code ${manifestResp.statusCode}).');
    }
    final body = jsonDecode(utf8.decode(manifestResp.bodyBytes)) as Map<String, dynamic>;
    final entries = (body['photos'] as List? ?? []).cast<Map>();

    final dir = await _projectDir(project);
    final toDownload = <String>[];
    for (final e in entries) {
      final fn = (e['filename'] ?? '').toString();
      if (fn.isEmpty) continue;
      if (onlyMissing) {
        final f = File('${dir.path}/$fn');
        if (await f.exists()) continue;
      }
      toDownload.add(fn);
    }

    if (toDownload.isEmpty) return 0;

    // 2) Download each missing file individually via /api/photos/file/<fn>
    // (simpler & more resumable than a single big ZIP for large batches).
    var done = 0;
    for (final fn in toDownload) {
      try {
        final fileUri = Uri.parse(
          '$serverUrl/api/photos/file/${Uri.encodeComponent(fn)}?project=$project',
        );
        final resp = await http.get(fileUri).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final f = File('${dir.path}/$fn');
          await f.writeAsBytes(resp.bodyBytes);
          done++;
        }
      } catch (_) {
        // Skip this file, continue with the rest — a partial sync is
        // still useful, and the next "Télécharger les photos" run will
        // retry only the still-missing ones.
      }
      onProgress?.call(done, toDownload.length);
    }
    return done;
  }

  /// Convenience: downloads photos for the CURRENT session project.
  Future<int> downloadCurrentProjectPhotos({
    bool onlyMissing = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final project = (await SessionService.instance.project) ?? 'wcag';
    return downloadProjectPhotos(project, onlyMissing: onlyMissing, onProgress: onProgress);
  }
}
