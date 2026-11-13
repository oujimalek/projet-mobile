import 'package:houmani/data/models/election.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/election_repository.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

import 'mock_utilisateur_repository.dart';

/// M4 - Implémentation "en mémoire" de ElectionRepository, pour les TESTS.
///
/// Mêmes règles que FirebaseElectionRepository (ElectionRepository.refus...).
/// La publication change le rôle des membres via le mock du module 1
/// (UtilisateurRepository().changerRole), comme le ferait l'admin.
class MockElectionRepository implements ElectionRepository {
  final List<Election> _elections = [];
  final Map<String, List<Candidat>> _candidats = {}; // electionId → candidats
  final Map<String, Map<String, String>> _votes = {}; // electionId → (uid → candidatId)
  final Set<String> _demandes = {}; // uids
  int _compteur = 0;

  /// Si ce n'est pas null : toutes les opérations échouent avec ce message.
  String? erreur;

  List<Election> get elections => List.of(_elections);

  Utilisateur _moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// Ajoute directement une élection (dates libres, pour placer un test
  /// dans la phase voulue).
  Election ajouterElection({
    required DateTime debut,
    required DateTime finCandidatures,
    required DateTime finVote,
    int nbPlaces = 2,
    bool premiere = true,
    bool publiee = false,
    List<String> elusNoms = const [],
  }) {
    _compteur++;
    final Election election = Election(
      id: 'el$_compteur',
      nbPlaces: nbPlaces,
      debut: debut,
      finCandidatures: finCandidatures,
      finVote: finVote,
      premiere: premiere,
      publiee: publiee,
      elusNoms: elusNoms,
    );
    _elections.add(election);
    _candidats[election.id] = [];
    _votes[election.id] = {};
    return election;
  }

  /// Ajoute directement un candidat avec un nombre de voix.
  void ajouterCandidat(Election election, Utilisateur membre, {int voix = 0}) {
    _candidats[election.id]!.add(
      Candidat(id: membre.id, nom: EvenementRepository.nomCourt(membre), nbVoix: voix),
    );
  }

  Election? _derniere() {
    if (_elections.isEmpty) {
      return null;
    }
    final List<Election> triees = List.of(_elections);
    triees.sort((a, b) => b.debut.compareTo(a.debut));
    return triees.first;
  }

