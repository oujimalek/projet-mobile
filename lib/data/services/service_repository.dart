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

/// Le nouveau point de départ de la rotation, calculé quand l'auteur change
/// la liste des participants (voir [ServiceRepository.nouvelleAncre]).
class AncreRotation {
  final DateTime depuis;
  final int index;
  final Map<String, TourRotation> toursFiges;

  const AncreRotation({
    required this.depuis,
    required this.index,
    required this.toursFiges,
  });
}

/// Un rappel à afficher dans le bandeau (aujourd'hui ou demain).
class RappelCreneau {
  final CreneauCommun creneau;
  final bool demain; // false = aujourd'hui
  final bool tourNonConfirme; // true = tour calculé, pas encore confirmé

  const RappelCreneau({
    required this.creneau,
    required this.demain,
    required this.tourNonConfirme,
  });

  /// Ex : « Rappel : demain, tu es de service pour Sortie des poubelles (20:00 - 20:30) ».
  String get texte {
    final String quand = demain ? 'demain' : 'aujourd\'hui';
    return 'Rappel : $quand, tu es de service pour ${creneau.titre} '
        '(${creneau.heureDebut} - ${creneau.heureFin})';
  }
}

/// Le prochain créneau d'un participant (null : aucun à venir).
class ProchainTour {
  final TourRotation participant;
  final CreneauCommun? creneau;

