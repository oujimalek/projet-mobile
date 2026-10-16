import '../models/creneau_commun.dart';
import '../models/demande_service.dart';
import '../models/evaluation.dart';
import '../models/service.dart';
import '../models/statut_demande.dart';
import '../models/utilisateur.dart';
import 'utilisateur_repository.dart';

/// M2 - Accès aux services entre voisins, aux demandes, aux évaluations
/// et aux créneaux des services communs.
///
/// Les données sont gardées EN MÉMOIRE dans des listes static : elles sont
/// partagées entre tous les écrans (et perdues quand l'app se ferme).
/// Plus tard, seul l'intérieur de ces méthodes changera (appel à une API),
/// pas les écrans.
class ServiceRepository {
  // ----- Les données en mémoire (static = partagées par tous les écrans) -----
  static List<Service> _services = _servicesInitiaux();
  static List<DemandeService> _demandes = _demandesInitiales();
  static List<Evaluation> _evaluations = _evaluationsInitiales();
  static List<CreneauCommun> _creneaux = _creneauxInitiaux();
  static int _compteurId = 100; // pour genererId()

  /// Les tags proposés dans l'écran d'évaluation.
  static const List<String> _tagsEvaluation = [
    'Ponctuel',
    'Sympa',
    'Très serviable',
    'Matériel en bon état',
  ];

  // =====================================================================
  // Utilisateur connecté
  // =====================================================================

  /// Nom court de l'utilisateur connecté, tel qu'il apparaît dans les
  /// services et les demandes (ex : "Amira B.").
  String getMonNom() {
    final Utilisateur moi = UtilisateurRepository().getUtilisateurConnecte();
    String initialeNom = '';
    if (moi.nom.isNotEmpty) {
      initialeNom = ' ${moi.nom[0]}.';
    }
    return '${moi.prenom}$initialeNom';
  }

  /// Le bloc de l'utilisateur connecté (ex : "Bloc B"), vide si inconnu.
  /// La résidence est écrite "Résidence Yasmine, Bloc B" : on garde la fin.
  String _getMonBloc() {
    final String residence =
        UtilisateurRepository().getUtilisateurConnecte().residence;
    final int virgule = residence.lastIndexOf(', ');
    if (virgule == -1) {
      return '';
    }
    return residence.substring(virgule + 2);
  }

  // =====================================================================
  // Services
  // =====================================================================

  /// Les catégories utilisées pour les filtres de la liste des services.
  /// "Tous" est le filtre par défaut.
  List<String> getCategories() {
    return const ['Tous', 'Bricolage', 'Prêt d\'outils', 'Garde d\'enfants', 'Courses'];
  }

  /// Tous les services du quartier (les plus récents en premier).
  List<Service> getServices() {
    return List<Service>.of(_services);
  }

  /// Les services d'une catégorie ("Tous" renvoie toute la liste).
  List<Service> getServicesParCategorie(String categorie) {
    if (categorie == 'Tous') {
      return getServices();
    }
    // On parcourt tous les services et on garde ceux de la bonne catégorie
    final List<Service> resultat = [];
    for (final service in getServices()) {
      if (service.categorie == categorie) {
        resultat.add(service);
      }
    }
    return resultat;
  }

  /// Uniquement les services communs hebdomadaires.
  List<Service> getServicesCommuns() {
    final List<Service> resultat = [];
    for (final service in getServices()) {
      if (service.estCommun) {
        resultat.add(service);
      }
    }
    return resultat;
  }

  /// Retrouve un service à partir de son id (null s'il n'existe pas).
  Service? getServiceParId(String id) {
    for (final service in _services) {
      if (service.id == id) {
        return service;
      }
    }
    return null;
  }

  /// Fabrique un identifiant unique, ex : "s101", "d102".
  String genererId([String prefixe = 'x']) {
    _compteurId = _compteurId + 1;
    return '$prefixe$_compteurId';
  }

