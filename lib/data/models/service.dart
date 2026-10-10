/// M2 - Un service proposé (ou demandé) entre voisins.
class Service {
  final String id;
  final String titre;
  final String description;
  final String categorie; // une valeur de ServiceRepository.getCategories()
  final String auteur; // nom du voisin qui publie
  final bool estOffre; // true = "je propose", false = "je cherche"
  final bool estCommun; // true = service commun hebdomadaire
  final String? jour; // jour du service commun (ex : "Samedi"), sinon null
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
    required this.auteur,
    required this.estOffre,
    this.estCommun = false,
    this.jour,
    this.prix,
    this.bloc = '',
    this.datePublication,
    this.disponibilite,
    this.duree,
    this.recuperation,
  });

  /// Copie du service avec quelques champs changés (les autres sont gardés).
  Service copyWith({
    String? titre,
    String? description,
    String? categorie,
    String? auteur,
    bool? estOffre,
    bool? estCommun,
    String? jour,
    String? prix,
    String? bloc,
    DateTime? datePublication,
    String? disponibilite,
    String? duree,
    String? recuperation,
  }) {
    return Service(
      id: id,
      titre: titre ?? this.titre,
      description: description ?? this.description,
      categorie: categorie ?? this.categorie,
      auteur: auteur ?? this.auteur,
      estOffre: estOffre ?? this.estOffre,
      estCommun: estCommun ?? this.estCommun,
      jour: jour ?? this.jour,
      prix: prix ?? this.prix,
      bloc: bloc ?? this.bloc,
      datePublication: datePublication ?? this.datePublication,
      disponibilite: disponibilite ?? this.disponibilite,
      duree: duree ?? this.duree,
      recuperation: recuperation ?? this.recuperation,
    );
  }
}
