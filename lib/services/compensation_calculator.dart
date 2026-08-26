import 'dart:math' as math;
import '../models/enquete_champ.dart';
import '../models/structure.dart' as es;
import 'reference_data_service.dart';

/// Result of a compensation breakdown for a single PAP (owner), matching
/// the "RÉCAPITULATIF DES COMPENSATIONS" table of the OKAPI/WCAG contracts.
class CompensationSummary {
  double parcelles = 0; // Compensation des parcelles (foncier)
  double champsCulturesAnnuelles =
      0; // Compensation des champs (cultures annuelles)
  double culturesPerennes = 0; // Compensation des cultures pérennes
  double especesSauvages = 0; // Compensation des espèces sauvages
  double boisDoeuvre = 0; // Compensation des bois d'oeuvre
  double ressources = 0; // Compensation des ressources
  double structures = 0; // Compensation des structures

  double get total =>
      parcelles +
      champsCulturesAnnuelles +
      culturesPerennes +
      especesSauvages +
      boisDoeuvre +
      ressources +
      structures;

  // Detail lines for annex generation
  final List<ParcelleDetail> parcelleDetails = [];
  final List<CultureAnnuelleDetail> cultureAnnuelleDetails = [];
  final List<CulturePerenneDetail> culturePerenneDetails = [];
  final List<EspeceSauvageDetail> especeSauvageDetails = [];
  final List<BoisDoeuvreDetail> boisDoeuvreDetails = [];
  final List<StructureDetail> structureDetails = [];
}

class CultureAnnuelleDetail {
  final String culture;
  final double superficieHa;
  final double revenuHa;
  final double montant;
  CultureAnnuelleDetail({
    required this.culture,
    required this.superficieHa,
    required this.revenuHa,
    required this.montant,
  });
}

class ParcelleDetail {
  final String typeDeTerrain;
  final double superficie;
  final double coutM2;
  final double montant;
  ParcelleDetail(
    this.typeDeTerrain,
    this.superficie,
    this.coutM2,
    this.montant,
  );
}

class CulturePerenneDetail {
  final String espece;
  final int plantules;
  final int jeunesNp;
  final int jeunesP;
  final int matures;
  final int adulteDeclinant;
  final double prixPlante,
      prixJeuneNp,
      prixJeuneP,
      prixAdulte,
      prixAdulteDeclinant;
  final double montant;
  CulturePerenneDetail({
    required this.espece,
    required this.plantules,
    required this.jeunesNp,
    required this.jeunesP,
    required this.matures,
    required this.adulteDeclinant,
    required this.prixPlante,
    required this.prixJeuneNp,
    required this.prixJeuneP,
    required this.prixAdulte,
    required this.prixAdulteDeclinant,
    required this.montant,
  });
}

class EspeceSauvageDetail {
  final String espece;
  final int jeunesNp;
  final int jeunesP;
  final double prixNp, prixP;
  final double montant;
  EspeceSauvageDetail({
    required this.espece,
    required this.jeunesNp,
    required this.jeunesP,
    required this.prixNp,
    required this.prixP,
    required this.montant,
  });
}

class BoisDoeuvreDetail {
  final String espece;
  final double circonference;
  final double hauteur;
  final double volumeUnitaire;
  final int nombrePieds;
  final double volumeTotal;
  final double prixUnitaire;
  final double montant;
  BoisDoeuvreDetail({
    required this.espece,
    required this.circonference,
    required this.hauteur,
    required this.volumeUnitaire,
    required this.nombrePieds,
    required this.volumeTotal,
    required this.prixUnitaire,
    required this.montant,
  });
}

class StructureDetail {
  final String designation;
  final String unite;
  final double quantite;
  final double prixUnitaire;
  final double montant;
  StructureDetail({
    required this.designation,
    required this.unite,
    required this.quantite,
    required this.prixUnitaire,
    required this.montant,
  });
}

/// Computes automatic compensation amounts using the OKAPI/AMC price matrix,
/// mirroring the structure of the official WCAG compensation agreements.
class CompensationCalculator {
  static final _ref = ReferenceDataService.instance;

  /// Compute compensation for one PAP (owner code), aggregating all
  /// [EnqueteChamp] parcelles belonging to that owner + all structures from
  /// [EnqueteStructure] belonging to that owner.
  static CompensationSummary computeForOwner({
    required List<EnqueteChamp> champsEnquetes,
    required List<es.EnqueteStructure> structureEnquetes,
    required String codeProprietaire,
    String project = 'wcag',
  }) {
    final summary = CompensationSummary();

    for (final enquete in champsEnquetes.where(
      (e) => e.codeProprietaire == codeProprietaire,
    )) {
      _accumulateChampsEnquete(summary, enquete, project);
    }

    for (final enquete in structureEnquetes.where(
      (e) => e.proprietaireStructure == codeProprietaire,
    )) {
      _accumulateStructureEnquete(summary, enquete, project);
    }

    return summary;
  }

