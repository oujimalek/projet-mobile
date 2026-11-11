import '../models/evenement.dart';
import '../models/quartier.dart';
import '../models/sondage.dart';
import '../models/utilisateur.dart';
import '../models/vie_evenement.dart';
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

  /// Le texte d'un choix de date : "sam. 14/11 · 18:00".
  static String texteChoixDate(DateTime date) {
    const List<String> jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    final String jj = date.day.toString().padLeft(2, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String hh = date.hour.toString().padLeft(2, '0');
    final String mi = date.minute.toString().padLeft(2, '0');
    return '${jours[date.weekday - 1]} $jj/$mm · $hh:$mi';
  }

  /// Les textes des choix d'un sondage de date.
  static List<String> textesDates(List<DateTime> dates) {
    final List<String> textes = [];
    for (final DateTime date in dates) {
      textes.add(texteChoixDate(date));
    }
    return textes;
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
  /// [attente] : les uids de la liste d'attente, du premier au dernier.
  /// Quand des places se libèrent, elles reviennent d'abord aux premiers
  /// de la liste d'attente.
  static String? refusParticipation(
    Evenement evenement, {
    List<String> attente = const [],
    String moiId = '',
  }) {
    if (evenement.annule) {
      return 'Cet événement est annulé';
    }
    if (evenement.estPasse) {
      return 'Cet événement est terminé';
    }
    if (evenement.estComplet) {
      return 'Cet événement est complet';
    }
    final int? libres = evenement.placesRestantes;
    if (libres != null && attente.isNotEmpty) {
      final int rang = attente.indexOf(moiId); // -1 : pas sur la liste
      if (rang < 0 ? attente.length >= libres : rang >= libres) {
        return 'Les places libérées reviennent d\'abord à la liste d\'attente';
      }
    }
    return null;
  }

  /// Pourquoi on ne peut pas rejoindre la liste d'attente (null : on peut).
  static String? refusAttente(
    Evenement evenement, {
    required bool inscrit,
    required bool dejaEnAttente,
  }) {
    if (inscrit) {
      return 'Tu participes déjà';
    }
    if (dejaEnAttente) {
      return 'Tu es déjà sur la liste d\'attente';
    }
    if (evenement.annule || evenement.estPasse) {
      return 'Cet événement n\'est plus ouvert';
    }
    if (!evenement.estComplet) {
      return 'Il reste des places : inscris-toi directement';
    }
    return null;
  }

  static const int placesLimite = 500;
  static const int commentaireMax = 300;
  static const int objetMax = 60;

  /// Pourquoi ce commentaire est refusé (null : accepté).
  static String? refusCommentaire(String texte) {
    if (texte.trim().isEmpty) {
      return 'Écris ton message';
    }
    if (texte.trim().length > commentaireMax) {
      return '$commentaireMax caractères au maximum';
    }
    return null;
  }

  /// Pourquoi cet objet à apporter est refusé (null : accepté).
  static String? refusObjet(String objet) {
    if (objet.trim().isEmpty) {
      return 'Écris l\'objet à apporter';
    }
    if (objet.trim().length > objetMax) {
      return '$objetMax caractères au maximum';
    }
    return null;
  }

  /// Pourquoi cet avis est refusé (null : accepté). Seuls les participants
  /// notent, après l'événement, une seule fois (mêmes conditions que les règles).
  static String? refusAvis(
    Evenement evenement,
    int note, {
    required bool participe,
    required bool dejaDonne,
  }) {
    if (!participe) {
      return 'Seuls les participants peuvent donner leur avis';
    }
    if (!evenement.estPasse) {
      return 'Tu pourras donner ton avis après l\'événement';
    }
    if (dejaDonne) {
      return 'Tu as déjà donné ton avis';
    }
    if (note < 1 || note > 5) {
      return 'Choisis de 1 à 5 étoiles';
    }
    return null;
  }

  /// La moyenne des notes (null : aucun avis).
  static double? moyenne(List<AvisEvenement> avis) {
    if (avis.isEmpty) {
      return null;
    }
    int total = 0;
    for (final AvisEvenement un in avis) {
      total += un.note;
    }
    return total / avis.length;
  }

  /// Son auteur, l'organisateur de l'événement ou l'admin supprime un commentaire.
  static bool peutSupprimerCommentaire(
    Utilisateur utilisateur,
    Commentaire commentaire,
    Evenement evenement,
  ) {
    return utilisateur.id == commentaire.auteurId ||
        peutModifier(utilisateur, evenement);
  }

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

  /// La liste des participants à partager (organisateur ou admin) :
  /// "Participants — Fête des voisins (14/11/2026)" puis "1. Salma G."...
  static String texteListeParticipants(
    Evenement evenement,
    List<Participant> participants,
  ) {
    final String date =
        '${evenement.date.day.toString().padLeft(2, '0')}/${evenement.date.month.toString().padLeft(2, '0')}/${evenement.date.year}';
    final StringBuffer texte = StringBuffer()
      ..writeln('Participants — ${evenement.titre} ($date)');
    if (participants.isEmpty) {
      texte.write('Personne n\'est encore inscrit.');
      return texte.toString();
    }
    for (int i = 0; i < participants.length; i++) {
      texte.writeln('${i + 1}. ${participants[i].nom}');
    }
    texte.write('Total : ${participants.length}');
    if (evenement.placesMax > 0) {
      texte.write(' / ${evenement.placesMax} places');
    }
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
  /// Sans Internet, Firestore renvoie la copie gardée sur le téléphone :
  /// voir [horsLigne].
  Future<Resultat<List<Evenement>>> chargerEvenements();

  /// true si le dernier chargement vient de la copie locale (pas d'Internet).
  bool get horsLigne;

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
    PointGps? position,
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

  // ----- Liste d'attente (événement complet) -----

  /// La liste d'attente, du premier inscrit au dernier.
  Future<Resultat<List<Participant>>> getAttente(String evenementId);

  /// Je rejoins la liste d'attente (seulement si l'événement est complet).
  Future<Resultat<void>> rejoindreAttente(Evenement evenement);

  /// Je quitte la liste d'attente.
  Future<Resultat<void>> quitterAttente(String evenementId);

  // ----- Questions / commentaires -----

  /// Les commentaires, du plus ancien au plus récent.
  Future<Resultat<List<Commentaire>>> getCommentaires(String evenementId);

  Future<Resultat<void>> ajouterCommentaire(String evenementId, String texte);

  /// Son auteur, l'organisateur ou l'admin supprime un commentaire.
  Future<Resultat<void>> supprimerCommentaire(String evenementId, String commentaireId);

  // ----- Qui apporte quoi ? -----

  Future<Resultat<List<ObjetAApporter>>> getObjets(String evenementId);

  /// L'organisateur (ou l'admin) ajoute un objet à la liste.
  Future<Resultat<void>> ajouterObjet(Evenement evenement, String objet);

  /// L'organisateur (ou l'admin) retire un objet de la liste.
  Future<Resultat<void>> supprimerObjet(Evenement evenement, String objetId);

  /// Je m'en charge ([prendre] = true) ou je ne m'en charge plus.
  Future<Resultat<void>> prendreObjet(
      String evenementId, ObjetAApporter objet, bool prendre);

  // ----- Avis après l'événement -----

  Future<Resultat<List<AvisEvenement>>> getAvis(String evenementId);

  /// Un participant note l'événement terminé (1 à 5), une seule fois.
  Future<Resultat<void>> donnerAvis(
      Evenement evenement, int note, String commentaire);

  // =====================================================================
  // Sondages
  // =====================================================================

  /// Le sondage ouvert qui se termine le plus tôt (dernier chargement),
  /// null s'il n'y en a pas. Pour l'accueil : ne lève jamais d'exception.
  Sondage? getSondageActif();

  /// Tous les sondages, avec leurs votes, les ouverts d'abord.
  Future<Resultat<List<Sondage>>> chargerSondages();

  /// Crée un sondage proposé par l'utilisateur connecté.
  /// [dates] non vide : sondage de date (les choix sont ces dates, [options]
  /// est ignoré). [evenementId] : sondage rattaché à cet événement.
  Future<Resultat<void>> creerSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
    List<DateTime> dates = const [],
    String? evenementId,
  });

  /// Les sondages rattachés à un événement, avec leurs votes.
  Future<Resultat<List<Sondage>>> chargerSondagesDe(String evenementId);

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
