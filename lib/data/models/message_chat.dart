import '../services/firestore_commun.dart';

/// M2 - Un message du chat entre le demandeur et l'auteur d'un service.
///
/// Firestore : quartiers/{q}/demandes/{demandeId}/messages/{id}.
class MessageChat {
  final String id;
  final String demandeId; // id de la DemandeService concernée (dans le chemin)
  final String auteurId; // uid du voisin qui écrit
  final String auteurNom; // nom court (ex : "Nizar H.")
  final String texte;
  final DateTime date;
  final bool lu; // true une fois lu par son destinataire

  const MessageChat({
    required this.id,
    required this.demandeId,
    required this.auteurId,
    required this.auteurNom,
    required this.texte,
    required this.date,
    this.lu = false,
  });

  /// Le nom de l'auteur (ancien nom du champ).
  String get auteur => auteurNom;

  /// Les champs enregistrés dans Firestore (demandeId est dans le chemin).
  Map<String, dynamic> toMap() {
    return {
      'auteurId': auteurId,
      'auteurNom': auteurNom,
      'texte': texte,
      'date': date, // DateTime → Timestamp
      'lu': lu,
    };
  }

  /// Construit un message à partir d'un document Firestore.
  factory MessageChat.fromMap(
    String id,
    String demandeId,
    Map<String, dynamic> map,
  ) {
    return MessageChat(
      id: id,
      demandeId: demandeId,
      auteurId: map['auteurId'] ?? '',
      auteurNom: map['auteurNom'] ?? '',
      texte: map['texte'] ?? '',
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
      lu: map['lu'] ?? false,
    );
  }
}
