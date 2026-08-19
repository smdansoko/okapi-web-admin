import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/champ_agricole.dart';
import '../../models/enquete_champ.dart';
import '../../models/individu.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common_fields.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/repeat_section.dart';
import 'parcelle_dialogs.dart';

/// Full "WCAG_Enquête_Champs_V1" form.
/// Owner (1.7 "Sélectionnez le propriétaire de la parcelle agricole") is
/// picked dynamically from the household's own members (individusForMenage).
class ChampFormScreen extends StatefulWidget {
  final EnqueteChamp? existing;
  const ChampFormScreen({super.key, this.existing});

  @override
  State<ChampFormScreen> createState() => _ChampFormScreenState();
}

class _ChampFormScreenState extends State<ChampFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  late EnqueteChamp _enquete;
  late LocationPickerData _location;

  late TextEditingController _enqueteursCtrl;
  late TextEditingController _numBatchCtrl;
  late TextEditingController _numEnqueteCtrl;
  late TextEditingController _nomRepondantCtrl;
  late TextEditingController _telRepondantCtrl;
  late TextEditingController _numeroPieceRepondantCtrl;

  DateTime? _dateEnquete;
  DateTime? _datePieceRepondant;

  String? _selectedMenageCode; // household this parcelle belongs to
  Individu? _selectedProprietaire;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _enquete = e ?? EnqueteChamp(id: _uuid.v4(), dateEnquete: DateTime.now());
    _location = LocationPickerData(
      region: _enquete.region.isEmpty ? null : _enquete.region,
      prefecture: _enquete.prefecture.isEmpty ? null : _enquete.prefecture,
      sousPrefecture: _enquete.sousPrefecture.isEmpty
          ? null
          : _enquete.sousPrefecture,
      district: _enquete.district,
      village: _enquete.village,
    );
    _dateEnquete = _enquete.dateEnquete;
    _datePieceRepondant = Formatters.isoToDate(_enquete.datePieceRepondant);
    _selectedMenageCode = _enquete.codeMenage.isEmpty
        ? null
        : _enquete.codeMenage;

    _enqueteursCtrl = TextEditingController(text: _enquete.enqueteurs);
    _numBatchCtrl = TextEditingController(text: _enquete.numBatch);
    _numEnqueteCtrl = TextEditingController(
      text: _enquete.numEnqueteChamp.toString(),
    );
    _nomRepondantCtrl = TextEditingController(
      text: _enquete.nomPrenomRepondant ?? '',
    );
    _telRepondantCtrl = TextEditingController(
      text: _enquete.telephoneRepondant ?? '',
    );
    _numeroPieceRepondantCtrl = TextEditingController(
      text: _enquete.numeroPieceRepondant ?? '',
    );
  }

  @override
  void dispose() {
    _enqueteursCtrl.dispose();
    _numBatchCtrl.dispose();
    _numEnqueteCtrl.dispose();
    _nomRepondantCtrl.dispose();
    _telRepondantCtrl.dispose();
    _numeroPieceRepondantCtrl.dispose();
    super.dispose();
  }

  Future<void> _addOrEditParcelle({
    ParcelleAgricole? existing,
    int? index,
  }) async {
    final result = await showParcelleDialog(context, existing: existing);
    if (result != null) {
      setState(() {
        if (index != null) {
          _enquete.parcelles[index] = result;
        } else {
          _enquete.parcelles.add(result);
        }
      });
    }
  }

  Future<void> _addOrEditRessource({
    RessourceNaturelle? existing,
    int? index,
  }) async {
    final result = await showRessourceDialog(context, existing: existing);
    if (result != null) {
      setState(() {
        if (index != null) {
          _enquete.ressources[index] = result;
        } else {
          _enquete.ressources.add(result);
        }
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedMenageCode == null || _selectedMenageCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner le ménage.')),
      );
      return;
    }
    if (_selectedProprietaire == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez sélectionner le propriétaire de la parcelle agricole.',
          ),
        ),
      );
      return;
    }
    if (_enquete.parcelles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez ajouter au moins une parcelle agricole.'),
        ),
      );
      return;
    }

    _enquete.dateEnquete = _dateEnquete ?? DateTime.now();
    _enquete.enqueteurs = _enqueteursCtrl.text;
    _enquete.numBatch = _numBatchCtrl.text;
    _enquete.region = _location.region ?? '';
    _enquete.prefecture = _location.prefecture ?? '';
    _enquete.sousPrefecture = _location.sousPrefecture ?? '';
    _enquete.district = _location.district;
    _enquete.village = _location.village;
    _enquete.codeMenage = _selectedMenageCode!;
    _enquete.codeProprietaire = _selectedProprietaire!.id;
    _enquete.proprietaireNom = _selectedProprietaire!.nomPrenom;
    _enquete.numEnqueteChamp = int.tryParse(_numEnqueteCtrl.text) ?? 1;
    _enquete.nomPrenomRepondant = _nomRepondantCtrl.text.isEmpty
        ? null
        : _nomRepondantCtrl.text;
    _enquete.telephoneRepondant = _telRepondantCtrl.text.isEmpty
        ? null
        : _telRepondantCtrl.text;
    _enquete.numeroPieceRepondant = _numeroPieceRepondantCtrl.text.isEmpty
        ? null
        : _numeroPieceRepondantCtrl.text;
    _enquete.datePieceRepondant = Formatters.dateToIso(_datePieceRepondant);

    await context.read<AppDataProvider>().saveChamp(_enquete);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    final menages = data.menages;
    final individusDisponibles = _selectedMenageCode == null
        ? <Individu>[]
        : data.individusForMenage(_selectedMenageCode!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nouvelle enquête champs'
              : 'Modifier l\'enquête champs',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
              title: '1. Identification du ménage',
              icon: Icons.groups_rounded,
            ),
            DateField(
              label: 'Date de l\'enquête',
              value: _dateEnquete,
              required: true,
              onChanged: (v) => setState(() => _dateEnquete = v),
            ),
            const SizedBox(height: 12),
            LabeledTextField(
              label: 'Enquêteur(s)',
              controller: _enqueteursCtrl,
              required: true,
            ),
            const SizedBox(height: 12),
            LabeledTextField(label: 'N° de batch', controller: _numBatchCtrl),
            const SizedBox(height: 12),
            LabeledTextField(
              label: 'N° enquête champs',
              controller: _numEnqueteCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Localisation', icon: Icons.map_rounded),
            LocationPickerField(
              data: _location,
              onChanged: (d) => setState(() => _location = d),
            ),
            const SizedBox(height: 16),
            ChoiceDropdown(
              listName: 'type_propriete',
              label: 'Type de propriété',
              value: _enquete.typeDePropriete.isEmpty
                  ? null
                  : _enquete.typeDePropriete,
              required: true,
              onChanged: (v) =>
                  setState(() => _enquete.typeDePropriete = v ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  menages.any((m) => m.codeMenage == _selectedMenageCode)
                  ? _selectedMenageCode
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(label: Text('Ménage *')),
              items: menages
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.codeMenage,
                      child: Text(
                        '${m.codeMenage} — ${m.nomChefMenage}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedMenageCode = v;
                _selectedProprietaire = null;
              }),
              validator: (v) => v == null ? 'Champ requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  individusDisponibles.any(
                    (i) => i.id == _selectedProprietaire?.id,
                  )
                  ? _selectedProprietaire?.id
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                label: Text(
                  '1.7 Sélectionnez le propriétaire de la parcelle agricole *',
                ),
              ),
              items: individusDisponibles
                  .map(
                    (i) => DropdownMenuItem(
                      value: i.id,
                      child: Text(
                        i.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _selectedMenageCode == null
                  ? null
                  : (v) => setState(() {
                      _selectedProprietaire = individusDisponibles.firstWhere(
                        (i) => i.id == v,
                      );
                    }),
              validator: (v) => v == null ? 'Champ requis' : null,
            ),
            if (_selectedMenageCode != null && individusDisponibles.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Ce ménage n\'a aucun membre enregistré. Veuillez compléter l\'enquête ménage d\'abord.',
                  style: TextStyle(color: OkapiColors.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            const SectionHeader(
              title: 'Répondant',
              icon: Icons.record_voice_over_rounded,
            ),
            OuiNonField(
              label: 'Le répondant est-il le chef de ménage ?',
              value: _enquete.repondantCdm,
              onChanged: (v) =>
                  setState(() => _enquete.repondantCdm = v ?? 'Oui'),
            ),
            if (_enquete.repondantCdm == 'Non') ...[
              const SizedBox(height: 12),
              LabeledTextField(
                label: 'Prénom et Nom du répondant',
                controller: _nomRepondantCtrl,
              ),
              const SizedBox(height: 12),
              ChoiceDropdown(
                listName: 'relation_cdm',
                label: 'Lien avec le chef de ménage',
                value: _enquete.lienRepondantCdc,
                onChanged: (v) => setState(() => _enquete.lienRepondantCdc = v),
              ),
              const SizedBox(height: 12),
              LabeledTextField(
                label: 'Téléphone du répondant',
                controller: _telRepondantCtrl,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              ChoiceDropdown(
                listName: 'type_piece',
                label: 'Type de pièce du répondant',
                value: _enquete.typeDePieceRepondant,
                onChanged: (v) =>
                    setState(() => _enquete.typeDePieceRepondant = v),
              ),
              const SizedBox(height: 12),
              LabeledTextField(
                label: 'Numéro de pièce du répondant',
                controller: _numeroPieceRepondantCtrl,
              ),
              const SizedBox(height: 12),
              DateField(
                label: 'Date d\'établissement de la pièce du répondant',
                value: _datePieceRepondant,
                onChanged: (v) => setState(() => _datePieceRepondant = v),
              ),
            ],
            const SizedBox(height: 16),
            RepeatSection<ParcelleAgricole>(
              title: '2. Identification des parcelles agricoles',
              icon: Icons.landscape_rounded,
              items: _enquete.parcelles,
              addLabel: 'Ajouter une parcelle',
              itemTitle: (item, i) => '${i + 1}. ${item.typeDeTerrain}',
              itemSubtitle: (item, i) =>
                  '${item.superficieParcelle} m² — ${item.champs.length} champ(s), ${item.arbres.length} arbre(s)',
              onAdd: () => _addOrEditParcelle(),
              onEdit: (i) =>
                  _addOrEditParcelle(existing: _enquete.parcelles[i], index: i),
              onDelete: (i) => setState(() => _enquete.parcelles.removeAt(i)),
            ),
            const SizedBox(height: 12),
            RepeatSection<RessourceNaturelle>(
              title: '5. Liste des ressources naturelles',
              icon: Icons.forest_rounded,
              items: _enquete.ressources,
              addLabel: 'Ajouter une ressource',
              itemTitle: (item, i) =>
                  '${i + 1}. ${item.ressource ?? item.typeRessource}',
              itemSubtitle: (item, i) =>
                  '${item.typeRessource} — ${item.quantite ?? ""} ${item.uniteMesure ?? ""}',
              onAdd: () => _addOrEditRessource(),
              onEdit: (i) => _addOrEditRessource(
                existing: _enquete.ressources[i],
                index: i,
              ),
              onDelete: (i) => setState(() => _enquete.ressources.removeAt(i)),
            ),
            const SizedBox(height: 16),
            ChoiceDropdown(
              listName: 'compensation',
              label: 'Mode de compensation souhaité',
              value: _enquete.typeCompensation.isEmpty
                  ? null
                  : _enquete.typeCompensation,
              required: true,
              onChanged: (v) =>
                  setState(() => _enquete.typeCompensation = v ?? ''),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Enregistrer l\'enquête champs'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
