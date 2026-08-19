import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class MenageListScreen extends StatelessWidget {
  const MenageListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enquête Ménages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Formulaire de saisie ménage — à compléter dans la prochaine itération'),
          ));
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
                    title: Text(m.nomChefMenage.isEmpty ? m.codeMenage : m.nomChefMenage),
                    subtitle: Text('${m.codeMenage} — ${m.village}, ${m.sousPrefecture}\n'
                        '${m.individus.length} membre(s)'),
                    isThreeLine: true,
                    trailing: Text(Formatters.date(m.dateEnquete)),
                  ),
                );
              },
            ),
    );
  }
}
