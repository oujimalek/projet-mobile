import '../models/quartier.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'utilisateur_repository.dart';

/// M1 - Implémentation "fictive" de UtilisateurRepository.
///
/// Les données sont écrites en dur et gardées en mémoire : rien n'est
/// enregistré quand on relance l'application. Toute l'app partage la même
/// instance (UtilisateurRepository.instance), donc un changement fait sur un
/// écran (ex : un membre validé) est visible sur les autres écrans.
///
/// Elle suit le même contrat que FirebaseUtilisateurRepository (mêmes
/// Resultat, mêmes messages d'erreur) : les tests restent valables.
/// Phase 5 : ce fichier part dans test/ (plus de données fictives dans l'app).
class MockUtilisateurRepository implements UtilisateurRepository {
  // Compte de démonstration (données fictives, pour tester l'écran de connexion)
  static const String emailDemo = 'demo@houmani.tn';
  static const String motDePasseDemo = 'houmani123';

  static const Utilisateur _utilisateurDemo = Utilisateur(
    id: 'u1',
    prenom: 'Amira',
    nom: 'Ben Salah',
    email: emailDemo,
    telephone: '+216 22 345 678',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc B',
    logement: 'Bloc B - Appt 12',
    role: RoleUtilisateur.admin, // admin : pour pouvoir tester la liste des membres
    competences: ['Bricolage', 'Informatique', 'Cours de maths'],
    servicesRendus: 12,
    noteMoyenne: 4.8,
    nbSignalements: 7,
  );

  // Les quartiers que l'on peut rejoindre
  static const List<Quartier> _quartiers = [
    Quartier(
      id: 'q1',
      nom: 'Résidence El Yasmine',
      localisation: 'Ennasr 2, Ariana',
      codeInvitation: 'YAS72B',
      nbMembres: 42,
    ),
    Quartier(
      id: 'q2',
      nom: 'Cité El Wafa',
      localisation: 'Ennasr 1, Ariana',
      codeInvitation: 'WAF18C',
      nbMembres: 18,
    ),
    Quartier(
      id: 'q3',
      nom: 'Résidence Les Jasmins',
      localisation: 'El Menzah 6, Ariana',
      codeInvitation: 'JAS33A',
      nbMembres: 27,
    ),
  ];

  // L'utilisateur connecté (au départ : le compte de démo)
  Utilisateur _connecte = _utilisateurDemo;

  // Les mots de passe des comptes (clé = id de l'utilisateur)
  final Map<String, String> _motsDePasse = {'u1': motDePasseDemo};

  // Les comptes dont l'e-mail est vérifié (clé = id). Un nouveau compte
  // ne l'est pas : il faut "cliquer sur le lien" (simulerVerificationEmail).
  final Set<String> _emailsVerifies = {'u1'};

  // Numéro du prochain compte créé (u100, u101, ...)
  int _prochainNumero = 100;

  // Tous les membres de la houma de l'admin, quel que soit leur statut
  final List<Utilisateur> _membres = _membresDeDepart();

  static List<Utilisateur> _membresDeDepart() {
    final DateTime maintenant = DateTime.now();
    return [
      _utilisateurDemo,
      // ----- Demandes en attente -----
      Utilisateur(
        id: 'u4',
        prenom: 'Sarra',
        nom: 'Ben Ali',
        email: '',
        telephone: '+216 98 765 432',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc A',
        logement: 'Bloc A - Appt 4',
        statut: StatutUtilisateur.enAttente,
        dateDemande: maintenant.subtract(const Duration(hours: 2)),
      ),
      Utilisateur(
        id: 'u5',
        prenom: 'Hedi',
        nom: 'Trabelsi',
        email: '',
        telephone: '+216 50 123 456',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc C',
        logement: 'Bloc C - Appt 9',
        statut: StatutUtilisateur.enAttente,
        dateDemande: maintenant.subtract(const Duration(hours: 5)),
      ),
      Utilisateur(
        id: 'u6',
        prenom: 'Amira',
        nom: 'Chaabane',
        email: '',
        telephone: '+216 27 444 555',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc B',
        logement: 'Bloc B - Appt 2',
        statut: StatutUtilisateur.enAttente,
        dateDemande: maintenant.subtract(const Duration(days: 1)),
      ),
      // ----- Membres actifs -----
      const Utilisateur(
        id: 'u2',
        prenom: 'Youssef',
        nom: 'Trabelsi',
        email: 'youssef@houmani.tn',
        telephone: '+216 22 111 111',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc A',
        logement: 'Bloc A - Appt 7',
        competences: ['Plomberie'],
      ),
      const Utilisateur(
        id: 'u3',
        prenom: 'Salma',
        nom: 'Gharbi',
        email: 'salma@houmani.tn',
        telephone: '+216 55 222 222',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc C',
        logement: 'Bloc C - Appt 1',
        competences: ['Couture', 'Cuisine'],
      ),
      const Utilisateur(
        id: 'u7',
        prenom: 'Karim',
        nom: 'Mansour',
        email: '',
        telephone: '+216 93 333 333',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc A',
        logement: 'Bloc A - Appt 11',
      ),
      // ----- Membre bloqué -----
      const Utilisateur(
        id: 'u8',
        prenom: 'Walid',
        nom: 'Ferchichi',
        email: '',
        telephone: '+216 24 666 777',
        quartier: 'Résidence El Yasmine',
        residence: 'Résidence El Yasmine, Bloc D',
        logement: 'Bloc D - Appt 3',
        statut: StatutUtilisateur.bloque,
      ),
    ];
  }

