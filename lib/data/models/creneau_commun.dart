import '../services/firestore_commun.dart';

/// M2 - Un créneau d'un service commun (ex : "Sortie des poubelles", lundi 20:00).
///
/// Firestore : quartiers/{q}/creneaux/{id} (voir docs/schema_firestore.md).
class CreneauCommun {
  final String id;
  final String serviceId; // id du service commun auquel il appartient
  final String titre; // ex : "Sortie des poubelles"
  final DateTime date; // le jour du créneau (l'heure est dans heureDebut)
  final String heureDebut; // ex : "20:00"
  final String heureFin; // ex : "20:30"
  final String? inscritId; // uid du voisin inscrit, null = créneau libre
  final String? inscritNom; // nom court du voisin inscrit
  final bool rappelVeille; // true = "me rappeler la veille" (sans vraie notification)

  const CreneauCommun({
    required this.id,
    required this.serviceId,
    required this.titre,
    required this.date,
    required this.heureDebut,
    required this.heureFin,
    this.inscritId,
    this.inscritNom,
    this.rappelVeille = false,
  });

  /// Le nom de l'inscrit (ancien nom du champ).
  String? get inscrit => inscritNom;

  /// true si personne n'est inscrit.
  bool get estLibre {
    return inscritId == null;
  }

  /// Les champs enregistrés dans Firestore. inscritId et inscritNom sont
  /// TOUJOURS écrits (null si libre) : les règles de sécurité les lisent.
  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'titre': titre,
      'date': date, // DateTime → Timestamp
      'heureDebut': heureDebut,
      'heureFin': heureFin,
      'inscritId': inscritId,
      'inscritNom': inscritNom,
      'rappelVeille': rappelVeille,
    };
  }

  /// Construit un créneau à partir d'un document Firestore.
  factory CreneauCommun.fromMap(String id, Map<String, dynamic> map) {
    return CreneauCommun(
      id: id,
      serviceId: map['serviceId'] ?? '',
      titre: map['titre'] ?? '',
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
      heureDebut: map['heureDebut'] ?? '',
      heureFin: map['heureFin'] ?? '',
      inscritId: map['inscritId'],
      inscritNom: map['inscritNom'],
      rappelVeille: map['rappelVeille'] ?? false,
    );
  }
}
