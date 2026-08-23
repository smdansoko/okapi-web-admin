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
    await _storage.deleteMenage(id);
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
    await _storage.deleteChamp(id);
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
    await _storage.deleteStructureEnquete(id);
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
  }) async {
    for (final menage in menages) {
      await _storage.saveMenage(menage);
      final idx = _menages.indexWhere((m) => m.id == menage.id);
      if (idx >= 0) {
        _menages[idx] = menage;
      } else {
        _menages.insert(0, menage);
      }
    }
    for (final champ in champs) {
      await _storage.saveChamp(champ);
      final idx = _champs.indexWhere((c) => c.id == champ.id);
      if (idx >= 0) {
        _champs[idx] = champ;
      } else {
        _champs.insert(0, champ);
      }
    }
    for (final structure in structures) {
      await _storage.saveStructureEnquete(structure);
      final idx = _structures.indexWhere((s) => s.id == structure.id);
      if (idx >= 0) {
        _structures[idx] = structure;
      } else {
        _structures.insert(0, structure);
      }
    }
    notifyListeners();
  }

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