  // =====================================================================
  // Mode démo
  // =====================================================================

  @override
  bool get estDemo {
    return true;
  }

  @override
  String? get aideDemoConnexion {
    return '$emailDemo / $motDePasseDemo';
  }

  @override
  String? get aideDemoCodeQuartier {
    return _quartiers.first.codeInvitation;
  }

  @override
  Future<void> simulerVerificationEmail() async {
    _emailsVerifies.add(_connecte.id);
  }

  @override
  Future<void> simulerValidation() async {
    _remplacer(_connecte.copier(statut: StatutUtilisateur.actif));
  }

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  @override
  Future<Resultat<Utilisateur>> connexion(
    String email,
    String motDePasse,
  ) async {
    final String texte = email.trim().toLowerCase();
    for (final Utilisateur membre in _membres) {
      if (membre.email.isNotEmpty &&
          membre.email.toLowerCase() == texte &&
          _motsDePasse[membre.id] == motDePasse) {
        // Même règle que Firebase : un compte bloqué reste déconnecté
        if (membre.statut == StatutUtilisateur.bloque) {
          return const Resultat.echec(
            'Ton compte a été bloqué par l\'administrateur',
          );
        }
        _connecte = membre;
        return Resultat.succes(membre);
      }
    }
    return const Resultat.echec('E-mail ou mot de passe incorrect');
  }

