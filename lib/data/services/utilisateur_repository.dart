import '../models/quartier.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firebase_utilisateur_repository.dart';

/// M1 - Accès aux données des utilisateurs et des quartiers : le CONTRAT.
///
/// Cette classe abstraite liste ce que les écrans peuvent demander, sans dire
/// d'où viennent les données. Les écrans et les tests n'appellent QUE ces
/// méthodes, via `UtilisateurRepository()`.
///
/// Implémentations :
/// - FirebaseUtilisateurRepository : Firebase Auth + Cloud Firestore
///   (celle de l'application) ;
/// - MockUtilisateurRepository (dans test/) : données fictives en mémoire,
///   que les tests installent avec `UtilisateurRepository.instance = ...`.
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
  /// Les tests la remplacent par un mock neuf avant chaque test.
  static UtilisateurRepository instance = FirebaseUtilisateurRepository();

  /// `UtilisateurRepository()` ne crée pas d'objet : il renvoie l'instance
  /// ci-dessus. Les écrans écrivent donc toujours `UtilisateurRepository()`,
  /// quelle que soit l'implémentation branchée.
  factory UtilisateurRepository() {
    return instance;
  }

  /// Pourquoi [utilisateur] ne peut pas demander [quartier] (null : il peut).
  /// Partagé par les deux implémentations ; firestore.rules vérifie la
  /// même chose côté serveur.
  static String? refusChangement(Utilisateur utilisateur, Quartier quartier) {
    if (utilisateur.statut != StatutUtilisateur.actif) {
      return null; // en attente ou refusé : il choisit librement
    }
    if (utilisateur.estAdmin) {
      return 'Un administrateur ne peut pas quitter son quartier';
    }
    if (utilisateur.quartierId == quartier.id) {
      return 'Tu fais déjà partie de ce quartier';
    }
    return null;
  }

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

  /// Recharge le profil de l'utilisateur connecté depuis le serveur
  /// (ex : écran d'attente, pour voir si l'admin a validé la demande).
  Future<Resultat<Utilisateur>> rafraichirProfil();

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
  // Sécurité du compte (écran Paramètres)
  // =====================================================================
  // Firebase exige une connexion récente pour ces opérations : on redemande
  // donc le mot de passe actuel (preuve que c'est bien le propriétaire).

  /// Remplace le mot de passe (l'ancien est vérifié d'abord).
  Future<Resultat<void>> changerMotDePasse(String ancien, String nouveau);

  /// Envoie un lien de confirmation à la NOUVELLE adresse. L'e-mail ne
  /// change qu'après le clic sur ce lien (puis il faut se reconnecter).
  Future<Resultat<void>> changerEmail(String nouvelEmail, String motDePasse);

  /// Supprime le profil puis le compte, et déconnecte (droit à la
  /// suppression, loi 2004-63). Refusé pour un administrateur : son
  /// quartier resterait sans admin.
  Future<Resultat<void>> supprimerCompte(String motDePasse);

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
  /// Sert aussi à CHANGER de quartier (écran Mon quartier) : un résident
  /// actif quitte le sien et attend la validation du nouveau. Refusé pour
  /// un administrateur (son quartier resterait sans admin) et pour le
  /// quartier où l'on est déjà.
  Future<Resultat<void>> rejoindreQuartier(Quartier quartier);

  /// Le quartier de l'utilisateur connecté (`donnee == null` s'il n'en a pas).
  Future<Resultat<Quartier?>> getQuartierConnecte();

  /// Le code d'invitation du quartier, pour que l'admin le partage.
  /// Réservé à l'admin (`donnee == null` : aucun code trouvé).
  Future<Resultat<String?>> getCodeInvitation();

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
