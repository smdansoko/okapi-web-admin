/// Champ dans une parcelle agricole (3. Identification des champs)
class ChampAgricole {
  String id;
  int numOrdreChamps;
  String etatChamps; // Cultive / Jachere1 / Jachere2
  String culture;
  String? autreCulture;
  String propUsager; // Oui/Non
  String? menageExploitant;
  String? codeExploitant;
  double superficieChamps;
  String observation;

  /// Code de champ auto-généré: concat(codeParcelle, '-', numOrdreChamps).
  /// Read-only, computed and stored at save time by the UI dialog.
  String codeChamp;

  ChampAgricole({
    required this.id,
    required this.numOrdreChamps,
    this.etatChamps = '',
    this.culture = '',
    this.autreCulture,
    this.propUsager = 'Oui',
    this.menageExploitant,
    this.codeExploitant,
    this.superficieChamps = 0,
    this.observation = '',
    this.codeChamp = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'numOrdreChamps': numOrdreChamps,
    'etatChamps': etatChamps,
    'culture': culture,
    'autreCulture': autreCulture,
    'propUsager': propUsager,
    'menageExploitant': menageExploitant,
    'codeExploitant': codeExploitant,
    'superficieChamps': superficieChamps,
    'observation': observation,
    'codeChamp': codeChamp,
  };

  factory ChampAgricole.fromMap(Map map) => ChampAgricole(
    id: map['id'] as String,
    numOrdreChamps: map['numOrdreChamps'] as int? ?? 1,
    etatChamps: map['etatChamps'] as String? ?? '',
    culture: map['culture'] as String? ?? '',
    autreCulture: map['autreCulture'] as String?,
    propUsager: map['propUsager'] as String? ?? 'Oui',
    menageExploitant: map['menageExploitant'] as String?,
    codeExploitant: map['codeExploitant'] as String?,
    superficieChamps: (map['superficieChamps'] as num?)?.toDouble() ?? 0,
    observation: map['observation'] as String? ?? '',
    codeChamp: map['codeChamp'] as String? ?? '',
  );
}

/// Arbre dans une parcelle agricole (4. Liste des arbres)
class ArbreParcelle {
  String id;
  String typeArbre; // cultures_perennes / bois_doeuvre / especes_sauvages
  String especeArbre;
  String? autreTypeArbre;
  int? nombreDePieds; // bois d'oeuvre
  int? nombrePlante; // cultures perennes: plantules
  int? nombreJeuneNp; // jeunes non productifs
  int? nombreJeuneP; // jeunes productifs
  int? nombreMature; // adulte
  int? nombreAdulteDeclinant;
  double? hauteur; // bois d'oeuvre
  double? circonference; // bois d'oeuvre
  String propPropArbre; // Oui/Non
  String? menageProArbre;
  String? idPropArbre;
  String observation;

  ArbreParcelle({
    required this.id,
    this.typeArbre = '',
    this.especeArbre = '',
    this.autreTypeArbre,
    this.nombreDePieds,
    this.nombrePlante,
    this.nombreJeuneNp,
    this.nombreJeuneP,
    this.nombreMature,
    this.nombreAdulteDeclinant,
    this.hauteur,
    this.circonference,
    this.propPropArbre = 'Oui',
    this.menageProArbre,
    this.idPropArbre,
    this.observation = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'typeArbre': typeArbre,
    'especeArbre': especeArbre,
    'autreTypeArbre': autreTypeArbre,
    'nombreDePieds': nombreDePieds,
    'nombrePlante': nombrePlante,
    'nombreJeuneNp': nombreJeuneNp,
    'nombreJeuneP': nombreJeuneP,
    'nombreMature': nombreMature,
    'nombreAdulteDeclinant': nombreAdulteDeclinant,
    'hauteur': hauteur,
    'circonference': circonference,
    'propPropArbre': propPropArbre,
    'menageProArbre': menageProArbre,
    'idPropArbre': idPropArbre,
    'observation': observation,
  };

  factory ArbreParcelle.fromMap(Map map) => ArbreParcelle(
    id: map['id'] as String,
    typeArbre: map['typeArbre'] as String? ?? '',
    especeArbre: map['especeArbre'] as String? ?? '',
    autreTypeArbre: map['autreTypeArbre'] as String?,
    nombreDePieds: map['nombreDePieds'] as int?,
    nombrePlante: map['nombrePlante'] as int?,
    nombreJeuneNp: map['nombreJeuneNp'] as int?,
    nombreJeuneP: map['nombreJeuneP'] as int?,
    nombreMature: map['nombreMature'] as int?,
    nombreAdulteDeclinant: map['nombreAdulteDeclinant'] as int?,
    hauteur: (map['hauteur'] as num?)?.toDouble(),
    circonference: (map['circonference'] as num?)?.toDouble(),
    propPropArbre: map['propPropArbre'] as String? ?? 'Oui',
    menageProArbre: map['menageProArbre'] as String?,
    idPropArbre: map['idPropArbre'] as String?,
    observation: map['observation'] as String? ?? '',
  );
}

/// Ressource naturelle (5. Liste des ressources naturelles)
class RessourceNaturelle {
  String id;
  String typeRessource; // Aucun / cueillette / chasse / peche
  String? ressource;
  String? autreRessource;
  String? uniteMesure;
  int? quantite;
  String observation;