  /// Publie un nouveau service. L'auteur est l'utilisateur connecté,
  /// la date est maintenant. Le service est ajouté en haut de la liste.
  Service ajouterService({
    required String titre,
    required String description,
    required String categorie,
    required bool estOffre,
    String? disponibilite,
  }) {
    final Service service = Service(
      id: genererId('s'),
      titre: titre,
      description: description,
      categorie: categorie,
      auteur: getMonNom(),
      estOffre: estOffre,
      bloc: _getMonBloc(),
      datePublication: DateTime.now(),
      disponibilite: disponibilite,
    );
    _services.insert(0, service);
    return service;
  }

  // =====================================================================
  // Demandes
  // =====================================================================

  /// Les demandes que j'ai envoyées (les plus récentes en premier).
  List<DemandeService> getDemandesEnvoyees() {
    final String moi = getMonNom();
    final List<DemandeService> resultat = [];
    for (final demande in _demandes) {
      if (demande.demandeur == moi) {
        resultat.add(demande);
      }
    }
    resultat.sort((a, b) => b.dateDemande.compareTo(a.dateDemande));
    return resultat;
  }

  /// Les demandes reçues pour mes services (les plus récentes en premier).
  List<DemandeService> getDemandesRecues() {
    final String moi = getMonNom();
    final List<DemandeService> resultat = [];
    for (final demande in _demandes) {
      if (demande.auteurService == moi) {
        resultat.add(demande);
      }
    }
    resultat.sort((a, b) => b.dateDemande.compareTo(a.dateDemande));
    return resultat;
  }

  /// Retrouve une demande à partir de son id (null si elle n'existe pas).
  DemandeService? getDemandeParId(String id) {
    for (final demande in _demandes) {
      if (demande.id == id) {
        return demande;
      }
    }
    return null;
  }

  /// true si j'ai déjà demandé ce service (quel que soit le statut).
  bool aDejaDemande(String serviceId) {
    final String moi = getMonNom();
    for (final demande in _demandes) {
      if (demande.serviceId == serviceId && demande.demandeur == moi) {
        return true;
      }
    }
    return false;
  }

  /// Envoie une demande pour un service.
  /// Renvoie false (rien n'est créé) si le service n'existe pas,
  /// si c'est mon propre service ou si je l'ai déjà demandé.
  bool envoyerDemande(String serviceId) {
    final Service? service = getServiceParId(serviceId);
    if (service == null) {
      return false;
    }
    final String moi = getMonNom();
    if (service.auteur == moi) {
      return false; // on ne demande pas son propre service
    }
    if (aDejaDemande(serviceId)) {
      return false; // pas deux fois la même demande
    }
    _demandes.add(DemandeService(
      id: genererId('d'),
      serviceId: serviceId,
      demandeur: moi,
      auteurService: service.auteur,
      statut: StatutDemande.enAttente,
      dateDemande: DateTime.now(),
    ));
    return true;
  }

  /// Change le statut d'une demande. Renvoie false si ce n'est pas permis :
  ///   - accepter / refuser : seulement l'auteur du service, demande en attente ;
  ///   - réalisée : demande acceptée, par le demandeur ou par l'auteur.
  bool changerStatutDemande(String demandeId, StatutDemande statut) {
    final int index = _indexDemande(demandeId);
    if (index == -1) {
      return false;
    }
    final DemandeService demande = _demandes[index];
    final String moi = getMonNom();

    if (statut == StatutDemande.acceptee || statut == StatutDemande.refusee) {
      if (demande.auteurService != moi) {
        return false;
      }
      if (demande.statut != StatutDemande.enAttente) {
        return false;
      }
    } else if (statut == StatutDemande.realisee) {
      if (demande.statut != StatutDemande.acceptee) {
        return false;
      }
      if (demande.auteurService != moi && demande.demandeur != moi) {
        return false;
      }
    } else {
      return false; // on ne revient pas à "en attente"
    }

    _demandes[index] = demande.copyWith(statut: statut);
    return true;
  }

  int _indexDemande(String id) {
    for (int i = 0; i < _demandes.length; i++) {
      if (_demandes[i].id == id) {
        return i;
      }
    }
    return -1;
  }

  // =====================================================================
  // Évaluations
  // =====================================================================

  /// Les tags proposés pour évaluer un service.
  List<String> getTagsEvaluation() {
    return _tagsEvaluation;
  }

