import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/sondage.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M4 - Implémentation "en mémoire" de EvenementRepository, pour les TESTS.
///
/// Aucune donnée au départ : chaque test ajoute ce dont il a besoin avec
/// [ajouterEvenementDe] et [ajouterSondageDe]. Mêmes règles que
/// FirebaseEvenementRepository (EvenementRepository.refus...). Sans Internet.
class MockEvenementRepository implements EvenementRepository {
  final List<Evenement> _evenements = [];
  final List<Sondage> _sondages = [];

  // evenementId → (uid → nom) des participants
  final Map<String, Map<String, String>> _participants = {};
  // sondageId → (uid → choix) des votes
  final Map<String, Map<String, int>> _votes = {};

  int _compteur = 0;

  /// Si ce n'est pas null : toutes les opérations réseau échouent avec ce message.
  String? erreur;

  /// Nombre de membres renvoyé dans les sondages chargés.
  int nombreMembres = 0;

  /// Les événements enregistrés (pour vérifier les tests).
  List<Evenement> get evenements => List.of(_evenements);

  /// Les sondages enregistrés, SANS les votes (pour vérifier les tests).
  List<Sondage> get sondages => List.of(_sondages);

  String _nouvelId(String prefixe) {
    _compteur++;
    return '$prefixe$_compteur';
  }

  Utilisateur _moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// Ajoute directement un événement organisé par [organisateur].
  Evenement ajouterEvenementDe(
    Utilisateur organisateur, {
    String titre = 'Fête des voisins',
    String description = '',
    String lieu = 'Jardin de la résidence',
    DateTime? date,
    DateTime? dateFin,
    CategorieEvenement categorie = CategorieEvenement.fete,
  }) {
    final Evenement evenement = Evenement(
      id: _nouvelId('e'),
      titre: titre,
      description: description,
      date: date ?? DateTime.now().add(const Duration(days: 7)),
      dateFin: dateFin,
      lieu: lieu,
      categorie: categorie,
      organisateurId: organisateur.id,
      organisateur: EvenementRepository.nomCourt(organisateur),
    );
    _evenements.add(evenement);
    _participants[evenement.id] = {};
    return evenement;
  }

  /// Ajoute directement un sondage proposé par [auteur].
  Sondage ajouterSondageDe(
    Utilisateur auteur, {
    String question = 'Quelle date pour la réunion ?',
    List<String> options = const ['Mardi', 'Jeudi'],
    DateTime? dateFin,
  }) {
    final List<OptionSondage> choix = [];
    for (final String texte in options) {
      choix.add(OptionSondage(texte: texte));
    }
    final Sondage sondage = Sondage(
      id: _nouvelId('p'),
      question: question,
      options: choix,
      dateFin: dateFin ?? DateTime.now().add(const Duration(days: 2)),
      proposeParId: auteur.id,
      proposePar: EvenementRepository.nomCourt(auteur),
    );
    _sondages.add(sondage);
    _votes[sondage.id] = {};
    return sondage;
  }

  /// Ajoute directement le vote de [votant].
  void ajouterVoteDe(Utilisateur votant, Sondage sondage, int choix) {
    _votes[sondage.id]![votant.id] = choix;
  }

  int _index(String evenementId) {
    return _evenements.indexWhere((e) => e.id == evenementId);
  }

  /// Le sondage avec ses votes comptés (comme count() côté Firebase).
  Sondage _avecVotes(Sondage sondage) {
    final List<OptionSondage> options = [];
    for (int i = 0; i < sondage.options.length; i++) {
      int votes = 0;
      for (final int choix in _votes[sondage.id]!.values) {
        if (choix == i) {
          votes++;
        }
      }
      options.add(OptionSondage(texte: sondage.options[i].texte, votes: votes));
    }
    return Sondage(
      id: sondage.id,
      question: sondage.question,
      options: options,
      dateFin: sondage.dateFin,
      proposeParId: sondage.proposeParId,
      proposePar: sondage.proposePar,
      nombreMembres: nombreMembres,
    );
  }

  // =====================================================================
  // Événements
  // =====================================================================

  @override
  List<Evenement> getEvenements() {
    final List<Evenement> aVenir = [];
    for (final Evenement evenement in _evenements) {
      if (!evenement.estPasse) {
        aVenir.add(evenement);
      }
    }
    aVenir.sort((a, b) => a.date.compareTo(b.date));
    return aVenir;
  }

