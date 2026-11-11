import '../services/firestore_commun.dart';

/// M4 - Un choix possible dans un sondage.
class OptionSondage {
  final String texte;
  final int votes;

  const OptionSondage({required this.texte, this.votes = 0});
}

/// M4 - Un sondage entre voisins (ex : choisir la date de la fête).
///
/// Firestore : quartiers/{quartierId}/sondages/{id}. Seuls les TEXTES des
/// options sont stockés : les votes sont des documents votes/{uid}, comptés
/// avec count() par le repository (voir docs/schema_firestore.md).
class Sondage {
  final String id;
  final String question;
  final List<OptionSondage> options;
  final DateTime dateFin;
  final String proposeParId; // uid de l'auteur (règles de sécurité)
  final String proposePar; // ex : "Salma G.", vide si inconnu (Firestore : proposeParNom)
  final int nombreMembres; // nombre de membres qui peuvent voter (non stocké)
  final List<DateTime> dates; // sondage de date : une date par choix (sinon vide)
  final String? evenementId; // sondage rattaché à un événement (sinon null)
  final DateTime? dateCreation; // pour le badge « nouveau » (null : ancien sondage)

  const Sondage({
    required this.id,
    required this.question,
    required this.options,
    required this.dateFin,
    this.proposeParId = '',
    this.proposePar = '',
    this.nombreMembres = 0,
    this.dates = const [],
    this.evenementId,
    this.dateCreation,
  });

  /// true si les choix sont des dates (on peut créer l'événement à la date gagnante).
  bool get estSondageDeDate => dates.isNotEmpty && dates.length == options.length;

  /// L'index du choix qui a le plus de votes (null : aucun vote).
  /// Égalité : le premier des choix à égalité.
  int? get indexGagnant {
    int? meilleur;
    for (int i = 0; i < options.length; i++) {
      if (options[i].votes > 0 &&
          (meilleur == null || options[i].votes > options[meilleur].votes)) {
        meilleur = i;
      }
    }
    return meilleur;
  }

  /// Nombre total de votes, utile pour calculer les pourcentages.
  int get totalVotes {
    int total = 0;
    for (final option in options) {
      total += option.votes;
    }
    return total;
  }

  /// true tant qu'on peut encore voter.
  bool get estOuvert => dateFin.isAfter(DateTime.now());

  /// Le document Firestore : seulement les textes des options.
  Map<String, dynamic> toMap() {
    final List<String> textes = [];
    for (final OptionSondage option in options) {
      textes.add(option.texte);
    }
    return {
      'question': question,
      'options': textes,
      'dateFin': dateFin,
      'proposeParId': proposeParId,
      'proposeParNom': proposePar,
      'dates': dates, // DateTime → Timestamp (vide si sondage ordinaire)
      'evenementId': evenementId,
      'dateCreation': dateCreation ?? DateTime.now(), // pour le badge « nouveau »
    };
  }

  /// [votes] : le nombre de votes de chaque option, dans l'ordre (compté à
  /// part par le repository). Absent ou trop court : 0 vote.
  factory Sondage.fromMap(
    String id,
    Map<String, dynamic> map, {
    List<int> votes = const [],
    int nombreMembres = 0,
  }) {
    final List<OptionSondage> options = [];
    final List<dynamic> textes = map['options'] ?? [];
    for (int i = 0; i < textes.length; i++) {
      options.add(
        OptionSondage(
          texte: '${textes[i]}',
          votes: i < votes.length ? votes[i] : 0,
        ),
      );
    }
    final List<DateTime> dates = [];
    for (final Object? valeur in (map['dates'] as List<dynamic>? ?? [])) {
      final DateTime? date = FirestoreCommun.lireDate(valeur);
      if (date != null) {
        dates.add(date);
      }
    }
    return Sondage(
      id: id,
      question: map['question'] ?? '',
      options: options,
      dateFin: FirestoreCommun.lireDate(map['dateFin']) ?? DateTime.now(),
      proposeParId: map['proposeParId'] ?? '',
      proposePar: map['proposeParNom'] ?? '',
      nombreMembres: nombreMembres,
      dates: dates,
      evenementId: map['evenementId'],
      dateCreation: FirestoreCommun.lireDate(map['dateCreation']),
    );
  }
}
