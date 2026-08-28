import 'package:flutter/foundation.dart';
import '../models/menage.dart';
import '../models/individu.dart';
import '../models/enquete_champ.dart';
import '../models/structure.dart';
import 'storage_service.dart';

/// Central app state: households, field surveys and structure surveys.
/// Notifies listeners so that "Enquête Champs" and "Enquête Structures"
/// screens automatically see newly added ménages/individus.
class AppDataProvider extends ChangeNotifier {
  final _storage = StorageService.instance;

  List<Menage> _menages = [];
  List<EnqueteChamp> _champs = [];
  List<EnqueteStructure> _structures = [];

  List<Menage> get menages => List.unmodifiable(_menages);
  List<EnqueteChamp> get champs => List.unmodifiable(_champs);
  List<EnqueteStructure> get structures => List.unmodifiable(_structures);

  Future<void> loadAll() async {
    _menages = _storage.getAllMenages();
    _champs = _storage.getAllChamps();
    _structures = _storage.getAllStructures();
    notifyListeners();
  }

  // -------- Ménages --------
  Future<void> saveMenage(Menage menage) async {
    await _storage.saveMenage(menage);
    final idx = _menages.indexWhere((m) => m.id == menage.id);
    if (idx >= 0) {
      _menages[idx] = menage;
    } else {
      _menages.insert(0, menage);
    }
    notifyListeners();
  }

