import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'menage_form_screen.dart';

class MenageListScreen extends StatelessWidget {
  const MenageListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enquête Ménages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MenageFormScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouveau ménage'),
      ),
      body: data.menages.isEmpty
          ? const Center(child: Text('Aucun ménage enregistré.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.menages.length,
              itemBuilder: (context, i) {
                final m = data.menages[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: OkapiColors.primary,
                      child: Icon(Icons.home, color: Colors.white),
                    ),
                    title: Text(
                      m.nomChefMenage.isEmpty ? m.codeMenage : m.nomChefMenage,
                    ),
                    subtitle: Text(
                      '${m.codeMenage} — ${m.village}, ${m.sousPrefecture}\n'
                      '${m.individus.length} membre(s)',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Formatters.date(m.dateEnquete)),
                        IconButton(
                          icon: const Icon(Icons.edit, color: OkapiColors.info),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MenageFormScreen(existing: m),
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
                                  'Supprimer le ménage "${m.codeMenage}" et tous ses membres ?',
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
                                  .read<AppDataProvider>()
                                  .deleteMenage(m.id);
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
