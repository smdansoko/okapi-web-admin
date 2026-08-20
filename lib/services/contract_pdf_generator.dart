import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
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
  }

  static const PdfColor maroon = PdfColor.fromInt(0xFF6B1F1F);
  static const PdfColor darkGreen = PdfColor.fromInt(0xFF1F4A2E);
  static const PdfColor greyLight = PdfColor.fromInt(0xFFEDEDED);
  static const PdfColor greyBorder = PdfColor.fromInt(0xFFBBBBBB);

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
          pw.Row(
            children: [
              pw.Container(
                width: 10,
                height: 26,
                decoration: const pw.BoxDecoration(color: maroon),
              ),
              pw.SizedBox(width: 6),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'OKAPI',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: maroon,
                    ),
                  ),
                  pw.Text(
                    'Environnement Conseil',
                    style: pw.TextStyle(fontSize: 7, color: darkGreen),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'WCAG',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: darkGreen,
                ),
              ),
              pw.Text(
                'Winning Consortium Alumina Guinea',
                style: pw.TextStyle(fontSize: 7, color: maroon),
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
  static pw.MemoryImage? _decodePhoto(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return null;
    try {
      return pw.MemoryImage(base64Decode(base64Data));
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
        'ACCORD DE COMPENSATION CONCLU ENTRE AMC ET ${d.type.titleSuffix}',
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
                _fieldRow('District', d.district),
                _fieldRow('Localité', d.village),
                _fieldRow('Code du ménage', d.codeMenage),
                _fieldRow('Code de l\'individu', d.codeIndividu),
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
    final String repIntro;
    switch (d.type) {
      case ContractType.proprietaire:
        repIntro =
            'Le MÉNAGE AFFECTÉ identifié ci-dessus, valablement représenté à l\'effet des présentes par son Chef, '
            'Monsieur $chefName, agissant d\'un commun accord avec et pour le compte de l\'ensemble des personnes physiques '
            'composant ledit Ménage affecté, ci-après désigné « le Ménage affecté » ;';
        break;
      case ContractType.lignage:
        repIntro =
            'Le LIGNAGE AFFECTÉ identifié ci-dessus, valablement représenté à l\'effet des présentes par son Chef, '
            'Monsieur $chefName, agissant d\'un commun accord avec et pour le compte de l\'ensemble des personnes physiques '
            'composant ledit Lignage affecté, ci-après désigné « le Lignage affecté » ;';
        break;
      case ContractType.communautaire:
        repIntro =
            'La COMMUNAUTÉ AFFECTÉE identifiée ci-dessus, valablement représentée à l\'effet des présentes par son Chef, '
            'Monsieur $chefName, agissant d\'un commun accord avec et pour le compte de l\'ensemble des personnes '
            'composant ladite Communauté affectée, ci-après désignée « la Communauté affectée » ;';
        break;
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _paragraph('ENTRE LES SOUSSIGNÉS :'),
        _paragraph(
          'LA SOCIÉTÉ Winning Consortium Alumina Guinea (WCAG), société de droit guinéen immatriculée au Registre du '
          'Commerce et du Crédit Mobilier, ayant son siège social en République de Guinée, valablement représentée par '
          'son Directeur Général, Monsieur WU QIONG, agissant tant en son nom personnel qu\'au nom et pour le compte de '
          'sa filiale Alumina Minérale Compagnie (AMC), ci-après désignée « AMC » ou « la Société » ;',
        ),
        _paragraph('ET :'),
        _paragraph(repIntro),
      ],
    );
  }

  // ---------------- Page 2: preamble continued + Article 1 ----------------

  static List<pw.Widget> _page2PreambleAndArticle1(ContractData d) {
    final party = d.type.partyLabel;
    return [
      _paragraph('IL EST PRÉALABLEMENT EXPOSÉ CE QUI SUIT :'),
      _paragraph(
        '- AMC construit et exploite une raffinerie d\'alumine ainsi que les infrastructures connexes (« le Projet ») '
        'dans la zone couvrant notamment la localité de ${d.village} ;',
      ),
      _paragraph(
        '- Dans ce cadre, un recensement des ménages, biens et actifs affectés par le Projet a été mené à partir du '
        '21/11/2025, incluant celui du $party identifié ci-dessus ;',
      ),
      _paragraph(
        '- De ces études, il ressort que le $party détient des droits dans la zone visée par le Projet, dont le détail '
        'figure en Annexe 1 du présent Accord ;',
      ),
      _paragraph(
        '- Conformément au Plan d\'Action de Réinstallation et de Compensation (PARC) applicable au Projet, ces droits '
        'donnent lieu à une compensation au titre de l\'occupation permanente des terres et des actifs concernés ;',
      ),
      _paragraph(
        '- En application du PARC, une proposition de compensation personnalisée a été développée par WCAG, et '
        'communiquée, présentée et expliquée au $party et aux personnes le composant ;',
      ),
      _paragraph(
        '- Après avoir pris le temps nécessaire à la réflexion et à la consultation de l\'ensemble des personnes le '
        'constituant, le Chef du $party consent librement et en toute connaissance de cause aux termes du présent '
        'Accord.',
      ),
      pw.SizedBox(height: 6),
      _paragraph('IL A ÉTÉ CONVENU ET ARRÊTÉ CE QUI SUIT :', fontSize: 10.5),
      _articleTitle('Article 1 – Principe d\'indemnisation'),
      _paragraph(
        'Les Parties conviennent des termes et conditions de l\'indemnisation, pour la perte des terres et des biens '
        'du $party figurant en Annexe 1 du présent Accord. Le $party considère ces termes et conditions comme étant '
        'pleinement suffisants et satisfaisants, et de nature à compenser intégralement les conséquences de son '
        'déplacement physique et/ou économique du fait du Projet.',
      ),
    ];
  }

  // ---------------- Page 3: Articles 2, 3, 4 ----------------

  static List<pw.Widget> _page3ArticlesRest(ContractData d) {
    final party = d.type.partyLabel;
    return [
      _articleTitle('Article 2 – Principe de non-contestation'),
      _paragraph(
        'Le $party déclare expressément renoncer à réclamer à WCAG, ainsi qu\'à ses sous-traitants intervenant dans le '
        'cadre du Projet, toute indemnisation additionnelle liée à la perte des parcelles listées en Annexe 1 du '
        'présent Accord, ainsi que des actifs (cultures, arbres, structures) qui y sont implantés.',
      ),
      _articleTitle('Article 3 – Dispositions diverses'),
      _paragraph(
        'Le préambule et les annexes du présent Accord en font partie intégrante. Le présent Accord est régi par le '
        'droit guinéen. Tout différend relatif à sa validité, son interprétation ou son exécution sera réglé à '
        'l\'amiable et, à défaut, conformément à la réglementation guinéenne en vigueur.',
      ),
      _articleTitle('Article 4 – Intégrité du consentement du $party'),
      _paragraph(
        'Le représentant des autorités locales présent lors de la signature certifie :',
      ),
      _paragraph(
        '- Que l\'Accord a fait l\'objet d\'une traduction orale en soussou, langue parlée par le $party ;',
      ),
      _paragraph(
        '- Qu\'il a informé tous les membres présents, adultes et capables, du $party de l\'ensemble de leurs droits et '
        'obligations au titre du présent Accord ;',
      ),
      _paragraph(
        '- Que le $party a disposé du temps de réflexion nécessaire avant de donner son consentement final aux termes '
        'du présent Accord.',
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
            decoration: const pw.BoxDecoration(color: maroon),
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
                    color: PdfColors.white,
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
                    color: PdfColors.white,
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
              height: 70,
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
              height: 70,
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
    final String consentText;
    switch (d.type) {
      case ContractType.proprietaire:
        consentText =
            'Je, soussigné, Monsieur $chefName, en ma qualité de ${d.type.chefLabel}, certifie, en plein accord avec '
            'les membres dudit Ménage, donner mon consentement à l\'ensemble des termes et conditions du présent Accord '
            'qui m\'ont été traduits oralement du français en sousou, et ce, en présence d\'un représentant des autorités '
            'locales dont la fonction est ............................................................................';
        break;
      case ContractType.lignage:
        consentText =
            'Je, soussigné, Monsieur $chefName, en ma qualité de ${d.type.chefLabel}, certifie, en plein accord avec '
            'les membres dudit Lignage, donner mon consentement à l\'ensemble des termes et conditions du présent Accord '
            'qui m\'ont été traduits oralement du français en sousou, et ce, en présence d\'un représentant des autorités '
            'locales dont la fonction est ............................................................................';
        break;
      case ContractType.communautaire:
        consentText =
            'Je, soussigné, $chefName, en ma qualité de ${d.type.chefLabel}, certifie, en plein accord avec les membres '
            'de ladite Communauté, donner mon consentement à l\'ensemble des termes et conditions du présent Accord qui '
            'm\'ont été traduits oralement du français en sousou, et ce, en présence d\'un représentant des autorités '
            'locales dont la fonction est ............................................................................';
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
              d.type == ContractType.proprietaire
                  ? 'Le Ménage affecté'
                  : d.type.titleSuffix,
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
                    'AMC',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  signatureLine('Nom'),
                  signatureLine('Fonction'),
                  signatureLine('Signature'),
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
                    'Autorités',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  signatureLine('Nom'),
                  signatureLine('Institution/Fonction'),
                  signatureLine('Signature'),
                  signatureLine('Nom'),
                  signatureLine('Institution/Fonction'),
                ],
              ),
            ),
          ),
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

    // -------- Cultures annuelles (champs) --------
    widgets.add(pw.SizedBox(height: 10));
    widgets.add(_annexSubtitle('CULTURES ANNUELLES (CHAMPS)'));
    if (s.cultureAnnuelleDetails.isEmpty) {
      widgets.add(_emptyAnnexNote());
    } else {
      double totalSup = 0, totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Culture',
          'Superficie (ha)',
          'Revenu/ha (GNF)',
          'Montant (GNF)',
        ]),
      ];
      for (final c in s.cultureAnnuelleDetails) {
        totalSup += c.superficieHa;
        totalMontant += c.montant;
        rows.add(
          _annexDataRow([
            c.culture,
            c.superficieHa.toStringAsFixed(2),
            Formatters.number(c.revenuHa),
            Formatters.number(c.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow([
          'TOTAL',
          totalSup.toStringAsFixed(2),
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

    // -------- Bois d'œuvre --------
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
          'Volume\ntotal (m³)',
          'Prix\nunitaire',
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
            b.volumeUnitaire.toStringAsFixed(2),
            b.nombrePieds.toString(),
            b.volumeTotal.toStringAsFixed(2),
            Formatters.number(b.prixUnitaire),
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

    // -------- Cultures pérennes --------
    if (s.culturePerenneDetails.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_annexSubtitle('CULTURES PÉRENNES'));
      double totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Type d\'arbre',
          'Plantules',
          'Jeunes NP',
          'Jeunes P',
          'Matures',
          'Adulte décl.',
          'Montant (GNF)',
        ]),
      ];
      for (final c in s.culturePerenneDetails) {
        totalMontant += c.montant;
        rows.add(
          _annexDataRow([
            c.espece,
            c.plantules.toString(),
            c.jeunesNp.toString(),
            c.jeunesP.toString(),
            c.matures.toString(),
            c.adulteDeclinant.toString(),
            Formatters.number(c.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow([
          'TOTAUX',
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
      widgets.add(pw.SizedBox(height: 10));
    }

    // -------- Espèces sauvages --------
    if (s.especeSauvageDetails.isNotEmpty) {
      widgets.add(_annexSubtitle('ESPÈCES SAUVAGES'));
      double totalMontant = 0;
      final rows = <pw.TableRow>[
        _annexHeaderRow([
          'Type d\'arbre',
          'Prix NP',
          'Nombre NP',
          'Prix P',
          'Nombre P',
          'Montant (GNF)',
        ]),
      ];
      for (final e in s.especeSauvageDetails) {
        totalMontant += e.montant;
        rows.add(
          _annexDataRow([
            e.espece,
            Formatters.number(e.prixNp),
            e.jeunesNp.toString(),
            Formatters.number(e.prixP),
            e.jeunesP.toString(),
            Formatters.number(e.montant),
          ]),
        );
      }
      rows.add(
        _annexTotalRow([
          'TOTAUX',
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

  // ---------------- ANNEXE 2 ----------------

  static List<pw.Widget> _annexe2Text(ContractData d) {
    if (d.type == ContractType.communautaire) {
      return [
        _sectionTitle('ANNEXE 2 : MODALITÉS D\'INDEMNISATION'),
        _articleTitle('1. CONSTITUTION D\'UN BUDGET PROJET'),
        _paragraph(
          'Conformément au PARC, le montant total de l\'indemnisation due à la Communauté Affectée, indiqué en Annexe '
          '1 du présent Accord (soit ${Formatters.gnf(d.summary.total)}), est affecté à la constitution d\'un budget '
          'destiné au financement de projets collectifs au bénéfice de la Communauté Affectée.',
        ),
        _articleTitle('2. IDENTIFICATION DES PROJETS COLLECTIFS'),
        _paragraph(
          'Les projets collectifs financés par ce budget sont co-identifiés par la Communauté Affectée, représentée par '
          'un comité désigné à cet effet, et par AMC. Les catégories de projets éligibles incluent notamment : les '
          'aménagements agricoles collectifs, les puits communautaires, l\'amélioration des marchés, les écoles et '
          'centres de santé, ainsi que les pistes d\'accès.',
        ),
        _articleTitle('3. MISE EN ŒUVRE DES PROJETS'),
        _paragraph(
          'Les projets retenus sont mis en œuvre par des prestataires tiers sélectionnés par appel d\'offres, en '
          'coopération avec le comité communautaire désigné par la Communauté Affectée.',
        ),
        _articleTitle('4. RÉTROCESSION DES PROJETS'),
        _paragraph(
          'À l\'achèvement de chaque projet, celui-ci fait l\'objet d\'une rétrocession formelle à la Communauté '
          'Affectée, matérialisée par un procès-verbal de remise signé par les représentants des deux Parties.',
        ),
        _articleTitle('5. GESTION DES FONDS'),
        _paragraph(
          'Le budget alloué est provisionné dans la comptabilité d\'AMC et décaissé progressivement au fur et à mesure '
          'de l\'avancement des projets. Des points d\'étape financiers sont partagés trimestriellement avec le comité '
          'formé par la Communauté Affectée.',
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
