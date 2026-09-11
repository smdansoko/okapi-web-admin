import 'package:flutter/foundation.dart';
import '../models/survey_record.dart';
import 'storage_service.dart';

/// The 8 BIODIVERSITÉ survey form keys (see lib/data/survey_schema.json).
/// Exposed as a top-level constant so other files (SyncScreen) can filter
/// data by module without duplicating this list.
const List<String> kBiodiversiteFormKeys = [
  'pose_cameras',
  'chimpanzes_recce',
  'poisson',
  'flore',
  'oiseaux',
  'reptiles',
  'amphibiens',
  'mammiferes',
];

/// The 3 SOCIAL survey form keys (see lib/data/survey_schema.json).
const List<String> kSocialFormKeys = [
  'infrastructures',
  'patrimoine_culturel',
  'socioeconomique',
];

/// Central state holder for the 11 BIODIVERSITE/SOCIAL survey forms
/// (Pose caméras, Chimpanzés Recce, Poisson, Flore, Oiseaux, Reptiles,
/// Amphibiens, Mammifères, Infrastructures de base, Patrimoine culturel,
/// Socioéconomique). Mirrors [AppDataProvider]'s pattern (used for
/// Ménage/Champs/Structures) but generically, keyed by `formKey`, since all
/// 11 forms share one rendering/storage pipeline (see SurveySchema /
/// SurveyRecord / SurveyFormRenderer).
class SurveyDataProvider extends ChangeNotifier {
  final _storage = StorageService.instance;

  final Map<String, List<SurveyRecord>> _records = {};

  // The currently active project (simandou/wcag/smb), set via [setProject]
  // once the user has chosen a project (see RootShell.initState, mirroring
  // AppDataProvider's own pattern). All public getters below are FILTERED
  // by this value so a BIODIVERSITÉ/SOCIAL record belonging to one project
  // never leaks into another project's dashboard/list — this is the fix
  // for "les mêmes chiffres dans les tableaux de bord de tous les projets"
  // reported for the BIODIVERSITÉ/SOCIAL module dashboards.
  String? _activeProject;

  void setProject(String? project) {
    if (_activeProject == project) return;
    _activeProject = project;
    notifyListeners();
  }

  List<SurveyRecord> recordsFor(String formKey) {
    final list = _records[formKey] ?? const [];
    if (_activeProject == null) return List.unmodifiable(list);
    return List.unmodifiable(
      list.where((r) => r.project == _activeProject).toList(),
    );
  }

  int countFor(String formKey) => recordsFor(formKey).length;

  Future<void> loadAll(List<String> formKeys) async {
    for (final key in formKeys) {
      _records[key] = _storage.getAllSurveyRecords(key);
    }
    notifyListeners();
  }

  Future<void> loadForm(String formKey) async {
    _records[formKey] = _storage.getAllSurveyRecords(formKey);
    notifyListeners();
  }

  SurveyRecord? recordById(String formKey, String id) {
    final list = _records[formKey];
    if (list == null) return null;
    try {
      return list.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRecord(SurveyRecord record) async {
    if (record.project.isEmpty && _activeProject != null) {
      record.project = _activeProject!;
    }
    await _storage.saveSurveyRecord(record);
    final list = _records.putIfAbsent(record.formKey, () => []);
    final idx = list.indexWhere((r) => r.id == record.id);
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.insert(0, record);
    }
    notifyListeners();
  }

  Future<void> deleteRecord(String formKey, String id) async {
    await _storage.deleteSurveyRecord(formKey, id);
    _records[formKey]?.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Bulk-upsert records pulled from the OKAPI Web Admin server (sync).
  ///
  /// Server responses may not carry a `project` field (server DB is
  /// already project-scoped per project database, see okapi_web_admin/
  /// db.py); stamp it here from the active project so the pulled record
  /// is correctly filterable locally too (mirrors AppDataProvider's
  /// mergeFromServer behaviour for Ménages/Champs/Structures).
  Future<void> mergeFromServer(
    Map<String, List<SurveyRecord>> byFormKey,
  ) async {
    for (final entry in byFormKey.entries) {
      final formKey = entry.key;
      final list = _records.putIfAbsent(formKey, () => []);
      for (final record in entry.value) {
        if (record.project.isEmpty && _activeProject != null) {
          record.project = _activeProject!;
        }
        final idx = list.indexWhere((r) => r.id == record.id);
        // Last-write-wins: only overwrite the local copy if the server's
        // version is not older than what we already have locally.
        if (idx >= 0 && record.updatedAt.isBefore(list[idx].updatedAt)) {
          continue;
        }
        await _storage.saveSurveyRecord(record);
        if (idx >= 0) {
          list[idx] = record;
        } else {
          list.insert(0, record);
        }
      }
    }
    notifyListeners();
  }

  // -------- Aggregates for dashboard --------
  int totalFor(String formKey) => countFor(formKey);

  int get totalBiodiversiteRecords =>
      kBiodiversiteFormKeys.fold(0, (sum, k) => sum + countFor(k));

  int get totalSocialRecords =>
      kSocialFormKeys.fold(0, (sum, k) => sum + countFor(k));

  /// All BIODIVERSITÉ records across all 8 forms, keyed by formKey — used
  /// by SyncScreen to push/pull ONLY this module's data.
  Map<String, List<SurveyRecord>> recordsForBiodiversite() => {
    for (final key in kBiodiversiteFormKeys) key: recordsFor(key),
  };

  /// All SOCIAL records across all 3 forms, keyed by formKey — used by
  /// SyncScreen to push/pull ONLY this module's data.
  Map<String, List<SurveyRecord>> recordsForSocial() => {
    for (final key in kSocialFormKeys) key: recordsFor(key),
  };
}
