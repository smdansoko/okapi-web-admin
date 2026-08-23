import 'package:flutter/material.dart';

/// Maps the `icon` string stored in each [SurveySchema] (see survey_field.dart)
/// to an actual Material [IconData]. Icon name strings are assigned in the
/// form-extraction pipeline (extract_forms.py `SRC` dict) and copied verbatim
/// into lib/data/survey_schema.json.
const Map<String, IconData> surveyIconMap = {
  'camera': Icons.camera_alt,
  'eco': Icons.eco,
  'set_meal': Icons.set_meal,
  'local_florist': Icons.local_florist,
  'flutter_dash': Icons.flutter_dash,
  'pest_control': Icons.pest_control,
  'water_drop': Icons.water_drop,
  'pets': Icons.pets,
  'apartment': Icons.apartment,
  'temple_buddhist': Icons.temple_buddhist,
  'bar_chart': Icons.bar_chart,
};

IconData surveyIconFor(String? name) {
  if (name == null) return Icons.description;
  return surveyIconMap[name] ?? Icons.description;
}