  @override
  Future<Resultat<Election?>> getDerniereElection() async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_derniere());
  }

  @override
  Future<Resultat<List<Candidat>>> getCandidats(String electionId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(List.of(_candidats[electionId] ?? []));
  }

  @override
  Future<Resultat<String?>> getMonVote(String electionId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_votes[electionId]?[_moi().id]);
  }

  @override
  Future<Resultat<bool>> aDemandeElection() async {
    return Resultat.succes(_demandes.contains(_moi().id));
  }

  @override
  Future<Resultat<int>> compterDemandes() async {
    return Resultat.succes(await _nbDemandesValides(await _idsVotants()));
  }

  @override
  Future<Resultat<int>> compterVotants() async {
    return Resultat.succes((await _idsVotants()).length);
  }

  Future<Set<String>> _idsVotants() async {
    final Resultat<List<Utilisateur>> actifs =
        await UtilisateurRepository().getMembres(StatutUtilisateur.actif);
    return ElectionRepository.idsVotants(actifs.donnee ?? []);
  }

  Future<int> _nbDemandesValides(Set<String> idsVotants) async {
    return _demandes.where(idsVotants.contains).length;
  }

  @override
  Future<Resultat<void>> ouvrirElection({
    required int nbPlaces,
    required bool anticipee,
  }) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Election? derniere = _derniere();
    final Set<String> idsVotants = await _idsVotants();
    final String? refus = ElectionRepository.refusOuverture(
      _moi(),
      derniere,
      nbPlaces,
      anticipee: anticipee,
      nbDemandes: await _nbDemandesValides(idsVotants),
      nbActifs: idsVotants.length,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Election modele = ElectionRepository.nouvelle(
      debut: DateTime.now(),
      nbPlaces: nbPlaces,
      anticipee: anticipee,
      premiere: derniere == null,
    );
    ajouterElection(
      debut: modele.debut,
      finCandidatures: modele.finCandidatures,
      finVote: modele.finVote,
      nbPlaces: nbPlaces,
      premiere: modele.premiere,
    );
    _demandes.clear();
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> sePorterCandidat(Election election, String presentation) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Utilisateur moi = _moi();
    final List<Candidat> candidats = _candidats[election.id]!;
    bool deja = false;
    for (final Candidat candidat in candidats) {
      if (candidat.id == moi.id) {
        deja = true;
      }
    }
    final String? refus =
        ElectionRepository.refusCandidature(moi, election, dejaCandidat: deja);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    candidats.add(Candidat(
      id: moi.id,
      nom: EvenementRepository.nomCourt(moi),
      presentation: presentation.trim(),
    ));
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> retirerCandidature(Election election) async {
    if (election.phase() != PhaseElection.candidatures) {
      return const Resultat.echec('Les candidatures sont fermées');
    }
    _candidats[election.id]!.removeWhere((c) => c.id == _moi().id);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> voter(Election election, String candidatId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final String moi = _moi().id;
    final List<Candidat> candidats = _candidats[election.id]!;
    final String? refus = ElectionRepository.refusVote(
      election,
      candidatId,
      candidats,
      aDejaVote: _votes[election.id]!.containsKey(moi),
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    _votes[election.id]![moi] = candidatId;
    for (int i = 0; i < candidats.length; i++) {
      if (candidats[i].id == candidatId) {
        final Candidat c = candidats[i];
        candidats[i] = Candidat(
          id: c.id,
          nom: c.nom,
          presentation: c.presentation,
          nbVoix: c.nbVoix + 1,
        );
      }
    }
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> publierResultats(Election election, List<Candidat> elus) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    if (!_moi().estAdmin) {
      return const Resultat.echec('Seul l\'admin publie les résultats');
    }
    if (election.phase() != PhaseElection.depouillement) {
      return const Resultat.echec('Le vote n\'est pas encore terminé');
    }
    if (elus.isEmpty || elus.length > election.nbPlaces) {
      return Resultat.echec('Choisis entre 1 et ${election.nbPlaces} élus');
    }
    // Les rôles : comme le ferait l'admin, via le module 1
    final Resultat<List<Utilisateur>> actifs =
        await UtilisateurRepository().getMembres(StatutUtilisateur.actif);
    // Comme Firebase : seuls les élus encore actifs (et pas admin) comptent
    final List<Candidat> valides = elus
        .where((c) => ElectionRepository.idsVotants(actifs.donnee ?? []).contains(c.id))
        .toList();
    if (valides.isEmpty) {
      return const Resultat.echec(
          'L\'élu n\'est plus membre actif de la houma : choisis-en un autre');
    }
    elus = valides;
    for (final Utilisateur membre in actifs.donnee ?? []) {
      final bool elu = elus.any((c) => c.id == membre.id);
      if (membre.estLeader && !elu) {
        await UtilisateurRepository().changerRole(membre.id, RoleUtilisateur.resident);
      }
      if (elu && !membre.estLeader) {
        await UtilisateurRepository().changerRole(membre.id, RoleUtilisateur.leader);
      }
    }
    // Comme Firebase : le quartier a maintenant son leader
    final UtilisateurRepository utilisateurs = UtilisateurRepository();
    if (utilisateurs is MockUtilisateurRepository) {
      utilisateurs.noterLeader(_moi().quartierId);
    }
    final int index = _elections.indexWhere((e) => e.id == election.id);
    final Election e = _elections[index];
    _elections[index] = Election(
      id: e.id,
      nbPlaces: e.nbPlaces,
      debut: e.debut,
      finCandidatures: e.finCandidatures,
      finVote: e.finVote,
      anticipee: e.anticipee,
      premiere: e.premiere,
      publiee: true,
      elusIds: elus.map((c) => c.id).toList(),
      elusNoms: elus.map((c) => c.nom).toList(),
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> demanderElection(bool demander) async {
    if (demander) {
      _demandes.add(_moi().id);
    } else {
      _demandes.remove(_moi().id);
    }
    return const Resultat.succes(null);
  }
}
