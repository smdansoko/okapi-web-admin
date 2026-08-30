/// Generic data-driven survey engine models.
///
/// The 11 BIODIVERSITÉ / SOCIAL survey forms (Pose caméras, Chimpanzés
/// Recce, Poisson, Flore, Oiseaux, Reptiles, Amphibiens, Mammifères,
/// Infrastructures de base, Patrimoine culturel, Socioéconomique) are far
/// too numerous/large (up to ~300 fields for Socioéconomique) to hand-code
/// as 11 separate Dart models + screens like Menage/EnqueteChamp did.
///
/// Instead, this engine parses a JSON schema (lib/data/survey_schema.json,
/// generated from the uploaded XLSForm .xlsx files) describing each form's
/// fields/groups/repeats, and renders/stores them generically, while fully
/// reusing the existing app widgets (ChoiceDropdown, LabeledTextField,
/// LocationPickerField, RepeatSection) and services (ReferenceDataService,
/// StorageService pattern, SyncService).
library;

/// A single node in a survey's field tree: either a leaf field, a group
/// (field-list section, always visible together) or a repeat (dynamic list
/// of entries, like "Indice Caméra" or "Info individus").
class SurveyNode {
  final String kind; // 'field' | 'group' | 'repeat'
  final String name;
  final String? label;

  // group/repeat
  final List<SurveyNode> children;

  // field-only
  final String?
  type; // text/integer/decimal/date/time/geopoint/image/select_one/select_multiple
  final String? hint;
  final String? appearance;
  final String?
  listName; // key into survey_choices.json, or 'region'/'prefecture'/'sous_prefecture'
  final bool required;
  final String? choiceFilter; // e.g. "filter=${region}" or "type=${region}"
  final String? relevant; // ODK-XPath-lite relevant expression
  final String? calculation;
  final String? constraint;
  final bool readOnly;
  final String? defaultValue;

  SurveyNode({
    required this.kind,
    required this.name,
    this.label,
    List<SurveyNode>? children,
    this.type,
    this.hint,
    this.appearance,
    this.listName,
    this.required = false,
    this.choiceFilter,
    this.relevant,
    this.calculation,
    this.constraint,
    this.readOnly = false,
    this.defaultValue,
  }) : children = children ?? [];

  factory SurveyNode.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    return SurveyNode(
      kind: kind,
      name: json['name'] as String,
      label: json['label'] as String?,
      children: kind == 'field'
          ? const []
          : (json['children'] as List)
                .map((e) => SurveyNode.fromJson(e as Map<String, dynamic>))
                .toList(),
      type: json['type'] as String?,
      hint: json['hint'] as String?,
      appearance: json['appearance'] as String?,
      listName: json['listName'] as String?,
      required: json['required'] as bool? ?? false,
      choiceFilter: json['choiceFilter'] as String?,
      relevant: json['relevant'] as String?,
      calculation: json['calculation'] as String?,
      constraint: json['constraint'] as String?,
      readOnly: json['readOnly'] as bool? ?? false,
      defaultValue: json['default']?.toString(),
    );
  }

  bool get isGroup => kind == 'group';
  bool get isRepeat => kind == 'repeat';
  bool get isField => kind == 'field';

  /// True for the 3 special admin-division fields wired to guinea_admin.json
  /// (region / prefecture / sous_prefecture) instead of survey_choices.json.
  bool get isAdminDivisionField =>
      isField &&
      type == 'select_one' &&
      (name == 'region' || name == 'prefecture' || name == 'sous_prefecture');
}

/// Top-level definition of one survey form (one of the 11 BIODIVERSITÉ /
/// SOCIAL forms).
class SurveySchema {
  final String key; // e.g. 'pose_cameras'
  final String module; // 'BIODIVERSITE' | 'SOCIAL'
  final String title; // display title, e.g. 'Pose caméras'
  final String icon; // Material icon name (mapped in survey_icons.dart)
  final List<SurveyNode> fields;

  SurveySchema({
    required this.key,
    required this.module,
    required this.title,
    required this.icon,
    required this.fields,
  });

  factory SurveySchema.fromJson(Map<String, dynamic> json) {
    return SurveySchema(
      key: json['key'] as String,
      module: json['module'] as String,
      title: json['title'] as String,
      icon: json['icon'] as String,
      fields: (json['fields'] as List)
          .map((e) => SurveyNode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Recursively walks [fields] and returns every `image`-type field found,
  /// whether it sits at the top level or nested inside a repeat section.
  /// Used to build the "Photos" gallery (aggregating every photo captured
  /// across all records of a form) without hardcoding field names per form
  /// — stays automatically in sync with lib/data/survey_schema.json.
  List<SurveyImageFieldRef> get imageFields {
    final out = <SurveyImageFieldRef>[];
    void walk(List<SurveyNode> nodes, String? repeatName, String? repeatLabel) {
      for (final n in nodes) {
        if (n.isField && n.type == 'image') {
          out.add(
            SurveyImageFieldRef(
              fieldName: n.name,
              fieldLabel: n.label ?? n.name,
              repeatName: repeatName,
              repeatLabel: repeatLabel,
            ),
          );
        } else if (n.isRepeat) {
          walk(n.children, n.name, n.label ?? n.name);
        } else if (n.children.isNotEmpty) {
          walk(n.children, repeatName, repeatLabel);
        }
      }
    }

    walk(fields, null, null);
    return out;
  }
}

/// Reference to one `image`-type field within a [SurveySchema], noting
/// whether it lives at the top level (values map) or inside a repeat
/// section's instances (repeats map), so photo-aggregation code knows where
/// to look up the base64 data on a [SurveyRecord].
class SurveyImageFieldRef {
  final String fieldName;
  final String fieldLabel;
  final String? repeatName; // null if top-level (not inside a repeat)
  final String? repeatLabel;

  const SurveyImageFieldRef({
    required this.fieldName,
    required this.fieldLabel,
    this.repeatName,
    this.repeatLabel,
  });

  bool get isInRepeat => repeatName != null;
}
