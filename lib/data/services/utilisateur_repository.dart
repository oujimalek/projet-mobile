import '../models/quartier.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'mock_utilisateur_repository.dart';

/// M1 - Accès aux données des utilisateurs et des quartiers : le CONTRAT.
///
/// Cette classe abstraite liste ce que les écrans peuvent demander, sans dire
/// d'où viennent les données. Les écrans et les tests n'appellent QUE ces
/// méthodes, via `UtilisateurRepository()`.
///
/// Implémentations :
/// - FirebaseUtilisateurRepository : Firebase Auth + Cloud Firestore ;
/// - MockUtilisateurRepository : données fictives en mémoire (tests, et
///   l'application jusqu'à la phase 5).
/// Pour changer de source, on change UNE ligne ci-dessous (`instance = ...`).
///
/// Les opérations qui passent par le réseau renvoient un
/// `Future<Resultat<...>>` : il faut `await`, puis regarder
/// `resultat.estSucces`. En cas d'échec, `resultat.erreur` contient un
/// message en français à afficher (voir lib/data/resultat.dart).
///
/// ---------------------------------------------------------------------
/// RECOMMANDATION POUR LES MODULES 2, 3 ET 4 (Services, Signalements,
/// Événements) : ServiceRepository, SignalementRepository et
/// EvenementRepository sont encore des classes concrètes avec des données
/// en dur et des méthodes synchrones. Pour que toute l'équipe accède aux
/// données de la même façon, suivez ce même modèle avant de brancher une
/// vraie source :
///   1. `abstract class XRepository` (le contrat, avec des Future) ;
///   2. `MockXRepository implements XRepository` (les données fictives) ;
///   3. `static XRepository instance = MockXRepository();` + le `factory`
///      ci-dessous, pour que les écrans continuent d'écrire `XRepository()`.
/// ---------------------------------------------------------------------
abstract class UtilisateurRepository {
  /// L'implémentation utilisée par toute l'application.
  /// C'est la SEULE ligne à changer pour passer aux vraies données
  /// (phase 5 : FirebaseUtilisateurRepository()).
  /// Les tests la remplacent par un mock neuf avant chaque test.
  static UtilisateurRepository instance = MockUtilisateurRepository();

  /// `UtilisateurRepository()` ne crée pas d'objet : il renvoie l'instance
  /// ci-dessus. Les écrans écrivent donc toujours `UtilisateurRepository()`,
  /// quelle que soit l'implémentation branchée.
  factory UtilisateurRepository() {
    return instance;
  }

  // =====================================================================
  // Mode démo (supprimé en phase 5, avec le mock qui part dans test/)
  // =====================================================================

  /// true avec les données fictives : les écrans affichent alors les aides
  /// de démo et les raccourcis "simuler ...".
  bool get estDemo;

  /// Aides affichées sous les formulaires en mode démo (null = rien à afficher).
  String? get aideDemoConnexion; // ex : "demo@houmani.tn / houmani123"
  String? get aideDemoCodeQuartier; // ex : "YAS72B"

  /// DÉMO : fait comme si l'utilisateur avait cliqué sur le lien reçu par
  /// e-mail. Ne fait rien avec Firebase.
  Future<void> simulerVerificationEmail();

  /// DÉMO : simule la validation par l'admin de la demande de l'utilisateur
  /// connecté. Ne fait rien avec Firebase.
  Future<void> simulerValidation();

  // =====================================================================
  // Connexion et inscription (Firebase Auth : e-mail + mot de passe)
  // =====================================================================

  /// Vérifie l'e-mail et le mot de passe, puis charge le profil.
  /// Succès : l'utilisateur (l'écran regarde ensuite son statut).
  /// Échec : mauvais identifiants, pas de réseau, compte bloqué...
  Future<Resultat<Utilisateur>> connexion(String email, String motDePasse);

