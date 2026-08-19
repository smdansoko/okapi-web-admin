/// Membre du ménage (2. Identification des membres de ménage)
class Individu {
  String id; // = codeMenage-numOrdreIndividu
  int numOrdreIndividu;
  String nomPrenom;
  String sexe; // Masculin / Feminin
  String relationCdm; // Chef de menage / epouse / Fils ou fille / ...
  String typeDePiece; // Pas de document / Carte d'identite nationale / ...
  String numeroPiece;
  String? dateEtablissementPiece; // ISO date string
  String? dateNaissance;
  String telephone;
  String situationMatrimoniale;
  int? nombreFemmes;
  String groupeEthnique;
  String? autreGroupeEthnique;
  String nationalite;
  String? autreNationalite;
  String handicap;
  String? handicapPrecis;

  Individu({
    required this.id,
    required this.numOrdreIndividu,
    this.nomPrenom = '',
    this.sexe = '',
    this.relationCdm = '',
    this.typeDePiece = '',
    this.numeroPiece = '',
    this.dateEtablissementPiece,
    this.dateNaissance,
    this.telephone = '',
    this.situationMatrimoniale = '',
    this.nombreFemmes,
    this.groupeEthnique = '',
    this.autreGroupeEthnique,
    this.nationalite = '',
    this.autreNationalite,
    this.handicap = 'Non',
    this.handicapPrecis,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'numOrdreIndividu': numOrdreIndividu,
    'nomPrenom': nomPrenom,
    'sexe': sexe,
    'relationCdm': relationCdm,
    'typeDePiece': typeDePiece,
    'numeroPiece': numeroPiece,
    'dateEtablissementPiece': dateEtablissementPiece,
    'dateNaissance': dateNaissance,
    'telephone': telephone,
    'situationMatrimoniale': situationMatrimoniale,
    'nombreFemmes': nombreFemmes,
    'groupeEthnique': groupeEthnique,
    'autreGroupeEthnique': autreGroupeEthnique,
    'nationalite': nationalite,
    'autreNationalite': autreNationalite,
    'handicap': handicap,
    'handicapPrecis': handicapPrecis,
  };

  factory Individu.fromMap(Map map) => Individu(
    id: map['id'] as String,
    numOrdreIndividu: map['numOrdreIndividu'] as int? ?? 1,
    nomPrenom: map['nomPrenom'] as String? ?? '',
    sexe: map['sexe'] as String? ?? '',
    relationCdm: map['relationCdm'] as String? ?? '',
    typeDePiece: map['typeDePiece'] as String? ?? '',
    numeroPiece: map['numeroPiece'] as String? ?? '',
    dateEtablissementPiece: map['dateEtablissementPiece'] as String?,
    dateNaissance: map['dateNaissance'] as String?,
    telephone: map['telephone'] as String? ?? '',
    situationMatrimoniale: map['situationMatrimoniale'] as String? ?? '',
    nombreFemmes: map['nombreFemmes'] as int?,
    groupeEthnique: map['groupeEthnique'] as String? ?? '',
    autreGroupeEthnique: map['autreGroupeEthnique'] as String?,
    nationalite: map['nationalite'] as String? ?? '',
    autreNationalite: map['autreNationalite'] as String?,
    handicap: map['handicap'] as String? ?? 'Non',
    handicapPrecis: map['handicapPrecis'] as String?,
  );

  /// Label used in dropdown pickers: "Prénom NOM (numéro pièce) - relation"
  String get displayLabel {
    final piece = numeroPiece.isNotEmpty ? ' ($numeroPiece)' : '';
    return '$nomPrenom$piece - $relationCdm';
  }
}
