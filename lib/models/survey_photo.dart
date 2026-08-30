/// A single photo captured within a BIODIVERSITÉ/SOCIAL survey record,
/// resolved from a [SurveyRecord]'s `values`/`repeats` maps using the
/// owning [SurveySchema]'s `imageFields` (see survey_field.dart). Used to
/// build the per-module "Photos" gallery (aggregating every photo across
/// all records of every form in a module) and to support downloading a
/// photo to a chosen location ("enregistrer sous").
class SurveyPhoto {
  final String base64Data;
  final String formKey;
  final String formTitle;
  final String recordId;
  final String fieldLabel;
  // Non-null when the photo lives inside a repeat section instance (e.g.
  // "Identification espèce #2 — Photo espèce"); null for top-level fields.
  final String? repeatLabel;
  final int? repeatIndex;
  final DateTime updatedAt;

  const SurveyPhoto({
    required this.base64Data,
    required this.formKey,
    required this.formTitle,
    required this.recordId,
    required this.fieldLabel,
    required this.updatedAt,
    this.repeatLabel,
    this.repeatIndex,
  });

  /// Short human-readable caption, e.g. "Pose caméras — Photo dispositif"
  /// or "Poisson — Identification espèce #2 — Photo espèce".
  String get caption {
    final buf = StringBuffer(formTitle);
    if (repeatLabel != null) {
      buf.write(' — $repeatLabel');
      if (repeatIndex != null) buf.write(' #${repeatIndex! + 1}');
    }
    buf.write(' — $fieldLabel');
    return buf.toString();
  }

  /// Suggested file name for "enregistrer sous" downloads, safe for use on
  /// Android's filesystem (no slashes/accents-sensitive characters kept as
  /// simple ASCII-ish tokens).
  String suggestedFileName() {
    String slug(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final parts = [
      slug(formKey),
      if (repeatLabel != null) slug(repeatLabel!),
      if (repeatIndex != null) '${repeatIndex! + 1}',
      slug(fieldLabel),
      recordId.substring(0, recordId.length >= 6 ? 6 : recordId.length),
    ];
    return '${parts.where((p) => p.isNotEmpty).join('_')}.jpg';
  }
}
