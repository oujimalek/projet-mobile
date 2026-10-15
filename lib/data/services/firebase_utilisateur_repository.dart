import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/quartier.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
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

  // =====================================================================
  // Mode démo : rien avec Firebase
  // =====================================================================

  @override
  bool get estDemo => false;

  @override
  String? get aideDemoConnexion => null;

  @override
  String? get aideDemoCodeQuartier => null;

  @override
  Future<void> simulerVerificationEmail() async {}

  @override
  Future<void> simulerValidation() async {}

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  @override
  Future<Resultat<Utilisateur>> connexion(
    String email,
    String motDePasse,
  ) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final DocumentSnapshot<Map<String, dynamic>> document =
          await _utilisateurs.doc(credential.user!.uid).get();
      if (!document.exists) {
        await _auth.signOut();
        return const Resultat.echec('Profil introuvable, contacte l\'administrateur');
      }

      final Utilisateur utilisateur =
          Utilisateur.fromMap(document.id, document.data()!);
      // Compte bloqué : on ne le laisse pas connecté
      if (utilisateur.statut == StatutUtilisateur.bloque) {
        await _auth.signOut();
        return const Resultat.echec(
          'Ton compte a été bloqué par l\'administrateur',
        );
      }
      _connecte = utilisateur;
      return Resultat.succes(utilisateur);
    } on FirebaseAuthException catch (e) {
      return Resultat.echec(_messageAuth(e.code));
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
    try {
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
      await _utilisateurs.doc(compte.uid).set(nouveau.toMap());

      _connecte = nouveau;

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
    await _auth.signOut();
    _connecte = _invite;
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
    try {
      // update : seulement ces champs (statut, rôle et quartier ne bougent pas)
      await _utilisateurs.doc(modifie.id).update({
        'prenom': modifie.prenom,
        'nom': modifie.nom,
        'telephone': modifie.telephone,
        'logement': modifie.logement,
        'competences': modifie.competences,
        'avatar': modifie.avatar,
      });
      _connecte = modifie;
      return const Resultat.succes(null);
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
      _connecte = demande;
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
        return const Resultat.succes(null);
      }
      return Resultat.succes(Quartier.fromMap(document.id, document.data()!));
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
      default:
        return 'Une erreur est survenue ($code)';
    }
  }

  /// Traduit les codes d'erreur de Firestore en messages pour l'écran.
  String _messageFirestore(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Action non autorisée';
      case 'unavailable':
        return 'Serveur injoignable, vérifie ta connexion Internet';
      case 'not-found':
        return 'Donnée introuvable';
      default:
        return 'Une erreur est survenue ($code)';
    }
  }
}
