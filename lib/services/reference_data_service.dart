import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/choice_item.dart';

/// Singleton loader for static JSON reference data bundled as assets:
/// - lib/data/choices.json      (ODK-style select_one choice lists)
/// - lib/data/price_matrix.json (OKAPI/AMC compensation price matrix)
/// - lib/data/guinea_admin.json (Guinea region > préfecture > sous-préfecture)
class ReferenceDataService {
  ReferenceDataService._();
  static final ReferenceDataService instance = ReferenceDataService._();

  Map<String, List<ChoiceItem>> _choices = {};
  Map<String, dynamic> _priceMatrix = {};
  Map<String, Map<String, List<String>>> _adminDivisions = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;

    final choicesRaw = await rootBundle.loadString('lib/data/choices.json');
    final choicesJson = jsonDecode(choicesRaw) as Map<String, dynamic>;
    _choices = choicesJson.map((key, value) {
      final list = (value as List)
          .map((e) => ChoiceItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return MapEntry(key, list);
    });

    final priceRaw = await rootBundle.loadString('lib/data/price_matrix.json');
    _priceMatrix = jsonDecode(priceRaw) as Map<String, dynamic>;

    final adminRaw = await rootBundle.loadString('lib/data/guinea_admin.json');
    final adminJson = jsonDecode(adminRaw) as Map<String, dynamic>;
    _adminDivisions = adminJson.map((region, prefMap) {
      final prefs = (prefMap as Map<String, dynamic>).map((pref, spList) {
        return MapEntry(
          pref,
          (spList as List).map((e) => e.toString()).toList(),
        );
      });
      return MapEntry(region, prefs);
    });

    _loaded = true;
  }

  // ---------------- Choices ----------------
  List<ChoiceItem> choices(String listName) => _choices[listName] ?? [];

  List<ChoiceItem> choicesFiltered(String listName, String? filterType) {
    final list = choices(listName);
    if (filterType == null || filterType.isEmpty) return list;
    return list.where((c) => c.type == filterType).toList();
  }

  ChoiceItem? findChoice(String listName, String? name) {
    if (name == null) return null;
    try {
      return choices(listName).firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  String labelFor(String listName, String? name) {
    if (name == null || name.isEmpty) return '';
    final c = findChoice(listName, name);
    return c?.label ?? name;
  }

  // ---------------- Guinea Admin ----------------
  List<String> get regions => _adminDivisions.keys.toList()..sort();

  List<String> prefecturesFor(String? region) {
    if (region == null) return [];
    final prefs = _adminDivisions[region]?.keys.toList() ?? [];
    prefs.sort();
    return prefs;
  }

  List<String> sousPrefecturesFor(String? region, String? prefecture) {
    if (region == null || prefecture == null) return [];
    final list = _adminDivisions[region]?[prefecture] ?? [];
    final sorted = List<String>.from(list)..sort();
    return sorted;
  }

  // ---------------- Price matrix ----------------
  Map<String, dynamic> get priceMatrix => _priceMatrix;

  List<Map<String, dynamic>> get terrains =>
      List<Map<String, dynamic>>.from(_priceMatrix['terrains'] ?? []);

  List<Map<String, dynamic>> get culturesAnnuelles =>
      List<Map<String, dynamic>>.from(_priceMatrix['cultures_annuelles'] ?? []);

  List<Map<String, dynamic>> get culturesPerennes =>
      List<Map<String, dynamic>>.from(_priceMatrix['cultures_perennes'] ?? []);

  List<Map<String, dynamic>> get especesSauvages =>
      List<Map<String, dynamic>>.from(_priceMatrix['especes_sauvages'] ?? []);

  List<Map<String, dynamic>> get boisDoeuvre =>
      List<Map<String, dynamic>>.from(_priceMatrix['bois_doeuvre'] ?? []);

  List<Map<String, dynamic>> get structuresPrix =>
      List<Map<String, dynamic>>.from(_priceMatrix['structures'] ?? []);

  Map<String, dynamic>? terrainByType(String? type) {
    if (type == null) return null;
    try {
      return terrains.firstWhere((e) => e['type'] == type);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? culturePerenneByName(String? nomUsuel) {
    if (nomUsuel == null) return null;
    try {
      return culturesPerennes.firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? especeSauvageByName(String? nomUsuel) {
    if (nomUsuel == null) return null;
    try {
      return especesSauvages.firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? boisDoeuvreByName(String? nomUsuel) {
    if (nomUsuel == null) return null;
    try {
      return boisDoeuvre.firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? structureByDesignation(String? designation) {
    if (designation == null) return null;
    try {
      return structuresPrix.firstWhere((e) => e['designation'] == designation);
    } catch (_) {
      return null;
    }
  }
}
