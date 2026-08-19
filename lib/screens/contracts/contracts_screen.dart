import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';

/// Contracts hub: Propriétaire (Ménage) / Lignage / Communautaire.
/// Full PDF generation matching the official WCAG agreement templates
/// (using the `pdf` package) is the next implementation step — see summary.
class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Contrats de compensation'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Propriétaire'),
              Tab(text: 'Lignage'),
              Tab(text: 'Communautaire'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ContractTab(
              emptyLabel: 'Aucun ménage disponible pour générer un accord Propriétaire.',
              items: data.menages
                  .map((m) => _ContractRow(
                        title: m.nomChefMenage.isEmpty ? m.codeMenage : m.nomChefMenage,
                        subtitle: m.codeMenage,
                      ))
                  .toList(),
            ),
            _ContractTab(
              emptyLabel: 'Aucune enquête de type Lignage disponible.',
              items: data.champs
                  .where((c) => c.typeDePropriete == 'Lignage')
                  .map((c) => _ContractRow(title: c.proprietaireNom, subtitle: c.id))
                  .toList(),
            ),
            _ContractTab(
              emptyLabel: 'Aucune enquête de type Communautaire disponible.',
              items: data.champs
                  .where((c) => c.typeDePropriete == 'Communautaire')
                  .map((c) => _ContractRow(title: c.proprietaireNom, subtitle: c.id))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractRow {
  final String title;
  final String subtitle;
  _ContractRow({required this.title, required this.subtitle});
}

class _ContractTab extends StatelessWidget {
  final String emptyLabel;
  final List<_ContractRow> items;
  const _ContractTab({required this.emptyLabel, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(emptyLabel, textAlign: TextAlign.center)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: OkapiColors.primary,
              child: Icon(Icons.description, color: Colors.white),
            ),
            title: Text(it.title),
            subtitle: Text(it.subtitle),
            trailing: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Génération PDF de l\'accord — à compléter dans la prochaine itération'),
                ));
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Générer'),
            ),
          ),
        );
      },
    );
  }
}
