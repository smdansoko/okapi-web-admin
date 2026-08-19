import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord — OKAPI Survey')),
      body: RefreshIndicator(
        onRefresh: data.loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _StatCard(
                  icon: Icons.groups_rounded,
                  label: 'Ménages enquêtés',
                  value: '${data.totalMenages}',
                  color: OkapiColors.primary,
                ),
                _StatCard(
                  icon: Icons.person_rounded,
                  label: 'Individus recensés',
                  value: '${data.totalIndividus}',
                  color: OkapiColors.secondary,
                ),
                _StatCard(
                  icon: Icons.grass_rounded,
                  label: 'Parcelles agricoles',
                  value: '${data.totalParcelles}',
                  color: const Color(0xFFC77B00),
                ),
                _StatCard(
                  icon: Icons.home_work_rounded,
                  label: 'Structures',
                  value: '${data.totalStructures}',
                  color: const Color(0xFF1F5A8F),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Superficie totale enquêtée',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      '${Formatters.number(data.totalSuperficieParcelles)} m²',
                      style: const TextStyle(fontSize: 22, color: OkapiColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enquêtes récentes',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    if (data.menages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucun ménage enquêté pour le moment.'),
                      )
                    else
                      ...data.menages.take(5).map((m) => ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: OkapiColors.primary,
                              child: Icon(Icons.home, color: Colors.white, size: 18),
                            ),
                            title: Text(m.nomChefMenage.isEmpty ? m.codeMenage : m.nomChefMenage),
                            subtitle: Text('${m.village} — ${m.codeMenage}'),
                            trailing: Text(Formatters.date(m.dateEnquete)),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(color: OkapiColors.textLight, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
