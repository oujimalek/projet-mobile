import '../services/firestore_commun.dart';

/// M2 - Le voisin dont c'est le tour dans une rotation (uid + nom court).
class TourRotation {
  final String id;
  final String nom;

  const TourRotation({required this.id, required this.nom});

  Map<String, dynamic> toMap() {
    return {'id': id, 'nom': nom};
  }

  factory TourRotation.fromMap(Map<String, dynamic> map) {
    return TourRotation(
      id: (map['id'] ?? '').toString(),
      nom: (map['nom'] ?? '').toString(),
    );
  }
}

/// M2 - Un créneau marqué « Fait » par l'auteur du service.
class FaitCreneau {
  final DateTime? faitLe; // date et heure du marquage
  final String parId; // uid de la personne de service ('' si personne)
  final String parNom; // son nom ('' si personne)

  const FaitCreneau({this.faitLe, this.parId = '', this.parNom = ''});

  Map<String, dynamic> toMap() {
    return {'faitLe': faitLe, 'parId': parId, 'parNom': parNom};
  }

  factory FaitCreneau.fromMap(Map<String, dynamic> map) {
    return FaitCreneau(
      faitLe: FirestoreCommun.lireDate(map['faitLe']),
      parId: (map['parId'] ?? '').toString(),
      parNom: (map['parNom'] ?? '').toString(),
    );
  }
}

/// Lit une liste de textes dans un document (absente : liste vide).
List<String> _lireListe(Object? valeur) {
  if (valeur is List) {
    return valeur.map((e) => e.toString()).toList();
  }
  return const [];
}

/// Lit une map d'objets (absente : map vide).
Map<String, Map<String, dynamic>> _lireMaps(Object? valeur) {
  final Map<String, Map<String, dynamic>> resultat = {};
  if (valeur is Map) {
    valeur.forEach((cle, contenu) {
      if (contenu is Map) {
        resultat[cle.toString()] = Map<String, dynamic>.from(contenu);
      }
    });
  }
  return resultat;
}

/// M2 - Un service proposé (ou demandé) entre voisins.
///
/// Firestore : quartiers/{q}/services/{id} (voir docs/schema_firestore.md).
class Service {
  final String id;
  final String titre;
  final String description;
  final String categorie; // une valeur de ServiceRepository.categories
  final String auteurId; // uid du voisin qui publie (vide si inconnu)
  final String auteurNom; // nom court recopié pour l'affichage (ex : "Karim M.")
  final bool estOffre; // true = "je propose", false = "je cherche"
  final bool estCommun; // true = service commun hebdomadaire
  final String? jour; // jour du service commun (ex : "Samedi"), sinon null
  final String? heureDebut; // service commun : ex "18:00", sinon null
  final String? heureFin; // service commun : ex "18:30", sinon null
  final String? prix; // ex : "10 DT", null si gratuit
  final String bloc; // bloc de l'auteur (ex : "Bloc A"), vide si inconnu
  final DateTime? datePublication; // date et heure de publication
  final String? disponibilite; // ex : "Ce week-end"
  final String? duree; // ex : "1 journée"
  final String? recuperation; // ex : "Bloc A · Appt 3"

  // ----- Services communs : rotation et créneaux faits (écrits par l'auteur) -----
  final bool modeRotation; // true = rotation automatique, false = inscription libre
  final List<String> participantsIds; // uid des participants, dans l'ordre de passage
  final List<String> participantsNoms; // leurs noms courts, même ordre
  final DateTime? rotationDepuis; // les créneaux à partir de cette date suivent le cycle
  final int rotationIndex; // participant du 1er créneau à partir de rotationDepuis
  final Map<String, TourRotation> toursFiges; // idCréneau -> tour figé (créneau du jour)
  final Map<String, FaitCreneau> creneauxFaits; // idCréneau -> créneau marqué fait

  const Service({
    required this.id,
    required this.titre,
    required this.description,
    required this.categorie,
    required this.auteurNom,
    required this.estOffre,
    this.auteurId = '',
    this.estCommun = false,
    this.jour,
    this.heureDebut,
    this.heureFin,
    this.prix,
    this.bloc = '',
    this.datePublication,
    this.disponibilite,
    this.duree,
    this.recuperation,
    this.modeRotation = false,
    this.participantsIds = const [],
    this.participantsNoms = const [],
    this.rotationDepuis,
    this.rotationIndex = 0,
    this.toursFiges = const {},
    this.creneauxFaits = const {},
  });

  /// Le nom de l'auteur (ancien nom du champ, utilisé par l'accueil).
  String get auteur => auteurNom;

