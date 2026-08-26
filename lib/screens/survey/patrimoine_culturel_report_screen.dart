import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/survey_record.dart';
import '../../services/survey_data_provider.dart';
import '../../theme/app_theme.dart';

/// Read-only "Annuaire des sites de patrimoine culturel" report screen,
/// mirroring the web admin's /social/patrimoine-culturel/rapport page and
/// matching the structure of the uploaded reference document (OKAPI_Annuaire
/// des sites Patrimoine culturel.docx): a summary table (VILLAGE / ZONE /
/// NOM DU SITE / TYPE / SOUS-TYPE / IMPORTANCE) followed by one detailed
/// label/value section per site, built live from the app's own
/// "Patrimoine culturel" (SOCIAL module) survey records.
///
/// Mobile is VIEW-ONLY (per the user's request: "visible dans l'application
/// mobile" vs. "visible et exportable sur le serveur web" - export/Word
/// generation is handled by the web admin, see rapport_patrimoine_docx.py).
class PatrimoineCulturelReportScreen extends StatelessWidget {
  const PatrimoineCulturelReportScreen({super.key});

  static const _formKey = 'patrimoine_culturel';

  String _val(Map<String, dynamic> v, String key, [String fallback = '—']) {
    final x = v[key];
    if (x == null) return fallback;
    final s = x.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _combine(
    Map<String, dynamic> v,
    List<String> keys, {
    String sep = ' — ',
  }) {
    final parts = <String>[];
    for (final k in keys) {
      final x = v[k];
      if (x == null) continue;
      final s = x.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }
    return parts.isEmpty ? '—' : parts.join(sep);
  }

  List<String> _coord(Map<String, dynamic> v) {
    final coord = v['coord'];
    if (coord == null) return ['—', '—'];
    final parts = coord.toString().split(' ');
    final lat = parts.isNotEmpty ? parts[0] : '—';
    final lon = parts.length > 1 ? parts[1] : '—';
    return ['Latitude : $lat', 'Longitude : $lon'];
  }

  String _sousType(Map<String, dynamic> v) {
    final st = (v['sous_type_site'] ?? '').toString().trim();
    final autre = (v['autre_sous_type_site'] ?? '').toString().trim();
    if (st.toLowerCase().contains('autre') && autre.isNotEmpty) return autre;
    return st.isEmpty ? '—' : st;
  }

  String _liensAutresSites(Map<String, dynamic> v) {
    if ((v['liens_autres_sites'] ?? '').toString().trim().toLowerCase() ==
        'oui') {
      return _val(v, 'autres_sites_lies');
    }
    return 'Non';
  }

  String _tensions(Map<String, dynamic> v) {
    if ((v['tensions_conflits'] ?? '').toString().trim().toLowerCase() ==
        'oui') {
      return _val(v, 'tensions_conflits_description');
    }
    return 'Non';
  }

  String _usageSite(Map<String, dynamic> v) {
    final us = (v['usage_site'] ?? '').toString().trim();
    final autre = (v['autre_usage_site'] ?? '').toString().trim();
    if (us.toLowerCase().contains('autre') && autre.isNotEmpty) return autre;
    return us.isEmpty ? '—' : us;
  }

  Map<String, dynamic> _siteFrom(SurveyRecord r) {
    final v = r.values;
    final coord = _coord(v);
    final nomSite = _val(v, 'nom_site');
    final identifiant = (v['identifiant'] ?? '').toString().trim();
    final typeSite = _val(v, 'type_site');
    final sousType = _sousType(v);

    final detailRows = <List<String>>[
      ['Signification du nom', _val(v, 'signification_nom')],
      ['Type de site', sousType != '—' ? '$typeSite / $sousType' : typeSite],
      ["Degré d'importance", _val(v, 'degre_importance')],
      ['Qualification du patrimoine', _val(v, 'qualification_patrimoine')],
      [
        'Description / Artefacts',
        _combine(v, ['description', 'artefacts']),
      ],
      ['Histoire et pratiques socioculturelles', _val(v, 'histoire')],
      [
        'Usages / Évolution / Fréquence',
        _combine(v, ['usages', 'evolution', 'frequence']),
      ],
      [
        'Propriétaires / Officiants',
        _combine(v, ['proprietaires', 'officiants']),
      ],
      [
        'Usagers / Rayonnement',
        _combine(v, ['usagers', 'rayonnement']),
      ],
      ['Liens à autres sites', _liensAutresSites(v)],
      [
        'Interdits / Accès',
        _combine(v, ['interdits', 'acces']),
      ],
      ['Impact hors mitigation', _val(v, 'impact_hors_mitigation')],
      [
        'Destructible / Reproductible',
        _combine(v, ['destructible', 'reproductible']),
      ],
      ['Traitement', _val(v, 'traitement')],
      ['Mitigation effets', _val(v, 'mitigation_effets')],
      ['Temps avant traitement', _val(v, 'temps_avant_traitement')],
      ['Durée de traitement', _val(v, 'duree_traitement')],
      ['Prochaines étapes', _val(v, 'prochaines_etapes')],
      ['Réaction de la communauté', _val(v, 'reaction_communaute')],
      ['Tensions et conflits', _tensions(v)],
      ['Responsables du site', _val(v, 'responsables_site')],
      ['Coordonnées GPS', '${coord[0]}    ${coord[1]}'],
    ];

    final village = (v['localite'] ?? v['sous_prefecture'] ?? '—').toString();
    final zone = (v['composante'] ?? _usageSite(v)).toString().isEmpty
        ? '—'
        : (v['composante'] ?? _usageSite(v)).toString();

    return {
      'nomSite': nomSite,
      'heading': (identifiant.isNotEmpty && identifiant != '—')
          ? '$nomSite – Id : $identifiant'
          : nomSite,
      'village': village.isEmpty ? '—' : village,
      'zone': zone,
      'typeSite': typeSite,
      'sousType': sousType,
      'importance': _val(v, 'degre_importance'),
      'detailRows': detailRows,
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SurveyDataProvider>();
    final records = provider.recordsFor(_formKey);
    final sites = records.map(_siteFrom).toList()
      ..sort((a, b) {
        final v = (a['village'] as String).compareTo(b['village'] as String);
        if (v != 0) return v;
        return (a['nomSite'] as String).compareTo(b['nomSite'] as String);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Annuaire Patrimoine culturel')),
      body: sites.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Aucun site de patrimoine culturel n'a encore été enregistré.\n"
                  'Ajoutez des fiches "Patrimoine culturel" dans le module SOCIAL pour '
                  'alimenter cet annuaire.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OkapiColors.textLight),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: OkapiColors.primary,
                          child: Icon(
                            Icons.temple_buddhist,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sites.length} site(s) de patrimoine culturel',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const Text(
                                'Rapport formaté — exportable en Word depuis le serveur web',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: OkapiColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tableau récapitulatif',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              OkapiColors.background,
                            ),
                            columns: const [
                              DataColumn(label: Text('VILLAGE')),
                              DataColumn(label: Text('ZONE')),
                              DataColumn(label: Text('NOM DU SITE')),
                              DataColumn(label: Text('TYPE')),
                              DataColumn(label: Text('SOUS-TYPE')),
                              DataColumn(label: Text('IMPORTANCE')),
                            ],
                            rows: sites
                                .map(
                                  (s) => DataRow(
                                    cells: [
                                      DataCell(Text(s['village'] as String)),
                                      DataCell(Text(s['zone'] as String)),
                                      DataCell(Text(s['nomSite'] as String)),
                                      DataCell(Text(s['typeSite'] as String)),
                                      DataCell(Text(s['sousType'] as String)),
                                      DataCell(Text(s['importance'] as String)),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final site in sites) _SiteCard(site: site),
              ],
            ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  final Map<String, dynamic> site;
  const _SiteCard({required this.site});

  @override
  Widget build(BuildContext context) {
    final rows = site['detailRows'] as List<List<String>>;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.temple_buddhist, color: OkapiColors.primary),
        title: Text(
          site['heading'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Table(
              columnWidths: const {
                0: FractionColumnWidth(0.38),
                1: FractionColumnWidth(0.62),
              },
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.6),
              children: rows
                  .map(
                    (row) => TableRow(
                      decoration: BoxDecoration(
                        color: rows.indexOf(row) % 2 == 0
                            ? OkapiColors.background
                            : Colors.white,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            row[0],
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: OkapiColors.textLight,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            row[1],
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
