import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menage.dart';
import '../models/enquete_champ.dart';
import '../models/structure.dart';
import '../models/survey_record.dart';
import 'session_service.dart';

/// Result of a synchronization attempt with the OKAPI Web Admin server.
class SyncResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? serverTotals;
  final Map<String, dynamic>? received;
  final DateTime timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.serverTotals,
    this.received,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Result of a pull-sync attempt (fetching data FROM the server, e.g. to
/// bring in ménages/enquêtes registered on ANOTHER tablet).
class PullResult {
  final bool success;
  final String message;
  final List<Menage> menages;
  final List<EnqueteChamp> champs;
  final List<EnqueteStructure> structures;
  // BIODIVERSITE/SOCIAL survey records, keyed by formKey (e.g.
  // 'pose_cameras', 'socioeconomique').
  final Map<String, List<SurveyRecord>> surveyRecords;
  // Deletion tombstones fetched from the server (records deleted on
  // another tablet, or by this tablet earlier), to be applied locally.
  final List<({String recordType, String recordId})> deletions;
  final Map<String, dynamic>? serverTotals;
  final DateTime timestamp;

  PullResult({
    required this.success,
    required this.message,
    this.menages = const [],
    this.champs = const [],
    this.structures = const [],
    this.surveyRecords = const {},
    this.deletions = const [],
    this.serverTotals,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Handles sending locally-saved data (Ménages, Enquêtes Champs, Enquêtes
/// Structures) from the OKAPI Survey mobile app to the separate OKAPI Web
/// Admin server (Flask app), via a simple JSON POST to /api/sync.
///
/// The server URL is configurable and persisted locally (SharedPreferences)
/// so it can be pointed at any deployment (sandbox preview, production
/// server, local network address of the admin PC, etc.) without rebuilding
/// the app.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _prefKeyServerUrl = 'sync_server_url';
  static const _prefKeyLastSyncAt = 'sync_last_at';
  static const _prefKeyDeviceId = 'sync_device_id';
  static const _prefKeyDeviceName = 'sync_device_name';

  String? _cachedServerUrl;
  String? _cachedDeviceId;

  /// Default OKAPI Web Admin server address (sandbox preview deployment).
  /// Update this value once the server is deployed to a permanent address.
  static const String defaultServerUrl =
      'https://okapi-web-admin.onrender.com';

  Future<String> get serverUrl async {
    if (_cachedServerUrl != null) return _cachedServerUrl!;
    final prefs = await SharedPreferences.getInstance();
    _cachedServerUrl = prefs.getString(_prefKeyServerUrl) ?? defaultServerUrl;
    return _cachedServerUrl!;
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _cachedServerUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyServerUrl, normalized);
  }

  Future<DateTime?> get lastSyncAt async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_prefKeyLastSyncAt);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> _setLastSyncAt(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLastSyncAt, dt.toIso8601String());
  }

  Future<String> get deviceId async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefKeyDeviceId);
    if (id == null || id.isEmpty) {
      id = 'device-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_prefKeyDeviceId, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  Future<String> get deviceName async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyDeviceName);
    if (saved != null && saved.isNotEmpty) return saved;
    String platformLabel;
    if (kIsWeb) {
      platformLabel = 'Web';
    } else {
      try {
        platformLabel = Platform.isAndroid
            ? 'Android'
            : Platform.operatingSystem;
      } catch (_) {
        platformLabel = 'Mobile';
      }
    }
    return 'Tablette OKAPI ($platformLabel)';
  }

  Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDeviceName, name);
  }

  /// Sends all provided data to the configured server's /api/sync endpoint.
  ///
  /// [surveyRecords] holds the 11 BIODIVERSITE/SOCIAL survey forms' records,
  /// keyed by formKey (e.g. 'pose_cameras', 'socioeconomique'); sent under a
  /// single `survey_records` payload key as `{formKey: [record.toMap(), ...]}`.
  ///
  /// The target project (SIMANDOU/WCAG/SMB) is always included as a
  /// `project` field so the server binds this sync to the correct
  /// project-specific database (see okapi_web_admin/auth.py
  /// mobile_request_project()). Falls back to the session's currently
  /// selected project if [project] isn't explicitly passed.
  Future<SyncResult> syncAll({
    required List<Menage> menages,
    required List<EnqueteChamp> champs,
    required List<EnqueteStructure> structures,
    Map<String, List<SurveyRecord>> surveyRecords = const {},
    String? project,
    // Deletions made locally that still need to be pushed to the server
    // (Req #3: propagate a deletion made on one tablet to every other
    // tablet + the web server). Each entry: {recordType, recordId,
    // tablette, deletedAt}.
    List<Map<String, dynamic>> deletions = const [],
  }) async {
    final url = await serverUrl;
    if (url.isEmpty) {
      return SyncResult(
        success: false,
        message:
            'Aucune adresse de serveur configurée. Veuillez renseigner l\'URL du serveur Web Admin OKAPI.',
      );
    }

    final targetProject = project ?? await SessionService.instance.project;

    final endpoint = Uri.parse('$url/api/sync');
    final payload = {
      'deviceId': await deviceId,
      'deviceName': await deviceName,
      'project': targetProject ?? 'wcag',
      'menages': menages.map((m) => m.toMap()).toList(),
      'champs': champs.map((c) => c.toMap()).toList(),
      'structures': structures.map((s) => s.toMap()).toList(),
      'survey_records': surveyRecords.map(
        (formKey, records) =>
            MapEntry(formKey, records.map((r) => r.toMap()).toList()),
      ),
      'deletions': deletions,
    };

    try {
      final response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        await _setLastSyncAt(DateTime.now());
        return SyncResult(
          success: true,
          message: 'Synchronisation réussie.',
          serverTotals: body['server_totals'] as Map<String, dynamic>?,
          received: body['received'] as Map<String, dynamic>?,
        );
      } else {
        return SyncResult(
          success: false,
          message:
              'Erreur du serveur (code ${response.statusCode}). Vérifiez l\'adresse ou réessayez plus tard.',
        );
      }
    } catch (e) {
      return SyncResult(
        success: false,
        message:
            'Connexion impossible au serveur. Vérifiez votre connexion internet/réseau et l\'adresse configurée.\n\nDétail : $e',
      );
    }
  }

  /// Fetches ALL Ménages, Enquêtes Champs and Enquêtes Structures currently
  /// stored on the OKAPI Web Admin server (including data pushed there by
  /// OTHER tablets) via GET /api/pull. Used by the "Actualiser" button so
  /// that a household registered on one tablet immediately becomes
  /// available in this tablet's own Champs/Structures survey forms.
  ///
  /// [project] selects which project's database to pull from (defaults to
  /// the current session's selected project).
  Future<PullResult> pullFromServer({String? project}) async {
    final url = await serverUrl;
    if (url.isEmpty) {
      return PullResult(
        success: false,
        message:
            'Aucune adresse de serveur configurée. Veuillez renseigner l\'URL du serveur Web Admin OKAPI.',
      );
    }

    final targetProject =
        (project ?? await SessionService.instance.project) ?? 'wcag';
    final endpoint = Uri.parse('$url/api/pull?project=$targetProject');
    try {
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 45));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        final menagesJson = (body['menages'] as List? ?? []);
        final champsJson = (body['champs'] as List? ?? []);
        final structuresJson = (body['structures'] as List? ?? []);

        final menages = <Menage>[];
        for (final m in menagesJson) {
          try {
            menages.add(Menage.fromMap(m as Map));
          } catch (_) {
            // Skip malformed records rather than aborting the whole pull.
          }
        }
        final champs = <EnqueteChamp>[];
        for (final c in champsJson) {
          try {
            champs.add(EnqueteChamp.fromMap(c as Map));
          } catch (_) {}
        }
        final structures = <EnqueteStructure>[];
        for (final s in structuresJson) {
          try {
            structures.add(EnqueteStructure.fromMap(s as Map));
          } catch (_) {}
        }

        // BIODIVERSITE/SOCIAL survey records: {formKey: [record, ...]}.
        final surveyRecordsJson =
            (body['survey_records'] as Map?)?.cast<String, dynamic>() ?? {};
        final surveyRecords = <String, List<SurveyRecord>>{};
        surveyRecordsJson.forEach((formKey, list) {
          final records = <SurveyRecord>[];
          for (final r in (list as List? ?? [])) {
            try {
              records.add(SurveyRecord.fromMap(Map<String, dynamic>.from(r as Map)));
            } catch (_) {}
          }
          surveyRecords[formKey] = records;
        });

        final deletionsJson = (body['deletions'] as List? ?? []);
        final deletions = <({String recordType, String recordId})>[];
        for (final d in deletionsJson) {
          if (d is Map) {
            final recordType = (d['recordType'] ?? '').toString();
            final recordId = (d['recordId'] ?? '').toString();
            if (recordType.isNotEmpty && recordId.isNotEmpty) {
              deletions.add((recordType: recordType, recordId: recordId));
            }
          }
        }

        await _setLastSyncAt(DateTime.now());
        return PullResult(
          success: true,
          message: 'Actualisation réussie.',
          menages: menages,
          champs: champs,
          structures: structures,
          surveyRecords: surveyRecords,
          deletions: deletions,
          serverTotals: body['totals'] as Map<String, dynamic>?,
        );
      } else {
        return PullResult(
          success: false,
          message:
              'Erreur du serveur (code ${response.statusCode}). Vérifiez l\'adresse ou réessayez plus tard.',
        );
      }
    } catch (e) {
      return PullResult(
        success: false,
        message:
            'Connexion impossible au serveur. Vérifiez votre connexion internet/réseau et l\'adresse configurée.\n\nDétail : $e',
      );
    }
  }

  /// Quick connectivity/health check against /api/status.
  Future<bool> testConnection(String url) async {
    try {
      final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
      final endpoint = Uri.parse('$normalized/api/status');
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
