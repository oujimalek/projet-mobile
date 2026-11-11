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

  const Sondage({
    required this.id,
    required this.question,
    required this.options,
    required this.dateFin,
    this.proposeParId = '',
    this.proposePar = '',
    this.nombreMembres = 0,
  });

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
    return Sondage(
      id: id,
      question: map['question'] ?? '',
      options: options,
      dateFin: FirestoreCommun.lireDate(map['dateFin']) ?? DateTime.now(),
      proposeParId: map['proposeParId'] ?? '',
      proposePar: map['proposeParNom'] ?? '',
      nombreMembres: nombreMembres,
    );
  }
}
