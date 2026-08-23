import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/champ_agricole.dart';
import '../../widgets/common_fields.dart';
import '../../widgets/repeat_section.dart';

const _uuid = Uuid();

/// Dialog to add/edit a "Champ" (culture) inside a parcelle.
///
/// [codeParcelle] is the parent parcelle's auto-generated code, used to
/// live-compute the read-only "Code de champ" = concat(codeParcelle, '-',
/// numOrdreChamps). [nextNumOrdre] is the suggested (but still manually
/// editable by the enquêteur) default value for a brand-new champ.
Future<ChampAgricole?> showChampDialog(
  BuildContext context, {
  ChampAgricole? existing,
  String codeParcelle = '',
  int nextNumOrdre = 1,
}) {
  final superficieCtrl = TextEditingController(
    text: existing?.superficieChamps.toString() ?? '',
  );
  final autreCultureCtrl = TextEditingController(
    text: existing?.autreCulture ?? '',
  );
  final codeExploitantCtrl = TextEditingController(
    text: existing?.codeExploitant ?? '',
  );
  final observationCtrl = TextEditingController(
    text: existing?.observation ?? '',
  );
  final numOrdreCtrl = TextEditingController(
    text: (existing?.numOrdreChamps ?? nextNumOrdre).toString(),
  );
  String etatChamps = existing?.etatChamps ?? '';
  String culture = existing?.culture ?? '';
  String propUsager = existing?.propUsager ?? 'Oui';

  String computeCodeChamp() {
    final n = numOrdreCtrl.text.trim();
    if (codeParcelle.isEmpty || n.isEmpty) return '';
    return '$codeParcelle-$n';
  }

  return showDialog<ChampAgricole>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(
            existing == null ? 'Ajouter un champ' : 'Modifier le champ',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabeledTextField(
                    label: 'N° d\'ordre du champ',
                    controller: numOrdreCtrl,
                    keyboardType: TextInputType.number,
                    required: true,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  IgnorePointer(
                    child: LabeledTextField(
                      label: 'Code de champ (généré automatiquement)',
                      controller: TextEditingController(
                        text: computeCodeChamp(),
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ChoiceDropdown(
                    listName: 'etat_champs',
                    label: 'État du champs',
                    value: etatChamps.isEmpty ? null : etatChamps,
                    required: true,
                    onChanged: (v) =>
                        setDialogState(() => etatChamps = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  ChoiceDropdown(
                    listName: 'culture',
                    label: 'Culture principale',
                    value: culture.isEmpty ? null : culture,
                    required: true,
                    onChanged: (v) => setDialogState(() => culture = v ?? ''),
                  ),
                  if (culture == 'Aucun') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Précisez la culture',
                      controller: autreCultureCtrl,
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Superficie du champ (ha)',
                    controller: superficieCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  OuiNonField(
                    label: 'L\'usager du champ est-il le propriétaire ?',
                    value: propUsager,
                    onChanged: (v) =>
                        setDialogState(() => propUsager = v ?? 'Oui'),
                  ),
                  if (propUsager == 'Non') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Code de l\'exploitant',
                      controller: codeExploitantCtrl,
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Observation',
                    controller: observationCtrl,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (etatChamps.isEmpty ||
                    culture.isEmpty ||
                    superficieCtrl.text.isEmpty ||
                    numOrdreCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir les champs obligatoires.',
                      ),
                    ),
                  );
                  return;
                }
                final numOrdre =
                    int.tryParse(numOrdreCtrl.text) ??
                    (existing?.numOrdreChamps ?? nextNumOrdre);
                Navigator.of(ctx).pop(
                  ChampAgricole(
                    id: existing?.id ?? _uuid.v4(),
                    numOrdreChamps: numOrdre,
                    etatChamps: etatChamps,
                    culture: culture,
                    autreCulture: autreCultureCtrl.text.isEmpty
                        ? null
                        : autreCultureCtrl.text,
                    propUsager: propUsager,
                    codeExploitant: codeExploitantCtrl.text.isEmpty
                        ? null
                        : codeExploitantCtrl.text,
                    superficieChamps: double.tryParse(superficieCtrl.text) ?? 0,
                    observation: observationCtrl.text,
                    codeChamp: codeParcelle.isEmpty
                        ? ''
                        : '$codeParcelle-$numOrdre',
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}

/// Dialog to add/edit an "Arbre" inside a parcelle.
Future<ArbreParcelle?> showArbreDialog(
  BuildContext context, {
  ArbreParcelle? existing,
}) {
  final autreTypeCtrl = TextEditingController(
    text: existing?.autreTypeArbre ?? '',
  );
  final nombrePiedsCtrl = TextEditingController(
    text: existing?.nombreDePieds?.toString() ?? '',
  );
  final nombrePlanteCtrl = TextEditingController(
    text: existing?.nombrePlante?.toString() ?? '',
  );
  final nombreJeuneNpCtrl = TextEditingController(
    text: existing?.nombreJeuneNp?.toString() ?? '',
  );
  final nombreJeunePCtrl = TextEditingController(
    text: existing?.nombreJeuneP?.toString() ?? '',
  );
  final nombreMatureCtrl = TextEditingController(
    text: existing?.nombreMature?.toString() ?? '',
  );
  final nombreAdulteDeclCtrl = TextEditingController(
    text: existing?.nombreAdulteDeclinant?.toString() ?? '',
  );
  final hauteurCtrl = TextEditingController(
    text: existing?.hauteur?.toString() ?? '',
  );
  final circonferenceCtrl = TextEditingController(
    text: existing?.circonference?.toString() ?? '',
  );
  final idPropArbreCtrl = TextEditingController(
    text: existing?.idPropArbre ?? '',
  );
  final observationCtrl = TextEditingController(
    text: existing?.observation ?? '',
  );
  String typeArbre = existing?.typeArbre ?? '';
  String especeArbre = existing?.especeArbre ?? '';
  String propPropArbre = existing?.propPropArbre ?? 'Oui';

  return showDialog<ArbreParcelle>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(
            existing == null ? 'Ajouter un arbre' : 'Modifier l\'arbre',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChoiceDropdown(
                    listName: 'type_arbre',
                    label: 'Type d\'arbre',
                    value: typeArbre.isEmpty ? null : typeArbre,
                    required: true,
                    onChanged: (v) => setDialogState(() {
                      typeArbre = v ?? '';
                      especeArbre = '';
                    }),
                  ),
                  const SizedBox(height: 12),
                  ChoiceDropdown(
                    listName: 'espece_arbre',
                    label: 'Espèce',
                    value: especeArbre.isEmpty ? null : especeArbre,
                    filterType: typeArbre.isEmpty ? null : typeArbre,
                    required: true,
                    onChanged: (v) =>
                        setDialogState(() => especeArbre = v ?? ''),
                  ),
                  if (typeArbre == 'cultures_perennes') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de plantules',
                      controller: nombrePlanteCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de jeunes non productifs',
                      controller: nombreJeuneNpCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de jeunes productifs',
                      controller: nombreJeunePCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de matures (adultes)',
                      controller: nombreMatureCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre d\'adultes déclinants',
                      controller: nombreAdulteDeclCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (typeArbre == 'especes_sauvages') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de jeunes pousses non productives',
                      controller: nombreJeuneNpCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de jeunes pousses productives',
                      controller: nombreJeunePCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (typeArbre == 'bois_doeuvre') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Nombre de pieds',
                      controller: nombrePiedsCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Hauteur moyenne (m)',
                      controller: hauteurCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Circonférence au DHP (m)',
                      controller: circonferenceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OuiNonField(
                    label:
                        'Le propriétaire de l\'arbre est-il le propriétaire de la parcelle ?',
                    value: propPropArbre,
                    onChanged: (v) =>
                        setDialogState(() => propPropArbre = v ?? 'Oui'),
                  ),
                  if (propPropArbre == 'Non') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Code du propriétaire de l\'arbre',
                      controller: idPropArbreCtrl,
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Observation',
                    controller: observationCtrl,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (typeArbre.isEmpty || especeArbre.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir les champs obligatoires.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop(
                  ArbreParcelle(
                    id: existing?.id ?? _uuid.v4(),
                    typeArbre: typeArbre,
                    especeArbre: especeArbre,
                    autreTypeArbre: autreTypeCtrl.text.isEmpty
                        ? null
                        : autreTypeCtrl.text,
                    nombreDePieds: int.tryParse(nombrePiedsCtrl.text),
                    nombrePlante: int.tryParse(nombrePlanteCtrl.text),
                    nombreJeuneNp: int.tryParse(nombreJeuneNpCtrl.text),
                    nombreJeuneP: int.tryParse(nombreJeunePCtrl.text),
                    nombreMature: int.tryParse(nombreMatureCtrl.text),
                    nombreAdulteDeclinant: int.tryParse(
                      nombreAdulteDeclCtrl.text,
                    ),
                    hauteur: double.tryParse(hauteurCtrl.text),
                    circonference: double.tryParse(circonferenceCtrl.text),
                    propPropArbre: propPropArbre,
                    idPropArbre: idPropArbreCtrl.text.isEmpty
                        ? null
                        : idPropArbreCtrl.text,
                    observation: observationCtrl.text,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}

/// Dialog to add/edit a "Ressource naturelle".
Future<RessourceNaturelle?> showRessourceDialog(
  BuildContext context, {
  RessourceNaturelle? existing,
}) {
  final autreRessourceCtrl = TextEditingController(
    text: existing?.autreRessource ?? '',
  );
  final quantiteCtrl = TextEditingController(
    text: existing?.quantite?.toString() ?? '',
  );
  final observationCtrl = TextEditingController(
    text: existing?.observation ?? '',
  );
  String typeRessource = existing?.typeRessource ?? '';
  String? ressource = existing?.ressource;
  String? uniteMesure = existing?.uniteMesure;

  return showDialog<RessourceNaturelle>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(
            existing == null
                ? 'Ajouter une ressource'
                : 'Modifier la ressource',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChoiceDropdown(
                    listName: 'type_ressource',
                    label: 'Type de ressource naturelle',
                    value: typeRessource.isEmpty ? null : typeRessource,
                    required: true,
                    onChanged: (v) => setDialogState(() {
                      typeRessource = v ?? '';
                      ressource = null;
                    }),
                  ),
                  if (typeRessource != 'Aucun' && typeRessource.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: 'ressource',
                      label: 'Ressource',
                      value: ressource,
                      filterType: typeRessource,
                      onChanged: (v) => setDialogState(() => ressource = v),
                    ),
                    if (ressource != null &&
                        ressource!.startsWith('Autre')) ...[
                      const SizedBox(height: 12),
                      LabeledTextField(
                        label: 'Précisez la ressource',
                        controller: autreRessourceCtrl,
                      ),
                    ],
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: 'unite',
                      label: 'Unité de mesure',
                      value: uniteMesure,
                      onChanged: (v) => setDialogState(() => uniteMesure = v),
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Quantité',
                      controller: quantiteCtrl,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Observation',
                    controller: observationCtrl,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (typeRessource.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir les champs obligatoires.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop(
                  RessourceNaturelle(
                    id: existing?.id ?? _uuid.v4(),
                    typeRessource: typeRessource,
                    ressource: ressource,
                    autreRessource: autreRessourceCtrl.text.isEmpty
                        ? null
                        : autreRessourceCtrl.text,
                    uniteMesure: uniteMesure,
                    quantite: int.tryParse(quantiteCtrl.text),
                    observation: observationCtrl.text,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}

/// Dialog to add/edit a "Parcelle agricole" — includes nested champs and arbres
/// management within its own StatefulBuilder-based mini screen.
///
/// [codeEnquete] is the parent enquête's auto-generated code, used to
/// live-compute the read-only "Code de parcelle" = concat(codeEnquete, '-',
/// numOrdreParcelle). [nextNumOrdre] is the suggested (but still manually
/// editable by the enquêteur) default value for a brand-new parcelle.
Future<ParcelleAgricole?> showParcelleDialog(
  BuildContext context, {
  ParcelleAgricole? existing,
  String codeEnquete = '',
  int nextNumOrdre = 1,
}) {
  final superficieCtrl = TextEditingController(
    text: existing?.superficieParcelle.toString() ?? '',
  );
  final numOrdreCtrl = TextEditingController(
    text: (existing?.numOrdreParcelle ?? nextNumOrdre).toString(),
  );
  String typeDeTerrain = existing?.typeDeTerrain ?? '';
  String arbreDansParcelle = existing?.arbreDansParcelle ?? 'Non';
  final champs = List<ChampAgricole>.from(existing?.champs ?? []);
  final arbres = List<ArbreParcelle>.from(existing?.arbres ?? []);

  String computeCodeParcelle() {
    final n = numOrdreCtrl.text.trim();
    if (codeEnquete.isEmpty || n.isEmpty) return '';
    return '$codeEnquete-$n';
  }

  return showDialog<ParcelleAgricole>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final currentCodeParcelle = computeCodeParcelle();
        return AlertDialog(
          title: Text(
            existing == null
                ? 'Ajouter une parcelle agricole'
                : 'Modifier la parcelle',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabeledTextField(
                    label: 'N° d\'ordre de la parcelle',
                    controller: numOrdreCtrl,
                    keyboardType: TextInputType.number,
                    required: true,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  IgnorePointer(
                    child: LabeledTextField(
                      label: 'Code de parcelle (généré automatiquement)',
                      controller: TextEditingController(
                        text: currentCodeParcelle,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ChoiceDropdown(
                    listName: 'type_terrain',
                    label: 'Type de terrain',
                    value: typeDeTerrain.isEmpty ? null : typeDeTerrain,
                    required: true,
                    onChanged: (v) =>
                        setDialogState(() => typeDeTerrain = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Superficie de la parcelle (m²)',
                    controller: superficieCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  RepeatSection<ChampAgricole>(
                    title: '3. Identification des champs',
                    icon: Icons.grass,
                    items: champs,
                    addLabel: 'Ajouter un champ',
                    itemTitle: (item, i) =>
                        '${i + 1}. ${item.culture == "Aucun" ? (item.autreCulture ?? "Aucun") : item.culture}',
                    itemSubtitle: (item, i) =>
                        '${item.etatChamps} — ${item.superficieChamps} ha'
                        '${item.codeChamp.isEmpty ? "" : " — ${item.codeChamp}"}',
                    onAdd: () async {
                      final r = await showChampDialog(
                        ctx,
                        codeParcelle: currentCodeParcelle,
                        nextNumOrdre: champs.length + 1,
                      );
                      if (r != null) setDialogState(() => champs.add(r));
                    },
                    onEdit: (i) async {
                      final r = await showChampDialog(
                        ctx,
                        existing: champs[i],
                        codeParcelle: currentCodeParcelle,
                      );
                      if (r != null) setDialogState(() => champs[i] = r);
                    },
                    onDelete: (i) => setDialogState(() => champs.removeAt(i)),
                  ),
                  const SizedBox(height: 12),
                  OuiNonField(
                    label: 'Y a-t-il des arbres dans cette parcelle ?',
                    value: arbreDansParcelle,
                    onChanged: (v) =>
                        setDialogState(() => arbreDansParcelle = v ?? 'Non'),
                  ),
                  if (arbreDansParcelle == 'Oui') ...[
                    const SizedBox(height: 8),
                    RepeatSection<ArbreParcelle>(
                      title: '4. Liste des arbres',
                      icon: Icons.park,
                      items: arbres,
                      addLabel: 'Ajouter un arbre',
                      itemTitle: (item, i) => '${i + 1}. ${item.especeArbre}',
                      itemSubtitle: (item, i) => item.typeArbre,
                      onAdd: () async {
                        final r = await showArbreDialog(ctx);
                        if (r != null) setDialogState(() => arbres.add(r));
                      },
                      onEdit: (i) async {
                        final r = await showArbreDialog(
                          ctx,
                          existing: arbres[i],
                        );
                        if (r != null) setDialogState(() => arbres[i] = r);
                      },
                      onDelete: (i) => setDialogState(() => arbres.removeAt(i)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (typeDeTerrain.isEmpty ||
                    superficieCtrl.text.isEmpty ||
                    numOrdreCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir les champs obligatoires.',
                      ),
                    ),
                  );
                  return;
                }
                final numOrdre =
                    int.tryParse(numOrdreCtrl.text) ??
                    (existing?.numOrdreParcelle ?? nextNumOrdre);
                Navigator.of(ctx).pop(
                  ParcelleAgricole(
                    id: existing?.id ?? _uuid.v4(),
                    numOrdreParcelle: numOrdre,
                    typeDeTerrain: typeDeTerrain,
                    superficieParcelle:
                        double.tryParse(superficieCtrl.text) ?? 0,
                    champs: champs,
                    arbreDansParcelle: arbreDansParcelle,
                    arbres: arbres,
                    codeParcelle: codeEnquete.isEmpty
                        ? ''
                        : '$codeEnquete-$numOrdre',
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}
