import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/evenement.dart';
import '../models/sondage.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'evenement_repository.dart';
import 'firestore_commun.dart';
import 'utilisateur_repository.dart';

/// M4 - Un refus métier (pas connecté, déjà inscrit...) : le message est en
/// français, prêt à afficher. Jamais levé vers les écrans : il est rangé
/// dans un `Resultat.echec`.
class RefusM4 implements Exception {
  final String message;

  const RefusM4(this.message);
}

/// M4 - Version Cloud Firestore de EvenementRepository (celle de l'application).
///
/// Écrit UNIQUEMENT dans quartiers/{q}/evenements (+ participants) et
/// quartiers/{q}/sondages (+ votes). Les règles correspondantes sont dans
/// firestore.rules (partie « M4 »).
class FirebaseEvenementRepository implements EvenementRepository {
  // Dernières listes chargées (l'accueil les lit sans attendre)
  List<Evenement> _evenements = const [];
  List<Sondage> _sondages = const [];
  bool _evenementsDemandes = false;
  bool _sondagesDemandes = false;

  // =====================================================================
  // Outils
  // =====================================================================

  /// L'utilisateur connecté, avec un quartier. Sinon un refus en français.
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

  CollectionReference<Map<String, dynamic>> get _collectionEvenements {
    return FirestoreCommun.collectionDuQuartier(
        _moi().quartierId!, 'evenements');
  }

  CollectionReference<Map<String, dynamic>> get _collectionSondages {
    return FirestoreCommun.collectionDuQuartier(_moi().quartierId!, 'sondages');
  }

  /// Comme FirestoreCommun.executer, mais range aussi les refus métier et
  /// toute autre erreur dans un Resultat en échec : jamais d'exception.
  Future<Resultat<T>> _executer<T>(Future<T> Function() action) async {
    try {
      return await FirestoreCommun.executer(action);
    } on RefusM4 catch (refus) {
      return Resultat.echec(refus.message);
    } catch (erreur) {
      return Resultat.echec('Une erreur est survenue');
    }
  }

  // =====================================================================
  // Événements
  // =====================================================================

  @override
  List<Evenement> getEvenements() {
    // Premier appel : on lance le chargement sans attendre (la liste sera
    // prête au prochain affichage de l'accueil).
    if (!_evenementsDemandes) {
      _evenementsDemandes = true;
      chargerEvenements();
    }
    final List<Evenement> aVenir = [];
    for (final Evenement evenement in _evenements) {
      if (!evenement.estPasse && !evenement.annule) {
        aVenir.add(evenement);
      }
    }
    return aVenir;
  }

