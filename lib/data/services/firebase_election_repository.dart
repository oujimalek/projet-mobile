import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/election.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'election_repository.dart';
import 'evenement_repository.dart';
import 'firebase_evenement_repository.dart';
import 'firestore_commun.dart';
import 'utilisateur_repository.dart';

/// M4 - Version Cloud Firestore de ElectionRepository.
///
/// Écrit dans quartiers/{q}/elections (+ candidats, votes) et
/// quartiers/{q}/demandesElection. À la publication des résultats, change
/// aussi le rôle (resident / leader) des membres concernés : c'est la
/// règle « admin : rôle » de utilisateurs dans firestore.rules.
class FirebaseElectionRepository implements ElectionRepository {
  // =====================================================================
  // Outils
  // =====================================================================

  Utilisateur _moi() {
    final Utilisateur utilisateur =
        UtilisateurRepository().getUtilisateurConnecte();
    if (utilisateur.id.isEmpty) {
      throw const RefusM4('Tu n\'es pas connecté');
    }
    if ((utilisateur.quartierId ?? '').isEmpty) {
      throw const RefusM4('Choisis d\'abord ton quartier');
    }
    return utilisateur;
  }

  CollectionReference<Map<String, dynamic>> get _elections {
    return FirestoreCommun.collectionDuQuartier(_moi().quartierId!, 'elections');
  }

  CollectionReference<Map<String, dynamic>> get _demandes {
    return FirestoreCommun.collectionDuQuartier(
        _moi().quartierId!, 'demandesElection');
  }

  CollectionReference<Map<String, dynamic>> _candidats(String electionId) {
    return _elections.doc(electionId).collection('candidats');
  }

  CollectionReference<Map<String, dynamic>> _votes(String electionId) {
    return _elections.doc(electionId).collection('votes');
  }

  /// Range les refus métier et toute erreur dans un Resultat en échec.
  Future<Resultat<T>> _executer<T>(Future<T> Function() action) async {
    try {
      return await FirestoreCommun.executer(action);
    } on RefusM4 catch (refus) {
      return Resultat.echec(refus.message);
    } catch (erreur) {
      return Resultat.echec('Une erreur est survenue');
    }
  }

