import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/historique_signalement.dart';
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
  Future<Resultat<int>> compterMesSignalements() async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // count() : Firestore renvoie seulement le nombre (1 lecture facturée
      // par tranche de 1000), pas les documents. Un seul filtre d'égalité :
      // pas besoin d'index composite.
      final AggregateQuerySnapshot resultat = await _signalements
          .where('auteurId', isEqualTo: moi.id)
          .count()
          .get();
      return resultat.count ?? 0;
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
        ) ??
        SignalementRepository.refusPhoto(signalement.photoUrl);
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
    // 1re étape de l'historique : "en attente", par l'auteur
    final EntreeHistorique premiere = EntreeHistorique(
      statut: StatutSignalement.enAttente,
      date: nouveau.date,
      parId: moi.id,
      parNom: nouveau.auteurNom,
    );
    return FirestoreCommun.executer(() async {
      final DocumentReference<Map<String, dynamic>> document;
      if (nouveau.id.isEmpty) {
        document = _signalements.doc(); // id choisi par Firestore
      } else {
        // Id choisi à l'avance (file d'envoi) : déjà créé = déjà envoyé
        document = _signalements.doc(nouveau.id);
        final DocumentSnapshot<Map<String, dynamic>> existant =
            await document.get();
        if (existant.exists) {
          return;
        }
      }
      // Le signalement ET sa 1re entrée d'historique dans le même lot :
      // firestore.rules n'accepte l'entrée que pendant la création
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.set(document, nouveau.toMap());
      batch.set(document.collection('historique').doc(), premiere.toMap());
      await batch.commit();
    });
  }

  @override
  Future<Resultat<List<EntreeHistorique>>> getHistorique(String id) async {
    final String? refus = SignalementRepository.refusUtilisateur(_moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // Un seul champ trié : pas d'index composite
      final QuerySnapshot<Map<String, dynamic>> resultat = await _signalements
          .doc(id)
          .collection('historique')
          .orderBy('date')
          .get();
      final List<EntreeHistorique> entrees = [];
      for (final document in resultat.docs) {
        entrees.add(EntreeHistorique.fromMap(document.id, document.data()));
      }
      return entrees;
    });
  }

  @override
  Future<Resultat<void>> modifierSignalement(Signalement signalement) async {
    final Resultat<Signalement> lecture = await getSignalement(signalement.id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final Signalement actuel = lecture.donnee!;
    final String? refus =
        SignalementRepository.refusModification(actuel, _moi.id) ??
            SignalementRepository.refusSignalement(
              titre: signalement.titre,
              description: signalement.description,
              lieu: signalement.lieu,
              categorieId: signalement.categorieId,
            ) ??
            SignalementRepository.refusPhoto(signalement.photoUrl);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    return FirestoreCommun.executer(() async {
      // Seulement ces champs (firestore.rules : changeSeulement).
      // Un champ réécrit avec la même valeur ne compte pas comme changé :
      // tant que la règle n'accepte pas 'danger', 'position' et 'photoUrl',
      // seul le fait de les CHANGER est refusé.
      final Map<String, dynamic> champs = {
        'titre': signalement.titre.trim(),
        'description': signalement.description.trim(),
        'categorieId': signalement.categorieId,
        'lieu': signalement.lieu.trim(),
        'danger': signalement.danger,
      };
      // Champs optionnels : jamais null dans Firestore. Présent → écrit ;
      // retiré par l'auteur → effacé du document (FieldValue.delete).
      final Map<String, dynamic> nouveau = signalement.toMap();
      if (nouveau.containsKey('position')) {
        champs['position'] = nouveau['position'];
      } else if (actuel.position != null) {
        champs['position'] = FieldValue.delete();
      }
      if (nouveau.containsKey('photoUrl')) {
        champs['photoUrl'] = nouveau['photoUrl'];
      } else if (actuel.photoUrl != null) {
        champs['photoUrl'] = FieldValue.delete();
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
    StatutSignalement statut, {
    String note = '',
  }) async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi) ??
        SignalementRepository.refusChangementStatut(moi) ??
        SignalementRepository.refusNote(statut, note);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Resultat<Signalement> lecture = await getSignalement(id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    if (lecture.donnee!.statut == statut) {
      return const Resultat.succes(null); // rien ne change : pas d'entrée
    }
    final EntreeHistorique entree = EntreeHistorique(
      statut: statut,
      note: note.trim(),
      date: DateTime.now(),
      parId: moi.id,
      parNom: SignalementRepository.nomCourt(moi),
    );
    return FirestoreCommun.executer(() async {
      // Le statut (seul champ changé : firestore.rules) ET l'entrée
      // d'historique, dans le même lot
      final DocumentReference<Map<String, dynamic>> document =
          _signalements.doc(id);
      final WriteBatch batch = FirestoreCommun.base.batch();
      batch.update(document, {'statut': statut.name});
      batch.set(document.collection('historique').doc(), entree.toMap());
      await batch.commit();
    });
  }
}