  /// Aggregates the compensation across ALL recorded champs/structures
  /// surveys (no owner filtering). Used for the dashboard's global
  /// compensation breakdown chart.
  static CompensationSummary computeGlobal({
    required List<EnqueteChamp> champsEnquetes,
    required List<es.EnqueteStructure> structureEnquetes,
    String project = 'wcag',
  }) {
    final summary = CompensationSummary();
    for (final enquete in champsEnquetes) {
      _accumulateChampsEnquete(summary, enquete, project);
    }
    for (final enquete in structureEnquetes) {
      _accumulateStructureEnquete(summary, enquete, project);
    }
    return summary;
  }

  static void _accumulateChampsEnquete(
    CompensationSummary summary,
    EnqueteChamp enquete,
    String project,
  ) {
    for (final parcelle in enquete.parcelles) {
      // ---- Foncier (parcelle) ----
      final terrain = _ref.terrainByType(
        parcelle.typeDeTerrain,
        project: project,
      );
      final coutM2 = (terrain?['prix_compensation'] as num?)?.toDouble() ?? 0;
      final montantParcelle = coutM2 * parcelle.superficieParcelle;
      summary.parcelles += montantParcelle;
      if (parcelle.superficieParcelle > 0) {
        summary.parcelleDetails.add(
          ParcelleDetail(
            parcelle.typeDeTerrain,
            parcelle.superficieParcelle,
            coutM2,
            montantParcelle,
          ),
        );
      }

      // ---- Cultures annuelles (champs) ----
      for (final champ in parcelle.champs) {
        final culture = _ref
            .culturesAnnuelles(project: project)
            .firstWhereOrNull((c) => c['culture'] == champ.culture);
        if (culture != null) {
          final revenuHa =
              (culture['revenu_annuel_ha'] as num?)?.toDouble() ?? 0;
          // superficie is entered in hectares to match the price matrix (GNF/ha)
          final montant = revenuHa * champ.superficieChamps;
          summary.champsCulturesAnnuelles += montant;
          if (montant > 0) {
            summary.cultureAnnuelleDetails.add(
              CultureAnnuelleDetail(
                culture: champ.culture,
                superficieHa: champ.superficieChamps,
                revenuHa: revenuHa,
                montant: montant,
              ),
            );
          }
        }
      }

      // ---- Arbres (cultures pérennes / espèces sauvages / bois d'oeuvre) ----
      for (final arbre in parcelle.arbres) {
        switch (arbre.typeArbre) {
          case 'cultures_perennes':
            _accumulateCulturePerenne(
              summary,
              arbre.especeArbre,
              arbre,
              project,
            );
            break;
          case 'especes_sauvages':
            _accumulateEspeceSauvage(
              summary,
              arbre.especeArbre,
              arbre,
              project,
            );
            break;
          case 'bois_doeuvre':
            _accumulateBoisDoeuvre(summary, arbre.especeArbre, arbre, project);
            break;
        }
      }
    }
    // Ressources naturelles: no unit price is defined in the OKAPI/AMC price
    // matrix for these items (matches official contracts which show 0 GNF).
  }

  static void _accumulateCulturePerenne(
    CompensationSummary summary,
    String espece,
    dynamic arbre,
    String project,
  ) {
    final data = _ref.culturePerenneByName(espece, project: project);
    if (data == null) return;
    final prixPlante = (data['prix_plante'] as num?)?.toDouble() ?? 0;
    final prixJeuneNp = (data['prix_jeune_non_prod'] as num?)?.toDouble() ?? 0;
    final prixJeuneP = (data['prix_jeune_prod'] as num?)?.toDouble() ?? 0;
    final prixAdulte = (data['prix_adulte'] as num?)?.toDouble() ?? 0;
    final prixAdulteDecl =
        (data['prix_adulte_declinant'] as num?)?.toDouble() ?? 0;

    final plantules = (arbre.nombrePlante as int?) ?? 0;
    final jeunesNp = (arbre.nombreJeuneNp as int?) ?? 0;
    final jeunesP = (arbre.nombreJeuneP as int?) ?? 0;
    final matures = (arbre.nombreMature as int?) ?? 0;
    final adulteDecl = (arbre.nombreAdulteDeclinant as int?) ?? 0;

    final montant =
        plantules * prixPlante +
        jeunesNp * prixJeuneNp +
        jeunesP * prixJeuneP +
        matures * prixAdulte +
        adulteDecl * prixAdulteDecl;

    summary.culturesPerennes += montant;
    if (montant > 0) {
      summary.culturePerenneDetails.add(
        CulturePerenneDetail(
          espece: espece,
          plantules: plantules,
          jeunesNp: jeunesNp,
          jeunesP: jeunesP,
          matures: matures,
          adulteDeclinant: adulteDecl,
          prixPlante: prixPlante,
          prixJeuneNp: prixJeuneNp,
          prixJeuneP: prixJeuneP,
          prixAdulte: prixAdulte,
          prixAdulteDeclinant: prixAdulteDecl,
          montant: montant,
        ),
      );
    }
  }