  RessourceNaturelle({
    required this.id,
    this.typeRessource = '',
    this.ressource,
    this.autreRessource,
    this.uniteMesure,
    this.quantite,
    this.observation = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'typeRessource': typeRessource,
    'ressource': ressource,
    'autreRessource': autreRessource,
    'uniteMesure': uniteMesure,
    'quantite': quantite,
    'observation': observation,
  };

  factory RessourceNaturelle.fromMap(Map map) => RessourceNaturelle(
    id: map['id'] as String,
    typeRessource: map['typeRessource'] as String? ?? '',
    ressource: map['ressource'] as String?,
    autreRessource: map['autreRessource'] as String?,
    uniteMesure: map['uniteMesure'] as String?,
    quantite: map['quantite'] as int?,
    observation: map['observation'] as String? ?? '',
  );
}

/// Parcelle agricole (2. Identification des parcelles agricoles)
class ParcelleAgricole {
  String id;
  int numOrdreParcelle;
  String typeDeTerrain;
  double superficieParcelle;
  List<ChampAgricole> champs;
  String arbreDansParcelle; // Oui/Non
  List<ArbreParcelle> arbres;

  /// Code de parcelle auto-généré: concat(codeEnquete, '-', numOrdreParcelle).
  /// Read-only, computed and stored at save time by the UI dialog.
  String codeParcelle;

  ParcelleAgricole({
    required this.id,
    required this.numOrdreParcelle,
    this.typeDeTerrain = '',
    this.superficieParcelle = 0,
    List<ChampAgricole>? champs,
    this.arbreDansParcelle = 'Non',
    List<ArbreParcelle>? arbres,
    this.codeParcelle = '',
  }) : champs = champs ?? [],
       arbres = arbres ?? [];

  Map<String, dynamic> toMap() => {
    'id': id,
    'numOrdreParcelle': numOrdreParcelle,
    'typeDeTerrain': typeDeTerrain,
    'superficieParcelle': superficieParcelle,
    'champs': champs.map((e) => e.toMap()).toList(),
    'arbreDansParcelle': arbreDansParcelle,
    'arbres': arbres.map((e) => e.toMap()).toList(),
    'codeParcelle': codeParcelle,
  };

  factory ParcelleAgricole.fromMap(Map map) => ParcelleAgricole(
    id: map['id'] as String,
    numOrdreParcelle: map['numOrdreParcelle'] as int? ?? 1,
    typeDeTerrain: map['typeDeTerrain'] as String? ?? '',
    superficieParcelle: (map['superficieParcelle'] as num?)?.toDouble() ?? 0,
    champs: (map['champs'] as List? ?? [])
        .map((e) => ChampAgricole.fromMap(e as Map))
        .toList(),
    arbreDansParcelle: map['arbreDansParcelle'] as String? ?? 'Non',
    arbres: (map['arbres'] as List? ?? [])
        .map((e) => ArbreParcelle.fromMap(e as Map))
        .toList(),
    codeParcelle: map['codeParcelle'] as String? ?? '',
  );
}
