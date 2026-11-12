import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/signalement.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'base_locale_m3.dart';
import 'connexion_m3.dart';
import 'firestore_commun.dart';
import 'photos_m3.dart';
import 'signalement_repository.dart';
import 'utilisateur_repository.dart';

/// Ce qu'est devenu un signalement publié.
enum EtatPublicationM3 {
  envoye, // il est dans Firestore
  misEnFile, // pas de réseau : gardé dans SQLite, envoyé plus tard
  doublonConfirme, // pas publié : j'ai confirmé le signalement similaire
  doublonOuvert, // pas publié : le signalement similaire est ouvert
}

/// Une liste de signalements, et d'où elle vient.
class ListeSignalementsM3 {
  final List<Signalement> signalements;
  final bool depuisCache; // true = lue dans SQLite (pas Firestore)
  final bool horsLigne; // true = pas de réseau
  final DateTime? miseAJour; // dernier chargement complet (cache)

  const ListeSignalementsM3({
    required this.signalements,
    this.depuisCache = false,
    this.horsLigne = false,
    this.miseAJour,
  });
}

/// Un signalement lu, et d'où il vient.
class SignalementLuM3 {
  final Signalement signalement;
  final bool depuisCache;

  const SignalementLuM3(this.signalement, {this.depuisCache = false});
}

/// M3 - Le chef d'orchestre en ligne / hors ligne.
///
/// Les écrans lui demandent de publier ou de charger ; LUI décide :
///   - en ligne  → SignalementRepository (Firestore), puis copie dans SQLite ;
///   - hors ligne → SQLite (BaseLocaleM3) : file d'envoi, cache, brouillon.
///
/// Envoi automatique de la file : au démarrage ([demarrer]) et à chaque
/// retour du réseau (écoute de ConnexionM3).
///
/// Aucune erreur SQLite ne remonte aux écrans : sans base locale,
/// l'application marche comme avant (en ligne seulement).
class SyncSignalementsM3 {
  /// L'instance utilisée par l'application (les tests en mettent une neuve).
  static SyncSignalementsM3 instance = SyncSignalementsM3();

  /// Délai maximum d'un appel réseau : le Wi-Fi peut être actif sans
  /// Internet, et Firestore attendrait alors sans fin.
  static Duration delaiReseau = const Duration(seconds: 15);

  /// Au-delà de ce nombre d'échecs, plus d'envoi automatique : seulement
  /// le bouton "Réessayer".
  static const int maxTentativesAuto = 3;

  static const String messageDelai =
      'Le réseau ne répond pas : le signalement sera envoyé plus tard';
  static const String messageHorsLigne = 'Pas de connexion Internet';

  /// +1 à chaque changement de la file d'envoi : la liste l'écoute pour
  /// se mettre à jour (ex : envoi automatique au retour du réseau).
  final ValueNotifier<int> changements = ValueNotifier<int>(0);

  StreamSubscription<bool>? _abonnement;
  bool _envoiEnCours = false; // évite deux envois de la file en même temps

  SignalementRepository get _repository => SignalementRepository();
  BaseLocaleM3 get _base => BaseLocaleM3.instance;
  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  /// Le réseau est-il là ?
  Future<bool> estEnLigne() {
    return ConnexionM3().estEnLigne();
  }

  /// Écoute le réseau et envoie la file au retour. Peut être appelé
  /// plusieurs fois (une seule écoute).
  void demarrer() {
    if (_abonnement != null) {
      return;
    }
    _abonnement = ConnexionM3().ecouter().listen((enLigne) {
      if (enLigne) {
        envoyerFile();
      }
    });
    envoyerFile();
    nettoyerPhotos();
  }

  /// Supprime les photos locales que plus rien n'utilise (ni brouillon, ni
  /// file d'envoi) : ex. l'application fermée au mauvais moment.
  Future<int> nettoyerPhotos() async {
    try {
      return await PhotosM3.nettoyer(await _base.cheminsPhotosUtilises());
    } catch (e) {
      return 0; // base locale indisponible : on ne supprime rien
    }
  }

  /// Arrête l'écoute (tests).
  Future<void> arreter() async {
    await _abonnement?.cancel();
    _abonnement = null;
  }