  /// Enregistre une évaluation. Renvoie false si ce n'est pas permis :
  /// il faut une demande "réalisée" que j'ai envoyée, pas déjà évaluée,
  /// et une note entre 1 et 5.
  bool evaluer(Evaluation evaluation) {
    final int index = _indexDemande(evaluation.demandeId);
    if (index == -1) {
      return false;
    }
    final DemandeService demande = _demandes[index];
    if (demande.statut != StatutDemande.realisee) {
      return false;
    }
    if (demande.evaluee) {
      return false; // une seule évaluation par demande
    }
    if (demande.demandeur != getMonNom()) {
      return false; // seul le demandeur évalue
    }
    if (evaluation.note < 1 || evaluation.note > 5) {
      return false;
    }
    _evaluations.add(evaluation);
    _demandes[index] = demande.copyWith(evaluee: true);
    return true;
  }

  /// Les évaluations reçues par un voisin (pour les services qu'il a publiés).
  List<Evaluation> _evaluationsDe(String auteur) {
    final List<Evaluation> resultat = [];
    for (final evaluation in _evaluations) {
      final Service? service = getServiceParId(evaluation.serviceId);
      if (service != null && service.auteur == auteur) {
        resultat.add(evaluation);
      }
    }
    return resultat;
  }

  /// Note moyenne d'un voisin (0 s'il n'a pas encore été évalué).
  double getNoteMoyenne(String auteur) {
    final List<Evaluation> evaluations = _evaluationsDe(auteur);
    if (evaluations.isEmpty) {
      return 0;
    }
    int total = 0;
    for (final evaluation in evaluations) {
      total += evaluation.note;
    }
    return total / evaluations.length;
  }

  /// Nombre d'évaluations reçues par un voisin.
  int getNombreEvaluations(String auteur) {
    return _evaluationsDe(auteur).length;
  }

  /// Nombre de services rendus par un voisin (demandes "réalisées").
  int getNombreServicesRendus(String auteur) {
    int total = 0;
    for (final demande in _demandes) {
      if (demande.auteurService == auteur &&
          demande.statut == StatutDemande.realisee) {
        total++;
      }
    }
    return total;
  }

  // =====================================================================
  // Créneaux des services communs
  // =====================================================================

  /// Les créneaux des 7 jours à partir de dateDebut (triés par date et heure).
  List<CreneauCommun> getCreneauxDeLaSemaine(DateTime dateDebut) {
    final DateTime debut = DateTime(dateDebut.year, dateDebut.month, dateDebut.day);
    final DateTime fin = DateTime(debut.year, debut.month, debut.day + 7);
    final List<CreneauCommun> resultat = [];
    for (final creneau in _creneaux) {
      if (!creneau.date.isBefore(debut) && creneau.date.isBefore(fin)) {
        resultat.add(creneau);
      }
    }
    _trier(resultat);
    return resultat;
  }

  /// Les créneaux d'un jour précis.
  List<CreneauCommun> getCreneauxDuJour(DateTime date) {
    final List<CreneauCommun> resultat = [];
    for (final creneau in _creneaux) {
      if (_memeJour(creneau.date, date)) {
        resultat.add(creneau);
      }
    }
    _trier(resultat);
    return resultat;
  }

  /// Tous les créneaux d'un service commun.
  List<CreneauCommun> getCreneauxParService(String serviceId) {
    final List<CreneauCommun> resultat = [];
    for (final creneau in _creneaux) {
      if (creneau.serviceId == serviceId) {
        resultat.add(creneau);
      }
    }
    _trier(resultat);
    return resultat;
  }

  /// Retrouve un créneau à partir de son id (null s'il n'existe pas).
  CreneauCommun? getCreneauParId(String id) {
    for (final creneau in _creneaux) {
      if (creneau.id == id) {
        return creneau;
      }
    }
    return null;
  }

  /// M'inscrit à un créneau. Renvoie false s'il n'existe pas ou s'il est
  /// déjà pris. rappelVeille = true : "me rappeler la veille" (sans notification).
  bool inscrire(String creneauId, {bool rappelVeille = false}) {
    final int index = _indexCreneau(creneauId);
    if (index == -1) {
      return false;
    }
    if (!_creneaux[index].estLibre) {
      return false;
    }
    _creneaux[index] = _creneaux[index].copyWith(
      inscrit: getMonNom(),
      rappelVeille: rappelVeille,
    );
    return true;
  }