  @override
  Future<Resultat<Utilisateur>> inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  }) async {
    for (final Utilisateur membre in _membres) {
      if (membre.email.isNotEmpty &&
          membre.email.toLowerCase() == email.trim().toLowerCase()) {
        return const Resultat.echec('Un compte existe déjà avec cet e-mail');
      }
    }
    // Le nom complet est découpé : premier mot = prénom, le reste = nom
    final List<String> mots = nomComplet.trim().split(' ');
    final Utilisateur nouveau = Utilisateur(
      id: 'u$_prochainNumero',
      prenom: mots[0],
      nom: _reste(mots),
      email: email.trim(),
      telephone: telephone.trim(),
      quartier: '',
      residence: '',
      statut: StatutUtilisateur.enAttente,
    );
    _prochainNumero++;
    _motsDePasse[nouveau.id] = motDePasse;
    _connecte = nouveau;
    // Pas de vrai e-mail : la vérification se fait avec simulerVerificationEmail
    return Resultat.succes(nouveau);
  }

  @override
  Future<Resultat<void>> envoyerEmailVerification() async {
    // Pas de vrai e-mail : rien à envoyer
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<bool>> emailEstVerifie() async {
    return Resultat.succes(_emailsVerifies.contains(_connecte.id));
  }

  @override
  Future<void> deconnexion() async {
    // On garde le compte de démo "connecté" : le module Signalements lit
    // toujours getUtilisateurConnecte(), même depuis l'écran de démo
  }

  @override
  Future<Resultat<void>> envoyerLienReinitialisation(String email) async {
    // Pas de vrai e-mail : rien à envoyer
    return const Resultat.succes(null);
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
    return _connecte.email;
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
    _remplacer(
      _connecte.copier(
        prenom: mots[0],
        nom: _reste(mots),
        telephone: telephone.trim(),
        logement: logement.trim(),
        competences: competences,
        avatar: avatar,
      ),
    );
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Quartiers
  // =====================================================================

  @override
  Future<Resultat<List<Quartier>>> rechercherQuartiers(String recherche) async {
    final String texte = recherche.trim().toLowerCase();
    final List<Quartier> resultats = [];
    for (final Quartier quartier in _quartiers) {
      if (quartier.nom.toLowerCase().contains(texte) ||
          quartier.localisation.toLowerCase().contains(texte)) {
        resultats.add(quartier);
      }
    }
    return Resultat.succes(resultats);
  }

  @override
  Future<Resultat<Quartier?>> trouverParCode(String code) async {
    for (final Quartier quartier in _quartiers) {
      if (quartier.codeInvitation == code.toUpperCase()) {
        return Resultat.succes(quartier);
      }
    }
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> rejoindreQuartier(Quartier quartier) async {
    // Même règle que firestore.rules : e-mail vérifié obligatoire
    if (!_emailsVerifies.contains(_connecte.id)) {
      return const Resultat.echec('Action non autorisée');
    }
    final Utilisateur demande = _connecte.copier(
      quartierId: quartier.id,
      quartier: quartier.nom,
      residence: quartier.nom,
      statut: StatutUtilisateur.enAttente,
      dateDemande: DateTime.now(),
    );

    // On l'ajoute à la liste des membres (s'il n'y est pas déjà)
    bool dejaPresent = false;
    for (final Utilisateur membre in _membres) {
      if (membre.id == demande.id) {
        dejaPresent = true;
      }
    }
    if (!dejaPresent) {
      _membres.add(demande);
    }
    _remplacer(demande);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<Quartier?>> getQuartierConnecte() async {
    for (final Quartier quartier in _quartiers) {
      if (quartier.nom == _connecte.quartier) {
        return Resultat.succes(quartier);
      }
    }
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Administration des membres
  // =====================================================================

  @override
  Future<Resultat<List<Utilisateur>>> getMembres(
    StatutUtilisateur statut, {
    String recherche = '',
  }) async {
    final String texte = recherche.trim().toLowerCase();
    final List<Utilisateur> resultats = [];
    for (final Utilisateur membre in _membres) {
      if (membre.quartier == _connecte.quartier &&
          membre.statut == statut &&
          membre.nomComplet.toLowerCase().contains(texte)) {
        resultats.add(membre);
      }
    }
    return Resultat.succes(resultats);
  }

  @override
  Future<Resultat<int>> compterMembres(StatutUtilisateur statut) async {
    final Resultat<List<Utilisateur>> membres = await getMembres(statut);
    return Resultat.succes(membres.donnee!.length);
  }

  @override
  Future<Resultat<List<Utilisateur>>> getVoisins() {
    return getMembres(StatutUtilisateur.actif);
  }

  @override
  Future<Resultat<void>> validerMembre(String id) async {
    return _changerStatut(id, StatutUtilisateur.actif);
  }

  @override
  Future<Resultat<void>> refuserMembre(String id) async {
    // Comme Firebase : le membre passe "refuse" (il n'est plus dans les onglets)
    return _changerStatut(id, StatutUtilisateur.refuse);
  }

  @override
  Future<Resultat<void>> bloquerMembre(String id) async {
    return _changerStatut(id, StatutUtilisateur.bloque);
  }

  @override
  Future<Resultat<void>> debloquerMembre(String id) async {
    return _changerStatut(id, StatutUtilisateur.actif);
  }

  // =====================================================================
  // Outils internes
  // =====================================================================

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

  /// Remplace un membre (même id) dans la liste, et l'utilisateur
  /// connecté si c'est lui.
  void _remplacer(Utilisateur modifie) {
    for (int i = 0; i < _membres.length; i++) {
      if (_membres[i].id == modifie.id) {
        _membres[i] = modifie;
      }
    }
    if (_connecte.id == modifie.id) {
      _connecte = modifie;
    }
  }

  Resultat<void> _changerStatut(String id, StatutUtilisateur statut) {
    for (final Utilisateur membre in _membres) {
      if (membre.id == id) {
        _remplacer(membre.copier(statut: statut));
        return const Resultat.succes(null);
      }
    }
    return const Resultat.echec('Donnée introuvable');
  }
}
