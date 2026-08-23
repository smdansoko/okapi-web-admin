import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/menage.dart';
import '../../models/individu.dart';
import '../../services/app_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common_fields.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/repeat_section.dart';

/// Full "WCAG_Enquête des ménages" form:
///  1. Identification du ménage
///  2. Identification des membres du ménage (repeat)
class MenageFormScreen extends StatefulWidget {
  final Menage? existing;
  const MenageFormScreen({super.key, this.existing});

  @override
  State<MenageFormScreen> createState() => _MenageFormScreenState();
}

class _MenageFormScreenState extends State<MenageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  late Menage _menage;
  late LocationPickerData _location;

  late TextEditingController _enqueteursCtrl;
  late TextEditingController _numOrdreCtrl;
  late TextEditingController _codeMenageCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lonCtrl;
  late TextEditingController _nomRepondantCtrl;
  late TextEditingController _telRepondantCtrl;
  late TextEditingController _numeroPieceRepondantCtrl;

  DateTime? _dateEnquete;
  DateTime? _datePieceRepondant;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _menage = e ?? Menage(id: _uuid.v4(), dateEnquete: DateTime.now());
    _location = LocationPickerData(
      region: _menage.region.isEmpty ? null : _menage.region,
      prefecture: _menage.prefecture.isEmpty ? null : _menage.prefecture,
      sousPrefecture: _menage.sousPrefecture.isEmpty
          ? null
          : _menage.sousPrefecture,
      district: _menage.district,
      village: _menage.village,
    );
    _dateEnquete = _menage.dateEnquete;
    _datePieceRepondant = Formatters.isoToDate(_menage.datePieceRepondant);

    _enqueteursCtrl = TextEditingController(text: _menage.enqueteurs);
    _numOrdreCtrl = TextEditingController(
      text: _menage.numOrdreMenage.toString(),
    );
    _codeMenageCtrl = TextEditingController(text: _menage.codeMenage);
    _latCtrl = TextEditingController(text: _menage.latitude?.toString() ?? '');
    _lonCtrl = TextEditingController(text: _menage.longitude?.toString() ?? '');
    _nomRepondantCtrl = TextEditingController(
      text: _menage.nomPrenomRepondant ?? '',
    );
    _telRepondantCtrl = TextEditingController(
      text: _menage.telephoneRepondant ?? '',
    );
    _numeroPieceRepondantCtrl = TextEditingController(
      text: _menage.numeroPieceRepondant ?? '',
    );
  }

  @override
  void dispose() {
    _enqueteursCtrl.dispose();
    _numOrdreCtrl.dispose();
    _codeMenageCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _nomRepondantCtrl.dispose();
    _telRepondantCtrl.dispose();
    _numeroPieceRepondantCtrl.dispose();
    super.dispose();
  }

  void _generateCodeMenage() {
    if (_dateEnquete == null) return;
    final tablette = _menage.tablette.isEmpty ? '0' : _menage.tablette;
    final villagePart = _location.village.isNotEmpty
        ? _location.village
              .substring(
                0,
                _location.village.length > 3 ? 3 : _location.village.length,
              )
              .toUpperCase()
        : 'VIL';
    final code =
        '$villagePart$tablette-${Formatters.dateCode(_dateEnquete!)}-${_numOrdreCtrl.text}';
    setState(() => _codeMenageCtrl.text = code);
  }

  /// Generates the next sequential "code individu" for a newly added
  /// member: `<codeMenage>-<N>`, where N increments with each member added
  /// (order of addition), reusing the ménage's code as an unchanged prefix.
  /// Example: codeMenage = KAT3-260820-1 → 1st member KAT3-260820-1-1,
  /// 2nd member KAT3-260820-1-2, 3rd member KAT3-260820-1-3, etc.
  /// The max existing suffix (rather than a plain count) is used so that
  /// deleting and re-adding members never produces a duplicate id.
  String _nextIndividuId() {
    final prefix = _codeMenageCtrl.text.isNotEmpty
        ? _codeMenageCtrl.text
        : (_menage.codeMenage.isNotEmpty ? _menage.codeMenage : _menage.id);
    var maxSuffix = 0;
    final pattern = RegExp('^${RegExp.escape(prefix)}-(\\d+)\$');
    for (final ind in _menage.individus) {
      final m = pattern.firstMatch(ind.id);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxSuffix) maxSuffix = n;
      }
    }
    return '$prefix-${maxSuffix + 1}';
  }

  /// Opens a camera/gallery chooser and returns the picked image as a
  /// base64-encoded string (resized/compressed for storage efficiency), or
  /// null if the user cancelled. Works identically on Web and Android.
  Future<String?> _pickPhotoBase64() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(c).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(c).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (file == null) return null;
      final Uint8List bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de capturer la photo : $e')),
        );
      }
      return null;
    }
  }

  /// A tappable square photo box used for profile/CNI photo capture inside
  /// the member dialog. Shows the current image (decoded from base64) or an
  /// "add photo" placeholder, plus a small clear (x) button when a photo is
  /// already set.
  Widget _photoPickerBox({
    required String label,
    required String? base64Data,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    Uint8List? bytes;
    if (base64Data != null && base64Data.isNotEmpty) {
      try {
        bytes = base64Decode(base64Data);
      } catch (_) {
        bytes = null;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade100,
            ),
            child: bytes != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: onClear,
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Icon(Icons.add_a_photo_rounded, color: Colors.grey),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _addOrEditIndividu({Individu? existing, int? index}) async {
    final result = await _showIndividuDialog(existing: existing);
    if (result != null) {
      setState(() {
        if (index != null) {
          _menage.individus[index] = result;
        } else {
          _menage.individus.add(result);
        }
      });
    }
  }

  Future<Individu?> _showIndividuDialog({Individu? existing}) async {
    final nomCtrl = TextEditingController(text: existing?.nomPrenom ?? '');
    final numeroPieceCtrl = TextEditingController(
      text: existing?.numeroPiece ?? '',
    );
    final telCtrl = TextEditingController(text: existing?.telephone ?? '');
    final nbFemmesCtrl = TextEditingController(
      text: existing?.nombreFemmes?.toString() ?? '',
    );
    final autreEthnieCtrl = TextEditingController(
      text: existing?.autreGroupeEthnique ?? '',
    );
    final autreNatCtrl = TextEditingController(
      text: existing?.autreNationalite ?? '',
    );
    final handicapPrecisCtrl = TextEditingController(
      text: existing?.handicapPrecis ?? '',
    );

    String sexe = existing?.sexe ?? '';
    String relationCdm = existing?.relationCdm ?? '';
    String typeDePiece = existing?.typeDePiece ?? '';
    String situationMatrimoniale = existing?.situationMatrimoniale ?? '';
    String groupeEthnique = existing?.groupeEthnique ?? '';
    String nationalite = existing?.nationalite ?? '';
    String handicap = existing?.handicap ?? 'Non';
    DateTime? dateNaissance = Formatters.isoToDate(existing?.dateNaissance);
    DateTime? dateEtablissementPiece = Formatters.isoToDate(
      existing?.dateEtablissementPiece,
    );
    String? photoProfilBase64 = existing?.photoProfilBase64;
    String? photoCniRectoBase64 = existing?.photoCniRectoBase64;
    String? photoCniVersoBase64 = existing?.photoCniVersoBase64;

    return showDialog<Individu>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final formKey = GlobalKey<FormState>();
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Ajouter un membre' : 'Modifier le membre',
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LabeledTextField(
                          label: 'Prénom et Nom',
                          controller: nomCtrl,
                          required: true,
                        ),
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'sexe',
                          label: 'Sexe',
                          value: sexe.isEmpty ? null : sexe,
                          required: true,
                          onChanged: (v) =>
                              setDialogState(() => sexe = v ?? ''),
                        ),
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'relation_cdm',
                          label: 'Lien de parenté avec le chef de ménage',
                          value: relationCdm.isEmpty ? null : relationCdm,
                          required: true,
                          onChanged: (v) =>
                              setDialogState(() => relationCdm = v ?? ''),
                        ),
                        const SizedBox(height: 12),
                        DateField(
                          label: 'Date de naissance',
                          value: dateNaissance,
                          onChanged: (v) =>
                              setDialogState(() => dateNaissance = v),
                        ),
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'type_piece',
                          label: 'Type de pièce d\'identité',
                          value: typeDePiece.isEmpty ? null : typeDePiece,
                          required: true,
                          onChanged: (v) =>
                              setDialogState(() => typeDePiece = v ?? ''),
                        ),
                        const SizedBox(height: 12),
                        LabeledTextField(
                          label: 'Numéro de la pièce',
                          controller: numeroPieceCtrl,
                        ),
                        const SizedBox(height: 12),
                        DateField(
                          label: 'Date d\'établissement de la pièce',
                          value: dateEtablissementPiece,
                          onChanged: (v) =>
                              setDialogState(() => dateEtablissementPiece = v),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Photos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _photoPickerBox(
                              label: 'Photo de profil',
                              base64Data: photoProfilBase64,
                              onTap: () async {
                                final b64 = await _pickPhotoBase64();
                                if (b64 != null) {
                                  setDialogState(() => photoProfilBase64 = b64);
                                }
                              },
                              onClear: () => setDialogState(
                                () => photoProfilBase64 = null,
                              ),
                            ),
                            if (typeDePiece.isNotEmpty &&
                                typeDePiece != 'Pas de document') ...[
                              _photoPickerBox(
                                label: 'Pièce d\'identité (recto)',
                                base64Data: photoCniRectoBase64,
                                onTap: () async {
                                  final b64 = await _pickPhotoBase64();
                                  if (b64 != null) {
                                    setDialogState(
                                      () => photoCniRectoBase64 = b64,
                                    );
                                  }
                                },
                                onClear: () => setDialogState(
                                  () => photoCniRectoBase64 = null,
                                ),
                              ),
                              _photoPickerBox(
                                label: 'Pièce d\'identité (verso)',
                                base64Data: photoCniVersoBase64,
                                onTap: () async {
                                  final b64 = await _pickPhotoBase64();
                                  if (b64 != null) {
                                    setDialogState(
                                      () => photoCniVersoBase64 = b64,
                                    );
                                  }
                                },
                                onClear: () => setDialogState(
                                  () => photoCniVersoBase64 = null,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        LabeledTextField(
                          label: 'Téléphone',
                          controller: telCtrl,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'matrimoniale',
                          label: 'Situation matrimoniale',
                          value: situationMatrimoniale.isEmpty
                              ? null
                              : situationMatrimoniale,
                          onChanged: (v) => setDialogState(
                            () => situationMatrimoniale = v ?? '',
                          ),
                        ),
                        if (situationMatrimoniale == 'Marie polygame') ...[
                          const SizedBox(height: 12),
                          LabeledTextField(
                            label: 'Nombre de femmes',
                            controller: nbFemmesCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'ethnie',
                          label: 'Groupe ethnique',
                          value: groupeEthnique.isEmpty ? null : groupeEthnique,
                          onChanged: (v) =>
                              setDialogState(() => groupeEthnique = v ?? ''),
                        ),
                        if (groupeEthnique == 'Autre') ...[
                          const SizedBox(height: 12),
                          LabeledTextField(
                            label: 'Précisez le groupe ethnique',
                            controller: autreEthnieCtrl,
                          ),
                        ],
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'nationalite',
                          label: 'Nationalité',
                          value: nationalite.isEmpty ? null : nationalite,
                          onChanged: (v) =>
                              setDialogState(() => nationalite = v ?? ''),
                        ),
                        if (nationalite == 'Autre') ...[
                          const SizedBox(height: 12),
                          LabeledTextField(
                            label: 'Précisez la nationalité',
                            controller: autreNatCtrl,
                          ),
                        ],
                        const SizedBox(height: 12),
                        ChoiceDropdown(
                          listName: 'handicap',
                          label: 'Handicap',
                          value: handicap.isEmpty ? 'Non' : handicap,
                          onChanged: (v) =>
                              setDialogState(() => handicap = v ?? 'Non'),
                        ),
                        if (handicap != 'Non') ...[
                          const SizedBox(height: 12),
                          LabeledTextField(
                            label: 'Précisez le handicap',
                            controller: handicapPrecisCtrl,
                          ),
                        ],
                      ],
                    ),
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
                    if (nomCtrl.text.isEmpty ||
                        sexe.isEmpty ||
                        relationCdm.isEmpty ||
                        typeDePiece.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Veuillez remplir les champs obligatoires.',
                          ),
                        ),
                      );
                      return;
                    }
                    final result = Individu(
                      id: existing?.id ?? _nextIndividuId(),
                      numOrdreIndividu:
                          existing?.numOrdreIndividu ??
                          (_menage.individus.length + 1),
                      nomPrenom: nomCtrl.text,
                      sexe: sexe,
                      relationCdm: relationCdm,
                      typeDePiece: typeDePiece,
                      numeroPiece: numeroPieceCtrl.text,
                      dateEtablissementPiece: Formatters.dateToIso(
                        dateEtablissementPiece,
                      ),
                      dateNaissance: Formatters.dateToIso(dateNaissance),
                      telephone: telCtrl.text,
                      situationMatrimoniale: situationMatrimoniale,
                      nombreFemmes: int.tryParse(nbFemmesCtrl.text),
                      groupeEthnique: groupeEthnique,
                      autreGroupeEthnique: autreEthnieCtrl.text.isEmpty
                          ? null
                          : autreEthnieCtrl.text,
                      nationalite: nationalite,
                      autreNationalite: autreNatCtrl.text.isEmpty
                          ? null
                          : autreNatCtrl.text,
                      handicap: handicap,
                      handicapPrecis: handicapPrecisCtrl.text.isEmpty
                          ? null
                          : handicapPrecisCtrl.text,
                      photoProfilBase64: photoProfilBase64,
                      photoCniRectoBase64: photoCniRectoBase64,
                      photoCniVersoBase64: photoCniVersoBase64,
                    );
                    Navigator.of(ctx).pop(result);
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_menage.individus.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez ajouter au moins un membre du ménage (le chef de ménage).',
          ),
        ),
      );
      return;
    }
    final hasChef = _menage.individus.any(
      (i) => i.relationCdm == 'Chef de menage',
    );
    if (!hasChef) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez désigner un membre comme "Chef de ménage".'),
        ),
      );
      return;
    }

    _menage.dateEnquete = _dateEnquete ?? DateTime.now();
    _menage.enqueteurs = _enqueteursCtrl.text;
    _menage.numOrdreMenage = int.tryParse(_numOrdreCtrl.text) ?? 1;
    _menage.region = _location.region ?? '';
    _menage.prefecture = _location.prefecture ?? '';
    _menage.sousPrefecture = _location.sousPrefecture ?? '';
    _menage.district = _location.district;
    _menage.village = _location.village;
    _menage.codeMenage = _codeMenageCtrl.text.isEmpty
        ? _menage.id
        : _codeMenageCtrl.text;
    _menage.latitude = double.tryParse(_latCtrl.text);
    _menage.longitude = double.tryParse(_lonCtrl.text);
    _menage.nomPrenomRepondant = _nomRepondantCtrl.text.isEmpty
        ? null
        : _nomRepondantCtrl.text;
    _menage.telephoneRepondant = _telRepondantCtrl.text.isEmpty
        ? null
        : _telRepondantCtrl.text;
    _menage.numeroPieceRepondant = _numeroPieceRepondantCtrl.text.isEmpty
        ? null
        : _numeroPieceRepondantCtrl.text;
    _menage.datePieceRepondant = Formatters.dateToIso(_datePieceRepondant);
    // id key must equal codeMenage so other forms can reference it consistently
    _menage.id = _menage.codeMenage;

    await context.read<AppDataProvider>().saveMenage(_menage);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nouvelle enquête ménage'
              : 'Modifier l\'enquête ménage',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
              title: '1. Identification du ménage',
              icon: Icons.home_rounded,
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
            ChoiceDropdown(
              listName: 'tablette',
              label: 'Tablette',
              value: _menage.tablette.isEmpty ? null : _menage.tablette,
              required: true,
              onChanged: (v) => setState(() => _menage.tablette = v ?? ''),
            ),
            const SizedBox(height: 12),
            LabeledTextField(
              label: 'N° d\'ordre du ménage',
              controller: _numOrdreCtrl,
              keyboardType: TextInputType.number,
              required: true,
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Localisation', icon: Icons.map_rounded),
            LocationPickerField(
              data: _location,
              onChanged: (d) => setState(() => _location = d),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LabeledTextField(
                    label: 'Code du ménage',
                    controller: _codeMenageCtrl,
                    required: true,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Générer automatiquement',
                  icon: const Icon(
                    Icons.auto_fix_high,
                    color: OkapiColors.primary,
                  ),
                  onPressed: _generateCodeMenage,
                ),
              ],
            ),
            if (_menage.individus.isNotEmpty) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  label: Text('Codes des individus (généré automatiquement)'),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _menage.individus
                      .map(
                        (ind) => Chip(
                          label: Text(
                            '${ind.id}${ind.nomPrenom.isEmpty ? "" : " — ${ind.nomPrenom}"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            OuiNonField(
              label: 'Résidence principale ?',
              value: _menage.residencePrincipale,
              onChanged: (v) =>
                  setState(() => _menage.residencePrincipale = v ?? 'Oui'),
            ),
            const SizedBox(height: 12),
            ChoiceDropdown(
              listName: 'statut_menage',
              label: 'Statut d\'occupation du ménage',
              value: _menage.statutMenage.isEmpty ? null : _menage.statutMenage,
              required: true,
              onChanged: (v) => setState(() => _menage.statutMenage = v ?? ''),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LabeledTextField(
                    label: 'Latitude (GPS)',
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledTextField(
                    label: 'Longitude (GPS)',
                    controller: _lonCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionHeader(
              title: 'Répondant',
              icon: Icons.record_voice_over_rounded,
            ),
            OuiNonField(
              label: 'Le répondant est-il le chef de ménage ?',
              value: _menage.repondantCdm,
              onChanged: (v) =>
                  setState(() => _menage.repondantCdm = v ?? 'Oui'),
            ),
            if (_menage.repondantCdm == 'Non') ...[
              const SizedBox(height: 12),
              LabeledTextField(
                label: 'Prénom et Nom du répondant',
                controller: _nomRepondantCtrl,
              ),
              const SizedBox(height: 12),
              ChoiceDropdown(
                listName: 'relation_cdm',
                label: 'Lien avec le chef de ménage',
                value: _menage.lienRepondantCdc,
                onChanged: (v) => setState(() => _menage.lienRepondantCdc = v),
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
                value: _menage.typeDePieceRepondant,
                onChanged: (v) =>
                    setState(() => _menage.typeDePieceRepondant = v),
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
            RepeatSection<Individu>(
              title: '2. Identification des membres du ménage',
              icon: Icons.groups_rounded,
              items: _menage.individus,
              addLabel: 'Ajouter un membre',
              itemTitle: (item, i) => '${i + 1}. ${item.nomPrenom}',
              itemSubtitle: (item, i) => item.displayLabel,
              onAdd: () => _addOrEditIndividu(),
              onEdit: (i) =>
                  _addOrEditIndividu(existing: _menage.individus[i], index: i),
              onDelete: (i) => setState(() => _menage.individus.removeAt(i)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Enregistrer l\'enquête ménage'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
