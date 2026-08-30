import 'package:uuid/uuid.dart';

/// A single generic data record for ONE of the 11 BIODIVERSITE/SOCIAL
/// survey forms (identified by [formKey], matching a key in
/// lib/data/survey_schema.json, e.g. 'pose_cameras', 'socioeconomique').
///
/// Rather than one hand-coded Dart class per form (like Menage/EnqueteChamp/
/// EnqueteStructure), a single generic container is used, storing answers as
/// nested Maps that mirror the SurveySchema's field tree:
///  - [values]  holds every non-repeat field's answer, flattened by field
///    name (ODK field names are unique within a single form, group nesting
///    is purely presentational).
///  - [repeats] holds, for every repeat-kind node (by its `name`), the list
///    of entered instances. Each instance is itself a Map<String, dynamic>
///    that may contain further nested repeat lists under a child repeat's
///    name (this supports Chimpanzés Recce's 2-level nested repeat:
///    "observation" repeat containing an "Indice" repeat).
class SurveyRecord {
  String id;
  final String formKey;
  Map<String, dynamic> values;
  Map<String, List<Map<String, dynamic>>> repeats;
  DateTime createdAt;
  DateTime updatedAt;
  // Which project (simandou/wcag/smb) this record belongs to. Empty for
  // records created before this field existed (legacy local cache) — these
  // are treated as belonging to no project (excluded from every project's
  // filtered view) until re-synced from the server. See
  // SurveyDataProvider.setProject()/AppDataProvider's equivalent pattern
  // for Ménages/Champs/Structures.
  String project;

  SurveyRecord({
    String? id,
    required this.formKey,
    Map<String, dynamic>? values,
    Map<String, List<Map<String, dynamic>>>? repeats,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? project,
  }) : id = id ?? const Uuid().v4(),
       values = values ?? {},
       repeats = repeats ?? {},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       project = project ?? '';

  /// Convenience accessors mirroring the existing app's
  /// region/prefecture/sousPrefecture convention (used by LocationPickerField
  /// & the dashboard/list screens), backed by the generic [values] map.
  String get region => values['region']?.toString() ?? '';
  String get prefecture => values['prefecture']?.toString() ?? '';
  String get sousPrefecture => values['sous_prefecture']?.toString() ?? '';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'formKey': formKey,
      'values': values,
      'repeats': repeats.map(
        (k, v) =>
            MapEntry(k, v.map((e) => Map<String, dynamic>.from(e)).toList()),
      ),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'project': project,
    };
  }

  factory SurveyRecord.fromMap(Map<String, dynamic> map) {
    final rawRepeats = (map['repeats'] as Map?) ?? {};
    final repeats = <String, List<Map<String, dynamic>>>{};
    rawRepeats.forEach((key, value) {
      final list = (value as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      repeats[key.toString()] = list;
    });
    return SurveyRecord(
      id: map['id'] as String?,
      formKey: map['formKey'] as String,
      values: Map<String, dynamic>.from((map['values'] as Map?) ?? {}),
      repeats: repeats,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      project: map['project']?.toString() ?? '',
    );
  }
}