  /// Un id de document comme ceux de Firestore (20 lettres et chiffres),
  /// choisi sur le téléphone avant l'envoi.
  static String nouvelIdDocument() {
    const String lettres =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final Random hasard = Random.secure();
    String id = '';
    for (int i = 0; i < 20; i++) {
      id += lettres[hasard.nextInt(lettres.length)];
    }
    return id;
  }

  /// Erreur due au réseau (on garde dans la file) ou refus définitif
  /// (droits, formulaire : on affiche l'erreur) ?
  static bool estErreurReseau(String? erreur) {
    return erreur == messageDelai ||
        erreur == messageHorsLigne ||
        erreur == PhotosM3.messageReseau ||
        erreur == FirestoreCommun.messageErreur('unavailable') ||
        erreur == FirestoreCommun.messageErreur('deadline-exceeded');
  }

  /// Un appel réseau avec un délai maximum.
  Future<Resultat<T>> _avecDelai<T>(Future<Resultat<T>> appel) {
    return appel.timeout(
      delaiReseau,
      onTimeout: () => Resultat<T>.echec(messageDelai),
    );
  }

  void _prevenir() {
    changements.value++;
  }

  // =====================================================================
  // Publier
  // =====================================================================

  /// Publie un signalement, avec une photo locale optionnelle
  /// ([photoLocale], déjà copiée par PhotosM3.garderSurTelephone) :
  ///   - formulaire ou compte refusé → échec (message) ;
  ///   - hors ligne → file SQLite (avec le chemin de la photo), sans appeler
  ///     Firestore ni Cloudinary ;
  ///   - en ligne → photo sur Cloudinary, puis Firestore ; si le réseau
  ///     lâche à l'une des deux étapes → file (la photo déjà envoyée n'est
  ///     pas renvoyée).
  Future<Resultat<EtatPublicationM3>> publier(
    Signalement saisi, {
    String? photoLocale,
  }) async {
    final Utilisateur moi = _moi;
    final String? refus = SignalementRepository.refusUtilisateur(moi) ??
        SignalementRepository.refusSignalement(
          titre: saisi.titre,
          description: saisi.description,
          lieu: saisi.lieu,
          categorieId: saisi.categorieId,
        );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // L'id est choisi MAINTENANT : un renvoi ne fera jamais de doublon
    Signalement signalement = saisi.copyWith(
      id: saisi.id.isEmpty ? nouvelIdDocument() : saisi.id,
    );

    if (!await estEnLigne()) {
      return _mettreEnFile(signalement, moi, null, photoLocale);
    }

    // 1) La photo d'abord : Firestore ne garde que son adresse
    if (photoLocale != null) {
      final Resultat<String> photo = await PhotosM3.envoyerFichier(photoLocale);
      if (!photo.estSucces) {
        if (estErreurReseau(photo.erreur)) {
          return _mettreEnFile(signalement, moi, photo.erreur, photoLocale);
        }
        return Resultat.echec(photo.erreur!); // trop lourde, refusée...
      }
      signalement = signalement.copyWith(photoUrl: photo.donnee);
    }

    // 2) Le signalement
    final Resultat<void> envoi =
        await _avecDelai(_repository.ajouterSignalement(signalement));
    if (envoi.estSucces) {
      await PhotosM3.supprimerLocale(photoLocale); // envoyée : plus utile
      return const Resultat.succes(EtatPublicationM3.envoye);
    }
    if (estErreurReseau(envoi.erreur)) {
      return _mettreEnFile(signalement, moi, envoi.erreur, photoLocale);
    }
    return Resultat.echec(envoi.erreur!);
  }

  /// Garde le signalement dans la file SQLite. Si la photo est déjà sur
  /// Cloudinary, son adresse est gardée aussi (`signalement.photoUrl`).
  Future<Resultat<EtatPublicationM3>> _mettreEnFile(
    Signalement signalement,
    Utilisateur moi,
    String? erreur,
    String? photoLocale,
  ) async {
    try {
      await _base.ajouterEnvoi(EnvoiEnAttente(
        idDocument: signalement.id,
        utilisateurId: moi.id,
        quartierId: moi.quartierId!,
        titre: signalement.titre.trim(),
        description: signalement.description.trim(),
        categorieId: signalement.categorieId,
        lieu: signalement.lieu.trim(),
        danger: signalement.danger,
        position: signalement.position, // le point GPS est gardé hors ligne
        photoLocale: photoLocale,
        photoUrl: signalement.photoUrl,
        dateCreation: DateTime.now(),
        derniereErreur: erreur,
      ));
    } catch (e) {
      return const Resultat.echec(
        'Pas de connexion, et impossible de garder le signalement sur le téléphone',
      );
    }
    _prevenir();
    return const Resultat.succes(EtatPublicationM3.misEnFile);
  }

