import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/survey_icons.dart';
import '../../models/survey_field.dart';
import '../../services/survey_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'survey_form_screen.dart';

/// Generic list/browse screen for ANY of the 11 BIODIVERSITE/SOCIAL survey
/// forms, parameterized by [schema]. Mirrors StructuresListScreen's pattern
/// (Card + ListTile per record, edit/delete actions, FAB to add new).
class SurveyListScreen extends StatelessWidget {
  final SurveySchema schema;

  const SurveyListScreen({super.key, required this.schema});

  String _titleFor(Map<String, dynamic> values, int index) {
    // Prefer common identifying fields if present, else fall back to
    // village/localite, else a generic numbered label.
    for (final key in [
      'id_installation',
      'id_recce',
      'nom_site',
      'code_menage',
      'nom_expert',
      'identifiant',
      'composante',
    ]) {
      final v = values[key];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '${schema.title} #${index + 1}';
  }

  String _subtitleFor(Map<String, dynamic> values) {
    final parts = <String>[];
    final village = values['village'] ?? values['localite'];
    if (village != null && village.toString().isNotEmpty) {
      parts.add(village.toString());
    }
    final region = values['region'];
    if (region != null && region.toString().isNotEmpty) {
      parts.add(region.toString());
    }
    return parts.join(' — ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SurveyDataProvider>();
    final records = provider.recordsFor(schema.key);
    final icon = surveyIconFor(schema.icon);

    return Scaffold(
      appBar: AppBar(title: Text(schema.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SurveyFormScreen(schema: schema)),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle fiche'),
      ),
      body: records.isEmpty
          ? Center(child: Text('Aucune fiche "${schema.title}" enregistrée.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: records.length,
              itemBuilder: (context, i) {
                final r = records[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: schema.module == 'BIODIVERSITE'
                          ? OkapiColors.secondary
                          : OkapiColors.primary,
                      child: Icon(icon, color: Colors.white),
                    ),
                    title: Text(_titleFor(r.values, i)),
                    subtitle: Text(_subtitleFor(r.values)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Formatters.date(r.updatedAt)),
                        IconButton(
                          icon: const Icon(Icons.edit, color: OkapiColors.info),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SurveyFormScreen(schema: schema, existing: r),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: OkapiColors.error,
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Supprimer ?'),
                                content: Text(
                                  'Supprimer cette fiche "${schema.title}" ?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Annuler'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              await context
                                  .read<SurveyDataProvider>()
                                  .deleteRecord(schema.key, r.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
