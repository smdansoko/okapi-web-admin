import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../utils/formatters.dart';

class StructuresListScreen extends StatelessWidget {
  const StructuresListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Enquête Structures')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (data.menages.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Veuillez d\'abord créer un ménage avant de saisir une enquête structures.'),
            ));
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Formulaire de saisie enquête structures — à compléter dans la prochaine itération'),
          ));
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
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF1F5A8F),
                      child: Icon(Icons.home_work, color: Colors.white),
                    ),
                    title: Text(s.proprietaireNom.isEmpty ? s.id : s.proprietaireNom),
                    subtitle: Text('${s.village}\n${s.structures.length} structure(s)'),
                    isThreeLine: true,
                    trailing: Text(Formatters.date(s.dateEnquete)),
                  ),
                );
              },
            ),
    );
  }
}
