import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/choice_item.dart';
import '../models/survey_field.dart';

/// Singleton loader for static JSON reference data bundled as assets:
/// - lib/data/choices.json         (ODK-style select_one choice lists - PARC module)
/// - lib/data/price_matrix.json    (OKAPI/AMC compensation price matrix)
/// - lib/data/guinea_admin.json    (Guinea region > préfecture > sous-préfecture)
/// - lib/data/survey_schema.json   (BIODIVERSITE/SOCIAL form schemas - 11 forms)
/// - lib/data/survey_choices.json  (BIODIVERSITE/SOCIAL choice lists, sv_ prefixed)
class ReferenceDataService {
  ReferenceDataService._();
  static final ReferenceDataService instance = ReferenceDataService._();

  Map<String, List<ChoiceItem>> _choices = {};
  Map<String, dynamic> _priceMatrix = {};
  Map<String, dynamic> _priceMatrixSimandou = {};
  Map<String, Map<String, List<String>>> _adminDivisions = {};
  Map<String, SurveySchema> _surveyForms = {};

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

    final priceSimandouRaw = await rootBundle.loadString(
      'lib/data/price_matrix_simandou.json',
    );
    _priceMatrixSimandou = jsonDecode(priceSimandouRaw) as Map<String, dynamic>;

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

    // BIODIVERSITE / SOCIAL survey choices (sv_ prefixed, no collision risk
    // with the PARC module's choices.json entries) - merge into _choices.
    final surveyChoicesRaw = await rootBundle.loadString(
      'lib/data/survey_choices.json',
    );
    final surveyChoicesJson =
        jsonDecode(surveyChoicesRaw) as Map<String, dynamic>;
    surveyChoicesJson.forEach((key, value) {
      final list = (value as List)
          .map((e) => ChoiceItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _choices[key] = list;
    });

    // BIODIVERSITE / SOCIAL survey form schemas (11 forms).
    final surveySchemaRaw = await rootBundle.loadString(
      'lib/data/survey_schema.json',
    );
    final surveySchemaJson =
        jsonDecode(surveySchemaRaw) as Map<String, dynamic>;
    _surveyForms = surveySchemaJson.map((key, value) {
      return MapEntry(
        key,
        SurveySchema.fromJson(value as Map<String, dynamic>),
      );
    });

    _loaded = true;
  }

  // ---------------- Survey forms (BIODIVERSITE / SOCIAL) ----------------
  Map<String, SurveySchema> get surveyForms => _surveyForms;

  SurveySchema? surveySchema(String key) => _surveyForms[key];

  List<SurveySchema> surveySchemasForModule(String module) {
    final list = _surveyForms.values.where((s) => s.module == module).toList();
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
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
  // The app currently ships two price matrices:
  //  - lib/data/price_matrix.json           (default, used by WCAG and SMB)
  //  - lib/data/price_matrix_simandou.json  (used by SIMANDOU project)
  // All lookup methods below accept an optional [project] argument
  // ('wcag' | 'simandou' | 'smb'); anything other than 'simandou' resolves
  // to the default (WCAG/SMB) price matrix.
  Map<String, dynamic> _matrixFor(String? project) =>
      project == 'simandou' ? _priceMatrixSimandou : _priceMatrix;

  Map<String, dynamic> priceMatrix({String? project}) => _matrixFor(project);

  List<Map<String, dynamic>> terrains({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['terrains'] ?? [],
      );

  List<Map<String, dynamic>> culturesAnnuelles({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['cultures_annuelles'] ?? [],
      );

  List<Map<String, dynamic>> culturesPerennes({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['cultures_perennes'] ?? [],
      );

  List<Map<String, dynamic>> especesSauvages({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['especes_sauvages'] ?? [],
      );

  List<Map<String, dynamic>> boisDoeuvre({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['bois_doeuvre'] ?? [],
      );

  List<Map<String, dynamic>> structuresPrix({String? project}) =>
      List<Map<String, dynamic>>.from(
        _matrixFor(project)['structures'] ?? [],
      );

  Map<String, dynamic>? terrainByType(String? type, {String? project}) {
    if (type == null) return null;
    try {
      return terrains(project: project).firstWhere((e) => e['type'] == type);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? culturePerenneByName(
    String? nomUsuel, {
    String? project,
  }) {
    if (nomUsuel == null) return null;
    try {
      return culturesPerennes(
        project: project,
      ).firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? especeSauvageByName(
    String? nomUsuel, {
    String? project,
  }) {
    if (nomUsuel == null) return null;
    try {
      return especesSauvages(
        project: project,
      ).firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? boisDoeuvreByName(String? nomUsuel, {String? project}) {
    if (nomUsuel == null) return null;
    try {
      return boisDoeuvre(
        project: project,
      ).firstWhere((e) => e['nom_usuel'] == nomUsuel);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? structureByDesignation(
    String? designation, {
    String? project,
  }) {
    if (designation == null) return null;
    try {
      return structuresPrix(
        project: project,
      ).firstWhere((e) => e['designation'] == designation);
    } catch (_) {
      return null;
    }
  }
}