  static void _accumulateEspeceSauvage(
    CompensationSummary summary,
    String espece,
    dynamic arbre,
    String project,
  ) {
    final data = _ref.especeSauvageByName(espece, project: project);
    if (data == null) return;
    final prixNp =
        (data['indemnisation_plant_non_productif'] as num?)?.toDouble() ?? 0;
    final prixP =
        (data['revenu_brut_annuel_plant_productif'] as num?)?.toDouble() ?? 0;

    final jeunesNp = (arbre.nombreJeuneNp as int?) ?? 0;
    final jeunesP = (arbre.nombreJeuneP as int?) ?? 0;

    final montant = jeunesNp * prixNp + jeunesP * prixP;
    summary.especesSauvages += montant;
    if (montant > 0) {
      summary.especeSauvageDetails.add(
        EspeceSauvageDetail(
          espece: espece,
          jeunesNp: jeunesNp,
          jeunesP: jeunesP,
          prixNp: prixNp,
          prixP: prixP,
          montant: montant,
        ),
      );
    }
  }

  static void _accumulateBoisDoeuvre(
    CompensationSummary summary,
    String espece,
    dynamic arbre,
    String project,
  ) {
    final data = _ref.boisDoeuvreByName(espece, project: project);
    if (data == null) return;
    final valeurM3 = (data['valeur_bois_m3'] as num?)?.toDouble() ?? 0;

    final hauteur = (arbre.hauteur as double?) ?? 0;
    final circonference = (arbre.circonference as double?) ?? 0;
    final nombrePieds = (arbre.nombreDePieds as int?) ?? 0;

    if (hauteur <= 0 || circonference <= 0 || nombrePieds <= 0) return;

    // Volume unitaire (m3) = (PI/4) * (circonference/PI)^2 * hauteur
    final rayonEquivalent = circonference / math.pi;
    final volumeUnitaire =
        (math.pi / 4) * (rayonEquivalent * rayonEquivalent) * hauteur;
    final volumeTotal = volumeUnitaire * nombrePieds;
    final montant = volumeTotal * valeurM3;

    summary.boisDoeuvre += montant;
    summary.boisDoeuvreDetails.add(
      BoisDoeuvreDetail(
        espece: espece,
        circonference: circonference,
        hauteur: hauteur,
        volumeUnitaire: volumeUnitaire,
        nombrePieds: nombrePieds,
        volumeTotal: volumeTotal,
        prixUnitaire: valeurM3,
        montant: montant,
      ),
    );
  }

  /// Mapping from the `type_structure` XLSForm choice name to the matching
  /// row designation in the "Structures" price matrix sheet + the unit of
  /// measurement used to interpret the survey's dimension fields.
  static const Map<String, _AutreStructureMapping> _autresStructuresMap = {
    'Douche Moderne (Piece)': _AutreStructureMapping(
      'Douche moderne',
      _Qty.piece,
    ),
    'WC traditionnel': _AutreStructureMapping('WC traditionnel', _Qty.piece),
    'WC modeme': _AutreStructureMapping('WC moderne (avec ciment)', _Qty.piece),
    'Fosse septique étayée mètre cube': _AutreStructureMapping(
      'Fosse septique étayée',
      _Qty.sol,
    ),
    'Dalle de fosse en béton armé (avec ou sans trappe métallique m2)':
        _AutreStructureMapping(
          'Dalle de fosse en béton armé (avec ou sans trappe métallique)',
          _Qty.sol,
        ),
    'Puits traditionnel étayé mètre linéaire': _AutreStructureMapping(
      'Puits traditionnel / Fosse septique étayée',
      _Qty.longueur,
    ),
    'Puits moderne busé avec pompe manuelle pièce': _AutreStructureMapping(
      'Puits moderne busé avec pompe manuelle',
      _Qty.piece,
    ),
    'Abris pour animaux en tôles et planches m2': _AutreStructureMapping(
      'Abris pour animaux en tôles et planches',
      _Qty.sol,
    ),
    'Poulailler en brique creuse et toles piece': _AutreStructureMapping(
      'Poulailler en briques creuses et toles',
      _Qty.piece,
    ),
    'Hutte temporaire - abris dans les champs paille et bois':
        _AutreStructureMapping(
          'Hutte temporaire - abris dans les champs paille et bois',
          _Qty.piece,
        ),
  };

