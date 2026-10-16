/// M2 - L'évaluation d'un service rendu (note de 1 à 5, tags, petit mot).
class Evaluation {
  final String id;
  final String demandeId; // id de la DemandeService évaluée
  final String serviceId; // id du Service évalué
  final String auteurEvalue; // nom du voisin qui donne la note
  final int note; // de 1 à 5
  final List<String> tags; // ex : ["Ponctuel", "Sympa"]
  final String? message; // petit mot optionnel
  final DateTime date;

  const Evaluation({
    required this.id,
    required this.demandeId,
    required this.serviceId,
    required this.auteurEvalue,
    required this.note,
    this.tags = const [],
    this.message,
    required this.date,
  });
}
