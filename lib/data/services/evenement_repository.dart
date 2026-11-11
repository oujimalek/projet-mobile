import '../models/evenement.dart';
import '../models/sondage.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firebase_evenement_repository.dart';

/// M4 - Accès aux événements et aux sondages du quartier : le CONTRAT.
///
/// Implémentations :
/// - FirebaseEvenementRepository : Cloud Firestore (celle de l'application) ;
/// - MockEvenementRepository (dans test/) : données en mémoire, que les
///   tests installent avec `EvenementRepository.instance = ...`.
///
/// Les opérations réseau renvoient `Future<Resultat<...>>` (voir
/// lib/data/resultat.dart). [getEvenements] et [getSondageActif] restent
/// SYNCHRONES : l'accueil les appelle sans attendre, ils renvoient la
/// dernière liste chargée.
///
/// Collections écrites (sous quartiers/{quartierId}/) : evenements
/// (+ participants) et sondages (+ votes). Format : docs/schema_firestore.md.
abstract class EvenementRepository {
  /// L'implémentation utilisée par toute l'application.
  static EvenementRepository instance = FirebaseEvenementRepository();

  /// `EvenementRepository()` renvoie l'instance ci-dessus (pas de nouvel objet).
  factory EvenementRepository() {
    return instance;
  }

  // =====================================================================
  // Règles métier (communes à Firebase et au mock)
  // =====================================================================

  static const int titreMax = 80;
  static const int descriptionMax = 500;
  static const int optionsMin = 2; // vérifié aussi par firestore.rules
  static const int optionsMax = 6;

  /// Le nom affiché d'un voisin : "Salma G.".
  static String nomCourt(Utilisateur utilisateur) {
    String initialeNom = '';
    if (utilisateur.nom.isNotEmpty) {
      initialeNom = ' ${utilisateur.nom[0]}.';
    }
    return '${utilisateur.prenom}$initialeNom';
  }

  /// Pourquoi cet événement ne peut pas être enregistré (null : il peut).
  static String? refusEvenement({
    required String titre,
    required String description,
    required String lieu,
    required DateTime date,
    DateTime? dateFin,
  }) {
    if (titre.trim().isEmpty) {
      return 'Donne un titre à l\'événement';
    }
    if (titre.trim().length > titreMax) {
      return 'Titre trop long ($titreMax caractères au maximum)';
    }
    if (description.trim().length > descriptionMax) {
      return 'Description trop longue ($descriptionMax caractères au maximum)';
    }
    if (lieu.trim().isEmpty) {
      return 'Indique le lieu';
    }
    if (date.isBefore(DateTime.now())) {
      return 'La date doit être dans le futur';
    }
    if (dateFin != null && !dateFin.isAfter(date)) {
      return 'L\'heure de fin doit être après l\'heure de début';
    }
    return null;
  }

  /// Pourquoi ce sondage ne peut pas être créé (null : il peut).
  static String? refusSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
  }) {
    if (question.trim().isEmpty) {
      return 'Écris la question du sondage';
    }
    int remplies = 0;
    for (final String option in options) {
      if (option.trim().isNotEmpty) {
        remplies++;
      }
    }
    if (remplies < optionsMin) {
      return 'Propose au moins $optionsMin choix';
    }
    if (remplies > optionsMax) {
      return '$optionsMax choix au maximum';
    }
    if (dateFin.isBefore(DateTime.now())) {
      return 'La date de fin doit être dans le futur';
    }
    return null;
  }

  /// Pourquoi ce vote est refusé (null : il est accepté).
  /// [monVote] : l'option déjà choisie, null si pas encore voté.
  static String? refusVote(Sondage sondage, int choix, int? monVote) {
    if (monVote != null) {
      return 'Tu as déjà voté';
    }
    if (!sondage.estOuvert) {
      return 'Ce sondage est terminé';
    }
    if (choix < 0 || choix >= sondage.options.length) {
      return 'Choix invalide';
    }
    return null;
  }

  /// true si [utilisateur] peut supprimer ce contenu : son auteur ou l'admin.
  static bool peutSupprimer(Utilisateur utilisateur, String auteurId) {
    return utilisateur.id == auteurId || utilisateur.estAdmin;
  }

  /// true si [utilisateur] peut modifier l'événement : l'organisateur ou l'admin.
  static bool peutModifier(Utilisateur utilisateur, Evenement evenement) {
    return utilisateur.id == evenement.organisateurId || utilisateur.estAdmin;
  }

  /// Les noms des participants ne sont montrés qu'à l'organisateur et à
  /// l'admin ; les autres voisins voient seulement le nombre.
  static bool peutVoirParticipants(Utilisateur utilisateur, Evenement evenement) {
    return peutModifier(utilisateur, evenement);
  }

  // =====================================================================
  // Événements
  // =====================================================================

  /// Les événements à venir de la dernière liste chargée (pour l'accueil).
  /// Ne lève jamais d'exception ; liste vide si rien n'est encore chargé.
  List<Evenement> getEvenements();

  /// Tous les événements du quartier, du plus proche au plus lointain.
  Future<Resultat<List<Evenement>>> chargerEvenements();

  /// Un événement par son id (pour l'écran de détail).
  Future<Resultat<Evenement>> getEvenement(String evenementId);

  /// Crée un événement dont l'utilisateur connecté est l'organisateur.
  Future<Resultat<void>> creerEvenement({
    required String titre,
    required String description,
    required DateTime date,
    DateTime? dateFin,
    required String lieu,
    required CategorieEvenement categorie,
  });

  /// L'organisateur (ou l'admin) modifie titre, description, dates, lieu
  /// et catégorie. Le compteur de participants ne change pas.
  Future<Resultat<void>> modifierEvenement(Evenement evenement);

  /// L'organisateur (ou l'admin) supprime l'événement.
  Future<Resultat<void>> supprimerEvenement(String evenementId);

  /// true si l'utilisateur connecté participe à cet événement.
  Future<Resultat<bool>> estInscrit(String evenementId);

  /// Les noms des participants.
  Future<Resultat<List<String>>> getParticipants(String evenementId);

  /// Je participe : ma fiche + compteur +1 (en une seule écriture).
  Future<Resultat<void>> participer(String evenementId);

  /// Je me retire : ma fiche supprimée + compteur -1 (en une seule écriture).
  Future<Resultat<void>> seRetirer(String evenementId);

  // =====================================================================
  // Sondages
  // =====================================================================

  /// Le sondage ouvert qui se termine le plus tôt (dernier chargement),
  /// null s'il n'y en a pas. Pour l'accueil : ne lève jamais d'exception.
  Sondage? getSondageActif();

  /// Tous les sondages, avec leurs votes, les ouverts d'abord.
  Future<Resultat<List<Sondage>>> chargerSondages();

  /// Crée un sondage proposé par l'utilisateur connecté.
  Future<Resultat<void>> creerSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
  });

  /// L'auteur (ou l'admin) supprime le sondage.
  Future<Resultat<void>> supprimerSondage(String sondageId);

  /// L'option choisie par l'utilisateur connecté, null s'il n'a pas voté.
  Future<Resultat<int?>> getMonVote(String sondageId);

  /// Vote pour l'option [choix] (0, 1, 2...). Un seul vote, définitif.
  Future<Resultat<void>> voter(Sondage sondage, int choix);
}