  @override
  Future<Resultat<List<Evenement>>> chargerEvenements() async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final List<Evenement> liste = List.of(_evenements);
    liste.sort((a, b) => a.date.compareTo(b.date));
    return Resultat.succes(liste);
  }

  @override
  Future<Resultat<Evenement>> getEvenement(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Cet événement n\'existe plus');
    }
    return Resultat.succes(_evenements[index]);
  }

  @override
  Future<Resultat<void>> creerEvenement({
    required String titre,
    required String description,
    required DateTime date,
    DateTime? dateFin,
    required String lieu,
    required CategorieEvenement categorie,
  }) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final String? refus = EvenementRepository.refusEvenement(
      titre: titre,
      description: description,
      lieu: lieu,
      date: date,
      dateFin: dateFin,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    if (!EvenementRepository.peutOrganiser(_moi())) {
      return const Resultat.echec(EvenementRepository.refusOrganiser);
    }
    ajouterEvenementDe(
      _moi(),
      titre: titre.trim(),
      description: description.trim(),
      lieu: lieu.trim(),
      date: date,
      dateFin: dateFin,
      categorie: categorie,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> modifierEvenement(Evenement evenement) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenement.id);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutModifier(_moi(), _evenements[index])) {
      return const Resultat.echec(
          'Seul l\'organisateur ou l\'admin peut modifier l\'événement');
    }
    final String? refus = EvenementRepository.refusEvenement(
      titre: evenement.titre,
      description: evenement.description,
      lieu: evenement.lieu,
      date: evenement.date,
      dateFin: evenement.dateFin,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Le compteur ne change pas (comme dans les règles)
    _evenements[index] = _evenements[index].copyWith(
      titre: evenement.titre.trim(),
      description: evenement.description.trim(),
      lieu: evenement.lieu.trim(),
      date: evenement.date,
      dateFin: evenement.dateFin,
      sansFin: evenement.dateFin == null,
      categorie: evenement.categorie,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerEvenement(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutSupprimer(
        _moi(), _evenements[index].organisateurId)) {
      return const Resultat.echec('Action non autorisée');
    }
    _evenements.removeAt(index);
    _participants.remove(evenementId);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<bool>> estInscrit(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, String>? fiches = _participants[evenementId];
    return Resultat.succes(fiches != null && fiches.containsKey(_moi().id));
  }

  @override
  Future<Resultat<List<String>>> getParticipants(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, String> fiches = _participants[evenementId] ?? {};
    return Resultat.succes(fiches.values.toList());
  }

  @override
  Future<Resultat<void>> participer(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    final Utilisateur moi = _moi();
    if (_participants[evenementId]!.containsKey(moi.id)) {
      return const Resultat.echec('Tu participes déjà à cet événement');
    }
    _participants[evenementId]![moi.id] = EvenementRepository.nomCourt(moi);
    final Evenement evenement = _evenements[index];
    _evenements[index] =
        evenement.copyWith(participants: evenement.participants + 1);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> seRetirer(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (_participants[evenementId]!.remove(_moi().id) == null) {
      return const Resultat.echec('Tu ne participes pas à cet événement');
    }
    final Evenement evenement = _evenements[index];
    _evenements[index] =
        evenement.copyWith(participants: evenement.participants - 1);
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Sondages
  // =====================================================================

  /// Les ouverts (fin la plus proche d'abord), puis les terminés (récents d'abord).
  List<Sondage> _tries() {
    final List<Sondage> ouverts = [];
    final List<Sondage> termines = [];
    for (final Sondage sondage in _sondages) {
      if (sondage.estOuvert) {
        ouverts.add(_avecVotes(sondage));
      } else {
        termines.add(_avecVotes(sondage));
      }
    }
    ouverts.sort((a, b) => a.dateFin.compareTo(b.dateFin));
    termines.sort((a, b) => b.dateFin.compareTo(a.dateFin));
    return [...ouverts, ...termines];
  }

  @override
  Sondage? getSondageActif() {
    for (final Sondage sondage in _tries()) {
      if (sondage.estOuvert) {
        return sondage;
      }
    }
    return null;
  }

  @override
  Future<Resultat<List<Sondage>>> chargerSondages() async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_tries());
  }

  @override
  Future<Resultat<void>> creerSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
  }) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final String? refus = EvenementRepository.refusSondage(
      question: question,
      options: options,
      dateFin: dateFin,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final List<String> remplies = [];
    for (final String texte in options) {
      if (texte.trim().isNotEmpty) {
        remplies.add(texte.trim());
      }
    }
    if (!EvenementRepository.peutOrganiser(_moi())) {
      return const Resultat.echec(EvenementRepository.refusOrganiser);
    }
    ajouterSondageDe(
      _moi(),
      question: question.trim(),
      options: remplies,
      dateFin: dateFin,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerSondage(String sondageId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _sondages.indexWhere((s) => s.id == sondageId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutSupprimer(
        _moi(), _sondages[index].proposeParId)) {
      return const Resultat.echec('Action non autorisée');
    }
    _sondages.removeAt(index);
    _votes.remove(sondageId);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<int?>> getMonVote(String sondageId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_votes[sondageId]?[_moi().id]);
  }

  @override
  Future<Resultat<void>> voter(Sondage sondage, int choix) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, int>? votes = _votes[sondage.id];
    if (votes == null) {
      return const Resultat.echec('Donnée introuvable');
    }
    final String moi = _moi().id;
    final String? refus =
        EvenementRepository.refusVote(sondage, choix, votes[moi]);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    votes[moi] = choix;
    return const Resultat.succes(null);
  }
}