  /// Les participants de la rotation, dans l'ordre de passage.
  List<TourRotation> get participants {
    final List<TourRotation> liste = [];
    for (int i = 0; i < participantsIds.length; i++) {
      liste.add(TourRotation(
        id: participantsIds[i],
        nom: i < participantsNoms.length ? participantsNoms[i] : '',
      ));
    }
    return liste;
  }

  /// Copie du service avec quelques champs changés (les autres sont gardés).
  Service copyWith({
    String? titre,
    String? description,
    String? categorie,
    bool? estOffre,
    String? disponibilite,
    List<String>? participantsIds,
    List<String>? participantsNoms,
    DateTime? rotationDepuis,
    int? rotationIndex,
    Map<String, TourRotation>? toursFiges,
    Map<String, FaitCreneau>? creneauxFaits,
  }) {
    return Service(
      id: id,
      titre: titre ?? this.titre,
      description: description ?? this.description,
      categorie: categorie ?? this.categorie,
      auteurId: auteurId,
      auteurNom: auteurNom,
      estOffre: estOffre ?? this.estOffre,
      estCommun: estCommun,
      jour: jour,
      heureDebut: heureDebut,
      heureFin: heureFin,
      prix: prix,
      bloc: bloc,
      datePublication: datePublication,
      disponibilite: disponibilite ?? this.disponibilite,
      duree: duree,
      recuperation: recuperation,
      modeRotation: modeRotation,
      participantsIds: participantsIds ?? this.participantsIds,
      participantsNoms: participantsNoms ?? this.participantsNoms,
      rotationDepuis: rotationDepuis ?? this.rotationDepuis,
      rotationIndex: rotationIndex ?? this.rotationIndex,
      toursFiges: toursFiges ?? this.toursFiges,
      creneauxFaits: creneauxFaits ?? this.creneauxFaits,
    );
  }

  /// Les champs enregistrés dans Firestore (l'id est le nom du document).
  /// Un champ optionnel vide n'est pas écrit.
  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'titre': titre,
      'description': description,
      'categorie': categorie,
      'auteurId': auteurId,
      'auteurNom': auteurNom,
      'auteurBloc': bloc,
      'estOffre': estOffre,
      'estCommun': estCommun,
      'datePublication': datePublication, // DateTime → Timestamp
    };
    void ajouter(String cle, String? valeur) {
      if (valeur != null && valeur.isNotEmpty) {
        map[cle] = valeur;
      }
    }

    ajouter('jour', jour);
    ajouter('heureDebut', heureDebut);
    ajouter('heureFin', heureFin);
    ajouter('prix', prix);
    ajouter('disponibilite', disponibilite);
    ajouter('duree', duree);
    ajouter('recuperation', recuperation);
    // La rotation n'est écrite que pour un service commun en rotation :
    // les autres documents restent identiques à avant.
    if (estCommun && modeRotation) {
      map['modeRotation'] = true;
      map['participantsIds'] = participantsIds;
      map['participantsNoms'] = participantsNoms;
      map['rotationDepuis'] = rotationDepuis;
      map['rotationIndex'] = rotationIndex;
      map['toursFiges'] = {
        for (final entree in toursFiges.entries) entree.key: entree.value.toMap(),
      };
    }
    return map;
  }

  /// Construit un service à partir d'un document Firestore.
  /// Un champ absent prend une valeur par défaut (pas de plantage).
  factory Service.fromMap(String id, Map<String, dynamic> map) {
    return Service(
      id: id,
      titre: map['titre'] ?? '',
      description: map['description'] ?? '',
      categorie: map['categorie'] ?? '',
      auteurId: map['auteurId'] ?? '',
      auteurNom: map['auteurNom'] ?? '',
      estOffre: map['estOffre'] ?? true,
      estCommun: map['estCommun'] ?? false,
      jour: map['jour'],
      heureDebut: map['heureDebut'],
      heureFin: map['heureFin'],
      prix: map['prix'],
      bloc: map['auteurBloc'] ?? '',
      datePublication: FirestoreCommun.lireDate(map['datePublication']),
      disponibilite: map['disponibilite'],
      duree: map['duree'],
      recuperation: map['recuperation'],
      modeRotation: map['modeRotation'] == true,
      participantsIds: _lireListe(map['participantsIds']),
      participantsNoms: _lireListe(map['participantsNoms']),
      rotationDepuis: FirestoreCommun.lireDate(map['rotationDepuis']),
      rotationIndex: map['rotationIndex'] is num
          ? (map['rotationIndex'] as num).toInt()
          : 0,
      toursFiges: {
        for (final entree in _lireMaps(map['toursFiges']).entries)
          entree.key: TourRotation.fromMap(entree.value),
      },
      creneauxFaits: {
        for (final entree in _lireMaps(map['creneauxFaits']).entries)
          entree.key: FaitCreneau.fromMap(entree.value),
      },
    );
  }
}
