import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/individu.dart';
import '../models/menage.dart';
import '../utils/formatters.dart';
import 'compensation_calculator.dart';

/// The 3 contract types supported, matching the official WCAG/AMC templates.
enum ContractType { proprietaire, lignage, communautaire }

extension ContractTypeX on ContractType {
  /// Text used in the main title: "... ET LE MÉNAGE AFFECTÉ" etc.
  String get titleSuffix {
    switch (this) {
      case ContractType.proprietaire:
        return 'LE MÉNAGE AFFECTÉ';
      case ContractType.lignage:
        return 'LE LIGNAGE AFFECTÉ';
      case ContractType.communautaire:
        return 'LA COMMUNAUTÉ AFFECTÉE';
    }
  }

  /// Term used throughout the body text to refer to the affected party.
  String get partyLabel {
    switch (this) {
      case ContractType.proprietaire:
        return 'Ménage affecté';
      case ContractType.lignage:
        return 'Lignage affecté';
      case ContractType.communautaire:
        return 'Communauté affectée';
    }
  }

  String get chefLabel {
    switch (this) {
      case ContractType.proprietaire:
        return 'Chef du Ménage affecté';
      case ContractType.lignage:
        return 'Chef du Lignage affecté';
      case ContractType.communautaire:
        return 'représentant de la Communauté Affectée';
    }
  }

  /// Footer label: "Accord Ménage" / "Accord Lignage" / "Accord collectif".
  String get footerLabel {
    switch (this) {
      case ContractType.proprietaire:
        return 'Accord Ménage';
      case ContractType.lignage:
        return 'Accord Lignage';
      case ContractType.communautaire:
        return 'Accord collectif';
    }
  }

  String get identificationSectionTitle {
    switch (this) {
      case ContractType.proprietaire:
        return '1. Identification du Représentant du ménage';
      case ContractType.lignage:
        return '1. Identification du Représentant du lignage';
      case ContractType.communautaire:
        return '1. Identification du Représentant';
    }
  }

  String get temoinsGroupLabel {
    switch (this) {
      case ContractType.proprietaire:
        return 'Témoins (Autres membres adultes du Ménage affecté présents, ou\npersonnes de confiance choisies par le Ménage affecté)';
      case ContractType.lignage:
        return 'Témoins (Autres membres adultes du Lignage affecté présents,\nreprésentants des autorités coutumières ou locales, personnes\nde confiance)';
      case ContractType.communautaire:
        return 'Témoins (Autres membres adultes de la Communauté Affectée\nprésents, représentants des autorités coutumières ou locales,\npersonnes de confiance)';
    }
  }
}

/// All data needed to render one contract PDF. Assembled by the caller
/// (ContractsScreen) from Menage / Individu / EnqueteChamp / EnqueteStructure.
class ContractData {
  final ContractType type;
  final String numeroLot;
  final String region;
  final String prefecture;
  final String sousPrefecture;
  final String district;
  final String village;
  final String codeMenage;
  final String codeIndividu;
  final String codePap;
  final String nomPrenom;
  final String sexe;
  final String dateNaissance; // formatted dd/mm/yyyy or empty
  final String typeDePiece;
  final String numeroPiece;
  final String dateEtablissementPiece;
  final String telephone;
  final DateTime dateEnquete;
  final CompensationSummary summary;

  /// Photos of the compensation beneficiary, stored as base64 strings on
  /// [Individu] and passed through here for embedding in the PDF (page 1):
  /// profile photo always shown when present; CNI recto/verso shown only
  /// when [hasIdentityDocument] is true.
  final String? photoProfilBase64;
  final String? photoCniRectoBase64;
  final String? photoCniVersoBase64;

  ContractData({
    required this.type,
    required this.numeroLot,
    required this.region,
    required this.prefecture,
    required this.sousPrefecture,
    required this.district,
    required this.village,
    required this.codeMenage,
    required this.codeIndividu,
    this.codePap = '',
    required this.nomPrenom,
    required this.sexe,
    required this.dateNaissance,
    required this.typeDePiece,
    required this.numeroPiece,
    required this.dateEtablissementPiece,
    required this.telephone,
    required this.dateEnquete,
    required this.summary,
    this.photoProfilBase64,
    this.photoCniRectoBase64,
    this.photoCniVersoBase64,
  });

  /// True when [typeDePiece] denotes an actual identity document (mirrors
  /// [Individu.hasIdentityDocument]) — controls whether the CNI recto/verso
  /// photo row is rendered on the contract's page 1.
  bool get hasIdentityDocument =>
      typeDePiece.isNotEmpty && typeDePiece != 'Pas de document';

  /// Builds a ContractData for the "Propriétaire/Ménage" contract, using
  /// the household's chef de ménage as the compensation beneficiary.
  factory ContractData.fromMenage({
    required Menage menage,
    required CompensationSummary summary,
  }) {
    final chef = menage.chefDeMenage;
    return ContractData(
      type: ContractType.proprietaire,
      numeroLot: menage.codeMenage,
      region: menage.region,
      prefecture: menage.prefecture,
      sousPrefecture: menage.sousPrefecture,
      district: menage.district,
      village: menage.village,
      codeMenage: menage.codeMenage,
      codeIndividu: chef?.id ?? menage.codeMenage,
      // "Code PAP" is normally attributed manually; when it hasn't been
      // set yet, fall back to displaying the auto-generated survey code
      // (same value "Code de l'individu" already carries here) instead of
      // a bare "-" placeholder.
      codePap: (chef?.codePap != null && chef!.codePap!.isNotEmpty)
          ? chef.codePap!
          : (chef?.id ?? menage.codeMenage),
      nomPrenom: chef?.nomPrenom ?? menage.nomChefMenage,
      sexe: chef?.sexe ?? '',
      dateNaissance: Formatters.date(Formatters.isoToDate(chef?.dateNaissance)),
      typeDePiece: chef?.typeDePiece ?? '',
      numeroPiece: chef?.numeroPiece ?? '',
      dateEtablissementPiece: Formatters.date(
        Formatters.isoToDate(chef?.dateEtablissementPiece),
      ),
      telephone: chef?.telephone ?? '',
      dateEnquete: menage.dateEnquete,
      summary: summary,
      photoProfilBase64: chef?.photoProfilBase64,
      photoCniRectoBase64: chef?.photoCniRectoBase64,
      photoCniVersoBase64: chef?.photoCniVersoBase64,
    );
  }

  /// Builds a ContractData for "Lignage"/"Communautaire" contracts, using
  /// the individu selected as "propriétaire" in the related Enquête Champs.
  factory ContractData.fromChampOwner({
    required ContractType type,
    required String numeroLot,
    required String region,
    required String prefecture,
    required String sousPrefecture,
    required String district,
    required String village,
    required String codeMenage,
    required Individu proprietaire,
    required DateTime dateEnquete,
    required CompensationSummary summary,
    String codeEnquete = '',
  }) {
    return ContractData(
      type: type,
      numeroLot: numeroLot,
      region: region,
      prefecture: prefecture,
      sousPrefecture: sousPrefecture,
      district: district,
      village: village,
      codeMenage: codeMenage,
      codeIndividu: proprietaire.id,
      // "Code PAP" is normally attributed manually; when it hasn't been
      // set yet, fall back to displaying the auto-generated "code de
      // l'enquête" (concat(codeProprietaire, '-', numEnqueteChamp)) instead
      // of a bare "-" placeholder.
      codePap: (proprietaire.codePap != null && proprietaire.codePap!.isNotEmpty)
          ? proprietaire.codePap!
          : (codeEnquete.isNotEmpty ? codeEnquete : proprietaire.id),
      nomPrenom: proprietaire.nomPrenom,
      sexe: proprietaire.sexe,
      dateNaissance: Formatters.date(
        Formatters.isoToDate(proprietaire.dateNaissance),
      ),
      typeDePiece: proprietaire.typeDePiece,
      numeroPiece: proprietaire.numeroPiece,
      dateEtablissementPiece: Formatters.date(
        Formatters.isoToDate(proprietaire.dateEtablissementPiece),
      ),
      telephone: proprietaire.telephone,
      dateEnquete: dateEnquete,
      summary: summary,
      photoProfilBase64: proprietaire.photoProfilBase64,
      photoCniRectoBase64: proprietaire.photoCniRectoBase64,
      photoCniVersoBase64: proprietaire.photoCniVersoBase64,
    );
  }