  Future<void> deleteMenage(String id) async {
    final tablette = menageById(id)?.tablette ?? '';
    await _storage.deleteMenage(id, tablette: tablette);
    _menages.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  Menage? menageById(String id) {
    try {
      return _menages.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// All individus across all ménages belonging to [codeMenage], for the
  /// "Sélectionnez le propriétaire" cascading picker (choice_filter type=${code_menage}).
  List<Individu> individusForMenage(String codeMenage) {
    final menage = menageById(codeMenage);
    return menage?.individus ?? [];
  }

  // -------- Enquêtes Champs --------
  Future<void> saveChamp(EnqueteChamp enquete) async {
    await _storage.saveChamp(enquete);
    final idx = _champs.indexWhere((c) => c.id == enquete.id);
    if (idx >= 0) {
      _champs[idx] = enquete;
    } else {
      _champs.insert(0, enquete);
    }
    notifyListeners();
  }

  Future<void> deleteChamp(String id) async {
    final idx = _champs.indexWhere((c) => c.id == id);
    final tablette = idx >= 0 ? _champs[idx].tablette : '';
    await _storage.deleteChamp(id, tablette: tablette);
    _champs.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // -------- Enquêtes Structures --------
  Future<void> saveStructureEnquete(EnqueteStructure enquete) async {
    await _storage.saveStructureEnquete(enquete);
    final idx = _structures.indexWhere((s) => s.id == enquete.id);
    if (idx >= 0) {
      _structures[idx] = enquete;
    } else {
      _structures.insert(0, enquete);
    }
    notifyListeners();
  }

  Future<void> deleteStructureEnquete(String id) async {
    final idx = _structures.indexWhere((s) => s.id == id);
    final tablette = idx >= 0 ? _structures[idx].tablette : '';
    await _storage.deleteStructureEnquete(id, tablette: tablette);
    _structures.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // -------- Cross-tablet pull-sync (merge data pulled from server) --------
  /// Bulk-upserts ménages/enquêtes fetched from the OKAPI Web Admin server
  /// (via SyncService.pullFromServer()) into local storage, so that
  /// households/records registered on ANOTHER tablet become immediately
  /// available in this tablet's own Champs/Structures survey forms
  /// (ménage picker, propriétaire picker, etc.).
  ///
  /// Matches by `id` (codeMenage / codeEnquete): existing local records are
  /// overwritten with the server's version, new ones are inserted. Only a
  /// single [notifyListeners] call is made at the end, once all records
  /// have been merged, so the UI does not rebuild once per record.
  Future<void> mergeFromServer({
    List<Menage> menages = const [],
    List<EnqueteChamp> champs = const [],
    List<EnqueteStructure> structures = const [],
    // Deletion tombstones (recordType/recordId pairs) fetched from the
    // server's /api/pull response: records deleted on ANOTHER tablet (or
    // pushed as a deletion by this same tablet) must also disappear here.
    // See Req #3: "quand un enregistrement est supprimé sur une tablette,
    // qu'il soit également supprimé sur toutes les tablettes".
    List<({String recordType, String recordId})> deletions = const [],
  }) async {
    // Apply deletions FIRST so a stale/late-arriving upsert for an
    // already-deleted id (e.g. from a tablet that hadn't yet learned about
    // the deletion when it queued its own sync) doesn't resurrect it.
    final deletedMenageIds = <String>{};
    final deletedChampIds = <String>{};
    final deletedStructureIds = <String>{};
    for (final d in deletions) {
      await _storage.applyRemoteDeletion(d.recordType, d.recordId);
      switch (d.recordType) {
        case 'menage':
          deletedMenageIds.add(d.recordId);
          break;
        case 'champ':
          deletedChampIds.add(d.recordId);
          break;
        case 'structure':
          deletedStructureIds.add(d.recordId);
          break;
      }
    }
    if (deletedMenageIds.isNotEmpty) {
      _menages.removeWhere((m) => deletedMenageIds.contains(m.id));
    }
    if (deletedChampIds.isNotEmpty) {
      _champs.removeWhere((c) => deletedChampIds.contains(c.id));
    }
    if (deletedStructureIds.isNotEmpty) {
      _structures.removeWhere((s) => deletedStructureIds.contains(s.id));
    }

    for (final menage in menages) {
      if (deletedMenageIds.contains(menage.id)) continue;
      final idx = _menages.indexWhere((m) => m.id == menage.id);
      // Last-write-wins: only overwrite the local copy if the server's
      // version is not older than what we already have locally (protects
      // a newer local edit from being clobbered by a stale server record
      // during a pull that races with another tablet's older push).
      if (idx >= 0 && menage.updatedAt.isBefore(_menages[idx].updatedAt)) {
        continue;
      }
      await _storage.saveMenage(menage, bumpTimestamp: false);
      if (idx >= 0) {
        _menages[idx] = menage;
      } else {
        _menages.insert(0, menage);
      }
    }
    for (final champ in champs) {
      if (deletedChampIds.contains(champ.id)) continue;
      final idx = _champs.indexWhere((c) => c.id == champ.id);
      if (idx >= 0 && champ.updatedAt.isBefore(_champs[idx].updatedAt)) {
        continue;
      }
      await _storage.saveChamp(champ, bumpTimestamp: false);
      if (idx >= 0) {
        _champs[idx] = champ;
      } else {
        _champs.insert(0, champ);
      }
    }
    for (final structure in structures) {
      if (deletedStructureIds.contains(structure.id)) continue;
      final idx = _structures.indexWhere((s) => s.id == structure.id);
      if (idx >= 0 && structure.updatedAt.isBefore(_structures[idx].updatedAt)) {
        continue;
      }
      await _storage.saveStructureEnquete(structure, bumpTimestamp: false);
      if (idx >= 0) {
        _structures[idx] = structure;
      } else {
        _structures.insert(0, structure);
      }
    }
    notifyListeners();
  }

  // -------- Pending deletions (push side of Req #3) --------
  /// Deletions made locally that still need to be pushed to the server via
  /// SyncService.syncAll(), so the deletion propagates to other tablets.
  List<Map<String, dynamic>> get pendingDeletions =>
      _storage.getPendingDeletions();

  Future<void> clearPendingDeletions(
    Iterable<({String recordType, String recordId})> keys,
  ) => _storage.clearPendingDeletions(keys);

  // -------- Aggregates for dashboard --------
  int get totalMenages => _menages.length;
  int get totalIndividus =>
      _menages.fold(0, (sum, m) => sum + m.individus.length);
  int get totalParcelles =>
      _champs.fold(0, (sum, c) => sum + c.parcelles.length);
  int get totalStructures =>
      _structures.fold(0, (sum, s) => sum + s.structures.length);

  double get totalSuperficieParcelles => _champs.fold(
    0.0,
    (sum, c) =>
        sum + c.parcelles.fold(0.0, (s2, p) => s2 + p.superficieParcelle),
  );
}
