import 'package:hive_flutter/hive_flutter.dart';
import '../models/menage.dart';
import '../models/enquete_champ.dart';
import '../models/structure.dart';
import '../models/survey_record.dart';

/// Local persistence layer using Hive boxes storing raw Maps
/// (avoids needing generated TypeAdapters, keeps models simple and portable).
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String boxMenages = 'menages';
  static const String boxChamps = 'enquetes_champs';
  static const String boxStructures = 'enquetes_structures';
  // Single generic box for all 11 BIODIVERSITE/SOCIAL survey forms, keyed
  // by 'formKey:recordId' so all forms can share one box without collisions.
  static const String boxSurveyRecords = 'survey_records';
  // Deletions made locally (via deleteMenage/deleteChamp/
  // deleteStructureEnquete) that still need to be pushed to the server on
  // the next "Synchroniser", so the deletion propagates to every other
  // tablet. Keyed by 'recordType:recordId'. Cleared once successfully
  // pushed. See SyncService.syncAll()/AppDataProvider for the propagation
  // flow (Req #3: "quand un enregistrement est supprimé sur une tablette,
  // qu'il soit également supprimé sur toutes les tablettes et sur le
  // serveur web").
  static const String boxPendingDeletions = 'pending_deletions';

  late Box _menagesBox;
  late Box _champsBox;
  late Box _structuresBox;
  late Box _surveyRecordsBox;
  late Box _pendingDeletionsBox;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _menagesBox = await Hive.openBox(boxMenages);
    _champsBox = await Hive.openBox(boxChamps);
    _structuresBox = await Hive.openBox(boxStructures);
    _surveyRecordsBox = await Hive.openBox(boxSurveyRecords);
    _pendingDeletionsBox = await Hive.openBox(boxPendingDeletions);
    _initialized = true;
  }

  // ---------------- Ménages ----------------
  List<Menage> getAllMenages() {
    return _menagesBox.values
        .map((e) => Menage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Menage? getMenage(String id) {
    final raw = _menagesBox.get(id);
    if (raw == null) return null;
    return Menage.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  /// [bumpTimestamp] is true for genuine local edits (default — stamps
  /// `updatedAt` = now so this device's edit "wins" the next sync), and
  /// false when merging a record fetched from the server during pull-sync
  /// (preserves the server's own `updatedAt` so later last-write-wins
  /// comparisons stay accurate across tablets).
  Future<void> saveMenage(Menage menage, {bool bumpTimestamp = true}) async {
    if (bumpTimestamp) menage.updatedAt = DateTime.now();
    await _menagesBox.put(menage.id, menage.toMap());
  }

  Future<void> deleteMenage(String id, {String tablette = ''}) async {
    await _menagesBox.delete(id);
    await _recordPendingDeletion('menage', id, tablette);
  }

  // ---------------- Enquêtes Champs ----------------
  List<EnqueteChamp> getAllChamps() {
    return _champsBox.values
        .map((e) => EnqueteChamp.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  EnqueteChamp? getChamp(String id) {
    final raw = _champsBox.get(id);
    if (raw == null) return null;
    return EnqueteChamp.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveChamp(EnqueteChamp enquete, {bool bumpTimestamp = true}) async {
    if (bumpTimestamp) enquete.updatedAt = DateTime.now();
    await _champsBox.put(enquete.id, enquete.toMap());
  }

  Future<void> deleteChamp(String id, {String tablette = ''}) async {
    await _champsBox.delete(id);
    await _recordPendingDeletion('champ', id, tablette);
  }

  // ---------------- Enquêtes Structures ----------------
  List<EnqueteStructure> getAllStructures() {
    return _structuresBox.values
        .map(
          (e) => EnqueteStructure.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  EnqueteStructure? getStructureEnquete(String id) {
    final raw = _structuresBox.get(id);
    if (raw == null) return null;
    return EnqueteStructure.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveStructureEnquete(
    EnqueteStructure enquete, {
    bool bumpTimestamp = true,
  }) async {
    if (bumpTimestamp) enquete.updatedAt = DateTime.now();
    await _structuresBox.put(enquete.id, enquete.toMap());
  }

  Future<void> deleteStructureEnquete(String id, {String tablette = ''}) async {
    await _structuresBox.delete(id);
    await _recordPendingDeletion('structure', id, tablette);
  }

  // ---------------- Survey records (BIODIVERSITE / SOCIAL, generic) ----------------
  String _surveyKey(String formKey, String id) => '$formKey:$id';

  List<SurveyRecord> getAllSurveyRecords(String formKey) {
    final prefix = '$formKey:';
    return _surveyRecordsBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .map(
          (k) => SurveyRecord.fromMap(
            Map<String, dynamic>.from(_surveyRecordsBox.get(k) as Map),
          ),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  SurveyRecord? getSurveyRecord(String formKey, String id) {
    final raw = _surveyRecordsBox.get(_surveyKey(formKey, id));
    if (raw == null) return null;
    return SurveyRecord.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveSurveyRecord(SurveyRecord record) async {
    record.updatedAt = DateTime.now();
    await _surveyRecordsBox.put(
      _surveyKey(record.formKey, record.id),
      record.toMap(),
    );
  }

  Future<void> deleteSurveyRecord(String formKey, String id) async {
    await _surveyRecordsBox.delete(_surveyKey(formKey, id));
  }

  int surveyRecordsCount(String formKey) {
    final prefix = '$formKey:';
    return _surveyRecordsBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .length;
  }

  // ---------------- Pending deletions (push side of Req #3) ----------------
  String _deletionKey(String recordType, String recordId) =>
      '$recordType:$recordId';

  Future<void> _recordPendingDeletion(
    String recordType,
    String recordId,
    String tablette,
  ) async {
    await _pendingDeletionsBox.put(_deletionKey(recordType, recordId), {
      'recordType': recordType,
      'recordId': recordId,
      'tablette': tablette,
      'deletedAt': DateTime.now().toIso8601String(),
    });
  }

  /// All deletions made locally that still need to be pushed to the server
  /// (via SyncService.syncAll()) so other tablets learn about them too.
  List<Map<String, dynamic>> getPendingDeletions() {
    return _pendingDeletionsBox.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Clears the given (recordType, recordId) pairs from the pending-push
  /// queue once the server has confirmed it received them.
  Future<void> clearPendingDeletions(
    Iterable<({String recordType, String recordId})> keys,
  ) async {
    for (final k in keys) {
      await _pendingDeletionsBox.delete(_deletionKey(k.recordType, k.recordId));
    }
  }

  /// Applies a deletion tombstone RECEIVED from the server (i.e. a record
  /// deleted on another tablet) to this tablet's own local storage, without
  /// re-queuing it as a pending push (it already originated from a delete
  /// pushed by another tablet, or was already pushed by us).
  Future<void> applyRemoteDeletion(String recordType, String recordId) async {
    switch (recordType) {
      case 'menage':
        await _menagesBox.delete(recordId);
        break;
      case 'champ':
        await _champsBox.delete(recordId);
        break;
      case 'structure':
        await _structuresBox.delete(recordId);
        break;
    }
    // If we had a pending (not-yet-pushed) deletion queued for this same
    // record, it's now moot since the server (or another tablet) already
    // knows about it — clear it to avoid a redundant future push.
    await _pendingDeletionsBox.delete(_deletionKey(recordType, recordId));
  }

  // ---------------- Utility / Seed ----------------
  Future<void> clearAll() async {
    await _menagesBox.clear();
    await _champsBox.clear();
    await _structuresBox.clear();
    await _surveyRecordsBox.clear();
    await _pendingDeletionsBox.clear();
  }

  int get menagesCount => _menagesBox.length;
  int get champsCount => _champsBox.length;
  int get structuresCount => _structuresBox.length;
}
