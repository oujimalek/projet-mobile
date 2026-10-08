import '../models/quartier.dart';
import '../models/utilisateur.dart';
import 'mock_utilisateur_repository.dart';

/// M1 - Accès aux données des utilisateurs et des quartiers : le CONTRAT.
///
/// Cette classe abstraite liste ce que les écrans peuvent demander, sans dire
/// d'où viennent les données. Les écrans et les tests n'appellent QUE ces
/// méthodes, via `UtilisateurRepository()`.
///
/// Implémentations :
/// - MockUtilisateurRepository : données fictives en mémoire (aujourd'hui) ;
/// - plus tard, par exemple FirebaseUtilisateurRepository (Firebase Auth +
///   Firestore) : on crée ce fichier, puis on change UNE ligne ci-dessous
///   (`instance = ...`). Aucun écran n'est à modifier.
///
/// Les opérations qui passeront par le réseau renvoient un Future (il faut
/// `await`), même si le mock répond tout de suite : c'est ce qui permettra de
/// brancher Firebase sans retoucher les écrans.
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
  /// C'est la SEULE ligne à changer pour passer aux vraies données.
  /// Les tests la remplacent par un mock neuf avant chaque test.
  static UtilisateurRepository instance = MockUtilisateurRepository();

  /// `UtilisateurRepository()` ne crée pas d'objet : il renvoie l'instance
  /// ci-dessus. Les écrans écrivent donc toujours `UtilisateurRepository()`,
  /// quelle que soit l'implémentation branchée.
  factory UtilisateurRepository() {
    return instance;
  }

  // =====================================================================
  // Mode démo
  // =====================================================================

  /// true avec les données fictives : les écrans affichent alors les aides
  /// de démo et le raccourci "simuler la validation".
  bool get estDemo;

  /// Aides affichées sous les formulaires en mode démo (null = rien à afficher).
  String? get aideDemoConnexion; // ex : "demo@houmani.tn / houmani123"
  String? get aideDemoCodeSms; // ex : "123456"
  String? get aideDemoCodeQuartier; // ex : "YAS72B"

  // =====================================================================
  // Connexion et inscription
  // =====================================================================

  /// Vérifie l'identifiant (e-mail OU téléphone) et le mot de passe.
  /// Renvoie l'utilisateur si c'est correct, sinon null.
  /// L'écran regarde ensuite son statut (actif, en attente, bloqué).
  Future<Utilisateur?> connexion(String identifiant, String motDePasse);

  /// Crée un nouveau compte (statut "en attente", sans quartier pour
  /// l'instant), le connecte et envoie le premier code par SMS.
  Future<Utilisateur> inscription({
    required String nomComplet,
    required String telephone,
    required String email,
    required String motDePasse,
  });

  /// Renvoie un nouveau code par SMS (bouton "Renvoyer le code").
  Future<void> renvoyerCodeSms();

  /// Vérifie le code reçu par SMS.
  Future<bool> verifierCode(String code);

  /// Déconnecte l'utilisateur.
  Future<void> deconnexion();

  /// Envoie un lien de réinitialisation du mot de passe
  /// (bouton "Envoyer le lien" de l'écran "Mot de passe oublié").
  /// Ne dit pas si le compte existe : l'écran affiche toujours le même message.
  Future<void> envoyerLienReinitialisation(String identifiant);

  // =====================================================================
  // Utilisateur connecté et profil
  // =====================================================================

  /// L'utilisateur connecté. Synchrone : l'implémentation garde en mémoire
  /// le profil chargé à la connexion (le module Signalements s'en sert aussi).
  Utilisateur getUtilisateurConnecte();

  /// Le numéro masqué affiché sur l'écran du code SMS : "+216 •• ••• 678".
  String telephoneMasque();

  /// Enregistre les modifications du profil de l'utilisateur connecté.
  /// avatar : identifiant d'un avatar de la galerie, vide = initiales.
  Future<void> modifierProfil({
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
  Future<List<Quartier>> rechercherQuartiers(String recherche);

  /// Le quartier qui a ce code d'invitation, ou null si le code est inconnu.
  Future<Quartier?> trouverParCode(String code);

  /// Envoie la demande pour rejoindre un quartier :
  /// l'utilisateur connecté passe "en attente" de validation.
  Future<void> rejoindreQuartier(Quartier quartier);

  /// Le quartier de l'utilisateur connecté (ou null s'il n'en a pas).
  Future<Quartier?> getQuartierConnecte();

  // =====================================================================
  // Administration des membres
  // =====================================================================

  /// Les membres du quartier de l'utilisateur connecté qui ont ce statut,
  /// et dont le nom contient la recherche.
  Future<List<Utilisateur>> getMembres(
    StatutUtilisateur statut, {
    String recherche = '',
  });

  /// Le nombre de membres qui ont ce statut (pour les compteurs).
  Future<int> compterMembres(StatutUtilisateur statut);

  /// La liste des voisins actifs de la résidence.
  Future<List<Utilisateur>> getVoisins();

  /// L'admin accepte une demande : le membre devient actif.
  Future<void> validerMembre(String id);

  /// L'admin refuse une demande : elle est retirée de la liste.
  Future<void> refuserMembre(String id);

  /// L'admin bloque un membre actif.
  Future<void> bloquerMembre(String id);

  /// L'admin débloque un membre : il redevient actif.
  Future<void> debloquerMembre(String id);

  /// DÉMO uniquement : simule la validation par l'admin de la demande de
  /// l'utilisateur connecté. Une vraie implémentation n'a rien à faire ici
  /// (le bouton n'est affiché que si estDemo est vrai).
  Future<void> simulerValidation();
}
