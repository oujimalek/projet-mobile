import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/signalement.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firestore_commun.dart';
import 'signalement_repository.dart';
import 'utilisateur_repository.dart';

/// M3 - Version Cloud Firestore de SignalementRepository (celle de l'application).
///
/// Écrit UNIQUEMENT dans quartiers/{q}/signalements et sa sous-collection
/// confirmations. Chaque écriture respecte firestore.rules (bloc
/// "M3 · Signalements") :
/// - créer : auteurId = mon uid, statut "enAttente", nbConfirmations = 0 ;
/// - l'auteur modifie seulement titre, description, categorieId, lieu,
///   tant que le statut est "enAttente" ;
/// - l'admin modifie seulement le statut ;
/// - confirmer : ma fiche confirmations/{monUid} ET nbConfirmations + 1,
///   dans le même WriteBatch.
class FirebaseSignalementRepository implements SignalementRepository {
  /// L'utilisateur connecté, tel que le module 1 le garde en mémoire.
  Utilisateur get _moi {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// quartiers/{quartierId}/signalements pour le quartier de l'utilisateur.
  CollectionReference<Map<String, dynamic>> get _signalements {
    return FirestoreCommun.collectionDuQuartier(
      _moi.quartierId ?? '',
      'signalements',
    );
  }

  /// quartiers/{q}/signalements/{id}/confirmations
  CollectionReference<Map<String, dynamic>> _confirmations(String id) {
    return _signalements.doc(id).collection('confirmations');
  }

  /// Transforme le résultat d'une requête en liste de signalements.
  List<Signalement> _lireListe(QuerySnapshot<Map<String, dynamic>> resultat) {
    final List<Signalement> liste = [];
    for (final document in resultat.docs) {
      liste.add(Signalement.fromMap(document.id, document.data()));
    }
    return liste;
  }

  // =====================================================================
  // Lecture
  // =====================================================================

  @override
  Future<Resultat<List<Signalement>>> getSignalements({
    StatutSignalement? statut,
    String? categorieId,
  }) async {
    final String? refus = SignalementRepository.refusUtilisateur(_moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      Query<Map<String, dynamic>> requete = _signalements;
      if (statut != null) {
        // Index composite statut ↑ + date ↓ (firestore.indexes.json)
        requete = requete.where('statut', isEqualTo: statut.name);
      }
      requete = requete.orderBy('date', descending: true);
      final QuerySnapshot<Map<String, dynamic>> resultat = await requete.get();
      // Filtre catégorie fait ici, en Dart : pas besoin d'un index de plus
      return SignalementRepository.filtrerParCategorie(
        _lireListe(resultat),
        categorieId,
      );
    });
  }