  /// Crée le compte (statut "en attente", sans quartier), le connecte,
  /// et envoie l'e-mail de vérification.
  /// Le téléphone est seulement un champ du profil.
  Future<Resultat<Utilisateur>> inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  });

  /// (Ré)envoie l'e-mail de vérification à l'utilisateur connecté.
  Future<Resultat<void>> envoyerEmailVerification();

  /// L'utilisateur a-t-il cliqué sur le lien reçu par e-mail ?
  /// (bouton "J'ai vérifié mon e-mail")
  Future<Resultat<bool>> emailEstVerifie();

  /// Déconnecte l'utilisateur.
  Future<void> deconnexion();

  /// Au démarrage de l'app : retrouve l'utilisateur resté connecté
  /// (version à jour du serveur ; sans réseau, le profil du cache local).
  /// null = personne de connecté, il faut passer par l'écran de connexion.
  Future<Utilisateur?> restaurerSession();

  /// Envoie un lien de réinitialisation du mot de passe à cet e-mail.
  /// Ne dit pas si le compte existe : l'écran affiche toujours le même message.
  Future<Resultat<void>> envoyerLienReinitialisation(String email);

  // =====================================================================
  // Utilisateur connecté et profil
  // =====================================================================

  /// L'utilisateur connecté. SYNCHRONE et ne lève jamais d'exception :
  /// l'implémentation garde en mémoire le profil chargé à la connexion
  /// (les modules Services et Signalements s'en servent aussi).
  /// Personne de connecté : un utilisateur vide (id '').
  Utilisateur getUtilisateurConnecte();

  /// L'adresse e-mail affichée sur l'écran de vérification.
  String emailConnecte();

  /// Enregistre les modifications du profil de l'utilisateur connecté.
  /// avatar : identifiant d'un avatar de la galerie, vide = initiales.
  Future<Resultat<void>> modifierProfil({
    required String nomComplet,
    required String telephone,
    required String logement,
    required List<String> competences,
    String avatar = '',
  });

  // =====================================================================
  // Quartiers
  // =====================================================================

  /// Les quartiers dont le nom ou la localisation contient le texte cherché.
  Future<Resultat<List<Quartier>>> rechercherQuartiers(String recherche);

  /// Le quartier qui a ce code d'invitation.
  /// Succès avec `donnee == null` : le code n'existe pas.
  Future<Resultat<Quartier?>> trouverParCode(String code);

  /// Envoie la demande pour rejoindre un quartier :
  /// l'utilisateur connecté passe "en attente" de validation.
  /// (Firebase exige un e-mail vérifié.)
  Future<Resultat<void>> rejoindreQuartier(Quartier quartier);

  /// Le quartier de l'utilisateur connecté (`donnee == null` s'il n'en a pas).
  Future<Resultat<Quartier?>> getQuartierConnecte();

  // =====================================================================
  // Administration des membres
  // =====================================================================

  /// Les membres du quartier de l'utilisateur connecté qui ont ce statut,
  /// et dont le nom contient la recherche.
  Future<Resultat<List<Utilisateur>>> getMembres(
    StatutUtilisateur statut, {
    String recherche = '',
  });

  /// Le nombre de membres qui ont ce statut (pour les compteurs).
  Future<Resultat<int>> compterMembres(StatutUtilisateur statut);

  /// La liste des voisins actifs du quartier.
  Future<Resultat<List<Utilisateur>>> getVoisins();

  /// L'admin accepte une demande : le membre devient actif.
  Future<Resultat<void>> validerMembre(String id);

  /// L'admin refuse une demande : le membre passe "refuse"
  /// (il pourra choisir un autre quartier).
  Future<Resultat<void>> refuserMembre(String id);

  /// L'admin bloque un membre actif.
  Future<Resultat<void>> bloquerMembre(String id);

  /// L'admin débloque un membre : il redevient actif.
  Future<Resultat<void>> debloquerMembre(String id);
}
