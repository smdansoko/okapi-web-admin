import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/structure.dart';
import '../../widgets/common_fields.dart';
import '../../widgets/gps_capture_button.dart';

const _uuid = Uuid();

/// Dialog to add/edit a "Structure" (WCAG_Enquête_Structures_V1 — section 2
/// "Identification des structures du ménage"). [project] selects the
/// project-specific choice lists ('type_structure_simandou', etc. for
/// 'simandou'; default WCAG/SMB lists otherwise).
Future<StructureItem?> showStructureDialog(
  BuildContext context, {
  StructureItem? existing,
  String project = 'wcag',
}) {
  final autreStructureCtrl = TextEditingController(
    text: existing?.autreStructure ?? '',
  );
  final latCtrl = TextEditingController(
    text: existing?.latitude?.toString() ?? '',
  );
  final lonCtrl = TextEditingController(
    text: existing?.longitude?.toString() ?? '',
  );
  final superficieSolCtrl = TextEditingController(
    text: existing?.superficieSol.toString() ?? '',
  );
  final superficieMurCtrl = TextEditingController(
    text: existing?.superficieMur.toString() ?? '',
  );
  final superficieToitCtrl = TextEditingController(
    text: existing?.superficieToit.toString() ?? '',
  );
  final superficieOuverturesCtrl = TextEditingController(
    text: existing?.superficieOuvertures.toString() ?? '',
  );
  final longueurProfondeurCtrl = TextEditingController(
    text: existing?.longueurProfondeur.toString() ?? '',
  );
  final notesCtrl = TextEditingController(text: existing?.notes ?? '');

  String typeDeStructure = existing?.typeDeStructure ?? '';
  String structureChamps = existing?.structureChamps ?? 'Non';
  String? materiauxToit = existing?.materiauxToit;
  String? materiauxMur = existing?.materiauxMur;
  String? materiauxSol = existing?.materiauxSol;
  String? materiauxFermeture = existing?.materiauxFermeture;
  String? materiauxPeinture = existing?.materiauxPeinture;
  String? materiauxCarrelage = existing?.materiauxCarrelage;
  String etatStructure = existing?.etatStructure ?? '';
  double? gpsAccuracy;

  bool usesMateriaux(String type) {
    if (project == 'simandou') {
      return type == 'Case Traditionnelle' || type == 'Batiment rectangulaire';
    }
    return type == 'Habitation et bien immobiliers' ||
        type == 'Case Traditionnelle' ||
        type == 'Batiment rectangulaire';
  }

  return showDialog<StructureItem>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final showMateriaux = usesMateriaux(typeDeStructure);
        return AlertDialog(
          title: Text(
            existing == null
                ? 'Ajouter une structure'
                : 'Modifier la structure',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChoiceDropdown(
                    listName: projectListName('type_structure', project),
                    label: 'Type de structure',
                    value: typeDeStructure.isEmpty ? null : typeDeStructure,
                    required: true,
                    onChanged: (v) =>
                        setDialogState(() => typeDeStructure = v ?? ''),
                  ),
                  if (typeDeStructure == 'Autre') ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Précisez le type de structure',
                      controller: autreStructureCtrl,
                    ),
                  ],
                  const SizedBox(height: 12),
                  OuiNonField(
                    label: 'Cette structure se trouve-t-elle dans un champ ?',
                    value: structureChamps,
                    onChanged: (v) =>
                        setDialogState(() => structureChamps = v ?? 'Non'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: LabeledTextField(
                          label: 'Latitude',
                          controller: latCtrl,
                          readOnly: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LabeledTextField(
                          label: 'Longitude',
                          controller: lonCtrl,
                          readOnly: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GpsCaptureButton(
                    lastAccuracy: gpsAccuracy,
                    onCaptured: (point) => setDialogState(() {
                      latCtrl.text = point.latitude.toString();
                      lonCtrl.text = point.longitude.toString();
                      gpsAccuracy = point.accuracy;
                    }),
                  ),
                  if (showMateriaux) ...[
                    const SizedBox(height: 16),
                    const SectionHeader(
                      title: 'Matériaux de construction',
                      icon: Icons.construction,
                    ),
                    ChoiceDropdown(
                      listName: projectListName('materiaux_toit', project),
                      label: 'Matériaux du toit',
                      value: materiauxToit,
                      onChanged: (v) => setDialogState(() => materiauxToit = v),
                    ),
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: projectListName('materiaux_mur', project),
                      label: 'Matériaux du mur',
                      value: materiauxMur,
                      onChanged: (v) => setDialogState(() => materiauxMur = v),
                    ),
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: projectListName('materiaux_sol', project),
                      label: 'Matériaux du sol',
                      value: materiauxSol,
                      onChanged: (v) => setDialogState(() => materiauxSol = v),
                    ),
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: projectListName(
                        'materiaux_carrelage',
                        project,
                      ),
                      label: 'Carrelage',
                      value: materiauxCarrelage,
                      onChanged: (v) =>
                          setDialogState(() => materiauxCarrelage = v),
                    ),
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: projectListName(
                        'materiaux_fermeture',
                        project,
                      ),
                      label: 'Matériaux de fermeture (portes/fenêtres)',
                      value: materiauxFermeture,
                      onChanged: (v) =>
                          setDialogState(() => materiauxFermeture = v),
                    ),
                    const SizedBox(height: 12),
                    ChoiceDropdown(
                      listName: projectListName(
                        'materiaux_peinture',
                        project,
                      ),
                      label: 'Peinture',
                      value: materiauxPeinture,
                      onChanged: (v) =>
                          setDialogState(() => materiauxPeinture = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const SectionHeader(
                    title: 'Dimensions',
                    icon: Icons.straighten,
                  ),
                  LabeledTextField(
                    label: showMateriaux
                        ? 'Superficie du sol (m²)'
                        : 'Superficie / quantité (selon le type)',
                    controller: superficieSolCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  if (showMateriaux) ...[
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Superficie du mur (m²)',
                      controller: superficieMurCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Superficie du toit (m²)',
                      controller: superficieToitCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      label: 'Superficie des ouvertures (m²)',
                      controller: superficieOuverturesCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Longueur / profondeur (mètre linéaire)',
                    controller: longueurProfondeurCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ChoiceDropdown(
                    listName: projectListName('etat_structure', project),
                    label: 'État de la structure',
                    value: etatStructure.isEmpty ? null : etatStructure,
                    required: true,
                    onChanged: (v) =>
                        setDialogState(() => etatStructure = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  LabeledTextField(
                    label: 'Notes / observation',
                    controller: notesCtrl,
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
                if (typeDeStructure.isEmpty || etatStructure.isEmpty) {
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
                  StructureItem(
                    id: existing?.id ?? _uuid.v4(),
                    numOrdreStructure: existing?.numOrdreStructure ?? 1,
                    typeDeStructure: typeDeStructure,
                    autreStructure: autreStructureCtrl.text.isEmpty
                        ? null
                        : autreStructureCtrl.text,
                    latitude: double.tryParse(latCtrl.text),
                    longitude: double.tryParse(lonCtrl.text),
                    structureChamps: structureChamps,
                    materiauxToit: showMateriaux ? materiauxToit : null,
                    materiauxMur: showMateriaux ? materiauxMur : null,
                    materiauxSol: showMateriaux ? materiauxSol : null,
                    materiauxFermeture: showMateriaux
                        ? materiauxFermeture
                        : null,
                    materiauxPeinture: showMateriaux ? materiauxPeinture : null,
                    materiauxCarrelage: showMateriaux
                        ? materiauxCarrelage
                        : null,
                    superficieSol: double.tryParse(superficieSolCtrl.text) ?? 0,
                    superficieMur: showMateriaux
                        ? (double.tryParse(superficieMurCtrl.text) ?? 0)
                        : 0,
                    superficieToit: showMateriaux
                        ? (double.tryParse(superficieToitCtrl.text) ?? 0)
                        : 0,
                    superficieOuvertures: showMateriaux
                        ? (double.tryParse(superficieOuverturesCtrl.text) ?? 0)
                        : 0,
                    longueurProfondeur:
                        double.tryParse(longueurProfondeurCtrl.text) ?? 0,
                    etatStructure: etatStructure,
                    notes: notesCtrl.text,
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
