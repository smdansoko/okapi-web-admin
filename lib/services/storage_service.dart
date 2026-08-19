import 'package:hive_flutter/hive_flutter.dart';
import '../models/menage.dart';
import '../models/enquete_champ.dart';
import '../models/structure.dart';

/// Local persistence layer using Hive boxes storing raw Maps
/// (avoids needing generated TypeAdapters, keeps models simple and portable).
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String boxMenages = 'menages';
  static const String boxChamps = 'enquetes_champs';
  static const String boxStructures = 'enquetes_structures';

  late Box _menagesBox;
  late Box _champsBox;
  late Box _structuresBox;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _menagesBox = await Hive.openBox(boxMenages);
    _champsBox = await Hive.openBox(boxChamps);
    _structuresBox = await Hive.openBox(boxStructures);
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

  Future<void> saveMenage(Menage menage) async {
    menage.updatedAt = DateTime.now();
    await _menagesBox.put(menage.id, menage.toMap());
  }

  Future<void> deleteMenage(String id) async {
    await _menagesBox.delete(id);
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

  Future<void> saveChamp(EnqueteChamp enquete) async {
    enquete.updatedAt = DateTime.now();
    await _champsBox.put(enquete.id, enquete.toMap());
  }

  Future<void> deleteChamp(String id) async {
    await _champsBox.delete(id);
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

  Future<void> saveStructureEnquete(EnqueteStructure enquete) async {
    enquete.updatedAt = DateTime.now();
    await _structuresBox.put(enquete.id, enquete.toMap());
  }

  Future<void> deleteStructureEnquete(String id) async {
    await _structuresBox.delete(id);
  }

  // ---------------- Utility / Seed ----------------
  Future<void> clearAll() async {
    await _menagesBox.clear();
    await _champsBox.clear();
    await _structuresBox.clear();
  }

  int get menagesCount => _menagesBox.length;
  int get champsCount => _champsBox.length;
  int get structuresCount => _structuresBox.length;
}
