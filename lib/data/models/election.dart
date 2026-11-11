import '../services/firestore_commun.dart';

/// M4 - Où en est une élection des leaders. Calculé à partir des dates
/// (aucun serveur ne tourne en arrière-plan sur le plan gratuit).
enum PhaseElection {
  candidatures, // les membres se portent candidats
  vote, // les membres votent (1 voix, secrète)
  depouillement, // vote fini : l'admin doit publier les résultats
  terminee, // résultats publiés : les élus sont leaders
}

/// M4 - Une élection des leaders du quartier.
///
/// Firestore : quartiers/{quartierId}/elections/{id}, avec les
/// sous-collections candidats/{uid} et votes/{uid} (vote secret : chacun ne
/// lit que le sien). Voir docs/module4_evenements.md.
class Election {
  final String id;
  final int nbPlaces; // nombre de leaders à élire (choisi par l'admin)
  final DateTime debut; // ouverture des candidatures
  final DateTime finCandidatures; // = début du vote
  final DateTime finVote;
  final bool anticipee; // élection de 24 h demandée par les membres
  final bool premiere; // première élection du quartier : tout membre peut se présenter
  final bool publiee; // l'admin a publié les résultats
  final List<String> elusIds;
  final List<String> elusNoms;

  const Election({
    required this.id,
    required this.nbPlaces,
    required this.debut,
    required this.finCandidatures,
    required this.finVote,
    this.anticipee = false,
    this.premiere = false,
    this.publiee = false,
    this.elusIds = const [],
    this.elusNoms = const [],
  });

  /// La phase à l'instant [maintenant] (par défaut : maintenant).
  PhaseElection phase([DateTime? maintenant]) {
    final DateTime instant = maintenant ?? DateTime.now();
    if (publiee) {
      return PhaseElection.terminee;
    }
    if (instant.isBefore(finCandidatures)) {
      return PhaseElection.candidatures;
    }
    if (instant.isBefore(finVote)) {
      return PhaseElection.vote;
    }
    return PhaseElection.depouillement;
  }

  Map<String, dynamic> toMap() {
    return {
      'nbPlaces': nbPlaces,
      'debut': debut,
      'finCandidatures': finCandidatures,
      'finVote': finVote,
      'anticipee': anticipee,
      'premiere': premiere,
      'publiee': publiee,
      'elusIds': elusIds,
      'elusNoms': elusNoms,
    };
  }

  factory Election.fromMap(String id, Map<String, dynamic> map) {
    final DateTime maintenant = DateTime.now();
    return Election(
      id: id,
      nbPlaces: map['nbPlaces'] ?? 1,
      debut: FirestoreCommun.lireDate(map['debut']) ?? maintenant,
      finCandidatures:
          FirestoreCommun.lireDate(map['finCandidatures']) ?? maintenant,
      finVote: FirestoreCommun.lireDate(map['finVote']) ?? maintenant,
      anticipee: map['anticipee'] ?? false,
      premiere: map['premiere'] ?? false,
      publiee: map['publiee'] ?? false,
      elusIds: List<String>.from(map['elusIds'] ?? []),
      elusNoms: List<String>.from(map['elusNoms'] ?? []),
    );
  }
}

/// M4 - Un candidat à une élection. L'id du document est son uid.
/// [nbVoix] est un compteur protégé : +1 seulement avec un vote, dans le
/// même WriteBatch (comme nbParticipants).
class Candidat {
  final String id; // uid du candidat
  final String nom;
  final String presentation; // quelques mots : pourquoi voter pour moi
  final int nbVoix;

  const Candidat({
    required this.id,
    required this.nom,
    this.presentation = '',
    this.nbVoix = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'presentation': presentation,
      'nbVoix': nbVoix,
    };
  }

  factory Candidat.fromMap(String id, Map<String, dynamic> map) {
    return Candidat(
      id: id,
      nom: map['nom'] ?? '',
      presentation: map['presentation'] ?? '',
      nbVoix: map['nbVoix'] ?? 0,
    );
  }
}
