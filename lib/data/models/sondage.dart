/// M4 - Un choix possible dans un sondage.
class OptionSondage {
  final String texte;
  final int votes;

  const OptionSondage({required this.texte, this.votes = 0});
}

/// M4 - Un sondage entre voisins (ex : choisir la date de la fête).
/// Le vote de l'utilisateur sera géré dans l'état (State) de SondageScreen.
class Sondage {
  final String id;
  final String question;
  final List<OptionSondage> options;
  final DateTime dateFin;

  const Sondage({
    required this.id,
    required this.question,
    required this.options,
    required this.dateFin,
  });

  /// Nombre total de votes, utile pour calculer les pourcentages.
  int get totalVotes {
    int total = 0;
    for (final option in options) {
      total += option.votes;
    }
    return total;
  }
}
