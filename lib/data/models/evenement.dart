/// M4 - Un événement du quartier (fête, réunion, nettoyage...).
class Evenement {
  final String id;
  final String titre;
  final String description;
  final DateTime date;
  final String lieu;
  final String organisateur;
  final int participants;

  const Evenement({
    required this.id,
    required this.titre,
    required this.description,
    required this.date,
    required this.lieu,
    required this.organisateur,
    this.participants = 0,
  });
}
