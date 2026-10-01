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
  });
}
