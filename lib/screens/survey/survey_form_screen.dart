import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/survey_field.dart';
import '../../models/survey_record.dart';
import '../../services/survey_data_provider.dart';
import '../../widgets/survey_form_renderer.dart';

/// Generic create/edit screen for ANY of the 11 BIODIVERSITE/SOCIAL survey
/// forms, parameterized by [schema]. Reuses [SurveyFormRenderer] to render
/// the form fields, wraps in a scrollable Form + AppBar save action,
/// mirroring the Menage/Champ/Structure form screen pattern.
class SurveyFormScreen extends StatefulWidget {
  final SurveySchema schema;
  final SurveyRecord? existing;

  const SurveyFormScreen({super.key, required this.schema, this.existing});

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late SurveyRecord _record;

  @override
  void initState() {
    super.initState();
    _record =
        widget.existing ??
        SurveyRecord(formKey: widget.schema.key, values: {}, repeats: {});
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    await context.read<SurveyDataProvider>().saveRecord(_record);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistrement sauvegardé.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schema.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            onPressed: _save,
            tooltip: 'Enregistrer',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SurveyFormRenderer(
            schema: widget.schema,
            values: _record.values,
            repeats: _record.repeats,
          ),
        ),
      ),
    );
  }
}
