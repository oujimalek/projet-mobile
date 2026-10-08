/// M1 - Un quartier (une "houma") que l'on peut rejoindre.
class Quartier {
  final String id;
  final String nom; // ex : "Résidence El Yasmine"
  final String localisation; // ex : "Ennasr 2, Ariana"
  final String codeInvitation; // code à 6 caractères donné par l'admin
  final int nbMembres;

  const Quartier({
    required this.id,
    required this.nom,
    required this.localisation,
    required this.codeInvitation,
    required this.nbMembres,
  });
}
