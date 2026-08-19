import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Veuillez d\'abord créer un ménage avant de saisir une enquête champs.'),
            ));
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Formulaire de saisie enquête champs — à compléter dans la prochaine itération'),
          ));
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
                    title: Text(c.proprietaireNom.isEmpty ? c.id : c.proprietaireNom),
                    subtitle: Text('${c.typeDePropriete} — ${c.village}\n'
                        '${c.parcelles.length} parcelle(s)'),
                    isThreeLine: true,
                    trailing: Text(Formatters.date(c.dateEnquete)),
                  ),
                );
              },
            ),
    );
  }
}