  @override
  Future<Resultat<List<Evenement>>> chargerEvenements() async {
    final Resultat<List<Evenement>> resultat = await _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _collectionEvenements.orderBy('date').get();
      final List<Evenement> liste = [];
      for (final document in snapshot.docs) {
        liste.add(Evenement.fromMap(document.id, document.data()));
      }
      return liste;
    });
    if (resultat.estSucces) {
      _evenements = resultat.donnee!;
    }
    return resultat;
  }

  @override
  Future<Resultat<Evenement>> getEvenement(String evenementId) {
    return _executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> document =
          await _collectionEvenements.doc(evenementId).get();
      if (!document.exists) {
        throw const RefusM4('Cet événement n\'existe plus');
      }
      return Evenement.fromMap(document.id, document.data()!);
    });
  }

  @override
  Future<Resultat<void>> creerEvenement({
    required String titre,
    required String description,
    required DateTime date,
    DateTime? dateFin,
    required String lieu,
    required CategorieEvenement categorie,
  }) {
    return _executer(() async {
      final String? refus = EvenementRepository.refusEvenement(
        titre: titre,
        description: description,
        lieu: lieu,
        date: date,
        dateFin: dateFin,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      final Utilisateur moi = _moi();
      if (!EvenementRepository.peutOrganiser(moi)) {
        throw const RefusM4(EvenementRepository.refusOrganiser);
      }
      final Evenement evenement = Evenement(
        id: '', // Firestore choisit l'id
        titre: titre.trim(),
        description: description.trim(),
        date: date,
        dateFin: dateFin,
        lieu: lieu.trim(),
        categorie: categorie,
        organisateurId: moi.id,
        organisateur: EvenementRepository.nomCourt(moi),
        participants: 0, // les règles exigent 0 à la création
        officiel: moi.estAdmin, // les événements de l'admin sont officiels
      );
      await _collectionEvenements.add(evenement.toMap());
    });
  }

  @override
  Future<Resultat<void>> annulerEvenement(Evenement evenement, bool annule) {
    return _executer(() async {
      if (!EvenementRepository.peutModifier(_moi(), evenement)) {
        throw const RefusM4(
            'Seul l\'organisateur ou l\'admin peut annuler l\'événement');
      }
      await _collectionEvenements.doc(evenement.id).update({'annule': annule});
    });
  }

  @override
  Future<Resultat<void>> modifierEvenement(Evenement evenement) {
    return _executer(() async {
      if (!EvenementRepository.peutModifier(_moi(), evenement)) {
        throw const RefusM4(
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
        throw RefusM4(refus);
      }
      // Seulement ces champs : les règles refusent tout autre changement
      // (le compteur et l'organisateur ne bougent jamais ici)
      await _collectionEvenements.doc(evenement.id).update({
        'titre': evenement.titre.trim(),
        'description': evenement.description.trim(),
        'date': evenement.date,
        'dateFin': evenement.dateFin,
        'lieu': evenement.lieu.trim(),
        'categorie': evenement.categorie.name,
      });
    });
  }

  @override
  Future<Resultat<void>> supprimerEvenement(String evenementId) {
    return _executer(() async {
      await _collectionEvenements.doc(evenementId).delete();
    });
  }

  @override
  Future<Resultat<bool>> estInscrit(String evenementId) {
    return _executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> fiche =
          await _collectionEvenements
              .doc(evenementId)
              .collection('participants')
              .doc(_moi().id)
              .get();
      return fiche.exists;
    });
  }

  @override
  Future<Resultat<List<Participant>>> getParticipants(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _collectionEvenements
              .doc(evenementId)
              .collection('participants')
              .orderBy('date')
              .get();
      final List<Participant> participants = [];
      for (final document in snapshot.docs) {
        participants.add(Participant(
          id: document.id,
          nom: document.data()['nom'] ?? '',
          avatar: document.data()['avatar'] ?? '',
        ));
      }
      return participants;
    });
  }

  @override
  Future<Resultat<void>> participer(String evenementId) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final DocumentReference<Map<String, dynamic>> evenement =
          _collectionEvenements.doc(evenementId);
      final DocumentReference<Map<String, dynamic>> maFiche =
          evenement.collection('participants').doc(moi.id);

      if ((await maFiche.get()).exists) {
        throw const RefusM4('Tu participes déjà à cet événement');
      }
      final DocumentSnapshot<Map<String, dynamic>> document =
          await evenement.get();
      if (!document.exists) {
        throw const RefusM4('Cet événement n\'existe plus');
      }
      final String? refus = EvenementRepository.refusParticipation(
          Evenement.fromMap(document.id, document.data()!));
      if (refus != null) {
        throw RefusM4(refus);
      }

      // Fiche + compteur dans le MÊME WriteBatch : sinon les règles refusent
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(maFiche, {
        'nom': EvenementRepository.nomCourt(moi),
        'avatar': moi.avatar, // l'avatar du module 1, pour la liste
        'date': FieldValue.serverTimestamp(),
      });
      batch.update(evenement, {'nbParticipants': FieldValue.increment(1)});
      await batch.commit();
    });
  }

  @override
  Future<Resultat<void>> seRetirer(String evenementId) {
    return _executer(() async {
      final DocumentReference<Map<String, dynamic>> evenement =
          _collectionEvenements.doc(evenementId);
      final DocumentReference<Map<String, dynamic>> maFiche =
          evenement.collection('participants').doc(_moi().id);

      if (!(await maFiche.get()).exists) {
        throw const RefusM4('Tu ne participes pas à cet événement');
      }

      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.delete(maFiche);
      batch.update(evenement, {'nbParticipants': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  // =====================================================================
  // Sondages
  // =====================================================================

  @override
  Sondage? getSondageActif() {
    if (!_sondagesDemandes) {
      _sondagesDemandes = true;
      chargerSondages();
    }
    // Liste triée : les ouverts d'abord, celui qui finit le plus tôt en tête
    for (final Sondage sondage in _sondages) {
      if (sondage.estOuvert) {
        return sondage;
      }
    }
    return null;
  }

  @override
  Future<Resultat<List<Sondage>>> chargerSondages() async {
    final Resultat<List<Sondage>> resultat = await _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _collectionSondages.orderBy('dateFin').get();

      // Nombre de membres qui peuvent voter (0 si on ne peut pas le savoir)
      final Resultat<int> membres = await UtilisateurRepository()
          .compterMembres(StatutUtilisateur.actif);
      final int nombreMembres = membres.donnee ?? 0;

      final List<Sondage> ouverts = [];
      final List<Sondage> termines = [];
      for (final document in snapshot.docs) {
        final Sondage sondage = await _avecVotes(
          document.id,
          document.data(),
          nombreMembres,
        );
        if (sondage.estOuvert) {
          ouverts.add(sondage);
        } else {
          termines.add(sondage);
        }
      }
      // Terminés : le plus récent d'abord
      return [...ouverts, ...termines.reversed];
    });
    if (resultat.estSucces) {
      _sondages = resultat.donnee!;
    }
    return resultat;
  }

  /// Construit le sondage en comptant ses votes option par option : count()
  /// compte sur le serveur, sans télécharger les votes.
  Future<Sondage> _avecVotes(
    String id,
    Map<String, dynamic> donnees,
    int nombreMembres,
  ) async {
    final CollectionReference<Map<String, dynamic>> votes =
        _collectionSondages.doc(id).collection('votes');
    final List<dynamic> options = donnees['options'] ?? [];
    final List<int> compteurs = [];
    for (int i = 0; i < options.length; i++) {
      final AggregateQuerySnapshot compte =
          await votes.where('choix', isEqualTo: i).count().get();
      compteurs.add(compte.count ?? 0);
    }
    return Sondage.fromMap(
      id,
      donnees,
      votes: compteurs,
      nombreMembres: nombreMembres,
    );
  }

  @override
  Future<Resultat<void>> creerSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
  }) {
    return _executer(() async {
      final String? refus = EvenementRepository.refusSondage(
        question: question,
        options: options,
        dateFin: dateFin,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      final Utilisateur moi = _moi();
      if (!EvenementRepository.peutOrganiser(moi)) {
        throw const RefusM4(EvenementRepository.refusOrganiser);
      }
      final List<OptionSondage> choix = [];
      for (final String texte in options) {
        if (texte.trim().isNotEmpty) {
          choix.add(OptionSondage(texte: texte.trim()));
        }
      }
      final Sondage sondage = Sondage(
        id: '',
        question: question.trim(),
        options: choix,
        dateFin: dateFin,
        proposeParId: moi.id,
        proposePar: EvenementRepository.nomCourt(moi),
      );
      await _collectionSondages.add(sondage.toMap());
    });
  }

  @override
  Future<Resultat<void>> supprimerSondage(String sondageId) {
    return _executer(() async {
      await _collectionSondages.doc(sondageId).delete();
    });
  }

  @override
  Future<Resultat<int?>> getMonVote(String sondageId) {
    return _executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> vote =
          await _collectionSondages
              .doc(sondageId)
              .collection('votes')
              .doc(_moi().id)
              .get();
      if (!vote.exists) {
        return null;
      }
      final Object? choix = vote.data()!['choix'];
      return choix is int ? choix : null;
    });
  }

  @override
  Future<Resultat<void>> voter(Sondage sondage, int choix) {
    return _executer(() async {
      final DocumentReference<Map<String, dynamic>> monVote =
          _collectionSondages.doc(sondage.id).collection('votes').doc(_moi().id);

      int? dejaVote;
      final DocumentSnapshot<Map<String, dynamic>> existant =
          await monVote.get();
      if (existant.exists) {
        dejaVote = existant.data()!['choix'] ?? 0;
      }
      final String? refus = EvenementRepository.refusVote(sondage, choix, dejaVote);
      if (refus != null) {
        throw RefusM4(refus);
      }

      await monVote.set({
        'choix': choix,
        'date': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Stream<List<int>> ecouterVotes(String sondageId, int nbOptions) {
    try {
      // snapshots() : Firestore renvoie la liste à chaque nouveau vote
      return _collectionSondages
          .doc(sondageId)
          .collection('votes')
          .snapshots()
          .map((snapshot) {
        final List<int> compteurs = List.filled(nbOptions, 0);
        for (final document in snapshot.docs) {
          final Object? choix = document.data()['choix'];
          if (choix is int && choix >= 0 && choix < nbOptions) {
            compteurs[choix]++;
          }
        }
        return compteurs;
      }).handleError((Object erreur) {
        // Pas de mise à jour en direct : l'écran garde les derniers nombres
      });
    } catch (erreur) {
      return const Stream.empty(); // pas connecté, Firebase absent...
    }
  }
}
