import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quartier.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'cache_local.dart';
import 'firestore_commun.dart';
import 'utilisateur_repository.dart';

/// M1 - Implémentation "réelle" de UtilisateurRepository.
///
/// - Firebase Auth : les comptes (e-mail + mot de passe, e-mail de
///   vérification, lien de réinitialisation). Le mot de passe n'est jamais
///   dans notre base.
/// - Cloud Firestore : les profils (utilisateurs/{uid}), les quartiers et
///   les codes d'invitation, selon docs/schema_firestore.md.
///
/// La sécurité n'est PAS ici : c'est firestore.rules qui décide côté
/// serveur. Si l'app tente une écriture interdite, Firebase la refuse et on
/// renvoie un Resultat en échec.
class FirebaseUtilisateurRepository implements UtilisateurRepository {
  // Getters (et pas des champs) : Firebase n'est appelé qu'au premier usage,
  // donc créer cet objet ne plante pas si Firebase n'est pas démarré.
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _base => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _utilisateurs =>
      _base.collection('utilisateurs');
  CollectionReference<Map<String, dynamic>> get _quartiers =>
      _base.collection('quartiers');
  // telephones/{8 chiffres} = {uid, email} : pour se connecter avec son numéro
  CollectionReference<Map<String, dynamic>> get _telephones =>
      _base.collection('telephones');

  /// Personne de connecté : un utilisateur vide.
  static const Utilisateur _invite = Utilisateur(
    id: '',
    prenom: '',
    nom: '',
    email: '',
    telephone: '',
    quartier: '',
    residence: '',
  );

  // Le profil chargé à la connexion : getUtilisateurConnecte() le renvoie
  // sans attendre le réseau (synchrone).
  Utilisateur _connecte = _invite;

  // Copie du profil sur le téléphone (Hive) : voir cache_local.dart
  final CacheLocal _cache;

  /// [cache] : les tests peuvent donner un cache dans un dossier temporaire.
  FirebaseUtilisateurRepository({CacheLocal? cache})
      : _cache = cache ?? CacheLocal();

