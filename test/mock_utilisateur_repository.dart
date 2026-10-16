import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M1 - Implémentation "fictive" de UtilisateurRepository, pour les TESTS.
///
/// Les données sont écrites en dur et gardées en mémoire. Les tests
/// l'installent avant chaque test (`UtilisateurRepository.instance = ...`) :
/// ils marchent sans Internet et sans Firebase.
///
/// Elle suit le même contrat que FirebaseUtilisateurRepository (mêmes
/// Resultat, mêmes messages d'erreur) : les tests restent valables.
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
  // Pas const : l'admin peut changer le contour (enregistrerContour)
  final List<Quartier> _quartiers = [
    Quartier(
      id: 'q1',
      nom: 'Résidence El Yasmine',
      localisation: 'Ennasr 2, Ariana',
      codeInvitation: 'YAS72B',
      nbMembres: 42,
      // Seul quartier placé sur la carte (les autres : pas de coordonnées)
      position: PointGps(36.8625, 10.1700),
      contour: [
        PointGps(36.8640, 10.1680),
        PointGps(36.8640, 10.1720),
        PointGps(36.8610, 10.1720),
        PointGps(36.8610, 10.1680),
      ],
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
  // Raccourcis pour les tests (pas dans le contrat : Firebase n'en a pas)
  // =====================================================================

  /// Fait comme si l'utilisateur connecté avait cliqué sur le lien de l'e-mail.
  Future<void> simulerVerificationEmail() async {
    _emailsVerifies.add(_connecte.id);
  }

  /// Fait comme si l'admin avait validé la demande de l'utilisateur connecté.
  Future<void> simulerValidation() async {
    await simulerStatut(StatutUtilisateur.actif);
  }

  /// Fait comme si l'admin avait changé le statut de l'utilisateur connecté
  /// (refusé, bloqué...).
  Future<void> simulerStatut(StatutUtilisateur statut) async {
    _remplacer(_connecte.copier(statut: statut));
  }

  /// Ajoute un compte qui peut se connecter (e-mail déjà vérifié).
  void ajouterCompte(Utilisateur utilisateur, String motDePasse) {
    _membres.add(utilisateur);
    _motsDePasse[utilisateur.id] = motDePasse;
    _emailsVerifies.add(utilisateur.id);
  }

  /// Le profil "resté connecté" que restaurerSession() renvoie au
  /// démarrage (null : personne, comme au premier lancement).
  Utilisateur? sessionGardee;

  /// Si ce n'est pas null : la liste des membres échoue avec ce message
  /// (comme Firebase sans réseau).
  String? erreurMembres;

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  @override
  Future<Resultat<Utilisateur>> connexion(
    String identifiant,
    String motDePasse,
  ) async {
    // Comme Firebase : un numéro est d'abord traduit en e-mail
    // (ici : le membre qui a ce numéro)
    if (UtilisateurRepository.estUnNumero(identifiant)) {
      final Utilisateur? titulaire = _titulaireDuNumero(identifiant);
      if (titulaire == null || titulaire.email.isEmpty) {
        return const Resultat.echec('Numéro ou mot de passe incorrect');
      }
      final Resultat<Utilisateur> resultat =
          await connexion(titulaire.email, motDePasse);
      if (resultat.erreur == 'E-mail ou mot de passe incorrect') {
        return const Resultat.echec('Numéro ou mot de passe incorrect');
      }
      return resultat;
    }
    final String texte = identifiant.trim().toLowerCase();
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
    if (UtilisateurRepository.normaliserTelephone(telephone) == null) {
      return const Resultat.echec('Numéro de téléphone invalide (8 chiffres)');
    }
    if (_titulaireDuNumero(telephone) != null) {
      return const Resultat.echec('Ce numéro est déjà utilisé par un autre compte');
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
    // Ajouté tout de suite à la liste : il pourra se reconnecter, et le même
    // e-mail ne pourra pas être réutilisé (sans quartier, aucun admin ne le voit)
    _membres.add(nouveau);
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
  Future<Utilisateur?> restaurerSession() async {
    // Par défaut pas de session gardée : on passe par la connexion.
    // Comme Firebase : un compte bloqué n'est pas restauré.
    final Utilisateur? session = sessionGardee;
    if (session == null || session.statut == StatutUtilisateur.bloque) {
      return null;
    }
    _connecte = session;
    return session;
  }

  @override
  Future<Resultat<Utilisateur>> rafraichirProfil() async {
    // Les données sont déjà en mémoire : rien à recharger.
    // Comme Firebase : un compte bloqué est déconnecté.
    if (_connecte.statut == StatutUtilisateur.bloque) {
      _connecte = const Utilisateur(
        id: '',
        prenom: '',
        nom: '',
        email: '',
        telephone: '',
        quartier: '',
        residence: '',
      );
      return const Resultat.echec(
        'Ton compte a été bloqué par l\'administrateur',
      );
    }
    return Resultat.succes(_connecte);
  }

  @override
  Future<Resultat<void>> envoyerLienReinitialisation(String email) async {
    // Pas de vrai e-mail : rien à envoyer
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Code SMS
  // =====================================================================

  /// Le code que "reçoit" chaque numéro (pas de vrai SMS).
  static const String codeSmsDemo = '123456';

  // Les comptes dont le numéro a été vérifié par SMS (clé = id)
  final Set<String> _telephonesVerifies = {'u1'};

  // Les 8 chiffres qui ont reçu le dernier code (null : aucun envoi)
  String? _numeroSms;

  @override
  Future<Resultat<void>> envoyerCodeSms(String telephone) async {
    final String? numero = UtilisateurRepository.normaliserTelephone(telephone);
    if (numero == null) {
      return const Resultat.echec('Numéro de téléphone invalide (8 chiffres)');
    }
    _numeroSms = numero;
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<Utilisateur>> connexionParSms(String code) async {
    final String? numero = _numeroSms;
    if (numero == null) {
      return const Resultat.echec('Demande d\'abord un code');
    }
    if (code.trim() != codeSmsDemo) {
      return const Resultat.echec('Code incorrect');
    }
    final Utilisateur? titulaire = _titulaireDuNumero(numero);
    if (titulaire == null || !_telephonesVerifies.contains(titulaire.id)) {
      return const Resultat.echec(UtilisateurRepository.numeroNonVerifie);
    }
    if (titulaire.statut == StatutUtilisateur.bloque) {
      return const Resultat.echec(
        'Ton compte a été bloqué par l\'administrateur',
      );
    }
    _connecte = titulaire;
    return Resultat.succes(titulaire);
  }

  @override
  Future<Resultat<void>> verifierTelephone(String code) async {
    if (_connecte.id.isEmpty) {
      return const Resultat.echec('Tu n\'es pas connecté');
    }
    final String? numero =
        UtilisateurRepository.normaliserTelephone(_connecte.telephone);
    if (numero == null || _numeroSms != numero) {
      return const Resultat.echec(
        'Le code doit être envoyé au numéro de ton profil',
      );
    }
    if (code.trim() != codeSmsDemo) {
      return const Resultat.echec('Code incorrect');
    }
    _telephonesVerifies.add(_connecte.id);
    return const Resultat.succes(null);
  }

  @override
  bool telephoneEstVerifie() {
    return _telephonesVerifies.contains(_connecte.id);
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
    final Utilisateur? titulaire = _titulaireDuNumero(telephone);
    if (titulaire != null && titulaire.id != _connecte.id) {
      return const Resultat.echec('Ce numéro est déjà utilisé par un autre compte');
    }
    // Comme Firebase : un nouveau numéro doit être vérifié à nouveau
    if (UtilisateurRepository.normaliserTelephone(telephone) !=
        UtilisateurRepository.normaliserTelephone(_connecte.telephone)) {
      _telephonesVerifies.remove(_connecte.id);
    }
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
  // Sécurité du compte
  // =====================================================================

  /// La nouvelle adresse demandée avec changerEmail (Firebase attendrait
  /// le clic sur le lien ; ici, les tests la regardent).
  String? emailEnAttente;

  @override
  Future<Resultat<void>> changerMotDePasse(String ancien, String nouveau) async {
    if (!_bonMotDePasse(ancien)) {
      return const Resultat.echec('Mot de passe actuel incorrect');
    }
    _motsDePasse[_connecte.id] = nouveau;
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> changerEmail(
    String nouvelEmail,
    String motDePasse,
  ) async {
    if (!_bonMotDePasse(motDePasse)) {
      return const Resultat.echec('Mot de passe actuel incorrect');
    }
    final String texte = nouvelEmail.trim().toLowerCase();
    for (final Utilisateur membre in _membres) {
      if (membre.email.toLowerCase() == texte) {
        return const Resultat.echec('Un compte existe déjà avec cet e-mail');
      }
    }
    emailEnAttente = nouvelEmail.trim();
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerCompte(String motDePasse) async {
    if (_connecte.estAdmin) {
      return const Resultat.echec(
        'Un administrateur ne peut pas supprimer son compte : '
        'contacte l\'équipe Houmani',
      );
    }
    if (!_bonMotDePasse(motDePasse)) {
      return const Resultat.echec('Mot de passe actuel incorrect');
    }
    final String id = _connecte.id;
    _membres.removeWhere((Utilisateur membre) => membre.id == id);
    _motsDePasse.remove(id);
    _emailsVerifies.remove(id);
    _telephonesVerifies.remove(id);
    _connecte = const Utilisateur(
      id: '',
      prenom: '',
      nom: '',
      email: '',
      telephone: '',
      quartier: '',
      residence: '',
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
    final String? refus =
        UtilisateurRepository.refusChangement(_connecte, quartier);
    if (refus != null) {
      return Resultat.echec(refus);
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

  @override
  Future<Resultat<String?>> getCodeInvitation() async {
    if (!_connecte.estAdmin) {
      return const Resultat.echec('Action non autorisée');
    }
    for (final Quartier quartier in _quartiers) {
      if (quartier.nom == _connecte.quartier) {
        return Resultat.succes(quartier.codeInvitation);
      }
    }
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> enregistrerContour(List<PointGps> contour) async {
    final String? refus = UtilisateurRepository.refusContour(_connecte, contour);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    for (int i = 0; i < _quartiers.length; i++) {
      final Quartier ancien = _quartiers[i];
      if (ancien.nom == _connecte.quartier) {
        _quartiers[i] = Quartier(
          id: ancien.id,
          nom: ancien.nom,
          localisation: ancien.localisation,
          codeInvitation: ancien.codeInvitation,
          nbMembres: ancien.nbMembres,
          position: Quartier.milieu(contour),
          contour: List.of(contour),
        );
        return const Resultat.succes(null);
      }
    }
    return const Resultat.echec('Quartier introuvable');
  }

  // =====================================================================
  // Administration des membres
  // =====================================================================

  @override
  Future<Resultat<List<Utilisateur>>> getMembres(
    StatutUtilisateur statut, {
    String recherche = '',
  }) async {
    if (erreurMembres != null) {
      return Resultat.echec(erreurMembres!);
    }
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
    if (!membres.estSucces) {
      return Resultat.echec(membres.erreur!);
    }
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

  /// Le mot de passe redemandé est-il celui du compte connecté ?
  bool _bonMotDePasse(String motDePasse) {
    return _motsDePasse[_connecte.id] == motDePasse;
  }

  /// Le membre qui a ce numéro (null : numéro libre ou invalide).
  /// Joue le rôle de la collection telephones/{numero} de Firebase.
  Utilisateur? _titulaireDuNumero(String telephone) {
    final String? numero = UtilisateurRepository.normaliserTelephone(telephone);
    if (numero == null) {
      return null;
    }
    for (final Utilisateur membre in _membres) {
      if (UtilisateurRepository.normaliserTelephone(membre.telephone) ==
          numero) {
        return membre;
      }
    }
    return null;
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
