import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../models/individu.dart';
import '../../models/menage.dart';
import '../../services/app_data_provider.dart';
import '../../services/compensation_calculator.dart';
import '../../services/contract_pdf_generator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync_status_banner.dart';
import '../sync/sync_screen.dart';

/// Contracts hub: Propriétaire (Ménage) / Lignage / Communautaire.
/// Generates the "Accord de compensation" PDF matching the official
/// WCAG/AMC agreement templates, using [ContractPdfGenerator].
class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();

    // Group champs by (codeMenage, codeProprietaire) so we generate a single
    // contract per owner rather than one per parcelle. The owner used is
    // always the individu selected in the Champs survey's "1.7 Sélectionnez
    // le propriétaire de la parcelle agricole" field (codeProprietaire /
    // proprietaireNom), for all 3 contract types, including Propriétaire.
    final proprietaireOwners = <String, _OwnerRef>{};
    final lignageOwners = <String, _OwnerRef>{};
    final communautaireOwners = <String, _OwnerRef>{};
    for (final c in data.champs) {
      final key = '${c.codeMenage}|${c.codeProprietaire}';
      final ref = _OwnerRef(
        codeMenage: c.codeMenage,
        codeProprietaire: c.codeProprietaire,
        nom: c.proprietaireNom,
        region: c.region,
        prefecture: c.prefecture,
        sousPrefecture: c.sousPrefecture,
        district: c.district,
        village: c.village,
        dateEnquete: c.dateEnquete,
        numBatch: c.numBatch,
      );
      if (c.typeDePropriete == 'Propriétaire') {
        proprietaireOwners[key] = ref;
      } else if (c.typeDePropriete == 'Lignage') {
        lignageOwners[key] = ref;
      } else if (c.typeDePropriete == 'Communautaire') {
        communautaireOwners[key] = ref;
      }
    }

    // Households that already have at least one "Propriétaire" Champs
    // survey: their contract uses the individu selected in that survey.
    final menagesWithProprietaireChamp = proprietaireOwners.values
        .map((o) => o.codeMenage)
        .toSet();
    // Fallback: households without any "Propriétaire" Champs survey yet
    // fall back to the chef de ménage, so a contract can still be produced
    // before the Champs survey has been completed for that household.
    final fallbackMenages = data.menages
        .where((m) => !menagesWithProprietaireChamp.contains(m.codeMenage))
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Contrats de compensation'),
          actions: [
            IconButton(
              tooltip: 'Synchroniser',
              icon: const Icon(Icons.cloud_upload_rounded),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Propriétaire'),
              Tab(text: 'Lignage'),
              Tab(text: 'Communautaire'),
            ],
          ),
        ),
        body: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  _ContractTab(
                    emptyLabel:
                        'Aucun ménage disponible pour générer un accord Propriétaire.',
                    items: [
                      ...proprietaireOwners.values.map(
                        (o) => _ContractEntry(
                          title: o.nom,
                          subtitle: 'Lot ${o.numBatch} · ${o.codeMenage}',
                          sortKey: o.numBatch,
                          onGenerate: () => _generateOwnerContract(
                            context,
                            ContractType.proprietaire,
                            o,
                          ),
                        ),
                      ),
                      ...fallbackMenages.map(
                        (m) => _ContractEntry(
                          title: m.nomChefMenage.isEmpty
                              ? m.codeMenage
                              : m.nomChefMenage,
                          subtitle: m.codeMenage,
                          sortKey: m.codeMenage,
                          onGenerate: () => _generateMenageContract(context, m),
                        ),
                      ),
                    ].toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
                  ),
                  _ContractTab(
                    emptyLabel: 'Aucune enquête de type Lignage disponible.',
                    items:
                        lignageOwners.values
                            .map(
                              (o) => _ContractEntry(
                                title: o.nom,
                                subtitle: 'Lot ${o.numBatch} · ${o.codeMenage}',
                                sortKey: o.numBatch,
                                onGenerate: () => _generateOwnerContract(
                                  context,
                                  ContractType.lignage,
                                  o,
                                ),
                              ),
                            )
                            .toList()
                          ..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
                  ),
                  _ContractTab(
                    emptyLabel:
                        'Aucune enquête de type Communautaire disponible.',
                    items:
                        communautaireOwners.values
                            .map(
                              (o) => _ContractEntry(
                                title: o.nom,
                                subtitle: 'Lot ${o.numBatch} · ${o.codeMenage}',
                                sortKey: o.numBatch,
                                onGenerate: () => _generateOwnerContract(
                                  context,
                                  ContractType.communautaire,
                                  o,
                                ),
                              ),
                            )
                            .toList()
                          ..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback contract generation for households that do not yet have a
  /// "Propriétaire" Champs survey: uses the chef de ménage as beneficiary.
  /// As soon as a Champs survey exists for the household, the contract is
  /// generated via [_generateOwnerContract] using the individu selected in
  /// the survey's "1.7 Sélectionnez le propriétaire de la parcelle
  /// agricole" field instead (see [proprietaireOwners] in build()).
  Future<void> _generateMenageContract(
    BuildContext context,
    Menage menage,
  ) async {
    final data = context.read<AppDataProvider>();
    final chef = menage.chefDeMenage;
    if (chef == null) {
      _showError(
        context,
        'Ce ménage n\'a aucun membre enregistré (chef de ménage introuvable).',
      );
      return;
    }
    final summary = CompensationCalculator.computeForOwner(
      champsEnquetes: data.champs,
      structureEnquetes: data.structures,
      codeProprietaire: chef.id,
    );
    final contractData = ContractData.fromMenage(
      menage: menage,
      summary: summary,
    );
    await _previewContract(context, contractData);
  }

  Future<void> _generateOwnerContract(
    BuildContext context,
    ContractType type,
    _OwnerRef ref,
  ) async {
    final data = context.read<AppDataProvider>();
    final menage = data.menageById(ref.codeMenage);
    Individu? proprietaire;
    if (menage != null) {
      try {
        proprietaire = menage.individus.firstWhere(
          (i) => i.id == ref.codeProprietaire,
        );
      } catch (_) {
        proprietaire = null;
      }
    }
    proprietaire ??= Individu(
      id: ref.codeProprietaire,
      numOrdreIndividu: 1,
      nomPrenom: ref.nom,
    );

    final summary = CompensationCalculator.computeForOwner(
      champsEnquetes: data.champs,
      structureEnquetes: data.structures,
      codeProprietaire: ref.codeProprietaire,
    );
    final contractData = ContractData.fromChampOwner(
      type: type,
      numeroLot: ref.numBatch.isEmpty ? ref.codeMenage : ref.numBatch,
      region: ref.region,
      prefecture: ref.prefecture,
      sousPrefecture: ref.sousPrefecture,
      district: ref.district,
      village: ref.village,
      codeMenage: ref.codeMenage,
      proprietaire: proprietaire,
      dateEnquete: ref.dateEnquete,
      summary: summary,
    );
    await _previewContract(context, contractData);
  }

  Future<void> _previewContract(
    BuildContext context,
    ContractData contractData,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await ContractPdfGenerator.generate(contractData);
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'Accord_${contractData.referenceCode}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showError(context, 'Erreur lors de la génération du contrat : $e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

class _OwnerRef {
  final String codeMenage;
  final String codeProprietaire;
  final String nom;
  final String region;
  final String prefecture;
  final String sousPrefecture;
  final String district;
  final String village;
  final DateTime dateEnquete;
  final String numBatch;
  _OwnerRef({
    required this.codeMenage,
    required this.codeProprietaire,
    required this.nom,
    required this.region,
    required this.prefecture,
    required this.sousPrefecture,
    required this.district,
    required this.village,
    required this.dateEnquete,
    required this.numBatch,
  });
}

class _ContractEntry {
  final String title;
  final String subtitle;
  final String sortKey;
  final VoidCallback onGenerate;
  _ContractEntry({
    required this.title,
    required this.subtitle,
    required this.sortKey,
    required this.onGenerate,
  });
}

class _ContractTab extends StatelessWidget {
  final String emptyLabel;
  final List<_ContractEntry> items;
  const _ContractTab({required this.emptyLabel, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyLabel, textAlign: TextAlign.center),
        ),
      );
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
              onPressed: it.onGenerate,
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Générer'),
            ),
          ),
        );
      },
    );
  }
}