  /// Contract reference code shown in the header/footer of every page.
  String get referenceCode => codeMenage.isEmpty ? codeIndividu : codeMenage;
}

/// Generates the full "Accord de compensation" PDF, matching page-by-page
/// the structure of the official OKAPI/WCAG templates (Ménage, Lignage,
/// Communautaire variants).
class ContractPdfGenerator {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _italic;

  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    _regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    _bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    _italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Oblique.ttf'),
    );
    try {
      _okapiLogo = pw.MemoryImage(
        (await rootBundle.load(
          'assets/logo/okapi_header_logo.png',
        )).buffer.asUint8List(),
      );
    } catch (_) {
      _okapiLogo = null;
    }
    try {
      _wcagLogo = pw.MemoryImage(
        (await rootBundle.load(
          'assets/logo/wcag_header_logo.png',
        )).buffer.asUint8List(),
      );
    } catch (_) {
      _wcagLogo = null;
    }
  }

  // NOTE: Per client request, contracts no longer use branded colors (maroon
  // / dark green) anywhere except the two header logo images and the
  // applicant's photos. maroon/darkGreen are kept only as aliases (now
  // black) so the rest of this file needs no further edits.
  static const PdfColor maroon = PdfColors.black;
  static const PdfColor darkGreen = PdfColors.black;
  static const PdfColor greyLight = PdfColor.fromInt(0xFFD9D9D9);
  static const PdfColor greyBorder = PdfColor.fromInt(0xFFBBBBBB);

  static pw.MemoryImage? _okapiLogo;
  static pw.MemoryImage? _wcagLogo;

  static Future<Uint8List> generate(ContractData d) async {
    await _ensureFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        italic: _italic,
      ),
    );

    final pages = <pw.Widget>[
      ..._page1Identification(d),
      pw.NewPage(),
      ..._page2PreambleAndArticle1(d),
      pw.NewPage(),
      ..._page3ArticlesRest(d),
      pw.NewPage(),
      ..._page4Recapitulatif(d),
      pw.NewPage(),
      ..._page5Signatures(d),
      pw.NewPage(),
      // ANNEXE 1: all 6 asset categories flow together without a forced
      // page break so they land on the same page whenever they fit; only
      // pw.MultiPage's natural overflow pagination will push extra
      // categories onto a following page when there are too many assets.
      ..._annexe1AllAssets(d),
      pw.NewPage(),
      ..._annexe2Text(d),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 24, 32, 36),
        header: (context) => _pageHeader(),
        footer: (context) =>
            _pageFooter(d, context.pageNumber, context.pagesCount),
        build: (context) => pages,
      ),
    );

    return doc.save();
  }

  // ---------------- Shared header/footer ----------------

  static pw.Widget _pageHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: greyBorder, width: 0.75),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _okapiLogo != null
              ? pw.Image(_okapiLogo!, height: 34)
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'OKAPI',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Environnement Conseil',
                      style: pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
          _wcagLogo != null
              ? pw.Image(_wcagLogo!, height: 34)
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'WCAG',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Winning Consortium Alumina Guinea',
                      style: pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(ContractData d, int pageNumber, int pagesCount) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: greyBorder, width: 0.75)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Winning Consortium Alumina Guinea (WCAG) ${d.type.footerLabel}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.Text(
            d.referenceCode,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page $pageNumber de $pagesCount',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _title(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    margin: const pw.EdgeInsets.only(bottom: 12),
    decoration: pw.BoxDecoration(
      color: greyLight,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: maroon,
      ),
    ),
  );

  static pw.Widget _sectionTitle(String text) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: darkGreen,
      ),
    ),
  );

  static pw.Widget _paragraph(
    String text, {
    bool italic = false,
    double fontSize = 9.5,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.justify,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      ),
    ),
  );

  static pw.Widget _articleTitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _fieldRow(String label, String value) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 165,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value.isEmpty ? '-' : value,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      ],
    ),
  );

  // ---------------- Page 1: identification + preamble start ----------------

  /// Decodes a base64-encoded photo string into a [pw.MemoryImage], or
  /// returns null if [base64Data] is null/empty/invalid.
  ///
  /// Photos captured on mobile phones frequently carry an EXIF
  /// "Orientation" tag instead of having the pixel data itself physically
  /// rotated. Flutter's on-screen `Image.memory` widget uses the platform's
  /// Skia JPEG decoder, which automatically honours this tag - so the
  /// photo looks correctly oriented on the phone screen. The `pdf`
  /// package's `pw.MemoryImage`, however, does NOT apply this correction,
  /// so without this fix the same photo appears sideways or upside-down in
  /// the generated PDF. We use the `image` package to bake the correct
  /// rotation into the pixel data first (mirroring what Skia already does
  /// on-screen), matching the behaviour of the mobile app's own preview.
  static pw.MemoryImage? _decodePhoto(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return null;
    try {
      final Uint8List raw = base64Decode(base64Data);
      try {
        final img.Image? decoded = img.decodeImage(raw);
        if (decoded == null) {
          return pw.MemoryImage(raw);
        }
        // bakeOrientation() physically rotates/flips the pixel data to
        // match what the EXIF orientation tag says it should look like,
        // then strips the tag (so no double-rotation can occur downstream).
        final img.Image oriented = img.bakeOrientation(decoded);
        final Uint8List reEncoded = Uint8List.fromList(
          img.encodeJpg(oriented, quality: 90),
        );
        return pw.MemoryImage(reEncoded);
      } catch (_) {
        // Fallback: if re-encoding fails for any reason, fall back to the
        // raw bytes so a photo still shows up (possibly mis-oriented)
        // rather than showing nothing at all.
        return pw.MemoryImage(raw);
      }
    } catch (_) {
      return null;
    }
  }

  /// A bordered photo box matching the official template's layout: profile
  /// photo (top-right of the identification table) or a CNI recto/verso
  /// photo below the table. Shows the real image when available, else a
  /// grey placeholder labelled with [placeholderLabel].
  static pw.Widget _photoBox({
    required pw.MemoryImage? image,
    required double width,
    required double height,
    required String placeholderLabel,
    String? caption,
  }) {
    final box = pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: greyBorder),
        color: image == null ? greyLight : null,
      ),
      child: image == null
          ? pw.Center(
              child: pw.Text(
                placeholderLabel,
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            )
          : pw.Image(image, fit: pw.BoxFit.cover),
    );
    if (caption == null) return box;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        box,
        pw.SizedBox(height: 2),
        pw.Text(
          caption,
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static List<pw.Widget> _page1Identification(ContractData d) {
    final profileImage = _decodePhoto(d.photoProfilBase64);
    final rectoImage = _decodePhoto(d.photoCniRectoBase64);
    final versoImage = _decodePhoto(d.photoCniVersoBase64);

    final widgets = <pw.Widget>[
      _title(
        'ACCORD DE COMPENSATION CONCLU ENTRE WCAG ET ${d.type.titleSuffix}',
      ),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _sectionTitle(d.type.identificationSectionTitle),
                _fieldRow('Numéro de lot', d.numeroLot),
                _fieldRow('Région', d.region),
                _fieldRow('Préfecture', d.prefecture),
                _fieldRow('Sous préfecture', d.sousPrefecture),
                _fieldRow('Localité', d.village),
                _fieldRow('Code de l\'individu', d.codeIndividu),
                _fieldRow('Code PAP', d.codePap),
                _fieldRow('Prénom et NOM', d.nomPrenom),
                _fieldRow('Sexe', d.sexe),
                _fieldRow('Date de naissance', d.dateNaissance),
                _fieldRow('Type de pièce d\'identité', d.typeDePiece),
                _fieldRow('Numéro de la pièce d\'identité', d.numeroPiece),
                _fieldRow(
                  'Date d\'établissement de la PI',
                  d.dateEtablissementPiece,
                ),
                _fieldRow('Numéro de téléphone', d.telephone),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 20),
            child: _photoBox(
              image: profileImage,
              width: 90,
              height: 110,
              placeholderLabel: 'PHOTO',
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 14),
    ];

    // CNI recto/verso photos, shown only when an actual identity document
    // was recorded for the beneficiary — matching the official templates.
    if (d.hasIdentityDocument) {
      widgets.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _photoBox(
              image: rectoImage,
              width: 220,
              height: 140,
              placeholderLabel: 'CNI - RECTO',
              caption: 'Pièce d\'identité (recto)',
            ),
            pw.SizedBox(width: 12),
            _photoBox(
              image: versoImage,
              width: 220,
              height: 140,
              placeholderLabel: 'CNI - VERSO',
              caption: 'Pièce d\'identité (verso)',
            ),
          ],
        ),
      );
      widgets.add(pw.SizedBox(height: 14));
    }

    widgets.add(_preambleText(d));
    return widgets;
  }

  static pw.Widget _preambleText(ContractData d) {
    final chefName = d.nomPrenom.isEmpty
        ? '...........................'
        : d.nomPrenom;
    final bool isCommunautaire = d.type == ContractType.communautaire;
    final String repIntro;
    if (isCommunautaire) {
      repIntro =
          'La COMMUNAUTÉ AFFECTÉE identifiée ci-dessus, valablement représentée à l\'effet des présentes par son Chef, '
          'Monsieur $chefName, agissant d\'un commun accord avec et pour le compte de l\'ensemble des personnes '
          'physiques composant ladite Communauté affectée, lesquelles lui ont reconnu et conféré l\'ensemble des '
          'pouvoirs nécessaires, en ce compris le pouvoir de représentation, pour conclure le présent accord.';
    } else {
      final partyWord = d.type == ContractType.proprietaire
          ? const ['MÉNAGE AFFECTÉ', 'Ménage']
          : const ['LIGNAGE AFFECTÉ', 'Lignage'];
      repIntro =
          'Le ${partyWord[0]} identifié ci-dessus, valablement représenté à l\'effet des présentes par son Chef, '
          'Monsieur $chefName, agissant d\'un commun accord avec et pour le compte de l\'ensemble des personnes '
          'physiques composant ledit ${partyWord[1]} affecté, lesquelles lui ont reconnu et conféré l\'ensemble des '
          'pouvoirs nécessaires, en ce compris le pouvoir de représentation, pour conclure le présent accord.';
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _paragraph(
          'LA SOCIÉTÉ Winning Consortium Alumina Guinea (WCAG), société de droit guinéen enregistrée au Registre de '
          'commerce sous le numéro RCCM/GN-KAL/2018.B.086411/2018 dont le siège social se situe à Camayenne, Corniche '
          'Nord, BP : 435, C/Dixinnn, Conakry, République de Guinée, représentée par son Directeur Général M. WU '
          'QIONG, dûment habilité aux fins des présentes,',
        ),
        _paragraph('Ci-après dénommée «WCAG».'),
        _paragraph('Et'),
        _paragraph(repIntro),
      ],
    );
  }

  // ---------------- Page 2: preamble continued + Article 1 ----------------

  static List<pw.Widget> _page2PreambleAndArticle1(ContractData d) {
    final bool isCommunautaire = d.type == ContractType.communautaire;
    // PARTY_LABEL: "Ménage affecté" / "Lignage affecté" / "Communauté affectée"
    final party = d.type.partyLabel;
    final partyLower = party[0].toLowerCase() + party.substring(1);
    final String chefOf;
    final String chefDesigne;
    switch (d.type) {
      case ContractType.proprietaire:
        chefOf = 'Chef du Ménage affecté';
        chefDesigne = 'Chef désigné du Ménage affecté';
        break;
      case ContractType.lignage:
        chefOf = 'Chef du Lignage affecté';
        chefDesigne = 'Chef désigné du Lignage affecté';
        break;
      case ContractType.communautaire:
        chefOf = 'Chef de la Communauté affectée';
        chefDesigne = 'Chef désigné de la Communauté affectée';
        break;
    }
    final art = isCommunautaire ? 'la' : 'le';

    return [
      _paragraph(
        'Ci-après dénommé${isCommunautaire ? 'e' : ''} « $party ».',
      ),
      _paragraph(
        'WCAG et ${isCommunautaire ? 'la' : 'le'} $partyLower étant également désignés ci-après collectivement '
        '« les Parties » et individuellement « la Partie ».',
      ),
      pw.SizedBox(height: 6),
      _paragraph('APRÈS AVOIR PRÉALABLEMENT RAPPELÉ QUE :', fontSize: 10.5),
      _paragraph(
        '- En vue de la construction et de l\'exploitation de la raffinerie d\'alumine par WCAG, un recensement des '
        'ayants droit et un inventaire de l\'ensemble de leurs biens affectés ont été entrepris depuis le '
        '21/11/2025, dans l\'emprise concernée du Projet ;',
      ),
      _paragraph(
        '- De ces études, il ressort que $art $partyLower détient des droits dans la zone visée par le Projet. Ces '
        'droits, dûment énumérés dans une fiche récapitulative signée par le $chefDesigne, sont détaillés en '
        'Annexe 1 ;',
      ),
      _paragraph(
        '- Conformément à ses principes et à ses engagements vis-à-vis de l\'État guinéen, WCAG a élaboré un Plan '
        'd\'action de Réinstallation et de Compensation (PARC) afin d\'assurer la compensation de tous les ayants '
        'droits affectés par le Projet. Le PARC prévoit la compensation pour une occupation permanente.',
      ),
      _paragraph(
        '- En application du PARC, une proposition de compensation personnalisée a été développée par WCAG, et '
        'communiquée, présentée et expliquée ${isCommunautaire ? 'à la' : 'au'} $partyLower et aux personnes le '
        'composant ;',
      ),
      _paragraph(
        '- Après avoir pris le temps nécessaire à la réflexion et à la consultation de l\'ensemble des personnes le '
        'constituant, le $chefOf consent librement et en toute connaissance de cause à l\'offre de compensation '
        'proposée par WCAG telle que décrite en Annexe 2 ;',
      ),
      _paragraph(
        'Dans ce contexte, les Parties ont conclu le présent accord de compensation (ci-après dénommé l\'« '
        'Accord »).',
      ),
      pw.SizedBox(height: 6),
      _paragraph('IL A ÉTÉ CONVENU ET ARRÊTÉ CE QUI SUIT :', fontSize: 10.5),
      _articleTitle('Article 1 – Principe d\'indemnisation'),
      _paragraph(
        'Les Parties conviennent des termes et conditions de l\'indemnisation, pour la perte des terres et des '
        'biens ${isCommunautaire ? 'de la' : 'du'} $partyLower figurant en Annexe 1. '
        '${isCommunautaire ? 'La' : 'Le'} $partyLower considère ces termes et conditions comme étant pleinement '
        'suffisants, satisfaisants et de nature à compenser intégralement tout préjudice causé par son '
        'déplacement physique et/ou économique ainsi que les éventuelles conséquences sur ses conditions de vie, '
        'y compris tous les dommages et pertes subis par ${isCommunautaire ? 'elle' : 'lui'} du fait de ce '
        'déplacement.',
      ),
    ];
  }

  // ---------------- Page 3: Articles 2, 3, 4 ----------------

  static List<pw.Widget> _page3ArticlesRest(ContractData d) {
    final bool isCommunautaire = d.type == ContractType.communautaire;
    final party = d.type.partyLabel;
    final partyLower = party[0].toLowerCase() + party.substring(1);
    final deParty = '${isCommunautaire ? 'de la' : 'du'} $partyLower';
    final artLeLa = isCommunautaire ? 'la' : 'le';
    final membresDe = isCommunautaire
        ? 'de la Communauté affectée'
        : 'du $partyLower';

    return [
      _articleTitle('Article 2 – Principe de non-contestation'),
      _paragraph(
        '${isCommunautaire ? 'La' : 'Le'} $partyLower déclare expressément renoncer à réclamer à WCAG, ainsi qu\'à '
        'ses sous-traitants intervenant dans le cadre de la mise en œuvre du Projet, une quelconque indemnisation '
        'supplémentaire, de quelque nature que ce soit, à raison des faits cités en préambule et autres que les '
        'indemnisations prévues dans le cadre du présent Accord.',
      ),
      _paragraph(
        '${isCommunautaire ? 'La' : 'Le'} $partyLower s\'engage ainsi dans les conditions prévues dans l\'Annexe 2 '
        'à renoncer :',
      ),
      _paragraph(
        '- À tous droits de quelque nature que ce soit, formels, informels ou coutumiers, sur les parcelles listées '
        'en Annexe 1 pour la durée prévue à cet accord ;',
      ),
      _paragraph(
        '- À tous droits sur les actifs de quelque nature que ce soit qui y sont implantés ou édifiés, (ci-après '
        'les « Actifs ») pour la durée prévue à cet accord.',
      ),
      _paragraph(
        'Les Parties s\'engagent à conclure, à cet effet, une attestation de reconnaissance de compensation au '
        'plus tard à la date à laquelle l\'indemnisation aura été effectivement mise à la disposition $deParty. '
        'Cette attestation prendra la forme d\'un acte de rétrocession.',
      ),
      _articleTitle('Article 3 – Dispositions diverses'),
      _paragraph(
        'Les Parties reconnaissent que le préambule ainsi que les annexes font partie intégrante du présent '
        'Accord.',
      ),
      _paragraph(
        'L\'Accord est régi et interprété conformément aux dispositions du droit guinéen.',
      ),
      _paragraph(
        'Tous différends qui surviendraient entre $artLeLa $partyLower ou l\'un quelconque de ses membres et les '
        'autres Parties découlant de l\'Accord ou en relation avec celui-ci seront réglés conformément aux '
        'dispositions légales en vigueur en République de Guinée.',
      ),
      _articleTitle('Article 4 – Intégrité du consentement $deParty'),
      _paragraph(
        'Les Parties reconnaissent qu\'un représentant des autorités locales a assisté à la présentation du '
        'présent Accord. En apposant sa signature au bas du présent Accord, ledit représentant confirme :',
      ),
      _paragraph(
        '- Que l\'Accord a fait l\'objet d\'une traduction orale en soussou, langue parlée par la Communauté '
        'affectée ;',
      ),
      _paragraph(
        '- Qu\'il a informé tous les membres présents, adultes et capables $membresDe de l\'ensemble de leurs '
        'droits et obligations au titre de l\'Accord et de ses annexes ; et',
      ),
      _paragraph(
        '- Qu\'il a répondu à toutes leurs interrogations et leur a communiqué l\'ensemble des éléments de réponse '
        'propres à leur permettre de se déterminer eux-mêmes.',
      ),
      _paragraph(
        'Le représentant des autorités locales s\'engage en outre expressément à assurer un suivi de l\'exécution '
        'du présent Accord, selon les termes et dans les conditions qui y sont définis.',
      ),
      _paragraph(
        'Les membres $membresDe, qui ont disposé du temps de réflexion nécessaire, déclarent ainsi avoir '
        'pleinement compris et accepté de leur plein gré, l\'ensemble de leurs droits et obligations au titre de '
        'l\'Accord.',
      ),
    ];
  }

  // ---------------- Page 4: RÉCAPITULATIF + signature stub ----------------

  static List<pw.Widget> _page4Recapitulatif(ContractData d) {
    final s = d.summary;
    pw.TableRow row(String label, double montant, {bool bold = false}) {
      return pw.TableRow(
        decoration: bold ? const pw.BoxDecoration(color: greyLight) : null,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: pw.Text(
              Formatters.number(montant),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      );
    }

    return [
      _sectionTitle('RÉCAPITULATIF DES COMPENSATIONS'),
      pw.Table(
        border: pw.TableBorder.all(color: greyBorder, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(1.3),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: greyLight),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 6,
                ),
                child: pw.Text(
                  'Type de biens',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 6,
                ),
                child: pw.Text(
                  'Montants (GNF)',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          row('Compensation des parcelles (foncier)', s.parcelles),
          row(
            'Compensation des champs (cultures annuelles)',
            s.champsCulturesAnnuelles,
          ),
          row('Compensation des cultures pérennes', s.culturesPerennes),
          row('Compensation des espèces sauvages', s.especesSauvages),
          row('Compensation des bois d\'œuvre', s.boisDoeuvre),
          row('Compensation des ressources', s.ressources),
          row('Compensation des structures', s.structures),
          row('Total des compensations', s.total, bold: true),
        ],
      ),
      pw.SizedBox(height: 30),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Container(
              height: 100,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: greyBorder),
              ),
              child: pw.Column(
                children: [
                  pw.Container(
                    width: double.infinity,
                    color: greyLight,
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text(
                      'SIGNATURE',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              height: 100,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: greyBorder),
              ),
              child: pw.Column(
                children: [
                  pw.Container(
                    width: double.infinity,
                    color: greyLight,
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Text(
                      'EMPREINTE POUCE GAUCHE',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ---------------- Page 5: Signature blocks ----------------

  static List<pw.Widget> _page5Signatures(ContractData d) {
    final chefName = d.nomPrenom.isEmpty
        ? '...........................'
        : d.nomPrenom;
    final bool isCommunautaire = d.type == ContractType.communautaire;
    final bool isLignage = d.type == ContractType.lignage;
    // party.split()[0]: "Ménage" / "Lignage" / "Communauté"
    final partyFirstWord = d.type.partyLabel.split(' ').first;
    final consentText =
        'Je, soussigné, ${isCommunautaire ? '' : 'Monsieur '}$chefName, en ma qualité de ${d.type.chefLabel}, '
        'certifie, en plein accord avec les membres du${isCommunautaire ? 'e' : ''} $partyFirstWord, donner mon '
        'consentement à l\'ensemble des termes et conditions du présent Accord qui m\'ont été traduits oralement '
        'du français en sousou, et ce, en présence d\'un représentant des autorités locales dont la fonction est '
        '............................................................................';

    // Consent-box header: corrected per-type (see contract_pdf.py _page5())
    // rather than replicating the reference documents' "Le Ménage affecté"
    // copy-paste artifact regardless of type.
    final String consentHeader;
    switch (d.type) {
      case ContractType.proprietaire:
        consentHeader = 'Le Ménage affecté';
        break;
      case ContractType.lignage:
        consentHeader = 'Le Lignage affecté';
        break;
      case ContractType.communautaire:
        consentHeader = 'La Communauté affectée';
        break;
    }

    pw.Widget signatureLine(String label) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Text(
        '$label : ......................................................................',
        style: const pw.TextStyle(fontSize: 8.5),
      ),
    );

    return [
      _paragraph(
        'Fait en deux (2) exemplaires originaux, un étant remis à chacune des Parties.\n'
        'À ........................, le ${Formatters.date(d.dateEnquete)}',
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.75),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              consentHeader,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              consentText,
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Signature :', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      ..._page5SignatureGrids(d, signatureLine, isLignage),
    ];
  }

  /// Builds the WCAG/Autorités signature boxes and, depending on the
  /// contract type, either the Ménage/Collectif layout (row1 = WCAG |
  /// Autorités; row2 = Témoins | Autorités locales) or the Lignage layout
  /// (row1 = WCAG | single "Autorités locales" box; full-width Témoins
  /// section with a 2x3 grid of signature slots and no second "Autorités
  /// locales" box) — mirrors contract_pdf.py's _page5().
  static List<pw.Widget> _page5SignatureGrids(
    ContractData d,
    pw.Widget Function(String) signatureLine,
    bool isLignage,
  ) {
    pw.Widget signatureBox(String title, List<String> labels) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: greyBorder)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            for (final l in labels) signatureLine(l),
          ],
        ),
      );
    }

    final wcagBox = signatureBox('WCAG', const ['Nom', 'Fonction', 'Signature']);

    if (isLignage) {
      // Lignage: row1 = WCAG box | single-slot "Autorités locales" box (NOT
      // the 2-slot "Autorités" box used by Ménage/Collectif).
      final autLocBox = signatureBox(
        'Autorités locales',
        const ['Nom', 'Fonction', 'Signature'],
      );
      pw.Widget temoinCell() => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            signatureLine('Nom'),
            signatureLine('Fonction'),
            signatureLine('Signature'),
          ],
        ),
      );
      final gridRows = <pw.TableRow>[];
      for (int i = 0; i < 3; i++) {
        gridRows.add(
          pw.TableRow(children: [temoinCell(), temoinCell()]),
        );
      }
      return [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: wcagBox),
            pw.SizedBox(width: 10),
            pw.Expanded(child: autLocBox),
          ],
        ),
        pw.SizedBox(height: 6),
        // Full-width Témoins section with a 2-column x 3-row grid of slots
        // (6 total), matching the Lignage reference's distinct layout.
        pw.Text(
          d.type.temoinsGroupLabel,
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: greyBorder, width: 0.75),
          children: gridRows,
        ),
      ];
    }

    // Ménage / Collectif: row1 = WCAG box | 2-slot "Autorités" box; row2 =
    // Témoins (4 slots) | Autorités locales (4 slots).
    final autoritesBox = pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: greyBorder)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Autorités',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
          signatureLine('Nom'),
          signatureLine('Institution/Fonction'),
          signatureLine('Signature'),
          signatureLine('Nom'),
          signatureLine('Institution/Fonction'),
        ],
      ),
    );

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: wcagBox),
          pw.SizedBox(width: 10),
          pw.Expanded(child: autoritesBox),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: greyBorder),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    d.type.temoinsGroupLabel,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  for (int i = 0; i < 4; i++) ...[
                    signatureLine('Nom'),
                    signatureLine('Relation'),
                    signatureLine('Signature'),
                    pw.SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: greyBorder),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Autorités locales (Chef du village, Chef du district ou\nAutres.......)',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  for (int i = 0; i < 4; i++) ...[
                    signatureLine('Nom'),
                    signatureLine('Fonction'),
                    signatureLine('Signature'),
                    pw.SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ---------------- ANNEXE 1: all asset categories (same page) ----------------

  /// Builds ALL 6 ANNEXE 1 asset-category tables (Parcelles agricoles,
  /// Cultures annuelles, Bois d'œuvre, Cultures pérennes, Espèces sauvages,
  /// Structures) as one continuous widget list with NO forced page break
  /// between categories, so pw.MultiPage's natural flow keeps them on the
  /// same page whenever they fit, only overflowing to a following page when
  /// there are genuinely too many assets to fit on one page.
  static List<pw.Widget> _annexe1AllAssets(ContractData d) {
    final s = d.summary;
    final widgets = <pw.Widget>[
      _sectionTitle('ANNEXE 1 – LISTE DES BIENS AFFECTÉS ET COMPENSATIONS'),
    ];

    // -------- Parcelles (foncier) --------
    widgets.add(_annexSubtitle('PARCELLES AGRICOLES (FONCIER)'));
    if (s.parcelleDetails.isEmpty) {
      widgets.add(_emptyAnnexNote());
    } else {
      double totalSup = 0, totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Type de terrain',
          'Coût/m² (GNF)',
          'Superficie (m²)',
          'Montant (GNF)',
        ]),
      ];
      for (final p in s.parcelleDetails) {
        totalSup += p.superficie;
        totalMontant += p.montant;
        rows.add(
          _annexDataRow([
            p.typeDeTerrain,
            Formatters.number(p.coutM2),
            p.superficie.toStringAsFixed(2),
            Formatters.number(p.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow([
          'TOTAL',
          '',
          totalSup.toStringAsFixed(2),
          Formatters.number(totalMontant),
        ]),
      );
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: greyBorder, width: 0.5),
          children: rows,
        ),
      );
    }

    // -------- Bois d'œuvre — column order matches the reference contracts:
    // Espèce, Circonférence, Hauteur, Volume unitaire, Nombre de pieds,
    // Coût/m³, Volume total, Montant (GNF). --------
    widgets.add(pw.SizedBox(height: 10));
    widgets.add(_annexSubtitle('BOIS D\'ŒUVRE'));
    if (s.boisDoeuvreDetails.isEmpty) {
      widgets.add(_emptyAnnexNote());
    } else {
      double totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Espèce',
          'Circonférence\nau DHP (m)',
          'Hauteur (m)',
          'Volume\nunitaire (m³)',
          'Nombre\nde pieds',
          'Coût/m³ (GNF)',
          'Volume\ntotal (m³)',
          'Montant (GNF)',
        ]),
      ];
      for (final b in s.boisDoeuvreDetails) {
        totalMontant += b.montant;
        rows.add(
          _annexDataRow([
            b.espece,
            b.circonference.toStringAsFixed(2),
            b.hauteur.toStringAsFixed(2),
            b.volumeUnitaire.toStringAsFixed(3),
            b.nombrePieds.toString(),
            Formatters.number(b.prixUnitaire),
            b.volumeTotal.toStringAsFixed(3),
            Formatters.number(b.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow([
          'TOTAL',
          '',
          '',
          '',
          '',
          '',
          '',
          Formatters.number(totalMontant),
        ]),
      );
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: greyBorder, width: 0.5),
          children: rows,
        ),
      );
    }

    // -------- Cultures pérennes — multi-level headers: Type d'arbre |
    // Plantules {Nombre, Prix unitaire, Montant} | Jeunes pousses non
    // productives {...} | Jeunes pousses productives {...} | Adultes {...}
    // | Montant (GNF) total, matching the reference contracts exactly. --------
    if (s.culturePerenneDetails.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_annexSubtitle('CULTURES PÉRENNES'));
      double totalMontant = 0;
      final dataRows = <List<String>>[];
      for (final c in s.culturePerenneDetails) {
        totalMontant += c.montant;
        final mPlantules = c.plantules * c.prixPlante;
        final mJnp = c.jeunesNp * c.prixJeuneNp;
        final mJp = c.jeunesP * c.prixJeuneP;
        final adultesCount = c.matures + c.adulteDeclinant;
        final mAdultes = adultesCount * c.prixAdulte;
        dataRows.add([
          c.espece,
          c.plantules.toString(),
          Formatters.number(c.prixPlante),
          Formatters.number(mPlantules),
          c.jeunesNp.toString(),
          Formatters.number(c.prixJeuneNp),
          Formatters.number(mJnp),
          c.jeunesP.toString(),
          Formatters.number(c.prixJeuneP),
          Formatters.number(mJp),
          adultesCount.toString(),
          Formatters.number(c.prixAdulte),
          Formatters.number(mAdultes),
          Formatters.number(c.montant),
        ]);
      }
      final totalRow = [
        'TOTAUX', '', '', '', '', '', '', '', '', '', '', '', '',
        Formatters.number(totalMontant),
      ];
      widgets.add(
        _annexGroupedTable(
          // NOTE: widened the "Type d'arbre" and "Montant (GNF)" solo
          // columns and narrowed the "Nb" sub-columns (mirrors the web
          // admin's contract_pdf.py col_widths fix) plus shortened labels
          // and a smaller font size, to prevent text overflow / misaligned
          // line-wraps reported in this table on both platforms.
          cols: [
            _AnnexCol.solo('Type\nd\'arbre', 22),
            _AnnexCol.group('Plantules', const [
              _AnnexSubCol('Nb', 8),
              _AnnexSubCol('P.U.\n(GNF)', 12),
              _AnnexSubCol('Montant\n(GNF)', 13),
            ]),
            _AnnexCol.group('Jeunes pousses\nnon productives', const [
              _AnnexSubCol('Nb', 8),
              _AnnexSubCol('P.U.\n(GNF)', 12),
              _AnnexSubCol('Montant\n(GNF)', 13),
            ]),
            _AnnexCol.group('Jeunes pousses\nproductives', const [
              _AnnexSubCol('Nb', 8),
              _AnnexSubCol('P.U.\n(GNF)', 12),
              _AnnexSubCol('Montant\n(GNF)', 13),
            ]),
            _AnnexCol.group('Adultes', const [
              _AnnexSubCol('Nb', 8),
              _AnnexSubCol('P.U.\n(GNF)', 12),
              _AnnexSubCol('Montant\n(GNF)', 13),
            ]),
            _AnnexCol.solo('Montant\n(GNF)', 20),
          ],
          dataRows: dataRows,
          totalRow: totalRow,
          headerFontSize: 5.6,
          dataFontSize: 5.6,
        ),
      );
      widgets.add(pw.SizedBox(height: 10));
    }

    // -------- Espèces sauvages — multi-level headers: Type d'arbre |
    // Jeunes pousses non productives {Prix unitaire, Nombre, Montant} |
    // Jeunes pousses productives {Prix unitaire, Nombre, Montant} |
    // Montant (GNF) total. --------
    if (s.especeSauvageDetails.isNotEmpty) {
      widgets.add(_annexSubtitle('ESPÈCES SAUVAGES'));
      double totalMontant = 0;
      final dataRows = <List<String>>[];
      for (final e in s.especeSauvageDetails) {
        totalMontant += e.montant;
        final mNp = e.jeunesNp * e.prixNp;
        final mP = e.jeunesP * e.prixP;
        dataRows.add([
          e.espece,
          Formatters.number(e.prixNp),
          e.jeunesNp.toString(),
          Formatters.number(mNp),
          Formatters.number(e.prixP),
          e.jeunesP.toString(),
          Formatters.number(mP),
          Formatters.number(e.montant),
        ]);
      }
      final totalRow = [
        'TOTAUX', '', '', '', '', '', '',
        Formatters.number(totalMontant),
      ];
      widgets.add(
        _annexGroupedTable(
          cols: [
            _AnnexCol.solo('Type d\'arbre', 34),
            _AnnexCol.group('Jeunes pousses non productives', const [
              _AnnexSubCol('Prix unitaire\n(GNF)', 24),
              _AnnexSubCol('Nombre', 18),
              _AnnexSubCol('Montant\n(GNF)', 24),
            ]),
            _AnnexCol.group('Jeunes pousses productives', const [
              _AnnexSubCol('Prix unitaire\n(GNF)', 24),
              _AnnexSubCol('Nombre', 18),
              _AnnexSubCol('Montant\n(GNF)', 24),
            ]),
            _AnnexCol.solo('Montant (GNF)', 30),
          ],
          dataRows: dataRows,
          totalRow: totalRow,
        ),
      );
      widgets.add(pw.SizedBox(height: 10));
    }

    // -------- Structures --------
    if (s.structureDetails.isNotEmpty) {
      widgets.add(_annexSubtitle('STRUCTURES'));
      double totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Désignation',
          'Unité',
          'Quantité',
          'Prix unitaire (GNF)',
          'Montant (GNF)',
        ]),
      ];
      for (final st in s.structureDetails) {
        totalMontant += st.montant;
        rows.add(
          _annexDataRow([
            st.designation,
            st.unite,
            st.quantite.toStringAsFixed(2),
            Formatters.number(st.prixUnitaire),
            Formatters.number(st.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow(['TOTAL', '', '', '', Formatters.number(totalMontant)]),
      );
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: greyBorder, width: 0.5),
          children: rows,
        ),
      );
      widgets.add(pw.SizedBox(height: 10));
    }

    if (s.culturePerenneDetails.isEmpty &&
        s.especeSauvageDetails.isEmpty &&
        s.structureDetails.isEmpty &&
        s.parcelleDetails.isEmpty &&
        s.cultureAnnuelleDetails.isEmpty &&
        s.boisDoeuvreDetails.isEmpty) {
      widgets.add(_emptyAnnexNote());
    }

    return widgets;
  }

  static pw.Widget _annexSubtitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: pw.FontWeight.bold,
        color: maroon,
      ),
    ),
  );

  static pw.Widget _emptyAnnexNote() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Text(
      'Aucun bien de cette catégorie n\'a été recensé.',
      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
    ),
  );

  static pw.TableRow _annexHeaderRow(List<String> labels) => pw.TableRow(
    decoration: const pw.BoxDecoration(color: greyLight),
    children: labels
        .map(
          (l) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
            child: pw.Text(
              l,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        )
        .toList(),
  );

  static pw.TableRow _annexDataRow(List<String> values) => pw.TableRow(
    children: values
        .asMap()
        .entries
        .map(
          (e) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
            child: pw.Text(
              e.value,
              textAlign: e.key == 0 ? pw.TextAlign.left : pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 7.5),
            ),
          ),
        )
        .toList(),
  );

  static pw.TableRow _annexTotalRow(List<String> values) => pw.TableRow(
    decoration: const pw.BoxDecoration(color: greyLight),
    children: values
        .asMap()
        .entries
        .map(
          (e) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
            child: pw.Text(
              e.value,
              textAlign: e.key == 0 ? pw.TextAlign.left : pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        )
        .toList(),
  );

  /// Renders a multi-level-header ANNEXE 1 table where some top-level
  /// columns are "solo" (single column, vertically centered label spanning
  /// both header rows, e.g. "Type d'arbre") and others are "grouped" (one
  /// top-level label spanning several sub-columns, e.g. "Plantules" over
  /// "Nombre / Prix unitaire (GNF) / Montant (GNF)"). Since [pw.Table] has
  /// no native colSpan/rowSpan support, the header is built with stacked
  /// [pw.Row]s using flex weights that match the underlying data table's
  /// column widths exactly, so both align pixel-perfectly.
  static pw.Widget _annexGroupedTable({
    required List<_AnnexCol> cols,
    required List<List<String>> dataRows,
    required List<String> totalRow,
    double headerFontSize = 6.3,
    double dataFontSize = 7.5,
  }) {
    // Flatten to leaf column flex weights (1 per leaf column).
    final leafFlex = <int>[];
    for (final c in cols) {
      if (c.subCols == null) {
        leafFlex.add(c.flex);
      } else {
        for (final sc in c.subCols!) {
          leafFlex.add(sc.flex);
        }
      }
    }

    pw.Widget headerCell(
      String text, {
      required int flex,
      bool bold = true,
    }) => pw.Expanded(
      flex: flex,
      child: pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 2),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: headerFontSize,
            fontWeight: bold ? pw.FontWeight.bold : null,
          ),
        ),
      ),
    );

    // Row 0: top-level labels. Solo columns render their label here and
    // occupy both header rows (via a taller container); grouped columns
    // render their group label spanning the group's total flex width.
    final row0Children = <pw.Widget>[];
    final row1Children = <pw.Widget>[];
    for (final c in cols) {
      if (c.subCols == null) {
        // Solo column: label centered vertically across both header rows.
        row0Children.add(
          pw.Expanded(
            flex: c.flex,
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2.5,
                horizontal: 2,
              ),
              constraints: const pw.BoxConstraints(minHeight: 26),
              child: pw.Text(
                c.label,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: headerFontSize, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
        row1Children.add(pw.Expanded(flex: c.flex, child: pw.SizedBox()));
      } else {
        final groupFlex = c.subCols!.fold<int>(0, (a, sc) => a + sc.flex);
        row0Children.add(headerCell(c.label, flex: groupFlex));
        for (final sc in c.subCols!) {
          row1Children.add(headerCell(sc.label, flex: sc.flex));
        }
      }
    }

    pw.Widget bordered(pw.Widget child) => pw.Container(
      decoration: pw.BoxDecoration(
        color: greyLight,
        border: pw.Border.all(color: greyBorder, width: 0.5),
      ),
      child: child,
    );

    final header = pw.Column(
      children: [
        bordered(pw.Row(children: row0Children)),
        bordered(pw.Row(children: row1Children)),
      ],
    );

    pw.Widget dataCell(String text, {required int flex, required bool isFirst, bool bold = false}) =>
        pw.Expanded(
          flex: flex,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: greyBorder, width: 0.5)),
            child: pw.Text(
              text,
              textAlign: isFirst ? pw.TextAlign.left : pw.TextAlign.right,
              style: pw.TextStyle(fontSize: dataFontSize, fontWeight: bold ? pw.FontWeight.bold : null),
            ),
          ),
        );

    pw.Widget buildDataRow(List<String> values, {bool bold = false, PdfColor? bg}) {
      final children = <pw.Widget>[];
      for (var i = 0; i < values.length; i++) {
        children.add(dataCell(values[i], flex: leafFlex[i], isFirst: i == 0, bold: bold));
      }
      return pw.Container(
        color: bg,
        child: pw.Row(children: children),
      );
    }

    return pw.Column(
      children: [
        header,
        ...dataRows.map((r) => buildDataRow(r)),
        buildDataRow(totalRow, bold: true, bg: greyLight),
      ],
    );
  }

  // ---------------- ANNEXE 2 ----------------

  static List<pw.Widget> _annexe2Text(ContractData d) {
    if (d.type == ContractType.communautaire) {
      return [
        _sectionTitle('ANNEXE 2 : MODALITÉS D\'INDEMNISATION'),
        _paragraph(
          'La Communauté Affectée, signataire de l\'Accord, accepte de quitter la ou les parcelles dont la liste '
          'figure en Annexe 1 au plus tard quinze (15) jours après la signature du présent Accord. Il appartient '
          'donc à la Communauté Affectée de prendre toutes les dispositions utiles afin de retirer les éléments '
          'meubles et immeubles qui s\'y trouvent avant cette échéance.',
        ),
        _paragraph(
          'En contrepartie, WCAG s\'engage, conformément au PARC, à indemniser la Communauté Affectée des '
          'conséquences du Projet sur ses conditions de vie, y compris tous les dommages et pertes subis par lui '
          'du fait de ce Projet, de la manière et dans les conditions décrites ci-après :',
        ),
        _articleTitle('1. CONSTITUTION D\'UN BUDGET PROJET'),
        _paragraph(
          'Conformément aux modalités d\'indemnisation prévues dans le PARC, les biens détenus par la Communauté '
          'Affectée seront compensés par le biais d\'un ou plusieurs projets d\'intérêt général réalisés au profit '
          'de la Communauté Affectée.',
        ),
        _paragraph(
          'Le budget dévolu à ce ou ces projets est fonction de la superficie totale des parcelles impactées par '
          'le projet et des biens qui s\'y trouvent, tel qu\'énumérés en Annexe 1.',
        ),
        _paragraph(
          'La Communauté Affectée considère ce budget comme étant suffisant, satisfaisant et de nature à '
          'compenser intégralement les pertes occasionnées par le Projet.',
        ),
        _paragraph(
          'Sur cette base, le budget total disponible s\'élève ainsi à ${Formatters.gnf(d.summary.total)}.',
        ),
        _articleTitle('2. IDENTIFICATION DES PROJETS COLLECTIFS'),
        _paragraph(
          'Conformément aux dispositions du PARC, les projets communautaires seront identifiés conjointement '
          'par :',
        ),
        _paragraph(
          '- La Communauté Affectée, représentée par un comité constitué à cet effet ; et\n'
          '- WCAG ou son représentant désigné,',
        ),
        _paragraph(
          'L\'appui des Services Techniques Déconcentrés compétents en la matière sera également sollicité, et '
          'une cohérence recherchée avec le Plan de Développement Local et le Plan Annuel d\'Investissement de la '
          'Commune concernée.',
        ),
        _paragraph(
          'Les Parties s\'engagent à prendre toutes les mesures requises afin que le ou les projets soient '
          'identifiés et démarrés dans un délai maximum de trois (3) mois à compter de la signature du présent '
          'Accord.',
        ),
        _paragraph(
          'Les projets seront sélectionnés parmi la liste de projets-types proposés ci-dessous :',
        ),
        _paragraph(
          '- Aménagement agricole collectif ;\n'
          '- Puits (pastoral, maraîcher, ou domestique) ;\n'
          '- Marché (amélioration d\'une structure existante) ;\n'
          '- École, centre de santé (amélioration et équipement d\'une structure existante) ;\n'
          '- Voies d\'accès à partir de la voie nouvellement créée ou en direction des axes principaux existants '
          '(cette création ne pourra pas donner lieu à de nouvelle compensation et leur tracé doit donc faire '
          'l\'objet d\'un consentement mutuel avec les parties concernées) ;\n'
          '- Autre projet identifié par la communauté et dans les limites du budget disponible.',
        ),
        _paragraph(
          'À l\'issue de ce processus de concertation, une fiche d\'identification sommaire sera corédigée par '
          'WCAG et le comité établi par la Communauté Affectée en vue de leur mise en œuvre. La fiche comprendra '
          'la sélection des projets à mettre en œuvre (plusieurs peuvent être prévus), et une estimation '
          'budgétaire par composante ainsi que le montant total.',
        ),
        _paragraph(
          'Seuls les projets pouvant être exécutés intégralement dans les limites du budget défini au point 1 '
          'ci-dessus pourront être entrepris dans le cadre du présent Accord.',
        ),
        _articleTitle('3. MISE EN ŒUVRE DES PROJETS'),
        _paragraph(
          'Conformément aux dispositions du PARC, les projets seront mis en œuvre par des prestataires '
          'sélectionnés par appel d\'offres ou directement par leur soin (cas des voies d\'accès notamment), selon '
          'leurs capacités techniques, leurs expériences et les prix proposés. À qualité et à prix comparables, '
          'la préférence sera accordée aux prestataires installés dans la préfecture d\'implantation du projet.',
        ),
        _paragraph('À cet effet :'),
        _paragraph(
          '- Un dossier d\'appel d\'offres sera développé par le maître d\'œuvre, sur base de la fiche '
          'd\'identification sommaire ;\n'
          '- Les offres seront ouvertes à l\'occasion d\'une réunion convoquée par le maître d\'œuvre, en présence '
          'du comité constitué par la Communauté Affectée.',
        ),
        _paragraph(
          'Les marchés seront attribués par WCAG, qui reste seule responsable de la sélection finale du ou des '
          'prestataires, sur base des critères énoncés dans le dossier d\'appel d\'offres, puis de la réalisation '
          'des travaux.',
        ),
        _paragraph(
          'Les travaux seront réalisés sous la supervision du maître d\'œuvre et du comité constitué par la '
          'Communauté Affectée. La réception provisoire du projet sera accordée à l\'achèvement des travaux, '
          'moyennant l\'accord du maître d\'œuvre et dudit comité.',
        ),
        _articleTitle('4. RÉTROCESSION DES PROJETS'),
        _paragraph(
          'À la suite de la réception provisoire des projets, il sera procédé à leur rétrocession formelle à la '
          'Communauté Affectée. À cet effet, un acte de rétrocession sera dressé dans lequel la Communauté '
          'Affectée s\'engage à utiliser le projet selon sa destination convenue jusqu\'à l\'achèvement de la '
          'période de garantie et le versement, par WCAG, de la retenue de garantie.',
        ),
        _paragraph(
          'La signature de l\'acte de rétrocession marque également la fin du processus de compensation.',
        ),
        _articleTitle('5. GESTION DES FONDS'),
        _paragraph(
          'Le budget défini au point 1 ci-dessus sera provisionné sur les livres de WCAG en vue de son '
          'décaissement progressif, au bénéfice des prestataires désignés pour assurer l\'exécution des projets.',
        ),
        _paragraph(
          'Une situation financière détaillée sera dressée par WCAG à la fin de chaque trimestre et transmise '
          'au comité constitué par la Communauté Affectée, avec copie au Préfet, afin qu\'à tout moment, la '
          'Communauté Affectée dispose d\'une information complète quant à la gestion des fonds.',
        ),
        _paragraph(
          'Conformément au PARC, les reliquats éventuels seront soit mis à la disposition de la Communauté '
          'Affectée, soit engagés sur un nouveau projet au bénéfice de la Communauté Affectée, selon leur '
          'montant. Dans tous les cas, ces reliquats éventuels restent acquis à la Communauté Affectée.',
        ),
      ];
    }

    final party = d.type.partyLabel;
    return [
      _sectionTitle('ANNEXE 2 : MODALITÉS D\'INDEMNISATION EN NUMÉRAIRE'),
      _paragraph(
        'Le $party, signataire de l\'Accord, accepte de quitter définitivement et irrévocablement la ou les parcelles '
        'dont la liste figure sur sa fiche d\'indemnisation, au plus tard sept (7) jours après la mise en œuvre des '
        'dispositions décrites ci-dessous. Il appartient donc au $party de prendre toutes les dispositions utiles afin '
        'de retirer les éléments meubles et immeubles qui s\'y trouvent avant cette échéance.',
      ),
      _paragraph(
        'En contrepartie, AMC s\'engage, conformément au PARC, à indemniser le $party des conséquences du Projet sur '
        'ses conditions de vie, y compris tous les dommages et pertes subis par lui du fait du Projet, de la manière et '
        'dans les conditions décrites ci-après :',
      ),
      _articleTitle('1. INDEMNISATION FINANCIÈRE'),
      _paragraph(
        'Conformément aux modalités d\'indemnisation prévues dans le PARC, les Parties conviennent que le montant total '
        'des indemnisations financières devant être payées au $party sera celui indiqué sur la fiche individuelle de '
        'compensation qui a été remise au Chef de Ménage, soit ${Formatters.gnf(d.summary.total)}. Le $party considère '
        'le montant total de l\'indemnisation comme étant suffisant, satisfaisant et de nature à compenser intégralement '
        'ses pertes du fait du Projet.',
      ),
      _articleTitle('2. MODALITÉS DE PAIEMENT'),
      _paragraph(
        'AMC portera assistance au $party pour l\'ouverture d\'un compte bancaire afin de recevoir les paiements dus par '
        'AMC au titre de l\'indemnisation financière.',
      ),
      _paragraph(
        'En cas de retard toutefois dans l\'ouverture de ce compte bancaire, le paiement de l\'indemnisation financière '
        'pourra s\'effectuer selon les modalités suivantes :',
      ),
      _paragraph(
        '- Tous les montants seront réglés par chèque, établi en francs guinéens à l\'ordre de la PAP.',
      ),
      _paragraph(
        'Dans tous les cas, les paiements seront effectués dans un délai maximal de vingt (20) jours après la signature '
        'du présent Accord.',
      ),
      _paragraph(
        'Le paiement, selon les modalités prévues ici, des sommes indiquées ci-dessus libère AMC de toute obligation au '
        'titre du paiement de l\'indemnisation.',
      ),
      _paragraph(
        'Pour faire valoir ses droits et être payé, le $party devra obligatoirement se munir de l\'Annexe 1 (montant et '
        'désignation du bénéficiaire) signée et validée par toutes les parties lors des inventaires des biens et de la '
        'carte d\'identité nationale à son nom renseignée sur l\'accord de compensation.',
      ),
    ];
  }
}

/// A sub-column within a grouped ANNEXE 1 header column (e.g. "Nombre",
/// "Prix unitaire (GNF)", "Montant (GNF)" inside the "Plantules" group).
class _AnnexSubCol {
  final String label;
  final int flex;
  const _AnnexSubCol(this.label, this.flex);
}

/// A top-level ANNEXE 1 header column: either "solo" (single leaf column,
/// [subCols] is null, [flex] is used directly) or "grouped" (a label
/// spanning several leaf [subCols]).
class _AnnexCol {
  final String label;
  final int flex;
  final List<_AnnexSubCol>? subCols;
  const _AnnexCol._(this.label, this.flex, this.subCols);

  factory _AnnexCol.solo(String label, int flex) =>
      _AnnexCol._(label, flex, null);

  factory _AnnexCol.group(String label, List<_AnnexSubCol> subCols) =>
      _AnnexCol._(label, 0, subCols);
}
