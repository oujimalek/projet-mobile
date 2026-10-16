import '../models/creneau_commun.dart';
import '../models/demande_service.dart';
import '../models/service.dart';
import '../models/statut_demande.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firebase_service_repository.dart';

/// La note d'un voisin, calculée à partir des évaluations qu'il a reçues.
class ResumeAuteur {
  final double noteMoyenne; // 0 s'il n'a pas encore été évalué
  final int nombreAvis;
  final int servicesRendus; // un service rendu est un service évalué

  const ResumeAuteur({
    required this.noteMoyenne,
    required this.nombreAvis,
    required this.servicesRendus,
  });
}

/// M2 - Accès aux services entre voisins, aux demandes, aux évaluations
/// et aux créneaux des services communs : le CONTRAT.
///
/// Implémentations :
/// - FirebaseServiceRepository : Cloud Firestore (celle de l'application) ;
/// - MockServiceRepository (dans test/) : données en mémoire, que les tests
///   installent avec `ServiceRepository.instance = ...`.
///
/// Les lectures sont des `Stream` (l'écran se met à jour tout seul), les
/// écritures renvoient `Future<Resultat<...>>` (voir lib/data/resultat.dart).
/// Un Stream en erreur porte un message en français (un String).
///
/// Collections écrites (toutes sous quartiers/{quartierId}/) : services,
/// demandes (+ messages, voir ChatRepository), evaluations, creneaux.
abstract class ServiceRepository {
  /// L'implémentation utilisée par toute l'application.
  static ServiceRepository instance = FirebaseServiceRepository();

  /// `ServiceRepository()` renvoie l'instance ci-dessus (pas de nouvel objet).
  factory ServiceRepository() {
    return instance;
  }

  // =====================================================================
  // Constantes et règles métier (communes à Firebase et au mock)
  // =====================================================================

  /// Les catégories des filtres. "Tous" est le filtre par défaut.
  static const List<String> categories = [
    'Tous',
    'Bricolage',
    'Prêt d\'outils',
    'Garde d\'enfants',
    'Courses',
  ];

  /// Les tags proposés dans l'écran d'évaluation.
  static const List<String> tagsEvaluation = [
    'Ponctuel',
    'Sympa',
    'Très serviable',
    'Matériel en bon état',
  ];

  /// Les jours d'un service commun (le numéro du jour = position + 1).
  static const List<String> jours = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  /// Nombre de semaines de créneaux créées à la publication d'un service commun.
  static const int semainesDeCreneaux = 4;

  /// Nom court affiché dans les services et les demandes (ex : "Amira B.").
  static String nomCourt(Utilisateur utilisateur) {
    String initialeNom = '';
    if (utilisateur.nom.isNotEmpty) {
      initialeNom = ' ${utilisateur.nom[0]}.';
    }
    return '${utilisateur.prenom}$initialeNom';
  }

  /// Le bloc de l'utilisateur ("Bloc B"), vide si inconnu.
  /// La résidence est écrite "Résidence Yasmine, Bloc B" : on garde la fin.
  static String blocDe(Utilisateur utilisateur) {
    final String residence = utilisateur.residence;
    final int virgule = residence.lastIndexOf(', ');
    if (virgule == -1) {
      return '';
    }
    return residence.substring(virgule + 2);
  }

  /// "18:30" est-il une heure valable ?
  static bool heureValide(String? heure) {
    if (heure == null) {
      return false;
    }
    final RegExpMatch? m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(heure);
    return m != null;
  }

