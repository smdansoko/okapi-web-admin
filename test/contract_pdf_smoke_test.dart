import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:okapi_survey/services/contract_pdf_generator.dart';
import 'package:okapi_survey/services/compensation_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generates PDF bytes for all 3 contract types x 3 projects without throwing', () async {
    final outDir = Directory('build/contract_pdf_check');
    outDir.createSync(recursive: true);
    for (final project in ['wcag', 'simandou', 'smb']) {
      for (final type in ContractType.values) {
        final summary = CompensationSummary();
        summary.parcelles = 1000000;
        summary.champsCulturesAnnuelles = 500000;
        // Populate cultureAnnuelleDetails so the Annexe 1 "Cultures
        // annuelles (champs)" table has data to render (regression test for
        // the table that was previously dropped from Annexe 1).
        summary.cultureAnnuelleDetails.add(
          CultureAnnuelleDetail(
            culture: 'Riz',
            superficieHa: 2.0,
            revenuHa: 12830000,
            montant: 25660000,
          ),
        );
        final data = ContractData(
          type: type,
          project: project,
          numeroLot: 'L-001',
          region: 'Boke',
          prefecture: 'Boke',
          sousPrefecture: 'Kamsar',
          district: 'Test',
          village: 'Test Village',
          codeMenage: 'KW4-260618-3',
          codeIndividu: 'KW4-260618-3-6',
          codePap: 'KW4-260618-3-6-1',
          nomPrenom: 'Test Person',
          sexe: 'M',
          dateNaissance: '01/01/1980',
          typeDePiece: 'CNI',
          numeroPiece: '12345',
          dateEtablissementPiece: '01/01/2020',
          telephone: '600000000',
          dateEnquete: DateTime(2025, 11, 21),
          summary: summary,
        );
        final bytes = await ContractPdfGenerator.generate(data);
        expect(bytes.length, greaterThan(1000));
        final f = File('${outDir.path}/${project}_${type.name}.pdf');
        f.writeAsBytesSync(bytes);
        // ignore: avoid_print
        print('$project/$type OK bytes=${bytes.length} -> ${f.path}');
      }
    }
  });
}
