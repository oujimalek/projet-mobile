/// M1 - Un quartier (une "houma") que l'on peut rejoindre.
///
/// Dans Firestore : document `quartiers/{id}` avec seulement `nom` et
/// `localisation` (voir docs/schema_firestore.md).
class Quartier {
  final String id;
  final String nom; // ex : "Résidence El Yasmine"
  final String localisation; // ex : "Ennasr 2, Ariana"
  // Code à 6 caractères donné par l'admin. Pas stocké dans le quartier :
  // il est dans codesQuartier/{code} (sinon tout le monde pourrait le lire).
  final String codeInvitation;
  // Pas stocké non plus : calculé (count) par un membre actif
  final int nbMembres;

  const Quartier({
    required this.id,
    required this.nom,
    required this.localisation,
    this.codeInvitation = '',
    this.nbMembres = 0,
  });

  /// Les champs enregistrés dans Firestore.
  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'localisation': localisation,
    };
  }

  /// Construit un quartier à partir d'un document Firestore.
  factory Quartier.fromMap(String id, Map<String, dynamic> map) {
    return Quartier(
      id: id,
      nom: map['nom'] ?? '',
      localisation: map['localisation'] ?? '',
    );
  }
}
