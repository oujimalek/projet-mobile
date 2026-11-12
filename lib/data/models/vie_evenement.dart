import '../services/firestore_commun.dart';

/// M4 - Ce qui vit autour d'un événement : questions, objets à apporter,
/// avis après l'événement. Sous-collections de
/// quartiers/{q}/evenements/{id} (voir firestore.rules, partie M4).

/// Une question ou un commentaire (commentaires/{autoId}).
class Commentaire {
  final String id;
  final String auteurId;
  final String auteurNom;
  final String texte;
  final DateTime date;

  const Commentaire({
    required this.id,
    required this.auteurId,
    required this.auteurNom,
    required this.texte,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'auteurId': auteurId,
      'auteurNom': auteurNom,
      'texte': texte,
      'date': date,
    };
  }

  factory Commentaire.fromMap(String id, Map<String, dynamic> map) {
    return Commentaire(
      id: id,
      auteurId: map['auteurId'] ?? '',
      auteurNom: map['auteurNom'] ?? '',
      texte: map['texte'] ?? '',
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
    );
  }
}

/// Un objet à apporter (aApporter/{autoId}) : "Chaises", "Boissons"...
/// [prisParId] : le voisin qui s'en charge (null : personne encore).
class ObjetAApporter {
  final String id;
  final String objet;
  final String? prisParId;
  final String prisParNom;

  const ObjetAApporter({
    required this.id,
    required this.objet,
    this.prisParId,
    this.prisParNom = '',
  });

  bool get estPris => prisParId != null;

  Map<String, dynamic> toMap() {
    return {
      'objet': objet,
      'prisParId': prisParId, // toujours écrit (testé par les règles)
      'prisParNom': prisParNom,
    };
  }

  factory ObjetAApporter.fromMap(String id, Map<String, dynamic> map) {
    return ObjetAApporter(
      id: id,
      objet: map['objet'] ?? '',
      prisParId: map['prisParId'],
      prisParNom: map['prisParNom'] ?? '',
    );
  }
}

/// L'avis d'un participant après l'événement (avis/{uid}) : 1 à 5 étoiles.
class AvisEvenement {
  final String id; // uid de l'auteur
  final String nom;
  final int note;
  final String commentaire;

  const AvisEvenement({
    required this.id,
    required this.nom,
    required this.note,
    this.commentaire = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'note': note,
      'commentaire': commentaire,
      'date': DateTime.now(),
    };
  }

  factory AvisEvenement.fromMap(String id, Map<String, dynamic> map) {
    return AvisEvenement(
      id: id,
      nom: map['nom'] ?? '',
      note: map['note'] ?? 0,
      commentaire: map['commentaire'] ?? '',
    );
  }
}
