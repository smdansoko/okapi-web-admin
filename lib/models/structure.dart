/// Structure item (2. Identification des structures du ménage)
class StructureItem {
  String id;
  int numOrdreStructure;
  String typeDeStructure;
  String? autreStructure;
  double? latitude;
  double? longitude;
  String structureChamps; // Oui/Non

  // Matériaux (only when case traditionnelle or batiment rectangulaire)
  String? materiauxToit;
  String? materiauxMur;
  String? materiauxSol;
  String? materiauxFermeture;
  String? materiauxPeinture;
  String? materiauxCarrelage;

  // Dimensions
  double superficieSol;
  double superficieMur;
  double superficieToit;
  double superficieOuvertures;
  double longueurProfondeur;
  String etatStructure;

  String notes;

  StructureItem({
    required this.id,
    required this.numOrdreStructure,
    this.typeDeStructure = '',
    this.autreStructure,
    this.latitude,
    this.longitude,
    this.structureChamps = 'Non',
    this.materiauxToit,
    this.materiauxMur,
    this.materiauxSol,
    this.materiauxFermeture,
    this.materiauxPeinture,
    this.materiauxCarrelage,
    this.superficieSol = 0,
    this.superficieMur = 0,
    this.superficieToit = 0,
    this.superficieOuvertures = 0,
    this.longueurProfondeur = 0,
    this.etatStructure = '',
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'numOrdreStructure': numOrdreStructure,
    'typeDeStructure': typeDeStructure,
    'autreStructure': autreStructure,
    'latitude': latitude,
    'longitude': longitude,
    'structureChamps': structureChamps,
    'materiauxToit': materiauxToit,
    'materiauxMur': materiauxMur,
    'materiauxSol': materiauxSol,
    'materiauxFermeture': materiauxFermeture,
    'materiauxPeinture': materiauxPeinture,
    'materiauxCarrelage': materiauxCarrelage,
    'superficieSol': superficieSol,
    'superficieMur': superficieMur,
    'superficieToit': superficieToit,
    'superficieOuvertures': superficieOuvertures,
    'longueurProfondeur': longueurProfondeur,
    'etatStructure': etatStructure,
    'notes': notes,
  };

  factory StructureItem.fromMap(Map map) => StructureItem(
    id: map['id'] as String,
    numOrdreStructure: map['numOrdreStructure'] as int? ?? 1,
    typeDeStructure: map['typeDeStructure'] as String? ?? '',
    autreStructure: map['autreStructure'] as String?,
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    structureChamps: map['structureChamps'] as String? ?? 'Non',
    materiauxToit: map['materiauxToit'] as String?,
    materiauxMur: map['materiauxMur'] as String?,
    materiauxSol: map['materiauxSol'] as String?,
    materiauxFermeture: map['materiauxFermeture'] as String?,
    materiauxPeinture: map['materiauxPeinture'] as String?,
    materiauxCarrelage: map['materiauxCarrelage'] as String?,
    superficieSol: (map['superficieSol'] as num?)?.toDouble() ?? 0,
    superficieMur: (map['superficieMur'] as num?)?.toDouble() ?? 0,
    superficieToit: (map['superficieToit'] as num?)?.toDouble() ?? 0,
    superficieOuvertures:
        (map['superficieOuvertures'] as num?)?.toDouble() ?? 0,
    longueurProfondeur: (map['longueurProfondeur'] as num?)?.toDouble() ?? 0,
    etatStructure: map['etatStructure'] as String? ?? '',
    notes: map['notes'] as String? ?? '',
  );

  /// True if this structure type uses the "matériaux" sub-group per the
  /// original XLSForm relevant expression.
  bool get usesMateriaux =>
      typeDeStructure == 'Habitation et bien immobiliers' ||
      typeDeStructure == 'Case Traditionnelle' ||
      typeDeStructure == 'Batiment rectangulaire';
}

/// Enquête structures (Formulaire 3: WCAG_Enquête_Structures_V1)
class EnqueteStructure {
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

  String codeMenage;
  String proprietaireStructure; // linked individu id
  String proprietaireNom;
  int numEnqueteStructure;

  String repondantCdm;
  String? nomPrenomRepondant;
  String? lienRepondantCdc;
  String? telephoneRepondant;
  String? typeDePieceRepondant;
  String? numeroPieceRepondant;
  String? datePieceRepondant;

  List<StructureItem> structures;
  String typeCompensation;

  DateTime createdAt;
  DateTime updatedAt;

  EnqueteStructure({
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
    this.codeMenage = '',
    this.proprietaireStructure = '',
    this.proprietaireNom = '',
    this.numEnqueteStructure = 1,
    this.repondantCdm = 'Oui',
    this.nomPrenomRepondant,
    this.lienRepondantCdc,
    this.telephoneRepondant,
    this.typeDePieceRepondant,
    this.numeroPieceRepondant,
    this.datePieceRepondant,
    List<StructureItem>? structures,
    this.typeCompensation = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : structures = structures ?? [],
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
    'codeMenage': codeMenage,
    'proprietaireStructure': proprietaireStructure,
    'proprietaireNom': proprietaireNom,
    'numEnqueteStructure': numEnqueteStructure,
    'repondantCdm': repondantCdm,
    'nomPrenomRepondant': nomPrenomRepondant,
    'lienRepondantCdc': lienRepondantCdc,
    'telephoneRepondant': telephoneRepondant,
    'typeDePieceRepondant': typeDePieceRepondant,
    'numeroPieceRepondant': numeroPieceRepondant,
    'datePieceRepondant': datePieceRepondant,
    'structures': structures.map((e) => e.toMap()).toList(),
    'typeCompensation': typeCompensation,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory EnqueteStructure.fromMap(Map map) => EnqueteStructure(
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
    codeMenage: map['codeMenage'] as String? ?? '',
    proprietaireStructure: map['proprietaireStructure'] as String? ?? '',
    proprietaireNom: map['proprietaireNom'] as String? ?? '',
    numEnqueteStructure: map['numEnqueteStructure'] as int? ?? 1,
    repondantCdm: map['repondantCdm'] as String? ?? 'Oui',
    nomPrenomRepondant: map['nomPrenomRepondant'] as String?,
    lienRepondantCdc: map['lienRepondantCdc'] as String?,
    telephoneRepondant: map['telephoneRepondant'] as String?,
    typeDePieceRepondant: map['typeDePieceRepondant'] as String?,
    numeroPieceRepondant: map['numeroPieceRepondant'] as String?,
    datePieceRepondant: map['datePieceRepondant'] as String?,
    structures: (map['structures'] as List? ?? [])
        .map((e) => StructureItem.fromMap(e as Map))
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
