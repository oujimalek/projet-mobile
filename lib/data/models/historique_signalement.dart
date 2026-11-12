import '../services/firestore_commun.dart';
import 'signalement.dart';

/// M3 - Une étape de l'historique d'un signalement : son statut à ce
/// moment, qui l'a décidé, quand, et une note (optionnelle ; obligatoire
/// pour "refusé").
///
/// Firestore : quartiers/{q}/signalements/{id}/historique/{entreeId}.
/// Une entrée n'est jamais modifiée ni supprimée (règles).
class EntreeHistorique {
  final String id; // id du document (pas écrit dans le document)
  final StatutSignalement statut;
  final String note; // '' = pas de note
  final DateTime date;
  final String parId; // uid de l'auteur (création) ou de l'admin
  final String parNom;

  const EntreeHistorique({
    this.id = '',
    required this.statut,
    this.note = '',
    required this.date,
    required this.parId,
    required this.parNom,
  });

  Map<String, dynamic> toMap() {
    return {
      'statut': statut.name,
      'note': note,
      'date': date, // DateTime → Timestamp (fait par Firestore)
      'parId': parId,
      'parNom': parNom,
    };
  }

  factory EntreeHistorique.fromMap(String id, Map<String, dynamic> map) {
    return EntreeHistorique(
      id: id,
      statut: FirestoreCommun.lireEnum(
        StatutSignalement.values,
        map['statut'],
        StatutSignalement.enAttente,
      ),
      note: map['note'] is String ? map['note'] : '',
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
      parId: map['parId'] is String ? map['parId'] : '',
      parNom: map['parNom'] is String ? map['parNom'] : '',
    );
  }
}