  @override
  Future<Resultat<List<Signalement>>> getMesSignalements() async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // Index composite auteurId ↑ + date ↓ (à ajouter dans firestore.indexes.json)
      final QuerySnapshot<Map<String, dynamic>> resultat = await _signalements
          .where('auteurId', isEqualTo: moi.id)
          .orderBy('date', descending: true)
          .get();
      return _lireListe(resultat);
    });
  }

  @override
  Future<Resultat<Signalement>> getSignalement(String id) async {
    final String? refus = SignalementRepository.refusUtilisateur(_moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Resultat<DocumentSnapshot<Map<String, dynamic>>> lecture =
        await FirestoreCommun.executer(() {
      return _signalements.doc(id).get();
    });
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final DocumentSnapshot<Map<String, dynamic>> document = lecture.donnee!;
    final Map<String, dynamic>? donnees = document.data();
    if (!document.exists || donnees == null) {
      return const Resultat.echec('Ce signalement n\'existe plus');
    }
    return Resultat.succes(Signalement.fromMap(document.id, donnees));
  }

  @override
  Future<Resultat<bool>> aConfirme(String id) async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> fiche =
          await _confirmations(id).doc(moi.id).get();
      return fiche.exists;
    });
  }

  // =====================================================================
  // Écriture
  // =====================================================================

  @override
  Future<Resultat<void>> ajouterSignalement(Signalement signalement) async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi) ??
        SignalementRepository.refusSignalement(
          titre: signalement.titre,
          description: signalement.description,
          lieu: signalement.lieu,
          categorieId: signalement.categorieId,
        );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Ce que firestore.rules exige à la création
    final Signalement nouveau = signalement.copyWith(
      titre: signalement.titre.trim(),
      description: signalement.description.trim(),
      lieu: signalement.lieu.trim(),
      auteurId: moi.id,
      auteurNom: SignalementRepository.nomCourt(moi),
      statut: StatutSignalement.enAttente,
      nbConfirmations: 0,
      date: DateTime.now(),
    );
    return FirestoreCommun.executer(() async {
      if (nouveau.id.isEmpty) {
        await _signalements.add(nouveau.toMap());
        return;
      }
      // Id choisi à l'avance (file d'envoi) : déjà créé = déjà envoyé
      final DocumentReference<Map<String, dynamic>> document =
          _signalements.doc(nouveau.id);
      final DocumentSnapshot<Map<String, dynamic>> existant =
          await document.get();
      if (existant.exists) {
        return;
      }
      await document.set(nouveau.toMap());
    });
  }

  @override
  Future<Resultat<void>> modifierSignalement(Signalement signalement) async {
    final Resultat<Signalement> lecture = await getSignalement(signalement.id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final String? refus = SignalementRepository.refusModification(
          lecture.donnee!,
          _moi.id,
        ) ??
        SignalementRepository.refusSignalement(
          titre: signalement.titre,
          description: signalement.description,
          lieu: signalement.lieu,
          categorieId: signalement.categorieId,
        );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // Seulement ces champs (firestore.rules : changeSeulement).
      // Un champ réécrit avec la même valeur ne compte pas comme changé :
      // tant que la règle n'accepte pas 'danger' et 'position', seul le
      // fait de les CHANGER est refusé.
      final Map<String, dynamic> champs = {
        'titre': signalement.titre.trim(),
        'description': signalement.description.trim(),
        'categorieId': signalement.categorieId,
        'lieu': signalement.lieu.trim(),
        'danger': signalement.danger,
      };
      // position : écrite seulement si elle existe (jamais null dans Firestore)
      final Object? position = signalement.toMap()['position'];
      if (position != null) {
        champs['position'] = position;
      }
      await _signalements.doc(signalement.id).update(champs);
    });
  }

  @override
  Future<Resultat<void>> supprimerSignalement(String id) async {
    final Resultat<Signalement> lecture = await getSignalement(id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final String? refus =
        SignalementRepository.refusSuppression(lecture.donnee!, _moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      await _signalements.doc(id).delete();
    });
  }

  @override
  Future<Resultat<void>> confirmer(String id) async {
    final Utilisateur moi = _moi;
    // 1) On lit le signalement (auteur, statut)
    final Resultat<Signalement> lecture = await getSignalement(id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final Signalement signalement = lecture.donnee!;
    // 2) Ai-je déjà confirmé ?
    final Resultat<bool> deja = await aConfirme(id);
    if (!deja.estSucces) {
      return Resultat.echec(deja.erreur!);
    }
    final String? refus = SignalementRepository.refusConfirmation(
      signalement,
      moi.id,
      deja.donnee!,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // 3) Ma fiche ET le compteur + 1, dans le même WriteBatch :
    //    firestore.rules refuse l'un sans l'autre.
    //    FieldValue.increment(1) : le serveur ajoute 1 à la valeur ACTUELLE,
    //    donc deux voisins qui confirment en même temps ne se gênent pas.
    return FirestoreCommun.executer(() async {
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(_confirmations(id).doc(moi.id), {'date': DateTime.now()});
      batch.update(_signalements.doc(id), {
        'nbConfirmations': FieldValue.increment(1),
      });
      await batch.commit();
    });
  }

  @override
  Future<Resultat<void>> changerStatut(
    String id,
    StatutSignalement statut,
  ) async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi) ??
        SignalementRepository.refusChangementStatut(moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // Seulement le statut (firestore.rules : changeSeulement)
      await _signalements.doc(id).update({'statut': statut.name});
    });
  }
}