  const ProchainTour({required this.participant, this.creneau});
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
    bool modeRotation = false,
    int nbParticipants = 0,
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
      if (modeRotation && nbParticipants < 1) {
        return 'Choisis au moins un participant pour la rotation';
      }
    }
    return null;
  }

  /// Pourquoi cette liste de participants est refusée (null : elle est valable).
  static String? refusParticipants(List<String> ids, List<String> noms) {
    if (ids.length != noms.length) {
      return 'Participants invalides';
    }
    if (ids.toSet().length != ids.length) {
      return 'Un participant ne peut être choisi qu\'une fois';
    }
    for (final String id in ids) {
      if (id.isEmpty) {
        return 'Participants invalides';
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
  ///
  /// [fait] : le créneau est marqué fait (plus modifiable). [tour] : le
  /// titulaire du tour dans un service en rotation (null : pas de rotation).
  /// Un tour non confirmé est réservé à son titulaire, tant qu'il ne s'est pas
  /// désisté.
  static String? refusInscription(
    CreneauCommun creneau,
    String moiId, {
    bool fait = false,
    TourRotation? tour,
  }) {
    if (fait) {
      return 'Ce créneau est déjà fait, il ne peut plus être modifié';
    }
    if (!creneau.estLibre) {
      return 'Ce créneau est déjà pris';
    }
    if (creneau.date.isBefore(jourDe(DateTime.now()))) {
      return 'Ce créneau est passé';
    }
    if (tour != null && tour.id != moiId && !creneau.estDesiste) {
      final String nom = tour.nom.isEmpty ? 'un autre voisin' : tour.nom;
      return 'Ce créneau est réservé à $nom';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas se désister de ce créneau (null : il peut).
  /// [fait] : le créneau est marqué fait, il ne peut plus être désisté.
  static String? refusDesinscription(
    CreneauCommun creneau,
    String moiId, {
    bool fait = false,
  }) {
    if (creneau.inscritId != moiId) {
      return 'Ce n\'est pas ton créneau';
    }
    if (fait) {
      return 'Ce créneau est déjà fait, il ne peut plus être modifié';
    }
    return null;
  }

  // =====================================================================
  // Rotation, « Fait », rappels, prolongation : fonctions PURES (testables)
  // =====================================================================

  /// Le jour (minuit) d'une date.
  static DateTime jourDe(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// L'identifiant fixe d'un créneau : « {serviceId}_{AAAAMMJJ} ». Il évite les
  /// doublons si on prolonge le planning deux fois.
  static String idCreneau(String serviceId, DateTime date) {
    final String annee = date.year.toString().padLeft(4, '0');
    final String mois = date.month.toString().padLeft(2, '0');
    final String jour = date.day.toString().padLeft(2, '0');
    return '${serviceId}_$annee$mois$jour';
  }

  /// Les créneaux triés par date puis par heure de début (liste neuve).
  static List<CreneauCommun> trierCreneaux(List<CreneauCommun> creneaux) {
    final List<CreneauCommun> liste = List.of(creneaux);
    liste.sort((a, b) {
      final int parDate = a.date.compareTo(b.date);
      if (parDate != 0) {
        return parDate;
      }
      return a.heureDebut.compareTo(b.heureDebut);
    });
    return liste;
  }

  /// Le tour de chacun, calculé (rien n'est écrit sur les créneaux) :
  /// idCréneau -> la personne dont c'est le tour.
  ///
  /// 1. un créneau figé (celui du jour au dernier changement) garde son titulaire ;
  /// 2. un créneau à partir de [Service.rotationDepuis] prend, à tour de rôle,
  ///    `participants[(rotationIndex + rang) % n]` ;
  /// 3. les créneaux plus anciens n'ont pas de tour calculé.
  /// [creneaux] doit contenir TOUS les créneaux du service.
  static Map<String, TourRotation> calculerTours(
    Service service,
    List<CreneauCommun> creneaux,
  ) {
    final Map<String, TourRotation> tours = {};
    final List<TourRotation> participants = service.participants;
    if (!service.modeRotation || participants.isEmpty) {
      return tours;
    }
    final int n = participants.length;
    final DateTime? depuis = service.rotationDepuis == null
        ? null
        : jourDe(service.rotationDepuis!);
    int rang = 0;
    for (final CreneauCommun creneau in trierCreneaux(creneaux)) {
      if (creneau.serviceId != service.id) {
        continue;
      }
      final TourRotation? fige = service.toursFiges[creneau.id];
      if (fige != null) {
        tours[creneau.id] = fige;
        continue;
      }
      if (depuis == null || !jourDe(creneau.date).isBefore(depuis)) {
        tours[creneau.id] = participants[(service.rotationIndex + rang) % n];
        rang++;
      }
    }
    return tours;
  }

  /// La personne de service d'un créneau : celle qui l'a fait, sinon
  /// l'inscrit, sinon le tour calculé (null : personne, ou tour désisté).
  static TourRotation? titulaire(
    Service service,
    CreneauCommun creneau,
    Map<String, TourRotation> tours,
  ) {
    final FaitCreneau? fait = service.creneauxFaits[creneau.id];
    if (fait != null) {
      return fait.parId.isEmpty
          ? null
          : TourRotation(id: fait.parId, nom: fait.parNom);
    }
    if (creneau.inscritId != null) {
      return TourRotation(id: creneau.inscritId!, nom: creneau.inscrit ?? '');
    }
    if (creneau.estDesiste) {
      return null;
    }
    return tours[creneau.id];
  }

  /// Le nouveau point de départ de la rotation quand l'auteur change la liste
  /// des participants ([ids] / [noms], dans le nouvel ordre) :
  /// - le créneau du jour est figé avec son titulaire actuel ;
  /// - le cycle reprend après le dernier créneau passé (ou du jour) : le
  ///   prochain participant, dans l'ancien ordre, encore présent dans la liste ;
  /// - les créneaux à partir de demain suivent la nouvelle liste.
  /// Les créneaux passés, faits ou du jour ne changent donc jamais.
  static AncreRotation nouvelleAncre(
    Service ancien,
    List<String> ids,
    List<CreneauCommun> creneaux,
    DateTime aujourdhui,
  ) {
    final DateTime jour = jourDe(aujourdhui);
    final List<CreneauCommun> tries = trierCreneaux(
      creneaux.where((c) => c.serviceId == ancien.id).toList(),
    );
    final Map<String, TourRotation> tours = calculerTours(ancien, tries);
    final Map<String, TourRotation> figes = {};
    CreneauCommun? dernier; // dernier créneau d'aujourd'hui ou avant
    DateTime? premierFutur;
    for (final CreneauCommun creneau in tries) {
      final DateTime date = jourDe(creneau.date);
      if (date.isAfter(jour)) {
        premierFutur ??= date;
        continue;
      }
      dernier = creneau;
      if (date == jour && tours[creneau.id] != null) {
        figes[creneau.id] = tours[creneau.id]!;
      }
    }

    int index = 0;
    final List<String> anciens = ancien.participantsIds;
    if (dernier != null && anciens.isNotEmpty) {
      String? titulaireId = titulaire(ancien, dernier, tours)?.id;
      if (titulaireId == null || !anciens.contains(titulaireId)) {
        titulaireId = tours[dernier.id]?.id;
      }
      final int place = titulaireId == null ? -1 : anciens.indexOf(titulaireId);
      if (place != -1) {
        for (int k = 1; k <= anciens.length; k++) {
          final int position = ids.indexOf(anciens[(place + k) % anciens.length]);
          if (position != -1) {
            index = position;
            break;
          }
        }
      }
    }
    return AncreRotation(
      depuis: premierFutur ?? DateTime(jour.year, jour.month, jour.day + 1),
      index: index,
      toursFiges: figes,
    );
  }

  /// Pourquoi [moiId] ne peut pas marquer ce créneau « Fait » (null : il peut).
  /// Seul l'auteur du service, le jour du créneau (dès minuit) ou après, une fois.
  static String? refusFait(
    Service service,
    CreneauCommun creneau,
    String moiId,
    DateTime maintenant,
  ) {
    if (service.auteurId.isEmpty || service.auteurId != moiId) {
      return 'Seul l\'auteur du service peut marquer un créneau comme fait';
    }
    if (service.creneauxFaits.containsKey(creneau.id)) {
      return 'Ce créneau est déjà marqué comme fait';
    }
    if (jourDe(creneau.date).isAfter(jourDe(maintenant))) {
      return 'Tu pourras le marquer comme fait le jour du créneau';
    }
    return null;
  }

  /// Les rappels de [moiId] pour aujourd'hui et demain.
  /// - créneau où je suis inscrit : aujourd'hui toujours, demain seulement si
  ///   « Me rappeler la veille » est coché ;
  /// - tour calculé à mon nom, non confirmé : aujourd'hui et demain ;
  /// - jamais pour un créneau fait ni désisté.
  static List<RappelCreneau> rappelsPour({
    required List<Service> services,
    required Map<String, TourRotation> tours,
    required List<CreneauCommun> creneaux,
    required String moiId,
    required DateTime maintenant,
  }) {
    final List<RappelCreneau> rappels = [];
    if (moiId.isEmpty) {
      return rappels;
    }
    final DateTime aujourdhui = jourDe(maintenant);
    final DateTime demain = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 1);
    for (final CreneauCommun creneau in trierCreneaux(creneaux)) {
      final DateTime date = jourDe(creneau.date);
      final bool leJour = date == aujourdhui;
      final bool laVeille = date == demain;
      if (!leJour && !laVeille) {
        continue;
      }
      Service? service;
      for (final Service s in services) {
        if (s.id == creneau.serviceId) {
          service = s;
        }
      }
      if (service != null && service.creneauxFaits.containsKey(creneau.id)) {
        continue;
      }
      if (creneau.inscritId == moiId) {
        if (leJour || creneau.rappelVeille) {
          rappels.add(RappelCreneau(
            creneau: creneau,
            demain: laVeille,
            tourNonConfirme: false,
          ));
        }
      } else if (creneau.estLibre &&
          !creneau.estDesiste &&
          service != null &&
          service.modeRotation &&
          tours[creneau.id]?.id == moiId) {
        rappels.add(RappelCreneau(
          creneau: creneau,
          demain: laVeille,
          tourNonConfirme: true,
        ));
      }
    }
    return rappels;
  }

  /// Le prochain créneau à venir de chaque participant (dans l'ordre de passage).
  static List<ProchainTour> prochainsTours(
    Service service,
    List<CreneauCommun> creneaux,
    Map<String, TourRotation> tours,
    DateTime aujourdhui,
  ) {
    final DateTime jour = jourDe(aujourdhui);
    final List<CreneauCommun> tries = trierCreneaux(creneaux);
    final List<ProchainTour> resultat = [];
    for (final TourRotation participant in service.participants) {
      CreneauCommun? prochain;
      for (final CreneauCommun creneau in tries) {
        if (creneau.serviceId != service.id ||
            jourDe(creneau.date).isBefore(jour) ||
            service.creneauxFaits.containsKey(creneau.id) ||
            creneau.estDesiste ||
            tours[creneau.id]?.id != participant.id) {
          continue;
        }
        if (creneau.inscritId != null && creneau.inscritId != participant.id) {
          continue; // pris par un autre voisin
        }
        prochain = creneau;
        break;
      }
      resultat.add(ProchainTour(participant: participant, creneau: prochain));
    }
    return resultat;
  }

  /// Note moyenne et nombre d'avis, calculés dans l'application à partir des
  /// notes des évaluations reçues (aucun average()/count() de Firestore).
  static ResumeAuteur resumeDepuisNotes(List<num> notes) {
    if (notes.isEmpty) {
      return const ResumeAuteur(noteMoyenne: 0, nombreAvis: 0, servicesRendus: 0);
    }
    double total = 0;
    for (final num note in notes) {
      total += note;
    }
    return ResumeAuteur(
      noteMoyenne: total / notes.length,
      nombreAvis: notes.length,
      servicesRendus: notes.length,
    );
  }

  /// Les créneaux (libres, avec leur id fixe) d'un service commun pour les
  /// [semaines] prochaines semaines, à partir d'[aujourdhui] :
  /// une date par semaine, le jour [jour] ("Samedi"...).
  static List<CreneauCommun> genererCreneaux({
    required String serviceId,
    required String titre,
    required String jour,
    required String heureDebut,
    required String heureFin,
    required DateTime aujourdhui,
    int semaines = semainesDeCreneaux,
  }) {
    final int numeroJour = jours.indexOf(jour) + 1;
    final DateTime debut = jourDe(aujourdhui);
    final List<CreneauCommun> creneaux = [];
    for (int i = 0; i < semaines * 7; i++) {
      final DateTime date = DateTime(debut.year, debut.month, debut.day + i);
      if (date.weekday == numeroJour) {
        creneaux.add(CreneauCommun(
          id: idCreneau(serviceId, date),
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

  /// Les créneaux à ajouter pour prolonger le planning de [semainesDeCreneaux]
  /// semaines : ils commencent après le dernier créneau existant (ou
  /// aujourd'hui), sans jamais refaire une date ou un id déjà présent.
  static List<CreneauCommun> creneauxAProlonger({
    required Service service,
    required List<CreneauCommun> existants,
    required DateTime aujourdhui,
  }) {
    final String? jour = service.jour;
    final String? debut = service.heureDebut;
    final String? fin = service.heureFin;
    if (!service.estCommun || jour == null || debut == null || fin == null) {
      return [];
    }
    DateTime depart = jourDe(aujourdhui);
    for (final CreneauCommun creneau in existants) {
      final DateTime lendemain = DateTime(
        creneau.date.year,
        creneau.date.month,
        creneau.date.day + 1,
      );
      if (lendemain.isAfter(depart)) {
        depart = lendemain;
      }
    }
    final Set<String> idsExistants = existants.map((c) => c.id).toSet();
    final Set<DateTime> datesExistantes = existants.map((c) => jourDe(c.date)).toSet();
    return genererCreneaux(
      serviceId: service.id,
      titre: service.titre,
      jour: jour,
      heureDebut: debut,
      heureFin: fin,
      aujourdhui: depart,
    ).where((c) {
      return !idsExistants.contains(c.id) && !datesExistantes.contains(c.date);
    }).toList();
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
    bool modeRotation = false,
    List<String> participantsIds = const [],
    List<String> participantsNoms = const [],
  });

  /// Rotation automatique : change les participants et leur ordre (seulement
  /// l'auteur du service). Les créneaux passés, faits ou du jour ne changent
  /// pas ; voir [nouvelleAncre]. N'écrit que sur le service.
  Future<Resultat<void>> modifierParticipants(
    String serviceId,
    List<String> ids,
    List<String> noms,
  );

  /// Marque un créneau « Fait » (seulement l'auteur du service, le jour du
  /// créneau ou après). N'écrit que sur le service (map creneauxFaits).
  Future<Resultat<void>> marquerFait(String creneauId);

  /// Prolonge le planning de 4 semaines (seulement l'auteur). Renvoie le
  /// nombre de créneaux créés (0 : déjà à jour). Ids fixes : pas de doublon.
  Future<Resultat<int>> prolongerPlanning(String serviceId);

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
