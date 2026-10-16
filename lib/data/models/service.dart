import '../services/firestore_commun.dart';

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
  });

  /// Le nom de l'auteur (ancien nom du champ, utilisé par l'accueil).
  String get auteur => auteurNom;

  /// Copie du service avec quelques champs changés (les autres sont gardés).
  Service copyWith({
    String? titre,
    String? description,
    String? categorie,
    bool? estOffre,
    String? disponibilite,
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
    );
  }
}
