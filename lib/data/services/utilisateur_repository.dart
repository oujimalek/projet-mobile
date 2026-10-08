import '../models/quartier.dart';
import '../models/utilisateur.dart';

/// M1 - Accès aux données des utilisateurs et des quartiers.
///
/// Pour l'instant les données sont écrites en dur (données fictives).
/// Plus tard, seul l'intérieur de ces méthodes changera (appel à une API) :
/// les écrans, eux, ne changeront pas.
///
/// Les données modifiables sont "static" : elles sont partagées par tous
/// les UtilisateurRepository(), donc un changement fait sur un écran
/// (ex : un membre validé) est visible sur les autres écrans.
class UtilisateurRepository {
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
  static Utilisateur _connecte = _utilisateurDemo;

  // Les mots de passe des comptes (clé = id de l'utilisateur)
  static final Map<String, String> _motsDePasse = {'u1': motDePasseDemo};

  // Numéro du prochain compte créé (u100, u101, ...)
  static int _prochainNumero = 100;

  // Tous les membres de la houma de l'admin, quel que soit leur statut
  static final List<Utilisateur> _membres = _membresDeDepart();

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
  // Connexion et inscription
  // =====================================================================

  /// Vérifie l'identifiant (e-mail OU téléphone) et le mot de passe.
  /// Renvoie l'utilisateur si c'est correct, sinon null.
  /// L'écran regarde ensuite son statut (actif, en attente, bloqué).
  Utilisateur? connexion(String identifiant, String motDePasse) {
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

  /// Crée un nouveau compte (statut "en attente", sans quartier pour l'instant).
  /// Le nom complet est découpé : premier mot = prénom, le reste = nom.
  Utilisateur inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  }) {
    final List<String> mots = nomComplet.trim().split(' ');
    final String prenom = mots[0];
    String nom = '';
    for (int i = 1; i < mots.length; i++) {
      if (mots[i].isNotEmpty) {
        nom = nom.isEmpty ? mots[i] : '$nom ${mots[i]}';
      }
    }

    final Utilisateur nouveau = Utilisateur(
      id: 'u$_prochainNumero',
      prenom: prenom,
      nom: nom,
      email: email.trim(),
      telephone: telephone.trim(),
      quartier: '',
      residence: '',
      statut: StatutUtilisateur.enAttente,
    );
    _prochainNumero++;
    _motsDePasse[nouveau.id] = motDePasse;
    _connecte = nouveau;
    return nouveau;
  }

  /// Vérifie le code reçu par SMS.
  bool verifierCode(String code) {
    return code == codeOtpDemo;
  }

  /// Le numéro masqué affiché sur l'écran OTP : "+216 •• ••• 678".
  String telephoneMasque() {
    final String chiffres = _garderChiffres(_connecte.telephone);
    if (chiffres.length < 3) {
      return _connecte.telephone;
    }
    return '+216 •• ••• ${chiffres.substring(chiffres.length - 3)}';
  }

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

  // =====================================================================
  // Utilisateur connecté et profil
  // =====================================================================

  /// L'utilisateur actuellement connecté (fictif pour l'instant).
  Utilisateur getUtilisateurConnecte() {
    return _connecte;
  }

  /// Enregistre les modifications du profil de l'utilisateur connecté.
  void modifierProfil({
    required String nomComplet,
    required String telephone,
    required String logement,
    required List<String> competences,
  }) {
    final List<String> mots = nomComplet.trim().split(' ');
    String nom = '';
    for (int i = 1; i < mots.length; i++) {
      if (mots[i].isNotEmpty) {
        nom = nom.isEmpty ? mots[i] : '$nom ${mots[i]}';
      }
    }
    _remplacer(
      _connecte.copier(
        prenom: mots[0],
        nom: nom,
        telephone: telephone.trim(),
        logement: logement.trim(),
        competences: competences,
      ),
    );
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

  // =====================================================================
  // Quartiers
  // =====================================================================

  /// Les quartiers dont le nom ou la localisation contient le texte cherché.
  List<Quartier> rechercherQuartiers(String recherche) {
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

  /// Le quartier qui a ce code d'invitation, ou null si le code est inconnu.
  Quartier? trouverParCode(String code) {
    for (final Quartier quartier in _quartiers) {
      if (quartier.codeInvitation == code.toUpperCase()) {
        return quartier;
      }
    }
    return null;
  }

  /// Envoie la demande pour rejoindre un quartier :
  /// l'utilisateur connecté passe "en attente" de validation.
  void rejoindreQuartier(Quartier quartier) {
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

  /// Le quartier de l'utilisateur connecté (ou null s'il n'en a pas).
  Quartier? getQuartierConnecte() {
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

  /// Les membres du quartier de l'utilisateur connecté qui ont ce statut,
  /// et dont le nom contient la recherche.
  List<Utilisateur> getMembres(StatutUtilisateur statut, {String recherche = ''}) {
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

  /// Le nombre de membres qui ont ce statut (pour les compteurs des onglets).
  int compterMembres(StatutUtilisateur statut) {
    return getMembres(statut).length;
  }

  /// La liste des voisins actifs de la résidence.
  List<Utilisateur> getVoisins() {
    return getMembres(StatutUtilisateur.actif);
  }

  /// L'admin accepte une demande : le membre devient actif.
  void validerMembre(String id) {
    _changerStatut(id, StatutUtilisateur.actif);
  }

  /// L'admin refuse une demande : elle est retirée de la liste.
  void refuserMembre(String id) {
    for (int i = 0; i < _membres.length; i++) {
      if (_membres[i].id == id) {
        _membres.removeAt(i);
        return;
      }
    }
  }

  /// L'admin bloque un membre actif.
  void bloquerMembre(String id) {
    _changerStatut(id, StatutUtilisateur.bloque);
  }

  /// L'admin débloque un membre : il redevient actif.
  void debloquerMembre(String id) {
    _changerStatut(id, StatutUtilisateur.actif);
  }

  void _changerStatut(String id, StatutUtilisateur statut) {
    for (final Utilisateur membre in _membres) {
      if (membre.id == id) {
        _remplacer(membre.copier(statut: statut));
        return;
      }
    }
  }

  /// DÉMO uniquement : simule la validation par l'admin de la demande
  /// de l'utilisateur connecté (en vrai, c'est l'admin qui valide).
  void simulerValidation() {
    _remplacer(_connecte.copier(statut: StatutUtilisateur.actif));
  }
}