  /// Pourquoi cette publication est refusée (null : elle est valable).
  static String? refusPublication({
    required String titre,
    required String description,
    required String categorie,
    required bool estCommun,
    String? jour,
    String? heureDebut,
    String? heureFin,
  }) {
    if (titre.trim().length < 3) {
      return 'Le titre doit avoir au moins 3 caractères';
    }
    if (description.trim().length < 10) {
      return 'La description doit avoir au moins 10 caractères';
    }
    if (!categories.contains(categorie) || categorie == 'Tous') {
      return 'Choisis une catégorie';
    }
    if (estCommun) {
      if (jour == null || !jours.contains(jour)) {
        return 'Choisis le jour du service commun';
      }
      if (!heureValide(heureDebut) || !heureValide(heureFin)) {
        return 'Choisis l\'heure de début et l\'heure de fin';
      }
      if (heureFin!.compareTo(heureDebut!) <= 0) {
        return 'L\'heure de fin doit être après l\'heure de début';
      }
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas demander ce service (null : il peut).
  static String? refusDemande(Service service, String moiId, bool dejaDemande) {
    if (service.auteurId.isEmpty) {
      return 'Ce service ne peut pas être demandé';
    }
    if (service.auteurId == moiId) {
      return 'Tu ne peux pas demander ton propre service';
    }
    if (service.estCommun) {
      return 'Un service commun se réserve dans le planning';
    }
    if (dejaDemande) {
      return 'Tu as déjà demandé ce service';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas passer cette demande au [nouveau] statut.
  ///   - accepter / refuser : seulement l'auteur du service, demande en attente ;
  ///   - réalisée : demande acceptée, par le demandeur ou par l'auteur.
  static String? refusStatut(
    DemandeService demande,
    StatutDemande nouveau,
    String moiId,
  ) {
    if (nouveau == StatutDemande.acceptee || nouveau == StatutDemande.refusee) {
      if (demande.auteurServiceId != moiId) {
        return 'Seul l\'auteur du service peut répondre à la demande';
      }
      if (demande.statut != StatutDemande.enAttente) {
        return 'Cette demande a déjà reçu une réponse';
      }
      return null;
    }
    if (nouveau == StatutDemande.realisee) {
      if (demande.statut != StatutDemande.acceptee) {
        return 'La demande doit d\'abord être acceptée';
      }
      if (demande.auteurServiceId != moiId && demande.demandeurId != moiId) {
        return 'Action non autorisée';
      }
      return null;
    }
    return 'Action non autorisée'; // on ne revient pas à "en attente"
  }

  /// Pourquoi [moiId] ne peut pas évaluer cette demande (null : il peut).
  static String? refusEvaluation(DemandeService demande, int note, String moiId) {
    if (demande.statut != StatutDemande.realisee) {
      return 'Le service doit d\'abord être réalisé';
    }
    if (demande.demandeurId != moiId) {
      return 'Seul le demandeur peut évaluer';
    }
    if (demande.evaluee) {
      return 'Tu as déjà évalué ce service';
    }
    if (note < 1 || note > 5) {
      return 'La note doit être entre 1 et 5';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas s'inscrire à ce créneau (null : il peut).
  static String? refusInscription(CreneauCommun creneau, String moiId) {
    if (!creneau.estLibre) {
      return 'Ce créneau est déjà pris';
    }
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    if (creneau.date.isBefore(aujourdhui)) {
      return 'Ce créneau est passé';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas se désister de ce créneau (null : il peut).
  static String? refusDesinscription(CreneauCommun creneau, String moiId) {
    if (creneau.inscritId != moiId) {
      return 'Ce n\'est pas ton créneau';
    }
    return null;
  }

  /// Les créneaux (libres, sans id) d'un service commun pour les
  /// [semainesDeCreneaux] prochaines semaines, à partir d'[aujourdhui] :
  /// une date par semaine, le jour [jour] ("Samedi"...).
  static List<CreneauCommun> genererCreneaux({
    required String serviceId,
    required String titre,
    required String jour,
    required String heureDebut,
    required String heureFin,
    required DateTime aujourdhui,
  }) {
    final int numeroJour = jours.indexOf(jour) + 1;
    final DateTime debut = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    final List<CreneauCommun> creneaux = [];
    for (int i = 0; i < semainesDeCreneaux * 7; i++) {
      final DateTime date = DateTime(debut.year, debut.month, debut.day + i);
      if (date.weekday == numeroJour) {
        creneaux.add(CreneauCommun(
          id: '',
          serviceId: serviceId,
          titre: titre,
          date: date,
          heureDebut: heureDebut,
          heureFin: heureFin,
        ));
      }
    }
    return creneaux;
  }

  // =====================================================================
  // Utilisateur connecté
  // =====================================================================

  /// Nom court de l'utilisateur connecté (ex : "Amira B.").
  String getMonNom();

  /// L'uid de l'utilisateur connecté ('' si personne n'est connecté).
  String getMonId();

  // =====================================================================
  // Services
  // =====================================================================

  /// Tous les services du quartier, les plus récents en premier.
  Stream<List<Service>> ecouterServices();

  /// Un service (null s'il n'existe plus).
  Stream<Service?> ecouterService(String id);

  /// La dernière liste de services reçue, SANS attendre (liste vide tant que
  /// rien n'est arrivé). Le premier appel démarre l'écoute. Ne lève jamais
  /// d'exception (utilisé par l'accueil).
  List<Service> getServices();

  /// Publie un service. Pour un service commun ([estCommun]), [jour],
  /// [heureDebut] et [heureFin] sont obligatoires : les créneaux libres des
  /// 4 prochaines semaines sont créés en un seul batch.
  Future<Resultat<Service>> ajouterService({
    required String titre,
    required String description,
    required String categorie,
    required bool estOffre,
    String? disponibilite,
    bool estCommun = false,
    String? jour,
    String? heureDebut,
    String? heureFin,
  });

  /// Modifie un service (seulement son auteur). Le type commun, le jour et
  /// les heures ne changent pas.
  Future<Resultat<void>> modifierService(
    String id, {
    required String titre,
    required String description,
    required String categorie,
    required bool estOffre,
    String? disponibilite,
  });

  /// Supprime un service (seulement son auteur) : ses demandes en attente
  /// passent à "refusée" et ses créneaux sont supprimés, en une seule opération.
  Future<Resultat<void>> supprimerService(String id);

  // =====================================================================
  // Demandes
  // =====================================================================

  /// Les demandes que j'ai envoyées, les plus récentes en premier.
  Stream<List<DemandeService>> ecouterDemandesEnvoyees();

  /// Les demandes reçues pour mes services, les plus récentes en premier.
  Stream<List<DemandeService>> ecouterDemandesRecues();

  /// Une demande (null si elle n'existe pas).
  Stream<DemandeService?> ecouterDemande(String id);

  /// Envoie une demande pour un service. Refusé : son propre service, un
  /// service commun, une demande déjà envoyée.
  Future<Resultat<void>> envoyerDemande(String serviceId);

  /// Change le statut d'une demande (voir [refusStatut]).
  Future<Resultat<void>> changerStatutDemande(
    String demandeId,
    StatutDemande statut,
  );

  // =====================================================================
  // Évaluations
  // =====================================================================

  /// Les tags proposés pour évaluer un service.
  List<String> getTagsEvaluation();

  /// Les catégories des filtres.
  List<String> getCategories();

  /// Évalue une demande réalisée : l'évaluation et "évaluée" sont écrites
  /// ensemble (voir [refusEvaluation]).
  Future<Resultat<void>> evaluer({
    required String demandeId,
    required int note,
    List<String> tags = const [],
    String? message,
  });

  /// Note moyenne, nombre d'avis et services rendus d'un voisin, calculés à
  /// partir des évaluations qu'il a reçues.
  Future<Resultat<ResumeAuteur>> getResumeAuteur(String auteurId);

  // =====================================================================
  // Créneaux des services communs
  // =====================================================================

  /// Les créneaux des 7 jours à partir de [dateDebut], triés par date et heure.
  Stream<List<CreneauCommun>> ecouterCreneauxDeLaSemaine(DateTime dateDebut);

  /// Tous les créneaux d'un service commun, triés par date et heure.
  Stream<List<CreneauCommun>> ecouterCreneauxParService(String serviceId);

  /// Un créneau (null s'il n'existe plus).
  Stream<CreneauCommun?> ecouterCreneau(String id);

  /// M'inscrit à un créneau (voir [refusInscription]).
  Future<Resultat<void>> inscrire(String creneauId, {bool rappelVeille = false});

  /// Me désinscrit d'un créneau (voir [refusDesinscription]).
  Future<Resultat<void>> desinscrire(String creneauId);
}
