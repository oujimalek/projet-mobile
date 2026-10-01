/// M1 - Un membre du quartier / de la résidence.
class Utilisateur {
  final String id;
  final String prenom;
  final String nom;
  final String email;
  final String telephone;
  final String quartier; // ex : "Cité Ennasr 2"
  final String residence; // ex : "Résidence Yasmine, Bloc B"

  const Utilisateur({
    required this.id,
    required this.prenom,
    required this.nom,
    required this.email,
    required this.telephone,
    required this.quartier,
    required this.residence,
  });

  /// Nom complet, pratique pour l'affichage.
  String get nomComplet {
    return '$prenom $nom';
  }
}
