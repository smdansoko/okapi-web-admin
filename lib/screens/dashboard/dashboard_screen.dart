import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_data_provider.dart';
import '../../services/compensation_calculator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    final summary = CompensationCalculator.computeGlobal(
      champsEnquetes: data.champs,
      structureEnquetes: data.structures,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/logo/okapi_icon_circular.png',
                height: 36,
                width: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Tableau de bord — OKAPI Survey',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: data.loadAll,
        child: ListView(
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
                        height: 64,
                        width: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'OKAPI Environnement Conseil\nSuivi des enquêtes et compensations',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Superficie totale enquêtée',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${Formatters.number(data.totalSuperficieParcelles)} m²',
                            style: const TextStyle(
                              fontSize: 22,
                              color: OkapiColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Montant total à indemniser',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            Formatters.gnf(summary.total),
                            style: const TextStyle(
                              fontSize: 20,
                              color: OkapiColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                      'Répartition des enquêtes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: _SurveyBarChart(
                        menages: data.totalMenages,
                        champs: data.champs.length,
                        structures: data.structures.length,
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
                      'Répartition des compensations par catégorie',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (summary.total <= 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Aucune compensation calculée pour le moment.',
                          ),
                        ),
                      )
                    else
                      _CompensationPieChart(summary: summary),
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
                      'Enquêtes récentes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (data.menages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucun ménage enquêté pour le moment.'),
                      )
                    else
                      ...data.menages
                          .take(5)
                          .map(
                            (m) => ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: OkapiColors.primary,
                                child: Icon(
                                  Icons.home,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                m.nomChefMenage.isEmpty
                                    ? m.codeMenage
                                    : m.nomChefMenage,
                              ),
                              subtitle: Text('${m.village} — ${m.codeMenage}'),
                              trailing: Text(Formatters.date(m.dateEnquete)),
                            ),
                          ),
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
              style: const TextStyle(
                color: OkapiColors.textLight,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bar chart comparing the number of Ménage / Champs / Structures surveys.
class _SurveyBarChart extends StatelessWidget {
  final int menages;
  final int champs;
  final int structures;
  const _SurveyBarChart({
    required this.menages,
    required this.champs,
    required this.structures,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = [
      menages,
      champs,
      structures,
    ].fold<int>(1, (m, v) => v > m ? v : m);
    final maxY = (maxVal * 1.25).clamp(4, double.infinity).toDouble();

    BarChartGroupData bar(int index, double value, Color color, String label) =>
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: value,
              color: color,
              width: 34,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          ],
        );

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
              getTitlesWidget: (value, meta) {
                const labels = ['Ménages', 'Champs', 'Structures'];
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          bar(0, menages.toDouble(), OkapiColors.primary, 'Ménages'),
          bar(1, champs.toDouble(), const Color(0xFFC77B00), 'Champs'),
          bar(2, structures.toDouble(), const Color(0xFF1F5A8F), 'Structures'),
        ],
      ),
    );
  }
}

/// Pie chart showing the breakdown of the global compensation total by
/// category, matching the "RÉCAPITULATIF DES COMPENSATIONS" categories used
/// in the contract PDFs.
class _CompensationPieChart extends StatelessWidget {
  final CompensationSummary summary;
  const _CompensationPieChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final entries = <_PieEntry>[
      _PieEntry('Parcelles (foncier)', summary.parcelles, OkapiColors.primary),
      _PieEntry(
        'Cultures annuelles',
        summary.champsCulturesAnnuelles,
        const Color(0xFFC77B00),
      ),
      _PieEntry(
        'Cultures pérennes',
        summary.culturesPerennes,
        OkapiColors.secondary,
      ),
      _PieEntry(
        'Espèces sauvages',
        summary.especesSauvages,
        const Color(0xFF7A9E3B),
      ),
      _PieEntry('Bois d\'œuvre', summary.boisDoeuvre, const Color(0xFF6D4C41)),
      _PieEntry('Ressources', summary.ressources, const Color(0xFF9C27B0)),
      _PieEntry('Structures', summary.structures, const Color(0xFF1F5A8F)),
    ].where((e) => e.value > 0).toList();

    final total = summary.total <= 0 ? 1.0 : summary.total;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: entries
                  .map(
                    (e) => PieChartSectionData(
                      value: e.value,
                      color: e.color,
                      title: '${(e.value / total * 100).toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: entries
              .map(
                (e) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: e.color),
                    const SizedBox(width: 4),
                    Text(
                      '${e.label} (${Formatters.gnf(e.value)})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _PieEntry {
  final String label;
  final double value;
  final Color color;
  _PieEntry(this.label, this.value, this.color);
}
