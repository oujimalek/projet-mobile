import '../models/quartier.dart';
import '../models/utilisateur.dart';
import 'utilisateur_repository.dart';

/// M1 - Implémentation "fictive" de UtilisateurRepository.
///
/// Les données sont écrites en dur et gardées en mémoire : rien n'est
/// enregistré quand on relance l'application. Toute l'app partage la même
/// instance (UtilisateurRepository.instance), donc un changement fait sur un
/// écran (ex : un membre validé) est visible sur les autres écrans.
class MockUtilisateurRepository implements UtilisateurRepository {
  // Compte de démonstration (données fictives, pour tester l'écran de connexion)
  static const String emailDemo = 'demo@houmani.tn';
  static const String motDePasseDemo = 'houmani123';

  // Code de vérification reçu "par SMS" (fictif : on l'affiche dans l'écran)
  static const String codeOtpDemo = '123456';

  static const Utilisateur _utilisateurDemo = Utilisateur(
    id: 'u1',
    prenom: 'Amira',
    nom: 'Ben Salah',
    email: emailDemo,
    telephone: '+216 22 345 678',
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
  String? get aideDemoCodeSms {
    return codeOtpDemo;
  }

  @override
  String? get aideDemoCodeQuartier {
    return _quartiers.first.codeInvitation;
  }

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  @override
  Future<Utilisateur?> connexion(String identifiant, String motDePasse) async {
    final String texte = identifiant.trim();
    // Connexion par téléphone : on compare uniquement les chiffres,
    // donc "+216 22 345 678", "22345678" et "22 345 678" sont acceptés
    final String chiffresSaisis = _garderChiffres(texte);

    for (final Utilisateur membre in _membres) {
      bool memeCompte = false;
      if (texte.contains('@')) {
        memeCompte = membre.email.isNotEmpty && membre.email == texte;
      } else if (chiffresSaisis.length >= 8) {
        memeCompte = _garderChiffres(membre.telephone).endsWith(chiffresSaisis);
      }

      if (memeCompte && _motsDePasse[membre.id] == motDePasse) {
        _connecte = membre;
        return membre;
      }
    }
    return null;
  }

  @override
  Future<Utilisateur> inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  }) async {
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
    // Pas de vrai SMS : le code est toujours codeOtpDemo
    return nouveau;
  }

  @override
  Future<void> renvoyerCodeSms() async {
    // Pas de vrai SMS : rien à faire
  }

  @override
  Future<bool> verifierCode(String code) async {
    return code == codeOtpDemo;
  }

  @override
  Future<void> deconnexion() async {
    // On garde le compte de démo "connecté" : le module Signalements lit
    // toujours getUtilisateurConnecte(), même depuis l'écran de démo
  }

  @override
  Future<void> envoyerLienReinitialisation(String identifiant) async {
    // Pas de vrai e-mail ni SMS : rien à envoyer
  }

  // =====================================================================
  // Utilisateur connecté et profil
  // =====================================================================

  @override
  Utilisateur getUtilisateurConnecte() {
    return _connecte;
  }

  @override
  String telephoneMasque() {
    final String chiffres = _garderChiffres(_connecte.telephone);
    if (chiffres.length < 3) {
      return _connecte.telephone;
    }
    return '+216 •• ••• ${chiffres.substring(chiffres.length - 3)}';
  }

  @override
  Future<void> modifierProfil({
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
  }

  // =====================================================================
  // Quartiers
  // =====================================================================

  @override
  Future<List<Quartier>> rechercherQuartiers(String recherche) async {
    final String texte = recherche.trim().toLowerCase();
    final List<Quartier> resultats = [];
    for (final Quartier quartier in _quartiers) {
      if (quartier.nom.toLowerCase().contains(texte) ||
          quartier.localisation.toLowerCase().contains(texte)) {
        resultats.add(quartier);
      }
    }
    return resultats;
  }

  @override
  Future<Quartier?> trouverParCode(String code) async {
    for (final Quartier quartier in _quartiers) {
      if (quartier.codeInvitation == code.toUpperCase()) {
        return quartier;
      }
    }
    return null;
  }

  @override
  Future<void> rejoindreQuartier(Quartier quartier) async {
    final Utilisateur demande = _connecte.copier(
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
  }

  @override
  Future<Quartier?> getQuartierConnecte() async {
    for (final Quartier quartier in _quartiers) {
      if (quartier.nom == _connecte.quartier) {
        return quartier;
      }
    }
    return null;
  }

  // =====================================================================
  // Administration des membres
  // =====================================================================

  @override
  Future<List<Utilisateur>> getMembres(
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
    return resultats;
  }

  @override
  Future<int> compterMembres(StatutUtilisateur statut) async {
    final List<Utilisateur> membres = await getMembres(statut);
    return membres.length;
  }

  @override
  Future<List<Utilisateur>> getVoisins() {
    return getMembres(StatutUtilisateur.actif);
  }

  @override
  Future<void> validerMembre(String id) async {
    _changerStatut(id, StatutUtilisateur.actif);
  }

  @override
  Future<void> refuserMembre(String id) async {
    for (int i = 0; i < _membres.length; i++) {
      if (_membres[i].id == id) {
        _membres.removeAt(i);
        return;
      }
    }
  }

  @override
  Future<void> bloquerMembre(String id) async {
    _changerStatut(id, StatutUtilisateur.bloque);
  }

  @override
  Future<void> debloquerMembre(String id) async {
    _changerStatut(id, StatutUtilisateur.actif);
  }

  @override
  Future<void> simulerValidation() async {
    _remplacer(_connecte.copier(statut: StatutUtilisateur.actif));
  }

  // =====================================================================
  // Outils internes
  // =====================================================================

  /// Garde seulement les chiffres d'un texte ("+216 22" donne "21622").
  String _garderChiffres(String texte) {
    String chiffres = '';
    for (int i = 0; i < texte.length; i++) {
      if ('0123456789'.contains(texte[i])) {
        chiffres = chiffres + texte[i];
      }
    }
    return chiffres;
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

  void _changerStatut(String id, StatutUtilisateur statut) {
    for (final Utilisateur membre in _membres) {
      if (membre.id == id) {
        _remplacer(membre.copier(statut: statut));
        return;
      }
    }
  }
}