  /// Change l'utilisateur connecté ET le garde dans le cache local.
  Future<void> _memoriser(Utilisateur utilisateur) async {
    _connecte = utilisateur;
    await _cache.enregistrerUtilisateur(utilisateur);
  }

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  @override
  Future<Resultat<Utilisateur>> connexion(
    String identifiant,
    String motDePasse,
  ) async {
    final bool parNumero = UtilisateurRepository.estUnNumero(identifiant);
    try {
      String email = identifiant.trim();
      if (parNumero) {
        // Firebase Auth ne connaît que l'e-mail : on le retrouve grâce au numéro
        final String? numero =
            UtilisateurRepository.normaliserTelephone(identifiant);
        final DocumentSnapshot<Map<String, dynamic>>? fiche =
            numero == null ? null : await _telephones.doc(numero).get();
        if (fiche == null || !fiche.exists) {
          return const Resultat.echec('Numéro ou mot de passe incorrect');
        }
        email = fiche.data()!['email'] ?? '';
      }
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: motDePasse,
      );
      return await _chargerProfil(credential.user!);
    } on FirebaseAuthException catch (e) {
      final String message = _messageAuth(e.code);
      if (parNumero && message == 'E-mail ou mot de passe incorrect') {
        return const Resultat.echec('Numéro ou mot de passe incorrect');
      }
      return Resultat.echec(message);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<Utilisateur>> inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  }) async {
    User? compte;
    final String? numero = UtilisateurRepository.normaliserTelephone(telephone);
    if (numero == null) {
      return const Resultat.echec('Numéro de téléphone invalide (8 chiffres)');
    }
    try {
      // 0. Le numéro doit être libre (lecture permise sans être connecté)
      if ((await _telephones.doc(numero).get()).exists) {
        return const Resultat.echec('Ce numéro est déjà utilisé par un autre compte');
      }

      // 1. Le compte Firebase Auth (vérifie l'e-mail et le mot de passe)
      final UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      compte = credential.user!;

      // 2. Le profil dans Firestore : en attente, résident, sans quartier
      //    (firestore.rules refuse tout autre statut ou rôle)
      final List<String> mots = nomComplet.trim().split(' ');
      final Utilisateur nouveau = Utilisateur(
        id: compte.uid,
        prenom: mots[0],
        nom: _reste(mots),
        email: compte.email ?? email.trim(),
        telephone: telephone.trim(),
        quartier: '',
        residence: '',
        statut: StatutUtilisateur.enAttente,
        role: RoleUtilisateur.resident,
      );
      // WriteBatch : le profil ET la fiche du numéro, tout ou rien
      final WriteBatch lot = _base.batch();
      lot.set(_utilisateurs.doc(compte.uid), nouveau.toMap());
      lot.set(_telephones.doc(numero), {
        'uid': compte.uid,
        'email': nouveau.email,
      });
      await lot.commit();

      await _memoriser(nouveau);

      // 3. L'e-mail de vérification (remplace le code SMS). S'il ne part
      //    pas, le compte est quand même créé : l'écran suivant a un
      //    bouton "Renvoyer l'e-mail".
      try {
        await compte.sendEmailVerification();
      } on FirebaseAuthException {
        // rien : voir ci-dessus
      }
      return Resultat.succes(nouveau);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    } on FirebaseException catch (e) {
      // Le compte Auth existe mais pas le profil : on l'efface pour que
      // l'utilisateur puisse réessayer avec le même e-mail
      await _supprimerCompteIncomplet(compte);
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<void>> envoyerEmailVerification() async {
    final User? compte = _auth.currentUser;
    if (compte == null) {
      return const Resultat.echec('Tu n\'es pas connecté');
    }
    try {
      await compte.sendEmailVerification();
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    }
  }

  @override
  Future<Resultat<bool>> emailEstVerifie() async {
    final User? compte = _auth.currentUser;
    if (compte == null) {
      return const Resultat.echec('Tu n\'es pas connecté');
    }
    try {
      // reload : relit l'état du compte sur le serveur (le clic sur le lien
      // a eu lieu dans la boîte mail, pas dans l'app)
      await compte.reload();
      final bool verifie = _auth.currentUser?.emailVerified ?? false;
      if (verifie) {
        // Nouveau jeton : firestore.rules lit "email_verified" dans le jeton,
        // l'ancien dit encore false
        await _auth.currentUser!.getIdToken(true);
      }
      return Resultat.succes(verifie);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    }
  }

  @override
  Future<void> deconnexion() async {
    try {
      await _auth.signOut();
    } finally {
      // Même si signOut échoue : le téléphone peut être prêté,
      // on n'y laisse pas le profil
      _connecte = _invite;
      await _cache.vider();
    }
  }

  @override
  Future<Utilisateur?> restaurerSession() async {
    // Firebase Auth se souvient du compte d'une fois sur l'autre ;
    // authStateChanges().first attend qu'il ait fini de le relire
    final User? compte = await _auth.authStateChanges().first;
    if (compte == null) {
      _connecte = _invite;
      await _cache.vider();
      return null;
    }

    // 1. Tout de suite : le profil gardé sur le téléphone
    final Utilisateur? enCache = await _cache.lireUtilisateur();
    if (enCache != null && enCache.id == compte.uid) {
      _connecte = enCache;
    } else if (enCache != null) {
      await _cache.vider(); // profil d'un autre compte : on l'efface
    }

    // 2. Ensuite : la version à jour du serveur (statut changé par l'admin...)
    try {
      final DocumentSnapshot<Map<String, dynamic>> document =
          await _utilisateurs.doc(compte.uid).get();
      if (!document.exists) {
        await deconnexion();
        return null;
      }
      final Utilisateur utilisateur = await _synchroniserEmail(
        compte,
        Utilisateur.fromMap(document.id, document.data()!),
      );
      if (utilisateur.statut == StatutUtilisateur.bloque) {
        await deconnexion();
        return null;
      }
      await _memoriser(utilisateur);
    } on FirebaseException catch (e) {
      // Pas de réseau ('unavailable') : on garde le profil du cache.
      // Autre erreur (droits refusés, compte supprimé...) : on déconnecte.
      if (e.code != 'unavailable' && e.code != 'deadline-exceeded') {
        await deconnexion();
        return null;
      }
    }

    if (_connecte.id.isEmpty) {
      // Ni cache ni réseau : on ouvre la connexion, mais sans déconnecter
      // de Firebase (le compte est valide, il manque juste le réseau)
      return null;
    }
    return _connecte;
  }

  @override
  Future<Resultat<Utilisateur>> rafraichirProfil() async {
    final User? compte = _auth.currentUser;
    if (compte == null) {
      return const Resultat.echec('Tu n\'es plus connecté : reconnecte-toi');
    }
    try {
      // Source.server : on veut la réponse de l'admin, pas la copie locale
      // de Firestore (sans réseau : erreur "serveur injoignable")
      final DocumentSnapshot<Map<String, dynamic>> document = await _utilisateurs
          .doc(compte.uid)
          .get(const GetOptions(source: Source.server));
      if (!document.exists) {
        await deconnexion();
        return const Resultat.echec('Profil introuvable : reconnecte-toi');
      }
      final Utilisateur utilisateur =
          Utilisateur.fromMap(document.id, document.data()!);
      // Même règle qu'à la connexion : un compte bloqué est déconnecté
      if (utilisateur.statut == StatutUtilisateur.bloque) {
        await deconnexion();
        return const Resultat.echec(
          'Ton compte a été bloqué par l\'administrateur',
        );
      }
      await _memoriser(utilisateur);
      return Resultat.succes(utilisateur);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<void>> envoyerLienReinitialisation(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      // On ne dit pas si le compte existe (sinon n'importe qui pourrait
      // tester des adresses)
      if (e.code == 'user-not-found') {
        return const Resultat.succes(null);
      }
      return Resultat.echec(_messageAuth(e.code));
    }
  }

  // =====================================================================
  // Code SMS (Firebase Phone Auth)
  // =====================================================================

  // Le dernier envoi : Firebase donne un identifiant, que l'on combine
  // ensuite avec les 6 chiffres tapés
  String? _idVerification;
  String? _numeroSms; // les 8 chiffres qui ont reçu le code
  // Android lit parfois le SMS tout seul : la preuve arrive sans code
  PhoneAuthCredential? _preuveAuto;

  @override
  Future<Resultat<void>> envoyerCodeSms(String telephone) async {
    final String? numero = UtilisateurRepository.normaliserTelephone(telephone);
    if (numero == null) {
      return const Resultat.echec('Numéro de téléphone invalide (8 chiffres)');
    }
    _idVerification = null;
    _preuveAuto = null;
    _numeroSms = numero;
    // verifyPhoneNumber répond en appelant une des fonctions ci-dessous ;
    // le Completer transforme la première réponse en un Future à attendre
    final Completer<Resultat<void>> reponse = Completer<Resultat<void>>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+216$numero',
        timeout: const Duration(seconds: 60),
        codeSent: (String idVerification, int? jetonRenvoi) {
          _idVerification = idVerification;
          if (!reponse.isCompleted) {
            reponse.complete(const Resultat.succes(null));
          }
        },
        verificationCompleted: (PhoneAuthCredential preuve) {
          _preuveAuto = preuve;
          if (!reponse.isCompleted) {
            reponse.complete(const Resultat.succes(null));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!reponse.isCompleted) {
            reponse.complete(Resultat.echec(_messageAuth(e.code)));
          }
        },
        codeAutoRetrievalTimeout: (String idVerification) {
          _idVerification = idVerification;
        },
      );
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    }
    // Sécurité : si Firebase ne répond jamais, on n'attend pas à l'infini
    return reponse.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        return const Resultat.echec('Le SMS n\'est pas parti, réessaie');
      },
    );
  }

  @override
  Future<Resultat<Utilisateur>> connexionParSms(String code) async {
    final PhoneAuthCredential? preuve = _preuveSms(code);
    if (preuve == null) {
      return const Resultat.echec('Demande d\'abord un code');
    }
    try {
      final UserCredential credential = await _auth.signInWithCredential(preuve);
      // Numéro jamais vérifié : Firebase vient de créer un compte vide.
      // On l'efface : un compte se crée seulement par l'inscription
      if (credential.additionalUserInfo?.isNewUser ?? false) {
        await _supprimerCompteIncomplet(credential.user);
        await _auth.signOut();
        return const Resultat.echec(UtilisateurRepository.numeroNonVerifie);
      }
      return await _chargerProfil(credential.user!);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<void>> verifierTelephone(String code) async {
    final User? compte = _auth.currentUser;
    if (compte == null) {
      return const Resultat.echec('Tu n\'es pas connecté');
    }
    final String? numero =
        UtilisateurRepository.normaliserTelephone(_connecte.telephone);
    if (numero == null || _numeroSms != numero) {
      return const Resultat.echec(
        'Le code doit être envoyé au numéro de ton profil',
      );
    }
    final PhoneAuthCredential? preuve = _preuveSms(code);
    if (preuve == null) {
      return const Resultat.echec('Demande d\'abord un code');
    }
    try {
      // Un autre numéro est encore lié au compte : on le retire d'abord
      // (un compte Firebase n'a qu'un seul numéro)
      if (compte.phoneNumber != null) {
        await compte.unlink(PhoneAuthProvider.PROVIDER_ID);
      }
      await compte.linkWithCredential(preuve);
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
    }
  }

  @override
  bool telephoneEstVerifie() {
    final String? numero =
        UtilisateurRepository.normaliserTelephone(_connecte.telephone);
    final String? numeroLie = _auth.currentUser?.phoneNumber;
    return numero != null && numeroLie == '+216$numero';
  }

  /// La preuve à donner à Firebase : l'envoi + les 6 chiffres tapés.
  /// null : aucun code n'a été demandé.
  PhoneAuthCredential? _preuveSms(String code) {
    final String? idVerification = _idVerification;
    if (idVerification != null) {
      return PhoneAuthProvider.credential(
        verificationId: idVerification,
        smsCode: code.trim(),
      );
    }
    return _preuveAuto;
  }

  // =====================================================================
  // Utilisateur connecté et profil
  // =====================================================================

  @override
  Utilisateur getUtilisateurConnecte() {
    return _connecte;
  }

  @override
  String emailConnecte() {
    return _auth.currentUser?.email ?? _connecte.email;
  }

  @override
  Future<Resultat<void>> modifierProfil({
    required String nomComplet,
    required String telephone,
    required String logement,
    required List<String> competences,
    String avatar = '',
  }) async {
    final List<String> mots = nomComplet.trim().split(' ');
    final Utilisateur modifie = _connecte.copier(
      prenom: mots[0],
      nom: _reste(mots),
      telephone: telephone.trim(),
      logement: logement.trim(),
      competences: competences,
      avatar: avatar,
    );
    final String? ancienNumero =
        UtilisateurRepository.normaliserTelephone(_connecte.telephone);
    final String? nouveauNumero =
        UtilisateurRepository.normaliserTelephone(modifie.telephone);
    try {
      final WriteBatch lot = _base.batch();
      // update : seulement ces champs (statut, rôle et quartier ne bougent pas)
      lot.update(_utilisateurs.doc(modifie.id), {
        'prenom': modifie.prenom,
        'nom': modifie.nom,
        'telephone': modifie.telephone,
        'logement': modifie.logement,
        'competences': modifie.competences,
        'avatar': modifie.avatar,
      });
      // Nouveau numéro : la fiche suit (dans le même lot, tout ou rien)
      if (nouveauNumero != ancienNumero) {
        if (nouveauNumero != null) {
          final DocumentSnapshot<Map<String, dynamic>> fiche =
              await _telephones.doc(nouveauNumero).get();
          if (fiche.exists && fiche.data()!['uid'] != modifie.id) {
            return const Resultat.echec(
              'Ce numéro est déjà utilisé par un autre compte',
            );
          }
          lot.set(_telephones.doc(nouveauNumero), {
            'uid': modifie.id,
            'email': emailConnecte(),
          });
        }
        if (ancienNumero != null && await _ficheEstAMoi(ancienNumero)) {
          lot.delete(_telephones.doc(ancienNumero));
        }
      }
      await lot.commit();
      await _memoriser(modifie);
      if (nouveauNumero != ancienNumero) {
        await _oublierNumeroVerifie();
      }
      return const Resultat.succes(null);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  // =====================================================================
  // Sécurité du compte
  // =====================================================================

  @override
  Future<Resultat<void>> changerMotDePasse(String ancien, String nouveau) async {
    try {
      final User compte = await _reauthentifier(ancien);
      await compte.updatePassword(nouveau);
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageSecurite(e.code));
    }
  }

  @override
  Future<Resultat<void>> changerEmail(
    String nouvelEmail,
    String motDePasse,
  ) async {
    try {
      final User compte = await _reauthentifier(motDePasse);
      // L'e-mail de Firebase Auth change seulement après le clic sur le
      // lien ; le profil est mis à jour à la connexion suivante
      // (voir _synchroniserEmail)
      await compte.verifyBeforeUpdateEmail(nouvelEmail.trim());
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageSecurite(e.code));
    }
  }

  @override
  Future<Resultat<void>> supprimerCompte(String motDePasse) async {
    if (_connecte.estAdmin) {
      return const Resultat.echec(
        'Un administrateur ne peut pas supprimer son compte : '
        'contacte l\'équipe Houmani',
      );
    }
    try {
      final User compte = await _reauthentifier(motDePasse);
      // D'abord le profil et la fiche du numéro (il faut encore être
      // connecté pour les règles), ensuite le compte Firebase Auth
      final WriteBatch lot = _base.batch();
      lot.delete(_utilisateurs.doc(compte.uid));
      final String? numero =
          UtilisateurRepository.normaliserTelephone(_connecte.telephone);
      if (numero != null && await _ficheEstAMoi(numero)) {
        lot.delete(_telephones.doc(numero));
      }
      await lot.commit();
      await compte.delete();
      _connecte = _invite;
      await _cache.vider();
      return const Resultat.succes(null);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageSecurite(e.code));
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  // =====================================================================
  // Quartiers
  // =====================================================================

  @override
  Future<Resultat<List<Quartier>>> rechercherQuartiers(String recherche) async {
    try {
      // Firestore ne sait pas chercher "contient ce texte" : on lit les
      // quartiers (peu nombreux) et on filtre ici
      final QuerySnapshot<Map<String, dynamic>> resultat =
          await _quartiers.get();
      final String texte = recherche.trim().toLowerCase();
      final List<Quartier> trouves = [];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in resultat.docs) {
        final Quartier quartier = Quartier.fromMap(document.id, document.data());
        if (quartier.nom.toLowerCase().contains(texte) ||
            quartier.localisation.toLowerCase().contains(texte)) {
          trouves.add(quartier);
        }
      }
      return Resultat.succes(trouves);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<Quartier?>> trouverParCode(String code) async {
    try {
      // Le nom du document EST le code : une seule lecture, et on ne peut
      // pas lister les autres codes (firestore.rules)
      final DocumentSnapshot<Map<String, dynamic>> documentCode = await _base
          .collection('codesQuartier')
          .doc(code.trim().toUpperCase())
          .get();
      if (!documentCode.exists) {
        return const Resultat.succes(null);
      }
      final String quartierId = documentCode.data()!['quartierId'] ?? '';
      final DocumentSnapshot<Map<String, dynamic>> documentQuartier =
          await _quartiers.doc(quartierId).get();
      if (!documentQuartier.exists) {
        return const Resultat.succes(null);
      }
      return Resultat.succes(
        Quartier.fromMap(documentQuartier.id, documentQuartier.data()!),
      );
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<void>> rejoindreQuartier(Quartier quartier) async {
    final String? refus =
        UtilisateurRepository.refusChangement(_connecte, quartier);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Utilisateur demande = _connecte.copier(
      quartierId: quartier.id,
      quartier: quartier.nom,
      residence: quartier.nom, // comme le mock : lu par le module 3
      statut: StatutUtilisateur.enAttente,
      dateDemande: DateTime.now(),
    );
    try {
      await _utilisateurs.doc(demande.id).update({
        'quartierId': quartier.id,
        'quartierNom': quartier.nom,
        'residence': quartier.nom,
        'statut': StatutUtilisateur.enAttente.name,
        'dateDemande': FieldValue.serverTimestamp(), // l'heure du serveur
      });
      await _memoriser(demande);
      return const Resultat.succes(null);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<Quartier?>> getQuartierConnecte() async {
    final String? quartierId = _connecte.quartierId;
    if (quartierId == null || quartierId.isEmpty) {
      return const Resultat.succes(null);
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> document =
          await _quartiers.doc(quartierId).get();
      if (!document.exists) {
        await _cache.oublierQuartier(); // quartier supprimé sur le serveur
        return const Resultat.succes(null);
      }
      final Quartier quartier = Quartier.fromMap(document.id, document.data()!);
      await _cache.enregistrerQuartier(quartier);
      return Resultat.succes(quartier);
    } on FirebaseException catch (e) {
      // Pas de réseau : la dernière version gardée, si c'est le bon quartier
      final Quartier? enCache = await _cache.lireQuartier();
      if (enCache != null && enCache.id == quartierId) {
        return Resultat.succes(enCache);
      }
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<String?>> getCodeInvitation() async {
    if (!_connecte.estAdmin) {
      return const Resultat.echec('Action non autorisée');
    }
    try {
      // Le filtre sur quartierId est obligatoire : firestore.rules ne laisse
      // l'admin lister QUE les codes de son quartier
      final QuerySnapshot<Map<String, dynamic>> resultat = await _base
          .collection('codesQuartier')
          .where('quartierId', isEqualTo: _connecte.quartierId)
          .limit(1)
          .get();
      if (resultat.docs.isEmpty) {
        return const Resultat.succes(null);
      }
      return Resultat.succes(resultat.docs.first.id); // l'id EST le code
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<void>> enregistrerContour(List<PointGps> contour) async {
    final String? refus = UtilisateurRepository.refusContour(_connecte, contour);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final List<GeoPoint> points = [];
    for (final PointGps point in contour) {
      points.add(GeoPoint(point.latitude, point.longitude));
    }
    final PointGps centre = Quartier.milieu(contour)!;
    try {
      // firestore.rules : seulement contour et position, par l'admin
      await _quartiers.doc(_connecte.quartierId).update({
        'contour': points,
        'position': GeoPoint(centre.latitude, centre.longitude),
      });
      // Le cache sera rafraîchi au prochain getQuartierConnecte
      return const Resultat.succes(null);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  // =====================================================================
  // Administration des membres
  // =====================================================================

  /// Les membres de MON quartier qui ont ce statut. Le filtre sur
  /// quartierId est obligatoire : firestore.rules refuse sinon la requête.
  Query<Map<String, dynamic>> _requeteMembres(StatutUtilisateur statut) {
    return _utilisateurs
        .where('quartierId', isEqualTo: _connecte.quartierId)
        .where('statut', isEqualTo: statut.name);
  }

  @override
  Future<Resultat<List<Utilisateur>>> getMembres(
    StatutUtilisateur statut, {
    String recherche = '',
  }) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> resultat =
          await _requeteMembres(statut).get();
      final String texte = recherche.trim().toLowerCase();
      final List<Utilisateur> membres = [];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in resultat.docs) {
        final Utilisateur membre =
            Utilisateur.fromMap(document.id, document.data());
        if (membre.nomComplet.toLowerCase().contains(texte)) {
          membres.add(membre);
        }
      }
      return Resultat.succes(membres);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<int>> compterMembres(StatutUtilisateur statut) async {
    try {
      // count() : Firebase compte sur le serveur, sans renvoyer les profils
      final AggregateQuerySnapshot resultat =
          await _requeteMembres(statut).count().get();
      return Resultat.succes(resultat.count ?? 0);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  @override
  Future<Resultat<List<Utilisateur>>> getVoisins() {
    return getMembres(StatutUtilisateur.actif);
  }

  @override
  Future<Resultat<void>> validerMembre(String id) {
    return _changerStatut(id, StatutUtilisateur.actif);
  }

  @override
  Future<Resultat<void>> refuserMembre(String id) {
    return _changerStatut(id, StatutUtilisateur.refuse);
  }

  @override
  Future<Resultat<void>> bloquerMembre(String id) {
    return _changerStatut(id, StatutUtilisateur.bloque);
  }

  @override
  Future<Resultat<void>> debloquerMembre(String id) {
    return _changerStatut(id, StatutUtilisateur.actif);
  }

  // =====================================================================
  // Outils internes
  // =====================================================================

  /// L'admin ne change QUE le statut (seul champ permis par firestore.rules).
  Future<Resultat<void>> _changerStatut(
    String id,
    StatutUtilisateur statut,
  ) async {
    try {
      await _utilisateurs.doc(id).update({'statut': statut.name});
      return const Resultat.succes(null);
    } on FirebaseException catch (e) {
      return Resultat.echec(_messageFirestore(e.code));
    }
  }

  /// Firebase exige une connexion récente pour changer le mot de passe,
  /// l'e-mail ou supprimer le compte : on se reconnecte avec le mot de passe.
  Future<User> _reauthentifier(String motDePasse) async {
    final User? compte = _auth.currentUser;
    final String? email = compte?.email;
    if (compte == null || email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await compte.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: motDePasse),
    );
    return compte;
  }

  /// Après un changement d'e-mail (lien cliqué), Firebase Auth a la nouvelle
  /// adresse mais le profil garde l'ancienne : on la recopie.
  Future<Utilisateur> _synchroniserEmail(
    User compte,
    Utilisateur utilisateur,
  ) async {
    final String? email = compte.email;
    if (email == null || email == utilisateur.email) {
      return utilisateur;
    }
    try {
      await _utilisateurs.doc(compte.uid).update({'email': email});
    } on FirebaseException {
      return utilisateur; // on réessaiera à la prochaine connexion
    }
    // La fiche du numéro doit donner la nouvelle adresse (sinon la
    // connexion par numéro échouerait)
    final String? numero =
        UtilisateurRepository.normaliserTelephone(utilisateur.telephone);
    if (numero != null) {
      try {
        await _telephones.doc(numero).update({'email': email});
      } on FirebaseException {
        // pas de fiche (ou celle d'un autre) : rien à recopier
      }
    }
    return utilisateur.copier(email: email);
  }

  /// Après la connexion à Firebase Auth (mot de passe ou SMS) : charge le
  /// profil, refuse un compte bloqué, puis le garde en mémoire.
  Future<Resultat<Utilisateur>> _chargerProfil(User compte) async {
    final DocumentSnapshot<Map<String, dynamic>> document =
        await _utilisateurs.doc(compte.uid).get();
    if (!document.exists) {
      await _auth.signOut();
      return const Resultat.echec('Profil introuvable, contacte l\'administrateur');
    }
    final Utilisateur utilisateur = await _synchroniserEmail(
      compte,
      Utilisateur.fromMap(document.id, document.data()!),
    );
    // Compte bloqué : on ne le laisse pas connecté
    if (utilisateur.statut == StatutUtilisateur.bloque) {
      await _auth.signOut();
      return const Resultat.echec(
        'Ton compte a été bloqué par l\'administrateur',
      );
    }
    await _memoriser(utilisateur);
    // Comptes créés avant la connexion par numéro : on crée leur fiche
    await _ajouterFicheTelephone(utilisateur);
    return Resultat.succes(utilisateur);
  }

  /// Le numéro du profil a changé : l'ancien, vérifié par SMS, ne doit plus
  /// ouvrir le compte. Au mieux : si ça échoue, le prochain
  /// verifierTelephone le remplacera.
  Future<void> _oublierNumeroVerifie() async {
    final User? compte = _auth.currentUser;
    if (compte == null || compte.phoneNumber == null) {
      return;
    }
    try {
      await compte.unlink(PhoneAuthProvider.PROVIDER_ID);
    } on FirebaseAuthException {
      // rien : voir ci-dessus
    }
  }

  /// La fiche telephones/{numero} existe-t-elle, et est-elle à moi ?
  /// (supprimer une fiche absente ou d'un autre ferait échouer tout le lot)
  Future<bool> _ficheEstAMoi(String numero) async {
    final DocumentSnapshot<Map<String, dynamic>> fiche =
        await _telephones.doc(numero).get();
    return fiche.exists && fiche.data()!['uid'] == _auth.currentUser?.uid;
  }

  /// Crée la fiche du numéro si elle manque (comptes créés avant la
  /// connexion par numéro). Au mieux : en cas d'échec, on réessaiera.
  Future<void> _ajouterFicheTelephone(Utilisateur utilisateur) async {
    final String? numero =
        UtilisateurRepository.normaliserTelephone(utilisateur.telephone);
    if (numero == null) {
      return;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> fiche =
          await _telephones.doc(numero).get();
      if (!fiche.exists) {
        await _telephones.doc(numero).set({
          'uid': utilisateur.id,
          'email': utilisateur.email,
        });
      }
    } on FirebaseException {
      // rien : la connexion par e-mail marche quand même
    }
  }

  Future<void> _supprimerCompteIncomplet(User? compte) async {
    if (compte == null) {
      return;
    }
    try {
      await compte.delete();
    } on FirebaseAuthException {
      // Tant pis : l'utilisateur pourra se connecter puis compléter plus tard
    }
  }

  /// Les mots après le premier, recollés : ["Amira", "Ben", "Salah"] → "Ben Salah".
  String _reste(List<String> mots) {
    String nom = '';
    for (int i = 1; i < mots.length; i++) {
      if (mots[i].isNotEmpty) {
        nom = nom.isEmpty ? mots[i] : '$nom ${mots[i]}';
      }
    }
    return nom;
  }

  /// Traduit les codes d'erreur de Firebase Auth en messages pour l'écran.
  String _messageAuth(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'E-mail ou mot de passe incorrect';
      case 'invalid-email':
        return 'Adresse e-mail invalide';
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet e-mail';
      case 'weak-password':
        return 'Mot de passe trop faible';
      case 'user-disabled':
        return 'Ce compte a été désactivé';
      case 'too-many-requests':
        return 'Trop de tentatives, réessaie dans quelques minutes';
      case 'network-request-failed':
        return 'Pas de connexion Internet';
      // ----- Code SMS -----
      case 'invalid-verification-code':
        return 'Code incorrect';
      case 'invalid-verification-id':
      case 'session-expired':
        return 'Code expiré : demande un nouveau code';
      case 'invalid-phone-number':
        return 'Numéro de téléphone invalide (8 chiffres)';
      case 'quota-exceeded':
        return 'Trop de SMS envoyés, réessaie plus tard';
      case 'credential-already-in-use':
        return 'Ce numéro est déjà vérifié sur un autre compte';
      case 'operation-not-allowed':
        return 'Ce mode de connexion n\'est pas activé';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'Connexion par SMS indisponible sur cet appareil';
      default:
        return 'Une erreur est survenue ($code)';
    }
  }

  /// Comme _messageAuth, mais ici seul le mot de passe a été saisi.
  String _messageSecurite(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'Mot de passe actuel incorrect';
      case 'no-current-user':
      case 'user-mismatch':
      case 'requires-recent-login':
        return 'Reconnecte-toi puis réessaie';
      default:
        return _messageAuth(code);
    }
  }

  /// Traduit les codes d'erreur de Firestore en messages pour l'écran
  /// (les mêmes pour les 4 modules : voir firestore_commun.dart).
  String _messageFirestore(String code) {
    return FirestoreCommun.messageErreur(code);
  }
}
