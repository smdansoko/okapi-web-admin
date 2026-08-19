import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'champ_form_screen.dart';

class ChampsListScreen extends StatelessWidget {
  const ChampsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enquête Champs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (data.menages.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Veuillez d\'abord créer un ménage avant de saisir une enquête champs.',
                ),
              ),
            );
            return;
          }
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ChampFormScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle enquête'),
      ),
      body: data.champs.isEmpty
          ? const Center(child: Text('Aucune enquête champs enregistrée.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.champs.length,
              itemBuilder: (context, i) {
                final c = data.champs[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: OkapiColors.secondary,
                      child: Icon(Icons.grass, color: Colors.white),
                    ),
                    title: Text(
                      c.proprietaireNom.isEmpty ? c.id : c.proprietaireNom,
                    ),
                    subtitle: Text(
                      '${c.typeDePropriete} — ${c.village}\n'
                      '${c.parcelles.length} parcelle(s)',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Formatters.date(c.dateEnquete)),
                        IconButton(
                          icon: const Icon(Icons.edit, color: OkapiColors.info),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChampFormScreen(existing: c),
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
                                content: const Text(
                                  'Supprimer cette enquête champs ?',
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
                              await context.read<AppDataProvider>().deleteChamp(
                                c.id,
                              );
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
