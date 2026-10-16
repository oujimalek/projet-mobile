/// M2 - Un message du chat entre le demandeur et l'auteur d'un service.
class MessageChat {
  final String id;
  final String demandeId; // id de la DemandeService concernée
  final String auteur; // nom du voisin qui écrit (ex : "Nizar H.")
  final String texte;
  final DateTime date;
  final bool lu; // true une fois lu par son destinataire

  const MessageChat({
    required this.id,
    required this.demandeId,
    required this.auteur,
    required this.texte,
    required this.date,
    this.lu = false,
  });

  /// Copie du message avec "lu" changé.
  MessageChat copyWith({bool? lu}) {
    return MessageChat(
      id: id,
      demandeId: demandeId,
      auteur: auteur,
      texte: texte,
      date: date,
      lu: lu ?? this.lu,
    );
  }
}
