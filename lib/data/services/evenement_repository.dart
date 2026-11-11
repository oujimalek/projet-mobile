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

  /// true si [utilisateur] peut créer des événements et des sondages :
  /// un leader ou l'admin (vérifié aussi par firestore.rules).
  static bool peutOrganiser(Utilisateur utilisateur) {
    return utilisateur.estLeader || utilisateur.estAdmin;
  }

  static const String refusOrganiser =
      'Seuls les leaders et l\'admin du quartier peuvent organiser';

  /// Les événements à rappeler : ceux où je participe, qui ont lieu
  /// aujourd'hui (pas encore terminés) ou demain, du plus proche au plus loin.
  static List<Evenement> rappels(
    List<Evenement> evenements,
    Set<String> mesParticipations,
    DateTime maintenant,
  ) {
    final DateTime aujourdhui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime apresDemain = aujourdhui.add(const Duration(days: 2));
    final List<Evenement> liste = [];
    for (final Evenement evenement in evenements) {
      final DateTime fin = evenement.dateFin ?? evenement.date;
      if (!evenement.annule &&
          mesParticipations.contains(evenement.id) &&
          fin.isAfter(maintenant) &&
          evenement.date.isBefore(apresDemain)) {
        liste.add(evenement);
      }
    }
    liste.sort((a, b) => a.date.compareTo(b.date));
    return liste;
  }

  /// "Rappel : demain à 18:00, Fête des voisins (Jardin)"
  static String texteRappel(Evenement evenement, DateTime maintenant) {
    final DateTime aujourdhui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime jour =
        DateTime(evenement.date.year, evenement.date.month, evenement.date.day);
    final String quand = jour == aujourdhui ? 'aujourd\'hui' : 'demain';
    final String heure =
        '${evenement.date.hour.toString().padLeft(2, '0')}:${evenement.date.minute.toString().padLeft(2, '0')}';
    return 'Rappel : $quand à $heure, ${evenement.titre} (${evenement.lieu})';
  }

  /// Pourquoi on ne peut pas s'inscrire à cet événement (null : on peut).
  static String? refusParticipation(Evenement evenement) {
    if (evenement.annule) {
      return 'Cet événement est annulé';
    }
    if (evenement.estPasse) {
      return 'Cet événement est terminé';
    }
    if (evenement.estComplet) {
      return 'Cet événement est complet';
    }
    return null;
  }

  static const int placesLimite = 500;

  /// Pourquoi ce nombre de places est refusé (null : accepté). 0 = sans limite.
  /// En modification, on ne descend pas sous le nombre d'inscrits.
  static String? refusPlaces(int placesMax, {int inscrits = 0}) {
    if (placesMax < 0 || placesMax > placesLimite) {
      return 'Entre 1 et $placesLimite places (ou sans limite)';
    }
    if (placesMax > 0 && placesMax < inscrits) {
      return 'Déjà $inscrits inscrits : choisis au moins $inscrits places';
    }
    return null;
  }

  /// Le texte partagé (WhatsApp, SMS...) pour inviter un voisin.
  static String texteInvitation(Evenement evenement) {
    final String heure =
        '${evenement.date.hour.toString().padLeft(2, '0')}:${evenement.date.minute.toString().padLeft(2, '0')}';
    final String date =
        '${evenement.date.day.toString().padLeft(2, '0')}/${evenement.date.month.toString().padLeft(2, '0')}/${evenement.date.year}';
    final StringBuffer texte = StringBuffer()
      ..writeln('📅 ${evenement.titre}')
      ..writeln('🕒 $date à $heure')
      ..writeln('📍 ${evenement.lieu}');
    if (evenement.description.isNotEmpty) {
      texte.writeln(evenement.description);
    }
    texte.write('Organisé par ${evenement.organisateur} · sur Houmani');
    return texte.toString();
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
    int placesMax = 0,
  });

  /// L'organisateur (ou l'admin) modifie titre, description, dates, lieu,
  /// catégorie et places. Le compteur de participants ne change pas.
  Future<Resultat<void>> modifierEvenement(Evenement evenement);

  /// L'organisateur (ou l'admin) supprime l'événement.
  Future<Resultat<void>> supprimerEvenement(String evenementId);

  /// true si l'utilisateur connecté participe à cet événement.
  Future<Resultat<bool>> estInscrit(String evenementId);

  /// Les participants (nom + avatar), du premier inscrit au dernier.
  Future<Resultat<List<Participant>>> getParticipants(String evenementId);

  /// L'organisateur (ou l'admin) annule l'événement, ou le rétablit : il
  /// reste visible avec un badge "Annulé" et on ne peut plus s'y inscrire.
  Future<Resultat<void>> annulerEvenement(Evenement evenement, bool annule);

  /// Je participe : ma fiche + compteur +1 (en une seule écriture).
  Future<Resultat<void>> participer(String evenementId);

  /// Je me retire : ma fiche supprimée + compteur -1 (en une seule écriture).
  Future<Resultat<void>> seRetirer(String evenementId);

  /// true si j'ai répondu "Peut-être" à cet événement.
  Future<Resultat<bool>> estInteresse(String evenementId);

  /// "Peut-être" : ma fiche interesses/{uid} + nbInteresses ±1, en une
  /// seule écriture (comme participer).
  Future<Resultat<void>> changerInteret(String evenementId, bool interesse);

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

  /// Les votes de chaque option, EN DIRECT : une nouvelle liste à chaque
  /// vote d'un voisin. En cas d'erreur, le Stream ne renvoie rien (l'écran
  /// garde les derniers nombres connus).
  Stream<List<int>> ecouterVotes(String sondageId, int nbOptions);
}