  // =====================================================================
  // File d'envoi
  // =====================================================================

  /// Mes envois en attente (liste vide si la base locale est indisponible).
  Future<List<EnvoiEnAttente>> getEnvois() async {
    try {
      return await _base.lireEnvois(_moi.id);
    } catch (e) {
      return [];
    }
  }

  /// Envoie toute ma file (démarrage, Accueil, retour du réseau). Renvoie le
  /// nombre de signalements envoyés.
  ///
  /// Appels simultanés (main.dart + Accueil + réseau qui revient) : le
  /// verrou [_envoiEnCours] est testé PUIS pris avant le premier `await`.
  /// Dart exécute ce code sur un seul fil : rien ne peut se glisser entre
  /// les deux, donc le second appel repart aussitôt (0) et rien n'est
  /// envoyé deux fois.
  Future<int> envoyerFile() async {
    if (_envoiEnCours) {
      return 0;
    }
    _envoiEnCours = true;
    int envoyes = 0;
    bool aChange = false; // la file a-t-elle changé (envoyé ou échec noté) ?
    try {
      if (!await estEnLigne()) {
        return 0;
      }
      final Utilisateur moi = _moi;
      for (final EnvoiEnAttente envoi in await getEnvois()) {
        // Trop d'échecs : on attend que l'utilisateur appuie sur "Réessayer"
        if (envoi.estEnEchec && envoi.nbTentatives >= maxTentativesAuto) {
          continue;
        }
        // Créé dans un autre quartier : les règles le refuseraient
        if (envoi.quartierId != moi.quartierId) {
          continue;
        }
        final Resultat<void> resultat = await _envoyer(envoi);
        aChange = true;
        if (resultat.estSucces) {
          envoyes++;
        } else if (resultat.erreur == messageDelai) {
          break; // le réseau ne répond pas : inutile d'essayer les suivants
        }
      }
    } catch (e) {
      // base locale indisponible : rien à envoyer
    } finally {
      _envoiEnCours = false;
    }
    if (aChange) {
      _prevenir();
    }
    return envoyes;
  }

  /// Envoie UN envoi : succès → retiré de la file ; échec → +1 essai.
  ///   1. la photo, si elle n'est pas encore sur Cloudinary (son adresse
  ///      est alors notée dans la file : jamais envoyée deux fois) ;
  ///   2. le signalement.
  /// Photo supprimée du téléphone entre-temps : le signalement part sans
  /// photo (le problème signalé compte plus que l'image).
  Future<Resultat<void>> _envoyer(EnvoiEnAttente envoi) async {
    Signalement signalement = envoi.versSignalement();
    final String? photoLocale = envoi.photoLocale;
    if (envoi.photoUrl == null && photoLocale != null) {
      final Resultat<String> photo = await PhotosM3.envoyerFichier(photoLocale);
      if (photo.estSucces) {
        await _base.enregistrerPhotoEnvoyee(envoi.id!, photo.donnee!);
        signalement = signalement.copyWith(photoUrl: photo.donnee);
      } else if (photo.erreur != PhotosM3.messageIntrouvable) {
        await _base.marquerEchec(envoi.id!, photo.erreur!);
        return Resultat.echec(photo.erreur!);
      }
    }

    final Resultat<void> resultat =
        await _avecDelai(_repository.ajouterSignalement(signalement));
    if (resultat.estSucces) {
      await _base.supprimerEnvoi(envoi.id!);
      await PhotosM3.supprimerLocale(photoLocale);
    } else {
      await _base.marquerEchec(envoi.id!, resultat.erreur!);
    }
    return resultat;
  }

  static const String messageEnvoiEnCours =
      'Envoi déjà en cours, réessaie dans un instant';

