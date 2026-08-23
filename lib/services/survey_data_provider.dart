import 'package:flutter/foundation.dart';
import '../models/survey_record.dart';
import 'storage_service.dart';

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

  List<SurveyRecord> recordsFor(String formKey) =>
      List.unmodifiable(_records[formKey] ?? const []);

  int countFor(String formKey) => _records[formKey]?.length ?? 0;

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
  Future<void> mergeFromServer(
    Map<String, List<SurveyRecord>> byFormKey,
  ) async {
    for (final entry in byFormKey.entries) {
      final formKey = entry.key;
      final list = _records.putIfAbsent(formKey, () => []);
      for (final record in entry.value) {
        await _storage.saveSurveyRecord(record);
        final idx = list.indexWhere((r) => r.id == record.id);
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

  int get totalBiodiversiteRecords {
    const keys = [
      'pose_cameras',
      'chimpanzes_recce',
      'poisson',
      'flore',
      'oiseaux',
      'reptiles',
      'amphibiens',
      'mammiferes',
    ];
    return keys.fold(0, (sum, k) => sum + countFor(k));
  }

  int get totalSocialRecords {
    const keys = ['infrastructures', 'patrimoine_culturel', 'socioeconomique'];
    return keys.fold(0, (sum, k) => sum + countFor(k));
  }
}
