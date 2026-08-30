import 'individu.dart';

/// Enquête ménage (Formulaire 1: WCAG_Enquête des ménages)
class Menage {
  String id; // codeMenage - unique key
  // Which OKAPI project (simandou/wcag/smb) this household belongs to.
  // Stamped automatically by AppDataProvider.saveMenage()/mergeFromServer()
  // so the mobile app can strictly isolate each project's household list
  // (a household created/pulled under SIMANDOU must never appear while the
  // WCAG project is active, and vice-versa). Empty for records created
  // before this field existed (legacy local cache) — these are filtered
  // out of every project's list until refreshed via "Actualiser" (pull),
  // since the server-side databases are already correctly split by
  // project (see okapi_web_admin/db.py).
  String project;
  DateTime dateEnquete;
  String enqueteurs;
  String tablette;
  int numOrdreMenage;

  // Localisation
  String region;
  String prefecture;
  String sousPrefecture;
  String district;
  String village;

  String codeMenage; // calculated: village+tablette-yyMMdd-numOrdre
  String residencePrincipale; // Oui/Non
  String statutMenage; // Proprietaire / Locataire payant / Locataire gratuit
  double? latitude;
  double? longitude;
  String repondantCdm; // Oui/Non

  // Représentant (if repondantCdm == Non)
  String? nomPrenomRepondant;
  String? lienRepondantCdc;
  String? telephoneRepondant;
  String? typeDePieceRepondant;
  String? numeroPieceRepondant;
  String? datePieceRepondant;

  List<Individu> individus;

  DateTime createdAt;
  DateTime updatedAt;

  Menage({
    required this.id,
    this.project = '',
    required this.dateEnquete,
    this.enqueteurs = '',
    this.tablette = '',
    this.numOrdreMenage = 1,
    this.region = '',
    this.prefecture = '',
    this.sousPrefecture = '',
    this.district = '',
    this.village = '',
    this.codeMenage = '',
    this.residencePrincipale = 'Oui',
    this.statutMenage = '',
    this.latitude,
    this.longitude,
    this.repondantCdm = 'Oui',
    this.nomPrenomRepondant,
    this.lienRepondantCdc,
    this.telephoneRepondant,
    this.typeDePieceRepondant,
    this.numeroPieceRepondant,
    this.datePieceRepondant,
    List<Individu>? individus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : individus = individus ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Individu? get chefDeMenage {
    try {
      return individus.firstWhere((i) => i.relationCdm == 'Chef de menage');
    } catch (_) {
      return individus.isNotEmpty ? individus.first : null;
    }
  }

  String get nomChefMenage => chefDeMenage?.nomPrenom ?? '';

  Map<String, dynamic> toMap() => {
    'id': id,
    'project': project,
    'dateEnquete': dateEnquete.toIso8601String(),
    'enqueteurs': enqueteurs,
    'tablette': tablette,
    'numOrdreMenage': numOrdreMenage,
    'region': region,
    'prefecture': prefecture,
    'sousPrefecture': sousPrefecture,
    'district': district,
    'village': village,
    'codeMenage': codeMenage,
    'residencePrincipale': residencePrincipale,
    'statutMenage': statutMenage,
    'latitude': latitude,
    'longitude': longitude,
    'repondantCdm': repondantCdm,
    'nomPrenomRepondant': nomPrenomRepondant,
    'lienRepondantCdc': lienRepondantCdc,
    'telephoneRepondant': telephoneRepondant,
    'typeDePieceRepondant': typeDePieceRepondant,
    'numeroPieceRepondant': numeroPieceRepondant,
    'datePieceRepondant': datePieceRepondant,
    'individus': individus.map((e) => e.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Menage.fromMap(Map map) => Menage(
    id: map['id'] as String,
    project: map['project'] as String? ?? '',
    dateEnquete: DateTime.parse(map['dateEnquete'] as String),
    enqueteurs: map['enqueteurs'] as String? ?? '',
    tablette: map['tablette'] as String? ?? '',
    numOrdreMenage: map['numOrdreMenage'] as int? ?? 1,
    region: map['region'] as String? ?? '',
    prefecture: map['prefecture'] as String? ?? '',
    sousPrefecture: map['sousPrefecture'] as String? ?? '',
    district: map['district'] as String? ?? '',
    village: map['village'] as String? ?? '',
    codeMenage: map['codeMenage'] as String? ?? '',
    residencePrincipale: map['residencePrincipale'] as String? ?? 'Oui',
    statutMenage: map['statutMenage'] as String? ?? '',
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    repondantCdm: map['repondantCdm'] as String? ?? 'Oui',
    nomPrenomRepondant: map['nomPrenomRepondant'] as String?,
    lienRepondantCdc: map['lienRepondantCdc'] as String?,
    telephoneRepondant: map['telephoneRepondant'] as String?,
    typeDePieceRepondant: map['typeDePieceRepondant'] as String?,
    numeroPieceRepondant: map['numeroPieceRepondant'] as String?,
    datePieceRepondant: map['datePieceRepondant'] as String?,
    individus: (map['individus'] as List? ?? [])
        .map((e) => Individu.fromMap(e as Map))
        .toList(),
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : DateTime.now(),
    updatedAt: map['updatedAt'] != null
        ? DateTime.parse(map['updatedAt'] as String)
        : DateTime.now(),
  );
}
