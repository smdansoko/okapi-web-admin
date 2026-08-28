import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/sync_status_banner.dart';
import '../sync/sync_screen.dart';
import 'menage_form_screen.dart';

class MenageListScreen extends StatefulWidget {
  const MenageListScreen({super.key});

  @override
  State<MenageListScreen> createState() => _MenageListScreenState();
}

class _MenageListScreenState extends State<MenageListScreen> {
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

  /// Delete is restricted to "Chef d'équipe" / "Administrateur principal",
  /// and (for Chef d'équipe) only for records created on their OWN
  /// tablette. Editing remains available to everyone regardless of statut.
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
      appBar: AppBar(
        title: const Text('Enquête Ménages'),
        actions: [
          IconButton(
            tooltip: 'Synchroniser',
            icon: const Icon(Icons.cloud_upload_rounded),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MenageFormScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouveau ménage'),
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: data.menages.isEmpty
                ? const Center(child: Text('Aucun ménage enregistré.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: data.menages.length,
                    itemBuilder: (context, i) {
                      final m = data.menages[i];
                      final canDelete = _canDelete(m.tablette);
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: OkapiColors.primary,
                            child: Icon(Icons.home, color: Colors.white),
                          ),
                          title: Text(
                            m.nomChefMenage.isEmpty
                                ? m.codeMenage
                                : m.nomChefMenage,
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
                                icon: const Icon(
                                  Icons.edit,
                                  color: OkapiColors.info,
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MenageFormScreen(existing: m),
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
                                        content: Text(
                                          'Supprimer le ménage "${m.codeMenage}" et tous ses membres ?\n\n'
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
          ),
        ],
      ),
    );
  }
}
