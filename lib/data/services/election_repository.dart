import '../models/election.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firebase_election_repository.dart';

/// M4 - Les élections des leaders du quartier : le CONTRAT.
///
/// Implémentations :
/// - FirebaseElectionRepository : Cloud Firestore (celle de l'application) ;
/// - MockElectionRepository (dans test/) : données en mémoire.
///
/// Collections (sous quartiers/{quartierId}/) : elections (+ candidats,
/// votes) et demandesElection. Les règles sont dans firestore.rules.
///
/// Sans serveur (plan gratuit), personne n'ouvre l'élection « tout seul » :
/// l'app calcule la date de la prochaine élection et l'admin l'ouvre.
abstract class ElectionRepository {
  /// L'implémentation utilisée par toute l'application.
  static ElectionRepository instance = FirebaseElectionRepository();

  /// `ElectionRepository()` renvoie l'instance ci-dessus.
  factory ElectionRepository() {
    return instance;
  }

  // =====================================================================
  // Règles métier (communes à Firebase et au mock)
  // =====================================================================

  static const Duration dureeCandidatures = Duration(days: 3);
  static const Duration dureeVote = Duration(days: 2);
  static const Duration dureeAnticipee = Duration(hours: 12); // par phase
  static const Duration periodicite = Duration(days: 182); // 6 mois
  static const Duration anciennete = Duration(days: 30); // pour être candidat
  static const int placesMax = 10;
  static const int presentationMax = 200;

  /// Les dates d'une nouvelle élection ouverte à [debut].
  /// Normale : 3 jours de candidatures + 2 jours de vote.
  /// Anticipée : 12 h + 12 h (24 h en tout).
  static Election nouvelle({
    required DateTime debut,
    required int nbPlaces,
    required bool anticipee,
    required bool premiere,
  }) {
    final Duration candidatures = anticipee ? dureeAnticipee : dureeCandidatures;
    final Duration vote = anticipee ? dureeAnticipee : dureeVote;
    return Election(
      id: '',
      nbPlaces: nbPlaces,
      debut: debut,
      finCandidatures: debut.add(candidatures),
      finVote: debut.add(candidatures).add(vote),
      anticipee: anticipee,
      premiere: premiere,
    );
  }

  /// La date de la prochaine élection semestrielle (null : aucune élection
  /// publiée, la première peut être ouverte tout de suite).
  static DateTime? prochaineElection(Election? derniere) {
    if (derniere == null || !derniere.publiee) {
      return null;
    }
    return derniere.finVote.add(periodicite);
  }

  /// Pourquoi [admin] ne peut pas ouvrir d'élection (null : il peut).
  static String? refusOuverture(
    Utilisateur admin,
    Election? derniere,
    int nbPlaces,
  ) {
    if (!admin.estAdmin) {
      return 'Seul l\'admin ouvre une élection';
    }
    if (derniere != null && derniere.phase() != PhaseElection.terminee) {
      return 'Une élection est déjà en cours';
    }
    if (nbPlaces < 1 || nbPlaces > placesMax) {
      return 'Entre 1 et $placesMax leaders';
    }
    return null;
  }

  /// Pourquoi [membre] ne peut pas se porter candidat (null : il peut).
  /// Première élection : tout membre ; ensuite : membre depuis 1 mois.
  /// L'admin ne peut jamais être leader. Mêmes conditions que les règles.
  static String? refusCandidature(
    Utilisateur membre,
    Election election, {
    required bool dejaCandidat,
    DateTime? maintenant,
  }) {
    final DateTime instant = maintenant ?? DateTime.now();
    if (membre.estAdmin) {
      return 'L\'administrateur ne peut pas être leader';
    }
    if (election.phase(instant) != PhaseElection.candidatures) {
      return 'Les candidatures sont fermées';
    }
    if (dejaCandidat) {
      return 'Tu es déjà candidat';
    }
    if (!election.premiere) {
      final DateTime? arrivee = membre.dateDemande;
      if (arrivee == null || arrivee.isAfter(instant.subtract(anciennete))) {
        return 'Il faut être membre du quartier depuis au moins 1 mois';
      }
    }
    return null;
  }

  /// Pourquoi ce vote est refusé (null : accepté).
  static String? refusVote(
    Election election,
    String candidatId,
    List<Candidat> candidats, {
    required bool aDejaVote,
  }) {
    if (aDejaVote) {
      return 'Tu as déjà voté';
    }
    if (election.phase() != PhaseElection.vote) {
      return 'Le vote n\'est pas ouvert';
    }
    for (final Candidat candidat in candidats) {
      if (candidat.id == candidatId) {
        return null;
      }
    }
    return 'Candidat introuvable';
  }

  /// Les candidats du plus voté au moins voté.
  static List<Candidat> classement(List<Candidat> candidats) {
    final List<Candidat> liste = List.of(candidats);
    liste.sort((a, b) => b.nbVoix.compareTo(a.nbVoix));
    return liste;
  }

  /// Les élus proposés : les [nbPlaces] premiers du classement.
  static List<Candidat> elusProposes(List<Candidat> candidats, int nbPlaces) {
    return classement(candidats).take(nbPlaces).toList();
  }

  /// true si le dernier élu est à égalité avec le premier non élu :
  /// l'admin doit alors choisir lui-même.
  static bool egalite(List<Candidat> candidats, int nbPlaces) {
    final List<Candidat> liste = classement(candidats);
    if (liste.length <= nbPlaces || nbPlaces < 1) {
      return false;
    }
    return liste[nbPlaces - 1].nbVoix == liste[nbPlaces].nbVoix;
  }

  // =====================================================================
  // Lectures
  // =====================================================================

  /// La dernière élection (en cours ou terminée), null s'il n'y en a jamais eu.
  Future<Resultat<Election?>> getDerniereElection();

  /// Les candidats d'une élection.
  Future<Resultat<List<Candidat>>> getCandidats(String electionId);

  /// Le candidat pour qui j'ai voté (null : pas encore voté).
  Future<Resultat<String?>> getMonVote(String electionId);

  /// true si j'ai demandé une nouvelle élection.
  Future<Resultat<bool>> aDemandeElection();

  /// Le nombre de membres qui demandent une nouvelle élection (admin).
  Future<Resultat<int>> compterDemandes();

  // =====================================================================
  // Écritures
  // =====================================================================

  /// L'admin ouvre une élection (normale ou anticipée). Les demandes
  /// d'élection sont effacées.
  Future<Resultat<void>> ouvrirElection({
    required int nbPlaces,
    required bool anticipee,
  });

  /// Je me porte candidat, avec une courte présentation.
  Future<Resultat<void>> sePorterCandidat(Election election, String presentation);

  /// Je retire ma candidature (pendant les candidatures seulement).
  Future<Resultat<void>> retirerCandidature(Election election);

  /// Je vote pour [candidatId] : mon vote + sa voix, en une seule écriture.
  Future<Resultat<void>> voter(Election election, String candidatId);

  /// L'admin publie les résultats : les [elus] deviennent leaders, les
  /// anciens leaders redeviennent résidents.
  Future<Resultat<void>> publierResultats(Election election, List<Candidat> elus);

  /// Je demande (ou je retire ma demande d') une nouvelle élection.
  Future<Resultat<void>> demanderElection(bool demander);
}