  /// Me désinscrit d'un créneau. Renvoie false si ce n'est pas mon créneau.
  bool desinscrire(String creneauId) {
    final int index = _indexCreneau(creneauId);
    if (index == -1) {
      return false;
    }
    if (_creneaux[index].inscrit != getMonNom()) {
      return false;
    }
    _creneaux[index] = _creneaux[index].copyWith(libere: true, rappelVeille: false);
    return true;
  }

  int _indexCreneau(String id) {
    for (int i = 0; i < _creneaux.length; i++) {
      if (_creneaux[i].id == id) {
        return i;
      }
    }
    return -1;
  }

  bool _memeJour(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Trie par date puis par heure de début.
  void _trier(List<CreneauCommun> liste) {
    liste.sort((a, b) {
      final int parDate = a.date.compareTo(b.date);
      if (parDate != 0) {
        return parDate;
      }
      return a.heureDebut.compareTo(b.heureDebut);
    });
  }

  // =====================================================================
  // Remise à zéro (utilisée uniquement par les tests)
  // =====================================================================

  /// Remet toutes les données dans leur état de départ.
  void reinitialiser() {
    _services = _servicesInitiaux();
    _demandes = _demandesInitiales();
    _evaluations = _evaluationsInitiales();
    _creneaux = _creneauxInitiaux();
    _compteurId = 100;
  }

  // =====================================================================
  // Données de départ
  // =====================================================================

  static List<Service> _servicesInitiaux() {
    // Les dates sont calculées à partir de maintenant pour que la liste
    // affiche toujours "1 h", "3 h", "hier"... comme sur la maquette.
    final DateTime maintenant = DateTime.now();

    return [
      // ----- Offres (les 4 de la maquette) -----
      Service(
        id: 's1',
        titre: 'Perceuse à prêter',
        description: 'Perceuse avec forets, à rendre sous 3 jours.',
        categorie: 'Prêt d\'outils',
        auteur: 'Karim M.',
        bloc: 'Bloc A',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 1)),
        disponibilite: 'Ce week-end',
        duree: '3 jours',
        recuperation: 'Bloc A · Appt 3',
      ),
      Service(
        id: 's2',
        titre: 'Garde d\'enfants le samedi',
        description: 'Je peux garder vos enfants le samedi après-midi.',
        categorie: 'Garde d\'enfants',
        auteur: 'Leila B.',
        bloc: 'Bloc C',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 3)),
        disponibilite: 'Samedi après-midi',
        duree: '4 heures',
        recuperation: 'Bloc C · Appt 5',
      ),
      Service(
        id: 's3',
        titre: 'Petits travaux de plomberie',
        description: 'Fuites, joints, robinets : je passe chez vous.',
        categorie: 'Bricolage',
        auteur: 'Nizar H.',
        bloc: 'Bloc B',
        estOffre: true,
        prix: '15 DT',
        datePublication: maintenant.subtract(const Duration(hours: 26)),
        disponibilite: 'En semaine, après 17 h',
        duree: '1 heure',
        recuperation: 'Je viens chez vous',
      ),
      Service(
        id: 's4',
        titre: 'Courses au Carrefour',
        description: 'Je vais au Carrefour, je peux ramener vos courses.',
        categorie: 'Courses',
        auteur: 'Sarra A.',
        bloc: 'Bloc A',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 30)),
        disponibilite: 'Jeudi soir',
        duree: '1 heure',
        recuperation: 'Bloc A · Appt 1',
      ),

      // ----- Services communs hebdomadaires (offres) -----
      Service(
        id: 's5',
        titre: 'Nettoyage des escaliers',
        description: 'Service commun : on nettoie ensemble les escaliers du bloc.',
        categorie: 'Bricolage',
        auteur: 'Syndic',
        bloc: 'Bloc B',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        datePublication: maintenant.subtract(const Duration(days: 3)),
        disponibilite: 'Chaque samedi',
        duree: '1 heure',
        recuperation: 'Hall du bloc B',
      ),
      Service(
        id: 's6',
        titre: 'Achat groupé du pain',
        description: 'Service commun : un voisin passe à la boulangerie pour tous.',
        categorie: 'Courses',
        auteur: 'Résidence Yasmine',
        bloc: 'Tous les blocs',
        estOffre: true,
        estCommun: true,
        jour: 'Dimanche',
        datePublication: maintenant.subtract(const Duration(days: 4)),
        disponibilite: 'Chaque dimanche',
        duree: '30 minutes',
        recuperation: 'Hall de la résidence',
      ),

      // ----- Demandes -----
      Service(
        id: 's7',
        titre: 'Qui va au marché samedi ?',
        description: 'Je cherche quelqu\'un pour me ramener des légumes.',
        categorie: 'Courses',
        auteur: 'Amira B.',
        bloc: 'Bloc B',
        estOffre: false,
        datePublication: maintenant.subtract(const Duration(hours: 5)),
        disponibilite: 'Samedi matin',
        duree: '1 heure',
        recuperation: 'Bloc B · Appt 4',
      ),
      Service(
        id: 's8',
        titre: 'Cherche une échelle',
        description: 'Pour changer une ampoule au plafond, une heure seulement.',
        categorie: 'Prêt d\'outils',
        auteur: 'Youssef T.',
        bloc: 'Bloc A',
        estOffre: false,
        datePublication: maintenant.subtract(const Duration(days: 2)),
        disponibilite: 'Dès que possible',
        duree: '1 heure',
        recuperation: 'Bloc A · Appt 2',
      ),
    ];
  }

  /// Demandes d'exemple : 3 envoyées et 2 reçues par l'utilisateur connecté
  /// ("Amira B."), plus quelques anciennes demandes entre d'autres voisins
  /// (elles servent aux notes moyennes et au nombre de services rendus).
  static List<DemandeService> _demandesInitiales() {
    final DateTime maintenant = DateTime.now();
    final String moi = _nomConnecte();

    return [
      // ----- Envoyées par moi -----
      DemandeService(
        id: 'd1',
        serviceId: 's1',
        demandeur: moi,
        auteurService: 'Karim M.',
        statut: StatutDemande.enAttente,
        dateDemande: maintenant.subtract(const Duration(hours: 2)),
      ),
      DemandeService(
        id: 'd2',
        serviceId: 's3',
        demandeur: moi,
        auteurService: 'Nizar H.',
        statut: StatutDemande.acceptee,
        dateDemande: maintenant.subtract(const Duration(hours: 20)),
      ),
      DemandeService(
        id: 'd3',
        serviceId: 's2',
        demandeur: moi,
        auteurService: 'Leila B.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 4)),
      ),

      // ----- Reçues pour mon service s7 -----
      DemandeService(
        id: 'd4',
        serviceId: 's7',
        demandeur: 'Youssef T.',
        auteurService: moi,
        statut: StatutDemande.enAttente,
        dateDemande: maintenant.subtract(const Duration(hours: 1)),
      ),
      DemandeService(
        id: 'd5',
        serviceId: 's7',
        demandeur: 'Sarra A.',
        auteurService: moi,
        statut: StatutDemande.acceptee,
        dateDemande: maintenant.subtract(const Duration(hours: 4)),
      ),

      // ----- Anciennes demandes entre voisins (déjà réalisées et évaluées) -----
      DemandeService(
        id: 'h1',
        serviceId: 's1',
        demandeur: 'Salma G.',
        auteurService: 'Karim M.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 20)),
        evaluee: true,
      ),
      DemandeService(
        id: 'h2',
        serviceId: 's1',
        demandeur: 'Youssef T.',
        auteurService: 'Karim M.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 12)),
        evaluee: true,
      ),
      DemandeService(
        id: 'h3',
        serviceId: 's2',
        demandeur: 'Sarra A.',
        auteurService: 'Leila B.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 15)),
        evaluee: true,
      ),
      DemandeService(
        id: 'h4',
        serviceId: 's3',
        demandeur: 'Karim M.',
        auteurService: 'Nizar H.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 9)),
        evaluee: true,
      ),
      DemandeService(
        id: 'h5',
        serviceId: 's4',
        demandeur: 'Leila B.',
        auteurService: 'Sarra A.',
        statut: StatutDemande.realisee,
        dateDemande: maintenant.subtract(const Duration(days: 7)),
        evaluee: true,
      ),
    ];
  }

  static List<Evaluation> _evaluationsInitiales() {
    final DateTime maintenant = DateTime.now();

    return [
      Evaluation(
        id: 'ev1',
        demandeId: 'h1',
        serviceId: 's1',
        auteurEvalue: 'Salma G.',
        note: 5,
        tags: const ['Ponctuel', 'Sympa'],
        message: 'Perceuse en parfait état, merci !',
        date: maintenant.subtract(const Duration(days: 19)),
      ),
      Evaluation(
        id: 'ev2',
        demandeId: 'h2',
        serviceId: 's1',
        auteurEvalue: 'Youssef T.',
        note: 4,
        tags: const ['Matériel en bon état'],
        date: maintenant.subtract(const Duration(days: 11)),
      ),
      Evaluation(
        id: 'ev3',
        demandeId: 'h3',
        serviceId: 's2',
        auteurEvalue: 'Sarra A.',
        note: 5,
        tags: const ['Très serviable', 'Sympa'],
        date: maintenant.subtract(const Duration(days: 14)),
      ),
      Evaluation(
        id: 'ev4',
        demandeId: 'h4',
        serviceId: 's3',
        auteurEvalue: 'Karim M.',
        note: 4,
        tags: const ['Ponctuel'],
        date: maintenant.subtract(const Duration(days: 8)),
      ),
      Evaluation(
        id: 'ev5',
        demandeId: 'h5',
        serviceId: 's4',
        auteurEvalue: 'Leila B.',
        note: 5,
        tags: const ['Très serviable'],
        date: maintenant.subtract(const Duration(days: 6)),
      ),
    ];
  }

  /// Créneaux d'exemple pour la semaine en cours (du lundi au dimanche)
  /// et la suivante. Certains sont libres, un est pris par l'utilisateur connecté.
  static List<CreneauCommun> _creneauxInitiaux() {
    final DateTime aujourdhui = DateTime.now();
    final DateTime lundi = DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day - (aujourdhui.weekday - 1),
    );
    final String moi = _nomConnecte();

    final List<CreneauCommun> creneaux = [];
    int numero = 0;

    // Ajoute un créneau le jour "jour" (0 = lundi) de la semaine "semaine"
    void ajouter(
      int semaine,
      int jour,
      String serviceId,
      String titre,
      String debut,
      String fin,
      String? inscrit,
    ) {
      numero++;
      creneaux.add(CreneauCommun(
        id: 'k$numero',
        serviceId: serviceId,
        titre: titre,
        date: DateTime(lundi.year, lundi.month, lundi.day + semaine * 7 + jour),
        heureDebut: debut,
        heureFin: fin,
        inscrit: inscrit,
      ));
    }

    for (int semaine = 0; semaine < 2; semaine++) {
      final bool cette = semaine == 0;

      // Sortie des poubelles : lundi, mercredi, vendredi
      ajouter(semaine, 0, 'c1', 'Sortie des poubelles', '20:00', '20:30', 'Karim M.');
      ajouter(semaine, 2, 'c1', 'Sortie des poubelles', '20:00', '20:30', null);
      ajouter(semaine, 4, 'c1', 'Sortie des poubelles', '20:00', '20:30', null);

      // Nettoyage des escaliers (service s5) : samedi
      ajouter(semaine, 5, 's5', 'Nettoyage des escaliers', '09:00', '10:00',
          cette ? 'Nizar H.' : null);

      // Arrosage du jardin : mardi, jeudi, dimanche
      ajouter(semaine, 1, 'c2', 'Arrosage du jardin', '18:00', '18:30', null);
      ajouter(semaine, 3, 'c2', 'Arrosage du jardin', '18:00', '18:30',
          cette ? moi : null);
      ajouter(semaine, 6, 'c2', 'Arrosage du jardin', '18:00', '18:30', null);
    }
    return creneaux;
  }

  /// Nom court de l'utilisateur connecté, utilisable dans les données de départ.
  static String _nomConnecte() {
    return ServiceRepository().getMonNom();
  }
}