  static void _accumulateStructureEnquete(
    CompensationSummary summary,
    es.EnqueteStructure enquete,
    String project,
  ) {
    for (final s in enquete.structures) {
      if (s.usesMateriauxForProject(project)) {
        _accumulateHabitation(summary, s, project);
      } else if (project == 'simandou') {
        _accumulateAutreStructureSimandou(summary, s);
      } else {
        final mapping = _autresStructuresMap[s.typeDeStructure];
        if (mapping == null) continue;
        final priceRow = _ref.structureByDesignation(
          mapping.designation,
          project: project,
        );
        if (priceRow == null) continue;
        final prixUnitaire =
            (priceRow['prix_unitaire'] as num?)?.toDouble() ?? 0;
        double quantite;
        switch (mapping.qty) {
          case _Qty.piece:
            quantite = 1;
            break;
          case _Qty.sol:
            quantite = s.superficieSol;
            break;
          case _Qty.longueur:
            quantite = s.longueurProfondeur;
            break;
        }
        final montant = prixUnitaire * quantite;
        summary.structures += montant;
        if (montant > 0) {
          summary.structureDetails.add(
            StructureDetail(
              designation: mapping.designation,
              unite: (priceRow['unite'] as String?) ?? '',
              quantite: quantite,
              prixUnitaire: prixUnitaire,
              montant: montant,
            ),
          );
        }
      }
    }
  }

  /// SIMANDOU-specific "autres structures" (non-Batiment/Case) computation.
  /// Unlike WCAG, the SIMANDOU XLSForm's `type_structure` choice names match
  /// the price matrix's "Annexe" row designations 1:1 (see
  /// lib/data/price_matrix_simandou.json), so no hardcoded name-mapping
  /// table is needed - the quantity base (superficie/longueur/nombre) is
  /// read directly from each row's `_base` field.
  static void _accumulateAutreStructureSimandou(
    CompensationSummary summary,
    es.StructureItem s,
  ) {
    final designation = s.typeDeStructure;
    if (designation.isEmpty) return;
    final priceRow = _ref.structureByDesignation(
      designation,
      project: 'simandou',
    );
    if (priceRow == null) return;
    final prixUnitaire = (priceRow['prix_unitaire'] as num?)?.toDouble() ?? 0;
    final base = (priceRow['_base'] as String?) ?? 'superficie';
    double quantite;
    switch (base) {
      case 'longueur':
        quantite = s.longueurProfondeur;
        break;
      case 'nombre':
        quantite = 1;
        break;
      case 'superficie':
      default:
        quantite = s.superficieSol;
        break;
    }
    final montant = prixUnitaire * quantite;
    summary.structures += montant;
    if (montant > 0) {
      summary.structureDetails.add(
        StructureDetail(
          designation: designation,
          unite: (priceRow['unite'] as String?) ?? '',
          quantite: quantite,
          prixUnitaire: prixUnitaire,
          montant: montant,
        ),
      );
    }
  }

  static void _accumulateHabitation(
    CompensationSummary summary,
    es.StructureItem s,
    String project,
  ) {
    double montantTotal = 0;

    void addLine(String? materiauLabel, double superficie) {
      if (materiauLabel == null ||
          materiauLabel.isEmpty ||
          materiauLabel == 'Aucun') {
        return;
      }
      final priceRow = _ref.structureByDesignation(
        materiauLabel,
        project: project,
      );
      if (priceRow == null) return;
      final prixUnitaire = (priceRow['prix_unitaire'] as num?)?.toDouble() ?? 0;
      final montant = prixUnitaire * superficie;
      montantTotal += montant;
      if (montant > 0) {
        summary.structureDetails.add(
          StructureDetail(
            designation: materiauLabel,
            unite: (priceRow['unite'] as String?) ?? 'm²',
            quantite: superficie,
            prixUnitaire: prixUnitaire,
            montant: montant,
          ),
        );
      }
    }

    addLine(s.materiauxToit, s.superficieToit);
    addLine(s.materiauxMur, s.superficieMur);
    addLine(s.materiauxSol, s.superficieSol);
    addLine(s.materiauxCarrelage, s.superficieSol);
    addLine(s.materiauxFermeture, s.superficieOuvertures);
    addLine(s.materiauxPeinture, s.superficieMur);

    summary.structures += montantTotal;
  }
}

enum _Qty { piece, sol, longueur }

class _AutreStructureMapping {
  final String designation;
  final _Qty qty;
  const _AutreStructureMapping(this.designation, this.qty);
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
