import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/evenement.dart';
import '../models/quartier.dart';
import '../models/sondage.dart';
import '../models/utilisateur.dart';
import '../models/vie_evenement.dart';
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
    int placesMax = 0,
    PointGps? position,
    String? photoUrl,
    String? serviceId,
    String? serviceNom,
    String? signalementId,
    String? signalementTitre,
  }) {
    return _executer(() async {
      final String? refus = EvenementRepository.refusEvenement(
            titre: titre,
            description: description,
            lieu: lieu,
            date: date,
            dateFin: dateFin,
          ) ??
          EvenementRepository.refusPlaces(placesMax);
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
        placesMax: placesMax,
        position: position,
        photoUrl: photoUrl,
        serviceId: serviceId,
        serviceNom: serviceNom,
        signalementId: signalementId,
        signalementTitre: signalementTitre,
      );
      await _collectionEvenements.add(evenement.toMap());
    });
  }

  @override
  Future<Resultat<List<Evenement>>> getEvenementsDuSignalement(
    String signalementId,
  ) {
    return _executer(() async {
      // (D3) Un seul filtre d'égalité : pas d'index composite ; le tri par
      // date est fait ici
      final QuerySnapshot<Map<String, dynamic>> resultat =
          await _collectionEvenements
              .where('signalementId', isEqualTo: signalementId)
              .get();
      final List<Evenement> evenements = [];
      for (final document in resultat.docs) {
        evenements.add(Evenement.fromMap(document.id, document.data()));
      }
      evenements.sort((a, b) => a.date.compareTo(b.date));
      return evenements;
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
          ) ??
          EvenementRepository.refusPlaces(evenement.placesMax,
              inscrits: evenement.participants);
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
        'placesMax': evenement.placesMax,
        'position': evenement.position == null
            ? null
            : GeoPoint(evenement.position!.latitude, evenement.position!.longitude),
        'photoUrl': evenement.photoUrl,
        'serviceId': evenement.serviceId,
        'serviceNom': evenement.serviceNom,
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
      // La liste d'attente passe en priorité sur les places libérées
      final List<String> attente = [];
      final QuerySnapshot<Map<String, dynamic>> enAttente =
          await evenement.collection('attente').orderBy('date').get();
      for (final fiche in enAttente.docs) {
        attente.add(fiche.id);
      }
      final String? refus = EvenementRepository.refusParticipation(
        Evenement.fromMap(document.id, document.data()!),
        attente: attente,
        moiId: moi.id,
      );
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
      // J'étais sur la liste d'attente : j'en sors
      if (attente.contains(moi.id)) {
        batch.delete(evenement.collection('attente').doc(moi.id));
      }
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

  @override
  Future<Resultat<bool>> estInteresse(String evenementId) {
    return _executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> fiche =
          await _collectionEvenements
              .doc(evenementId)
              .collection('interesses')
              .doc(_moi().id)
              .get();
      return fiche.exists;
    });
  }

  @override
  Future<Resultat<void>> changerInteret(String evenementId, bool interesse) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final DocumentReference<Map<String, dynamic>> evenement =
          _collectionEvenements.doc(evenementId);
      final DocumentReference<Map<String, dynamic>> maFiche =
          evenement.collection('interesses').doc(moi.id);
      final bool deja = (await maFiche.get()).exists;
      if (deja == interesse) {
        return; // rien à changer
      }
      // Fiche + compteur dans le MÊME WriteBatch (comme les participants)
      final WriteBatch batch = FirestoreCommun.base.batch();
      if (interesse) {
        batch.set(maFiche, {
          'nom': EvenementRepository.nomCourt(moi),
          'date': FieldValue.serverTimestamp(),
        });
        batch.update(evenement, {'nbInteresses': FieldValue.increment(1)});
      } else {
        batch.delete(maFiche);
        batch.update(evenement, {'nbInteresses': FieldValue.increment(-1)});
      }
      await batch.commit();
    });
  }

  // =====================================================================
  // Questions, objets à apporter, avis (sous-collections de l'événement)
  // =====================================================================

  CollectionReference<Map<String, dynamic>> _sous(
      String evenementId, String nom) {
    return _collectionEvenements.doc(evenementId).collection(nom);
  }

  @override
  Future<Resultat<List<Participant>>> getAttente(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _sous(evenementId, 'attente').orderBy('date').get();
      final List<Participant> liste = [];
      for (final document in snapshot.docs) {
        liste.add(Participant(
          id: document.id,
          nom: document.data()['nom'] ?? '',
          avatar: document.data()['avatar'] ?? '',
        ));
      }
      return liste;
    });
  }

  @override
  Future<Resultat<void>> rejoindreAttente(Evenement evenement) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final bool inscrit =
          (await _sous(evenement.id, 'participants').doc(moi.id).get()).exists;
      final bool deja =
          (await _sous(evenement.id, 'attente').doc(moi.id).get()).exists;
      final String? refus = EvenementRepository.refusAttente(
        evenement,
        inscrit: inscrit,
        dejaEnAttente: deja,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      await _sous(evenement.id, 'attente').doc(moi.id).set({
        'nom': EvenementRepository.nomCourt(moi),
        'avatar': moi.avatar,
        'date': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Resultat<void>> quitterAttente(String evenementId) {
    return _executer(() async {
      await _sous(evenementId, 'attente').doc(_moi().id).delete();
    });
  }

  @override
  Future<Resultat<List<Commentaire>>> getCommentaires(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _sous(evenementId, 'commentaires').orderBy('date').get();
      final List<Commentaire> liste = [];
      for (final document in snapshot.docs) {
        liste.add(Commentaire.fromMap(document.id, document.data()));
      }
      return liste;
    });
  }

  @override
  Future<Resultat<void>> ajouterCommentaire(String evenementId, String texte) {
    return _executer(() async {
      final String? refus = EvenementRepository.refusCommentaire(texte);
      if (refus != null) {
        throw RefusM4(refus);
      }
      final Utilisateur moi = _moi();
      final Commentaire commentaire = Commentaire(
        id: '',
        auteurId: moi.id,
        auteurNom: EvenementRepository.nomCourt(moi),
        texte: texte.trim(),
        date: DateTime.now(),
      );
      await _sous(evenementId, 'commentaires').add(commentaire.toMap());
    });
  }

  @override
  Future<Resultat<void>> supprimerCommentaire(
      String evenementId, String commentaireId) {
    return _executer(() async {
      await _sous(evenementId, 'commentaires').doc(commentaireId).delete();
    });
  }

  @override
  Future<Resultat<List<ObjetAApporter>>> getObjets(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _sous(evenementId, 'aApporter').get();
      final List<ObjetAApporter> liste = [];
      for (final document in snapshot.docs) {
        liste.add(ObjetAApporter.fromMap(document.id, document.data()));
      }
      liste.sort((a, b) => a.objet.compareTo(b.objet));
      return liste;
    });
  }

  @override
  Future<Resultat<void>> ajouterObjet(Evenement evenement, String objet) {
    return _executer(() async {
      if (!EvenementRepository.peutModifier(_moi(), evenement)) {
        throw const RefusM4('Seul l\'organisateur ou l\'admin gère la liste');
      }
      final String? refus = EvenementRepository.refusObjet(objet);
      if (refus != null) {
        throw RefusM4(refus);
      }
      await _sous(evenement.id, 'aApporter')
          .add(ObjetAApporter(id: '', objet: objet.trim()).toMap());
    });
  }

  @override
  Future<Resultat<void>> supprimerObjet(Evenement evenement, String objetId) {
    return _executer(() async {
      if (!EvenementRepository.peutModifier(_moi(), evenement)) {
        throw const RefusM4('Seul l\'organisateur ou l\'admin gère la liste');
      }
      await _sous(evenement.id, 'aApporter').doc(objetId).delete();
    });
  }

  @override
  Future<Resultat<void>> prendreObjet(
      String evenementId, ObjetAApporter objet, bool prendre) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      if (prendre && objet.estPris && objet.prisParId != moi.id) {
        throw RefusM4('${objet.prisParNom} s\'en charge déjà');
      }
      // Les règles : avant et après, c'est "personne" ou "moi"
      await _sous(evenementId, 'aApporter').doc(objet.id).update({
        'prisParId': prendre ? moi.id : null,
        'prisParNom': prendre ? EvenementRepository.nomCourt(moi) : '',
      });
    });
  }

  @override
  Future<Resultat<List<AvisEvenement>>> getAvis(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _sous(evenementId, 'avis').get();
      final List<AvisEvenement> liste = [];
      for (final document in snapshot.docs) {
        liste.add(AvisEvenement.fromMap(document.id, document.data()));
      }
      return liste;
    });
  }

  @override
  Future<Resultat<void>> donnerAvis(
      Evenement evenement, int note, String commentaire) {
    return _executer(() async {
      final Utilisateur moi = _moi();
      final bool participe = (await _sous(evenement.id, 'participants')
              .doc(moi.id)
              .get())
          .exists;
      final bool deja =
          (await _sous(evenement.id, 'avis').doc(moi.id).get()).exists;
      final String? refus = EvenementRepository.refusAvis(
        evenement,
        note,
        participe: participe,
        dejaDonne: deja,
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      final AvisEvenement avis = AvisEvenement(
        id: moi.id,
        nom: EvenementRepository.nomCourt(moi),
        note: note,
        commentaire: commentaire.trim(),
      );
      await _sous(evenement.id, 'avis').doc(moi.id).set(avis.toMap());
    });
  }

  // ----- Présence par QR code (A21) -----

  /// Un code au hasard, difficile à deviner (10 lettres et chiffres).
  String _nouveauCode() {
    const String lettres = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final Random hasard = Random.secure();
    String code = '';
    for (int i = 0; i < 10; i++) {
      code = code + lettres[hasard.nextInt(lettres.length)];
    }
    return code;
  }

  @override
  Future<Resultat<String>> getCodePresence(Evenement evenement) {
    return _executer(() async {
      // prive/presence : lisible seulement par l'organisateur et l'admin
      final DocumentReference<Map<String, dynamic>> document =
          _sous(evenement.id, 'prive').doc('presence');
      final DocumentSnapshot<Map<String, dynamic>> lu = await document.get();
      final String? existant = lu.data()?['code'] as String?;
      if (existant != null && existant.isNotEmpty) {
        return existant;
      }
      final String code = _nouveauCode();
      await document.set({'code': code});
      return code;
    });
  }

  @override
  Future<Resultat<void>> marquerPresent(Evenement evenement, String texteQr) {
    return _executer(() async {
      final List<String>? qr = EvenementRepository.lireQrPresence(texteQr);
      if (qr == null) {
        throw const RefusM4('Ce QR code n\'est pas un QR de présence Houmani');
      }
      final Utilisateur moi = _moi();
      final bool participe = (await _sous(evenement.id, 'participants')
              .doc(moi.id)
              .get())
          .exists;
      final bool deja =
          (await _sous(evenement.id, 'presences').doc(moi.id).get()).exists;
      final String? refus = EvenementRepository.refusPresence(
        evenement,
        qr[0],
        participe: participe,
        dejaPresent: deja,
        maintenant: DateTime.now(),
      );
      if (refus != null) {
        throw RefusM4(refus);
      }
      // Les règles comparent ce code avec le code secret de l'événement
      try {
        await _sous(evenement.id, 'presences').doc(moi.id).set({
          'code': qr[1],
          'nom': EvenementRepository.nomCourt(moi),
          'date': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw const RefusM4('Ce QR code n\'est plus valable');
        }
        rethrow;
      }
    });
  }

  @override
  Future<Resultat<bool>> estPresent(String evenementId) {
    return _executer(() async {
      return (await _sous(evenementId, 'presences').doc(_moi().id).get())
          .exists;
    });
  }

  @override
  Future<Resultat<List<String>>> getPresents(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _sous(evenementId, 'presences').get();
      final List<String> ids = [];
      for (final document in snapshot.docs) {
        ids.add(document.id);
      }
      return ids;
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
    // Vote secret : on ne lit pas les votes (interdit), seulement les
    // compteurs compteurs/{index} = {n}, tenus à jour avec chaque vote
    final List<dynamic> options = donnees['options'] ?? [];
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _collectionSondages.doc(id).collection('compteurs').get();
    final List<int> compteurs = _lireCompteurs(snapshot, options.length);
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
    List<DateTime> dates = const [],
    String? evenementId,
  }) {
    return _executer(() async {
      // Sondage de date : les choix sont les dates
      if (dates.isNotEmpty) {
        options = EvenementRepository.textesDates(dates);
      }
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
        dates: dates,
        evenementId: evenementId,
      );
      await _collectionSondages.add(sondage.toMap());
    });
  }

  @override
  Future<Resultat<List<Sondage>>> chargerSondagesDe(String evenementId) {
    return _executer(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _collectionSondages
          .where('evenementId', isEqualTo: evenementId)
          .get();
      final Resultat<int> membres = await UtilisateurRepository()
          .compterMembres(StatutUtilisateur.actif);
      final List<Sondage> liste = [];
      for (final document in snapshot.docs) {
        liste.add(await _avecVotes(
            document.id, document.data(), membres.donnee ?? 0));
      }
      return liste;
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

      // Mon vote (secret) + le compteur de mon choix, dans le MÊME WriteBatch
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(monVote, {
        'choix': choix,
        'date': FieldValue.serverTimestamp(),
      });
      batch.set(
        _collectionSondages.doc(sondage.id).collection('compteurs').doc('$choix'),
        {'n': FieldValue.increment(1)},
        SetOptions(merge: true), // crée le compteur s'il n'existe pas encore
      );
      await batch.commit();
    });
  }

  /// compteurs/{index} = {n} → la liste des votes de chaque option.
  List<int> _lireCompteurs(
      QuerySnapshot<Map<String, dynamic>> snapshot, int nbOptions) {
    final List<int> compteurs = List.filled(nbOptions, 0);
    for (final document in snapshot.docs) {
      final int? index = int.tryParse(document.id);
      final Object? n = document.data()['n'];
      if (index != null && index >= 0 && index < nbOptions && n is int) {
        compteurs[index] = n;
      }
    }
    return compteurs;
  }

  @override
  Stream<List<int>> ecouterVotes(String sondageId, int nbOptions) {
    try {
      // snapshots() des compteurs : Firestore renvoie les nombres à chaque
      // nouveau vote (les votes eux-mêmes restent secrets)
      return _collectionSondages
          .doc(sondageId)
          .collection('compteurs')
          .snapshots()
          .map((snapshot) {
        return _lireCompteurs(snapshot, nbOptions);
      }).handleError((Object erreur) {
        // Pas de mise à jour en direct : l'écran garde les derniers nombres
      });
    } catch (erreur) {
      return const Stream.empty(); // pas connecté, Firebase absent...
    }
  }
}