  Future<Election?> _derniere() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _elections.orderBy('debut', descending: true).limit(1).get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    final document = snapshot.docs.first;
    return Election.fromMap(document.id, document.data());
  }

  Future<List<Candidat>> _listeCandidats(String electionId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _candidats(electionId).get();
    final List<Candidat> liste = [];
    for (final document in snapshot.docs) {
      liste.add(Candidat.fromMap(document.id, document.data()));
    }
    return liste;
  }

  // =====================================================================
  // Lectures
  // =====================================================================

  @override
  Future<Resultat<Election?>> getDerniereElection() {
    return _executer(_derniere);
  }

  @override
  Future<Resultat<List<Candidat>>> getCandidats(String electionId) {
    return _executer(() => _listeCandidats(electionId));
  }

  @override
  Future<Resultat<String?>> getMonVote(String electionId) {
    return _executer(() async {
      // Vote secret : les règles ne laissent lire que SON vote
      final DocumentSnapshot<Map<String, dynamic>> vote =
          await _votes(electionId).doc(_moi().id).get();
      if (!vote.exists) {
        return null;
      }
      return vote.data()!['candidatId'] as String?;
    });
  }

  @override
  Future<Resultat<bool>> aDemandeElection() {
    return _executer(() async {
      return (await _demandes.doc(_moi().id).get()).exists;
    });
  }

  @override
  Future<Resultat<int>> compterDemandes() {
    return _executer(() async {
      return _nbDemandesValides(await _idsVotants());
    });
  }

  @override
  Future<Resultat<int>> compterVotants() {
    return _executer(() async {
      return (await _idsVotants()).length;
    });
  }

  /// Les membres actifs de la houma, sans l'admin global.
  Future<Set<String>> _idsVotants() async {
    final Resultat<List<Utilisateur>> actifs =
        await UtilisateurRepository().getMembres(StatutUtilisateur.actif);
    if (!actifs.estSucces) {
      throw RefusM4(actifs.erreur!);
    }
    return ElectionRepository.idsVotants(actifs.donnee ?? []);
  }

  /// Les demandes des membres encore actifs (pas celles des partis/bloqués).
  Future<int> _nbDemandesValides(Set<String> idsVotants) async {
    final QuerySnapshot<Map<String, dynamic>> demandes = await _demandes.get();
    int nb = 0;
    for (final document in demandes.docs) {
      if (idsVotants.contains(document.id)) {
        nb++;
      }
    }
    return nb;
  }

  // =====================================================================
  // Écritures
  // =====================================================================

  @override
  Future<Resultat<void>> ouvrirElection({
    required int nbPlaces,
    required bool anticipee,
  }) {
    return _executer(() async {
      final Election? derniere = await _derniere();
      int nbDemandes = 0;
      int nbActifs = 0;
      if (anticipee) {
        final Set<String> idsVotants = await _idsVotants();
        nbActifs = idsVotants.length;
        nbDemandes = await _nbDemandesValides(idsVotants);
      }
      final String? refus = ElectionRepository.refusOuverture(
        _moi(),
        derniere,
        nbPlaces,
        anticipee: anticipee,
        nbDemandes: nbDemandes,
        nbActifs: nbActifs,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      final Election election = ElectionRepository.nouvelle(
        debut: DateTime.now(),
        nbPlaces: nbPlaces,
        anticipee: anticipee,
        premiere: derniere == null,
      );

      // L'élection + l'effacement des demandes, en une seule écriture
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(_elections.doc(), election.toMap());
      final QuerySnapshot<Map<String, dynamic>> demandes = await _demandes.get();
      for (final document in demandes.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    });
  }

  @override
  Future<Resultat<void>> sePorterCandidat(Election election, String presentation) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final bool deja = (await _candidats(election.id).doc(moi.id).get()).exists;
      final String? refus = ElectionRepository.refusCandidature(
        moi,
        election,
        dejaCandidat: deja,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      if (presentation.trim().length > ElectionRepository.presentationMax) {
        throw const RefusM4(
            '${ElectionRepository.presentationMax} caractères au maximum');
      }
      final Candidat candidat = Candidat(
        id: moi.id,
        nom: EvenementRepository.nomCourt(moi),
        presentation: presentation.trim(),
      );
      await _candidats(election.id).doc(moi.id).set(candidat.toMap());
    });
  }

  @override
  Future<Resultat<void>> retirerCandidature(Election election) {
    return _executer(() async {
      if (election.phase() != PhaseElection.candidatures) {
        throw const RefusM4('Les candidatures sont fermées');
      }
      await _candidats(election.id).doc(_moi().id).delete();
    });
  }

  @override
  Future<Resultat<void>> voter(Election election, String candidatId) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final DocumentReference<Map<String, dynamic>> monVote =
          _votes(election.id).doc(moi.id);
      final bool dejaVote = (await monVote.get()).exists;
      final List<Candidat> candidats = await _listeCandidats(election.id);
      final String? refus = ElectionRepository.refusVote(
        election,
        candidatId,
        candidats,
        aDejaVote: dejaVote,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }

      // Mon vote + la voix du candidat dans le MÊME WriteBatch
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(monVote, {
        'candidatId': candidatId,
        'date': FieldValue.serverTimestamp(),
      });
      batch.update(
        _candidats(election.id).doc(candidatId),
        {'nbVoix': FieldValue.increment(1)},
      );
      await batch.commit();
    });
  }

  @override
  Future<Resultat<void>> publierResultats(Election election, List<Candidat> elus) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      if (!moi.estAdmin) {
        throw const RefusM4('Seul l\'admin publie les résultats');
      }
      if (election.phase() != PhaseElection.depouillement) {
        throw const RefusM4('Le vote n\'est pas encore terminé');
      }
      if (elus.isEmpty || elus.length > election.nbPlaces) {
        throw RefusM4('Choisis entre 1 et ${election.nbPlaces} élus');
      }

      final CollectionReference<Map<String, dynamic>> utilisateurs =
          FirestoreCommun.base.collection('utilisateurs');
      final Set<String> idsElus = {};
      for (final Candidat elu in elus) {
        idsElus.add(elu.id);
      }

      final WriteBatch batch = FirestoreCommun.base.batch();

      // Les anciens leaders qui ne sont pas réélus redeviennent résidents
      final QuerySnapshot<Map<String, dynamic>> anciens = await utilisateurs
          .where('quartierId', isEqualTo: moi.quartierId)
          .where('role', isEqualTo: RoleUtilisateur.leader.name)
          .get();
      for (final document in anciens.docs) {
        if (!idsElus.contains(document.id) &&
            document.data()['statut'] == StatutUtilisateur.actif.name) {
          batch.update(document.reference,
              {'role': RoleUtilisateur.resident.name});
        }
      }

      // Les élus deviennent leaders (s'ils sont toujours membres actifs)
      final List<String> elusIds = [];
      final List<String> elusNoms = [];
      for (final Candidat elu in elus) {
        final DocumentSnapshot<Map<String, dynamic>> profil =
            await utilisateurs.doc(elu.id).get();
        final Map<String, dynamic>? donnees = profil.data();
        if (donnees == null ||
            donnees['quartierId'] != moi.quartierId ||
            donnees['statut'] != StatutUtilisateur.actif.name ||
            donnees['role'] == RoleUtilisateur.admin.name) {
          continue; // parti, bloqué ou admin entre-temps
        }
        elusIds.add(elu.id);
        elusNoms.add(elu.nom);
        if (donnees['role'] != RoleUtilisateur.leader.name) {
          batch.update(profil.reference, {'role': RoleUtilisateur.leader.name});
        }
      }
      // Personne de valide : on ne publie pas (sinon 6 mois sans leader)
      if (elusIds.isEmpty) {
        throw const RefusM4(
            'L\'élu n\'est plus membre actif de la houma : choisis-en un autre');
      }

      batch.update(_elections.doc(election.id), {
        'publiee': true,
        'elusIds': elusIds,
        'elusNoms': elusNoms,
      });
      // La houma a maintenant un leader élu (les nouveaux habitants n'ont
      // plus besoin de contrat : le leader les valide)
      batch.update(
        FirestoreCommun.base.collection('quartiers').doc(moi.quartierId),
        {'aUnLeader': true},
      );
      await batch.commit();
    });
  }

  @override
  Future<Resultat<void>> demanderElection(bool demander) {
    return _executer(() async {
      final DocumentReference<Map<String, dynamic>> maDemande =
          _demandes.doc(_moi().id);
      if (demander) {
        await maDemande.set({'date': FieldValue.serverTimestamp()});
      } else {
        await maDemande.delete();
      }
    });
  }
}
