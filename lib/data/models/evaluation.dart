import '../services/firestore_commun.dart';

/// M2 - L'évaluation d'un service rendu (note de 1 à 5, tags, petit mot).
///
/// Firestore : quartiers/{q}/evaluations/{demandeId} : l'id du document est
/// l'id de la demande, donc une seule évaluation par demande.
class Evaluation {
  final String demandeId; // id de la DemandeService évaluée (= id du document)
  final String serviceId; // id du Service évalué
  final String auteurId; // uid du voisin qui donne la note (le demandeur)
  final String evalueId; // uid du voisin qui a rendu le service
  final String evalueNom; // nom court du voisin évalué
  final int note; // de 1 à 5
  final List<String> tags; // ex : ["Ponctuel", "Sympa"]
  final String? message; // petit mot optionnel
  final DateTime date;

  const Evaluation({
    required this.demandeId,
    required this.serviceId,
    required this.auteurId,
    required this.evalueId,
    required this.evalueNom,
    required this.note,
    this.tags = const [],
    this.message,
    required this.date,
  });

  String get id => demandeId;

  /// Les champs enregistrés dans Firestore (l'id est le nom du document).
  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'serviceId': serviceId,
      'auteurId': auteurId,
      'evalueId': evalueId,
      'evalueNom': evalueNom,
      'note': note,
      'tags': tags,
      'date': date, // DateTime → Timestamp
    };
    if (message != null && message!.isNotEmpty) {
      map['message'] = message;
    }
    return map;
  }

  /// Construit une évaluation à partir d'un document Firestore.
  factory Evaluation.fromMap(String id, Map<String, dynamic> map) {
    return Evaluation(
      demandeId: id,
      serviceId: map['serviceId'] ?? '',
      auteurId: map['auteurId'] ?? '',
      evalueId: map['evalueId'] ?? '',
      evalueNom: map['evalueNom'] ?? '',
      note: map['note'] ?? 0,
      tags: List<String>.from(map['tags'] ?? []),
      message: map['message'],
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
    );
  }
}
