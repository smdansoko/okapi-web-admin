import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/survey_icons.dart';
import '../../services/reference_data_service.dart';
import '../../services/survey_data_provider.dart';
import '../../theme/app_theme.dart';

/// Generic BIODIVERSITÉ / SOCIAL dashboard: total fiche count, per-form
/// breakdown bar chart and per-form stat list. Totally independent from
/// the PARC dashboard (no ménages/contrats/compensation here) — mirrors
/// the OKAPI Web Admin's own /biodiversite and /social dashboard pages.
class ModuleDashboardScreen extends StatelessWidget {
  final String module; // 'BIODIVERSITE' | 'SOCIAL'
  final String moduleTitle;
  final Color accentColor;

  const ModuleDashboardScreen({
    super.key,
    required this.module,
    required this.moduleTitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final schemas = ReferenceDataService.instance.surveySchemasForModule(
      module,
    );
    final provider = context.watch<SurveyDataProvider>();
    final counts = {for (final s in schemas) s.key: provider.countFor(s.key)};
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/logo/okapi_icon_circular.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tableau de bord — $moduleTitle',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/logo/okapi_icon_circular.png',
                      height: 56,
                      width: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'OKAPI Environnement Conseil\nStatistiques des fiches $moduleTitle synchronisées.\nCe module est totalement indépendant du module PARC (aucun contrat ni indemnisation n\'est calculé ici).',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 700 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _StatCard(
                icon: Icons.fact_check_rounded,
                label: 'Total des fiches',
                value: '$total',
                color: accentColor,
              ),
              _StatCard(
                icon: Icons.grid_view_rounded,
                label: 'Formulaires disponibles',
                value: '${schemas.length}',
                color: OkapiColors.primary,
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
                  const Text(
                    'Répartition par formulaire',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 220,
                    child: _FormBarChart(
                      labels: schemas.map((s) => s.title).toList(),
                      values: schemas
                          .map((s) => counts[s.key]!.toDouble())
                          .toList(),
                      color: accentColor,
                    ),
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
                  const Text(
                    'Détail par formulaire',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...schemas.map(
                    (s) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accentColor.withValues(alpha: 0.15),
                        child: Icon(surveyIconFor(s.icon), color: accentColor),
                      ),
                      title: Text(s.title),
                      trailing: Text(
                        '${counts[s.key]} fiche(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: OkapiColors.textLight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: OkapiColors.textLight, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final Color color;
  const _FormBarChart({
    required this.labels,
    required this.values,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(child: Text('Aucune donnée pour le moment.'));
    }
    final maxVal = values.fold<double>(1, (m, v) => v > m ? v : m);
    final maxY = (maxVal * 1.25).clamp(4, double.infinity).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                final short = labels[i].length > 10
                    ? '${labels[i].substring(0, 9)}…'
                    : labels[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Text(short, style: const TextStyle(fontSize: 9)),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: color,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