  /// Bouton "Réessayer" d'un envoi. Même verrou que [envoyerFile] : un
  /// envoi n'est jamais traité deux fois en même temps (sinon sa photo
  /// pourrait partir deux fois sur Cloudinary).
  Future<Resultat<void>> reessayer(int id) async {
    if (_envoiEnCours) {
      return const Resultat.echec(messageEnvoiEnCours);
    }
    _envoiEnCours = true; // pris AVANT le premier await
    try {
      if (!await estEnLigne()) {
        return const Resultat.echec(messageHorsLigne);
      }
      final EnvoiEnAttente? envoi = await _base.lireEnvoi(id);
      if (envoi == null) {
        return const Resultat.succes(null); // déjà envoyé entre-temps
      }
      final Resultat<void> resultat = await _envoyer(envoi);
      _prevenir();
      return resultat;
    } catch (e) {
      return const Resultat.echec('Base locale indisponible');
    } finally {
      _envoiEnCours = false;
    }
  }

  /// Bouton "Annuler" : le signalement ne sera jamais envoyé (sa photo
  /// locale est supprimée aussi).
  Future<void> annuler(int id) async {
    try {
      final EnvoiEnAttente? envoi = await _base.lireEnvoi(id);
      await _base.supprimerEnvoi(id);
      await PhotosM3.supprimerLocale(envoi?.photoLocale);
    } catch (e) {
      // rien à annuler
    }
    _prevenir();
  }

  // =====================================================================
  // Lecture avec cache
  // =====================================================================

  /// La liste : Firestore si possible (puis copie dans SQLite), sinon le
  /// cache SQLite avec les mêmes filtres, en SQL.
  Future<Resultat<ListeSignalementsM3>> chargerSignalements({
    StatutSignalement? statut,
    String? categorieId,
    bool mesSignalements = false,
  }) async {
    final Utilisateur moi = _moi;
    final String quartierId = moi.quartierId ?? '';
    final bool enLigne = await estEnLigne();
    String? erreur;

    if (enLigne) {
      final Resultat<List<Signalement>> resultat = await _avecDelai(
        mesSignalements
            ? _repository.getMesSignalements()
            : _repository.getSignalements(
                statut: statut,
                categorieId: categorieId,
              ),
      );
      if (resultat.estSucces) {
        List<Signalement> liste = resultat.donnee!;
        await _copierDansCache(
          quartierId,
          liste,
          complet: !mesSignalements && statut == null && categorieId == null,
        );
        if (mesSignalements) {
          // "Mes signalements" : les filtres sont appliqués ici
          if (statut != null) {
            liste = liste.where((s) => s.statut == statut).toList();
          }
          liste = SignalementRepository.filtrerParCategorie(liste, categorieId);
        }
        return Resultat.succes(ListeSignalementsM3(signalements: liste));
      }
      erreur = resultat.erreur;
    }

    // Hors ligne, ou Firestore en échec : le cache SQLite
    try {
      final DateTime? miseAJour = await _base.dateMiseAJour(quartierId);
      final List<Signalement> liste = await _base.lireCache(
        quartierId,
        statut: statut,
        categorieId: categorieId,
        auteurId: mesSignalements ? moi.id : null,
      );
      if (miseAJour != null || liste.isNotEmpty || !enLigne) {
        return Resultat.succes(ListeSignalementsM3(
          signalements: liste,
          depuisCache: true,
          horsLigne: !enLigne,
          miseAJour: miseAJour,
        ));
      }
    } catch (e) {
      // pas de base locale
    }
    return Resultat.echec(erreur ?? messageHorsLigne);
  }

  Future<void> _copierDansCache(
    String quartierId,
    List<Signalement> liste, {
    required bool complet,
  }) async {
    try {
      if (complet) {
        await _base.remplacerCache(quartierId, liste, DateTime.now());
      } else {
        await _base.mettreAJourCache(quartierId, liste);
      }
    } catch (e) {
      // pas de cache : tant pis, la liste s'affiche quand même
    }
  }

  /// Un signalement : Firestore si possible, sinon le cache.
  Future<Resultat<SignalementLuM3>> lireSignalement(String id) async {
    final String quartierId = _moi.quartierId ?? '';
    String? erreur;
    if (await estEnLigne()) {
      final Resultat<Signalement> resultat =
          await _avecDelai(_repository.getSignalement(id));
      if (resultat.estSucces) {
        await _copierDansCache(quartierId, [resultat.donnee!], complet: false);
        return Resultat.succes(SignalementLuM3(resultat.donnee!));
      }
      if (!estErreurReseau(resultat.erreur)) {
        return Resultat.echec(resultat.erreur!); // ex : supprimé
      }
      erreur = resultat.erreur;
    }
    try {
      final Signalement? enCache = await _base.lireDuCache(quartierId, id);
      if (enCache != null) {
        return Resultat.succes(SignalementLuM3(enCache, depuisCache: true));
      }
    } catch (e) {
      // pas de base locale
    }
    return Resultat.echec(erreur ?? messageHorsLigne);
  }

