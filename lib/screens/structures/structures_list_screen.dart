import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'structure_form_screen.dart';

class StructuresListScreen extends StatefulWidget {
  final String projectCode;
  const StructuresListScreen({super.key, this.projectCode = 'wcag'});

  @override
  State<StructuresListScreen> createState() => _StructuresListScreenState();
}

class _StructuresListScreenState extends State<StructuresListScreen> {
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.instance.currentUser;
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  bool _canDelete(String recordTablette) {
    final user = _currentUser;
    if (user == null) return false;
    return SessionService.canDeleteRecord(
      statut: user.statut,
      userTablette: user.tablette,
      recordTablette: recordTablette,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enquête Structures')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (data.menages.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Veuillez d\'abord créer un ménage avant de saisir une enquête structures.',
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  StructureFormScreen(projectCode: widget.projectCode),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle enquête'),
      ),
      body: data.structures.isEmpty
          ? const Center(child: Text('Aucune enquête structures enregistrée.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.structures.length,
              itemBuilder: (context, i) {
                final s = data.structures[i];
                final canDelete = _canDelete(s.tablette);
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: OkapiColors.secondary,
                      child: Icon(Icons.home_work, color: Colors.white),
                    ),
                    title: Text(
                      s.proprietaireNom.isEmpty ? s.id : s.proprietaireNom,
                    ),
                    subtitle: Text(
                      '${s.village}\n${s.structures.length} structure(s)',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Formatters.date(s.dateEnquete)),
                        IconButton(
                          icon: const Icon(Icons.edit, color: OkapiColors.info),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StructureFormScreen(
                                existing: s,
                                projectCode: widget.projectCode,
                              ),
                            ),
                          ),
                        ),
                        if (canDelete)
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
                                    'Supprimer cette enquête structures ?\n\n'
                                    'Cette suppression sera propagée à toutes les tablettes et au serveur lors de la prochaine synchronisation.',
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
                                    .deleteStructureEnquete(s.id);
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
