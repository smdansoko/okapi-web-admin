import 'champ_agricole.dart';

/// Enquête champs (Formulaire 2: WCAG_Enquête_Champs_V1)
class EnqueteChamp {
  String id; // codeEnquete
  DateTime dateEnquete;
  String numBatch;
  String enqueteurs;
  String tablette;

  String region;
  String prefecture;
  String sousPrefecture;
  String district;
  String village;

  String typeDePropriete; // Lignage / Propriétaire / Communautaire
  String codeMenage; // linked household
  String codeProprietaire; // linked individu id
  String proprietaireNom; // cached display label

  int numEnqueteChamp;
  String repondantCdm;
  String? nomPrenomRepondant;
  String? lienRepondantCdc;
  String? telephoneRepondant;
  String? typeDePieceRepondant;
  String? numeroPieceRepondant;
  String? datePieceRepondant;

  List<ParcelleAgricole> parcelles;
  List<RessourceNaturelle> ressources;
  String typeCompensation; // Nature / Espèce

  DateTime createdAt;
  DateTime updatedAt;

  /// Code de l'enquête auto-généré:
  /// concat(codeProprietaire, '-', numEnqueteChamp).
  /// Read-only, always derived — never manually entered.
  String get codeEnquete => codeProprietaire.isEmpty
      ? ''
      : '$codeProprietaire-$numEnqueteChamp';

  EnqueteChamp({
    required this.id,
    required this.dateEnquete,
    this.numBatch = '',
    this.enqueteurs = '',
    this.tablette = '',
    this.region = '',
    this.prefecture = '',
    this.sousPrefecture = '',
    this.district = '',
    this.village = '',
    this.typeDePropriete = '',
    this.codeMenage = '',
    this.codeProprietaire = '',
    this.proprietaireNom = '',
    this.numEnqueteChamp = 1,
    this.repondantCdm = 'Oui',
    this.nomPrenomRepondant,
    this.lienRepondantCdc,
    this.telephoneRepondant,
    this.typeDePieceRepondant,
    this.numeroPieceRepondant,
    this.datePieceRepondant,
    List<ParcelleAgricole>? parcelles,
    List<RessourceNaturelle>? ressources,
    this.typeCompensation = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : parcelles = parcelles ?? [],
       ressources = ressources ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'dateEnquete': dateEnquete.toIso8601String(),
    'numBatch': numBatch,
    'enqueteurs': enqueteurs,
    'tablette': tablette,
    'region': region,
    'prefecture': prefecture,
    'sousPrefecture': sousPrefecture,
    'district': district,
    'village': village,
    'typeDePropriete': typeDePropriete,
    'codeMenage': codeMenage,
    'codeProprietaire': codeProprietaire,
    'proprietaireNom': proprietaireNom,
    'numEnqueteChamp': numEnqueteChamp,
    'repondantCdm': repondantCdm,
    'nomPrenomRepondant': nomPrenomRepondant,
    'lienRepondantCdc': lienRepondantCdc,
    'telephoneRepondant': telephoneRepondant,
    'typeDePieceRepondant': typeDePieceRepondant,
    'numeroPieceRepondant': numeroPieceRepondant,
    'datePieceRepondant': datePieceRepondant,
    'parcelles': parcelles.map((e) => e.toMap()).toList(),
    'ressources': ressources.map((e) => e.toMap()).toList(),
    'typeCompensation': typeCompensation,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory EnqueteChamp.fromMap(Map map) => EnqueteChamp(
    id: map['id'] as String,
    dateEnquete: DateTime.parse(map['dateEnquete'] as String),
    numBatch: map['numBatch'] as String? ?? '',
    enqueteurs: map['enqueteurs'] as String? ?? '',
    tablette: map['tablette'] as String? ?? '',
    region: map['region'] as String? ?? '',
    prefecture: map['prefecture'] as String? ?? '',
    sousPrefecture: map['sousPrefecture'] as String? ?? '',
    district: map['district'] as String? ?? '',
    village: map['village'] as String? ?? '',
    typeDePropriete: map['typeDePropriete'] as String? ?? '',
    codeMenage: map['codeMenage'] as String? ?? '',
    codeProprietaire: map['codeProprietaire'] as String? ?? '',
    proprietaireNom: map['proprietaireNom'] as String? ?? '',
    numEnqueteChamp: map['numEnqueteChamp'] as int? ?? 1,
    repondantCdm: map['repondantCdm'] as String? ?? 'Oui',
    nomPrenomRepondant: map['nomPrenomRepondant'] as String?,
    lienRepondantCdc: map['lienRepondantCdc'] as String?,
    telephoneRepondant: map['telephoneRepondant'] as String?,
    typeDePieceRepondant: map['typeDePieceRepondant'] as String?,
    numeroPieceRepondant: map['numeroPieceRepondant'] as String?,
    datePieceRepondant: map['datePieceRepondant'] as String?,
    parcelles: (map['parcelles'] as List? ?? [])
        .map((e) => ParcelleAgricole.fromMap(e as Map))
        .toList(),
    ressources: (map['ressources'] as List? ?? [])
        .map((e) => RessourceNaturelle.fromMap(e as Map))
        .toList(),
    typeCompensation: map['typeCompensation'] as String? ?? '',
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : DateTime.now(),
    updatedAt: map['updatedAt'] != null
        ? DateTime.parse(map['updatedAt'] as String)
        : DateTime.now(),
  );
}