  /// Le nombre de MES signalements (statistique du Profil) :
  ///   - en ligne : Firestore count() ;
  ///   - hors ligne (ou Firestore en échec) : le cache SQLite ;
  ///   - + mes signalements encore dans la file d'envoi (ils sont à moi,
  ///     même s'ils ne sont pas encore partis).
  /// null : impossible à savoir (ni réseau, ni cache).
  Future<int?> compterMesSignalements() async {
    final Utilisateur moi = _moi;
    int? publies;
    if (await estEnLigne()) {
      final Resultat<int> resultat =
          await _avecDelai(_repository.compterMesSignalements());
      publies = resultat.donnee;
    }
    if (publies == null) {
      try {
        if (await _base.dateMiseAJour(moi.quartierId ?? '') != null) {
          publies = (await _base.lireCache(
            moi.quartierId ?? '',
            auteurId: moi.id,
          ))
              .length;
        }
      } catch (e) {
        // pas de cache
      }
    }
    if (publies == null) {
      return null;
    }
    return publies + (await getEnvois()).length;
  }

  /// Anti-doublon : cherche dans le cache SQLite (rempli par la liste) un
  /// signalement ouvert de la même catégorie, des dernières 24 h, à 100 m.
  /// Aucune requête Firestore (donc pas de nouvel index), marche hors ligne.
  Future<DoublonPossible?> chercherDoublon(Signalement nouveau) async {
    if (nouveau.position == null) {
      return null;
    }
    try {
      final List<Signalement> memeCategorie = await _base.lireCache(
        _moi.quartierId ?? '',
        categorieId: nouveau.categorieId,
      );
      return SignalementRepository.doublonProbable(
        nouveau,
        memeCategorie,
        DateTime.now(),
      );
    } catch (e) {
      return null; // pas de cache : on publie sans vérifier
    }
  }

  /// Après une suppression : le signalement quitte aussi le cache.
  Future<void> oublier(String id) async {
    try {
      await _base.supprimerDuCache(_moi.quartierId ?? '', id);
    } catch (e) {
      // pas de cache
    }
  }

  // =====================================================================
  // Brouillon
  // =====================================================================

  Future<Brouillon?> lireBrouillon() async {
    try {
      return await _base.lireBrouillon(_moi.id);
    } catch (e) {
      return null;
    }
  }

  /// Enregistre le brouillon (ou l'efface s'il est vide). Si l'ancien
  /// brouillon avait une AUTRE photo, elle ne sert plus : supprimée.
  Future<void> enregistrerBrouillon(Brouillon brouillon) async {
    try {
      final Brouillon? ancien =
          await _base.lireBrouillon(brouillon.utilisateurId);
      if (brouillon.estVide) {
        await _base.supprimerBrouillon(brouillon.utilisateurId);
      } else {
        await _base.enregistrerBrouillon(brouillon);
      }
      final String? anciennePhoto = ancien?.photoLocale;
      if (anciennePhoto != null && anciennePhoto != brouillon.photoLocale) {
        await PhotosM3.supprimerLocale(anciennePhoto);
      }
    } catch (e) {
      // pas de base locale : pas de brouillon
    }
  }

  /// Supprime le brouillon.
  /// [avecPhoto] : true quand l'utilisateur JETTE le brouillon (sa photo
  /// est supprimée) ; false après une publication (la photo a été envoyée,
  /// ou attend dans la file d'envoi).
  Future<void> supprimerBrouillon({bool avecPhoto = false}) async {
    try {
      final Brouillon? brouillon = await _base.lireBrouillon(_moi.id);
      await _base.supprimerBrouillon(_moi.id);
      if (avecPhoto) {
        await PhotosM3.supprimerLocale(brouillon?.photoLocale);
      }
    } catch (e) {
      // rien à effacer
    }
  }
}
