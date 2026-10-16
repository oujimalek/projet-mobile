import 'dart:async';

import 'package:houmani/data/models/creneau_commun.dart';
import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/models/statut_demande.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M2 - Implémentation "en mémoire" de ServiceRepository, pour les TESTS.
///
/// Aucune donnée de départ : tout est vide, les tests ajoutent ce dont ils
/// ont besoin. Les règles métier sont celles de ServiceRepository (les mêmes
/// que FirebaseServiceRepository), et les lectures sont des Stream qui se
/// mettent à jour comme Firestore. Marche sans Internet et sans Firebase.
///
/// L'utilisateur connecté vient de UtilisateurRepository (le mock du M1).
class MockServiceRepository implements ServiceRepository {
  final List<Service> _services = [];
  final List<DemandeService> _demandes = [];
  final List<_EvaluationStockee> _evaluations = [];
  final List<CreneauCommun> _creneaux = [];
  int _compteur = 0;

  // Prévient les Stream ouverts qu'une donnée a changé
  final StreamController<void> _changements = StreamController<void>.broadcast();

  /// Si ce n'est pas null : toutes les lectures et écritures échouent avec
  /// ce message (comme Firebase sans réseau).
  String? erreur;

  /// Si true : le prochain ajout de créneaux échoue (test du retour arrière).
  bool echecCreneaux = false;

  /// Combien d'écritures ont été faites (pour vérifier "boutons désactivés").
  int ecritures = 0;

  /// Si ce n'est pas null : les écritures attendent ce Completer (permet de
  /// tester l'état "en cours" d'un écran).
  Completer<void>? blocage;

  // =====================================================================
  // Raccourcis pour les tests
  // =====================================================================

  /// Ajoute directement un service (publié par [auteur]).
  Service ajouterServiceDe(
    Utilisateur auteur, {
    required String titre,
    String categorie = 'Bricolage',
    bool estOffre = true,
    bool estCommun = false,
    String? jour,
    String? heureDebut,
    String? heureFin,
    DateTime? date,
  }) {
    final Service service = Service(
      id: _nouvelId('s'),
      titre: titre,
      description: 'Description de $titre',
      categorie: categorie,
      auteurId: auteur.id,
      auteurNom: ServiceRepository.nomCourt(auteur),
      estOffre: estOffre,
      estCommun: estCommun,
      jour: jour,
      heureDebut: heureDebut,
      heureFin: heureFin,
      bloc: ServiceRepository.blocDe(auteur),
      datePublication: date ?? DateTime.now(),
    );
    _services.add(service);
    _prevenir();
    return service;
  }

  /// Ajoute directement une demande.
  DemandeService ajouterDemandeDe(
    Utilisateur demandeur,
    Service service, {
    StatutDemande statut = StatutDemande.enAttente,
    bool evaluee = false,
  }) {
    final DemandeService demande = DemandeService(
      id: '${service.id}_${demandeur.id}',
      serviceId: service.id,
      serviceTitre: service.titre,
      demandeurId: demandeur.id,
      demandeurNom: ServiceRepository.nomCourt(demandeur),
      auteurServiceId: service.auteurId,
      auteurServiceNom: service.auteurNom,
      statut: statut,
      dateDemande: DateTime.now(),
      evaluee: evaluee,
    );
    _demandes.add(demande);
    _prevenir();
    return demande;
  }

  /// Ajoute directement un créneau libre ou pris.
  CreneauCommun ajouterCreneau({
    required String serviceId,
    required DateTime date,
    String titre = 'Service commun',
    String heureDebut = '18:00',
    String heureFin = '18:30',
    Utilisateur? inscrit,
  }) {
    final CreneauCommun creneau = CreneauCommun(
      id: _nouvelId('k'),
      serviceId: serviceId,
      titre: titre,
      date: DateTime(date.year, date.month, date.day),
      heureDebut: heureDebut,
      heureFin: heureFin,
      inscritId: inscrit?.id,
      inscritNom: inscrit == null ? null : ServiceRepository.nomCourt(inscrit),
    );
    _creneaux.add(creneau);
    _prevenir();
    return creneau;
  }

  /// Les données telles que Firestore les verrait (pour vérifier les tests).
  List<Service> get services => List.of(_services);
  List<DemandeService> get demandes => List.of(_demandes);
  List<CreneauCommun> get creneaux => List.of(_creneaux);
  int get nombreEvaluations => _evaluations.length;

  /// Le document d'une demande (null si elle n'existe pas).
  DemandeService? demandeParId(String id) {
    for (final DemandeService demande in _demandes) {
      if (demande.id == id) {
        return demande;
      }
    }
    return null;
  }

  /// Un créneau par id (null s'il n'existe pas).
  CreneauCommun? creneauParId(String id) {
    for (final CreneauCommun creneau in _creneaux) {
      if (creneau.id == id) {
        return creneau;
      }
    }
    return null;
  }

  // =====================================================================
  // Outils internes
  // =====================================================================

  String _nouvelId(String prefixe) {
    _compteur++;
    return '$prefixe$_compteur';
  }

  void _prevenir() {
    _changements.add(null);
  }

  Utilisateur _moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// Pourquoi on ne peut pas lire ni écrire (null : on peut).
  String? _refusAcces() {
    if (erreur != null) {
      return erreur;
    }
    final Utilisateur moi = _moi();
    if (moi.id.isEmpty) {
      return 'Tu n\'es pas connecté';
    }
    if ((moi.quartierId ?? '').isEmpty) {
      return 'Choisis d\'abord ton quartier';
    }
    return null;
  }

  /// Un Stream qui donne la valeur actuelle, puis une nouvelle à chaque changement.
  Stream<T> _flux<T>(T Function() lire) async* {
    final String? refus = _refusAcces();
    if (refus != null) {
      throw refus; // devient une erreur du Stream, un String comme pour Firebase
    }
    yield lire();
    await for (final _ in _changements.stream) {
      yield lire();
    }
  }

  /// Fait une écriture : vérifie l'accès, attend le blocage éventuel.
  Future<Resultat<T>> _ecrire<T>(Future<T> Function(Utilisateur moi) action) async {
    final String? refus = _refusAcces();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    ecritures++;
    if (blocage != null) {
      await blocage!.future;
    }
    try {
      final T valeur = await action(_moi());
      _prevenir();
      return Resultat.succes(valeur);
    } on _Refus catch (e) {
      return Resultat.echec(e.message);
    }
  }

  // =====================================================================
  // Utilisateur connecté
  // =====================================================================

  @override
  String getMonNom() {
    return ServiceRepository.nomCourt(_moi());
  }

  @override
  String getMonId() {
    return _moi().id;
  }

  @override
  List<String> getCategories() {
    return ServiceRepository.categories;
  }

  @override
  List<String> getTagsEvaluation() {
    return ServiceRepository.tagsEvaluation;
  }

  // =====================================================================
  // Services
  // =====================================================================

  List<Service> _servicesTries() {
    final List<Service> liste = List.of(_services);
    liste.sort((a, b) {
      final DateTime dateA = a.datePublication ?? DateTime(2000);
      final DateTime dateB = b.datePublication ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });
    return liste;
  }

  @override
  Stream<List<Service>> ecouterServices() {
    return _flux(_servicesTries);
  }

  @override
  Stream<Service?> ecouterService(String id) {
    return _flux<Service?>(() {
      for (final Service service in _services) {
        if (service.id == id) {
          return service;
        }
      }
      return null;
    });
  }

  @override
  List<Service> getServices() {
    if (_refusAcces() != null) {
      return const [];
    }
    return _servicesTries();
  }

  @override
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
  }) {
    return _ecrire<Service>((moi) async {
      final String? refus = ServiceRepository.refusPublication(
        titre: titre,
        description: description,
        categorie: categorie,
        estCommun: estCommun,
        jour: jour,
        heureDebut: heureDebut,
        heureFin: heureFin,
      );
      if (refus != null) {
        throw _Refus(refus);
      }
      final String dispo = (disponibilite ?? '').trim();
      final Service service = Service(
        id: _nouvelId('s'),
        titre: titre.trim(),
        description: description.trim(),
        categorie: categorie,
        auteurId: moi.id,
        auteurNom: ServiceRepository.nomCourt(moi),
        estOffre: estOffre,
        estCommun: estCommun,
        jour: estCommun ? jour : null,
        heureDebut: estCommun ? heureDebut : null,
        heureFin: estCommun ? heureFin : null,
        bloc: ServiceRepository.blocDe(moi),
        datePublication: DateTime.now(),
        disponibilite: dispo.isEmpty ? null : dispo,
      );
      _services.add(service);
      if (estCommun) {
        if (echecCreneaux) {
          _services.remove(service); // retour arrière, comme Firebase
          throw _Refus('Une erreur est survenue');
        }
        for (final CreneauCommun modele in ServiceRepository.genererCreneaux(
          serviceId: service.id,
          titre: service.titre,
          jour: jour!,
          heureDebut: heureDebut!,
          heureFin: heureFin!,
          aujourdhui: DateTime.now(),
        )) {
          _creneaux.add(CreneauCommun(
            id: _nouvelId('k'),
            serviceId: modele.serviceId,
            titre: modele.titre,
            date: modele.date,
            heureDebut: modele.heureDebut,
            heureFin: modele.heureFin,
          ));
        }
      }
      return service;
    });
  }

  @override
  Future<Resultat<void>> modifierService(
    String id, {
    required String titre,
    required String description,
    required String categorie,
    required bool estOffre,
    String? disponibilite,
  }) {
    return _ecrire<void>((moi) async {
      final int index = _services.indexWhere((s) => s.id == id);
      if (index == -1) {
        throw _Refus('Ce service n\'existe plus');
      }
      if (_services[index].auteurId != moi.id) {
        throw _Refus('Seul l\'auteur peut modifier ce service');
      }
      final String? refus = ServiceRepository.refusPublication(
        titre: titre,
        description: description,
        categorie: categorie,
        estCommun: false,
      );
      if (refus != null) {
        throw _Refus(refus);
      }
      final String dispo = (disponibilite ?? '').trim();
      final Service ancien = _services[index];
      _services[index] = Service(
        id: ancien.id,
        titre: titre.trim(),
        description: description.trim(),
        categorie: categorie,
        auteurId: ancien.auteurId,
        auteurNom: ancien.auteurNom,
        estOffre: estOffre,
        estCommun: ancien.estCommun,
        jour: ancien.jour,
        heureDebut: ancien.heureDebut,
        heureFin: ancien.heureFin,
        prix: ancien.prix,
        bloc: ancien.bloc,
        datePublication: ancien.datePublication,
        disponibilite: dispo.isEmpty ? null : dispo,
        duree: ancien.duree,
        recuperation: ancien.recuperation,
      );
    });
  }

  @override
  Future<Resultat<void>> supprimerService(String id) {
    return _ecrire<void>((moi) async {
      final int index = _services.indexWhere((s) => s.id == id);
      if (index == -1) {
        throw _Refus('Ce service n\'existe plus');
      }
      if (_services[index].auteurId != moi.id) {
        throw _Refus('Seul l\'auteur peut supprimer ce service');
      }
      // Ses demandes en attente passent à "refusée"
      for (int i = 0; i < _demandes.length; i++) {
        if (_demandes[i].serviceId == id &&
            _demandes[i].statut == StatutDemande.enAttente) {
          _demandes[i] = _demandes[i].copyWith(statut: StatutDemande.refusee);
        }
      }
      _creneaux.removeWhere((c) => c.serviceId == id);
      _services.removeAt(index);
    });
  }

  // =====================================================================
  // Demandes
  // =====================================================================

  List<DemandeService> _demandesOu(bool Function(DemandeService) garder) {
    final List<DemandeService> liste = _demandes.where(garder).toList();
    liste.sort((a, b) => b.dateDemande.compareTo(a.dateDemande));
    return liste;
  }

  @override
  Stream<List<DemandeService>> ecouterDemandesEnvoyees() {
    return _flux(() => _demandesOu((d) => d.demandeurId == _moi().id));
  }

  @override
  Stream<List<DemandeService>> ecouterDemandesRecues() {
    return _flux(() => _demandesOu((d) => d.auteurServiceId == _moi().id));
  }

  @override
  Stream<DemandeService?> ecouterDemande(String id) {
    return _flux<DemandeService?>(() => demandeParId(id));
  }

  @override
  Future<Resultat<void>> envoyerDemande(String serviceId) {
    return _ecrire<void>((moi) async {
      final int index = _services.indexWhere((s) => s.id == serviceId);
      if (index == -1) {
        throw _Refus('Ce service n\'existe plus');
      }
      final bool dejaDemande = _demandes.any(
        (d) => d.serviceId == serviceId && d.demandeurId == moi.id,
      );
      final String? refus = ServiceRepository.refusDemande(
        _services[index],
        moi.id,
        dejaDemande,
      );
      if (refus != null) {
        throw _Refus(refus);
      }
      final Service service = _services[index];
      _demandes.add(DemandeService(
        id: '${service.id}_${moi.id}',
        serviceId: service.id,
        serviceTitre: service.titre,
        demandeurId: moi.id,
        demandeurNom: ServiceRepository.nomCourt(moi),
        auteurServiceId: service.auteurId,
        auteurServiceNom: service.auteurNom,
        statut: StatutDemande.enAttente,
        dateDemande: DateTime.now(),
      ));
    });
  }

  @override
  Future<Resultat<void>> changerStatutDemande(
    String demandeId,
    StatutDemande statut,
  ) {
    return _ecrire<void>((moi) async {
      final int index = _demandes.indexWhere((d) => d.id == demandeId);
      if (index == -1) {
        throw _Refus('Cette demande n\'existe plus');
      }
      final String? refus =
          ServiceRepository.refusStatut(_demandes[index], statut, moi.id);
      if (refus != null) {
        throw _Refus(refus);
      }
      _demandes[index] = _demandes[index].copyWith(statut: statut);
    });
  }

  // =====================================================================
  // Évaluations
  // =====================================================================

  @override
  Future<Resultat<void>> evaluer({
    required String demandeId,
    required int note,
    List<String> tags = const [],
    String? message,
  }) {
    return _ecrire<void>((moi) async {
      final int index = _demandes.indexWhere((d) => d.id == demandeId);
      if (index == -1) {
        throw _Refus('Cette demande n\'existe plus');
      }
      final DemandeService demande = _demandes[index];
      final String? refus = ServiceRepository.refusEvaluation(demande, note, moi.id);
      if (refus != null) {
        throw _Refus(refus);
      }
      if (_evaluations.any((e) => e.demandeId == demandeId)) {
        throw _Refus('Tu as déjà évalué ce service');
      }
      _evaluations.add(_EvaluationStockee(
        demandeId: demandeId,
        evalueId: demande.auteurServiceId,
        note: note,
      ));
      _demandes[index] = demande.copyWith(evaluee: true);
    });
  }

  @override
  Future<Resultat<ResumeAuteur>> getResumeAuteur(String auteurId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    int total = 0;
    int nombre = 0;
    for (final _EvaluationStockee evaluation in _evaluations) {
      if (evaluation.evalueId == auteurId) {
        total += evaluation.note;
        nombre++;
      }
    }
    return Resultat.succes(ResumeAuteur(
      noteMoyenne: nombre == 0 ? 0 : total / nombre,
      nombreAvis: nombre,
      servicesRendus: nombre,
    ));
  }

  // =====================================================================
  // Créneaux des services communs
  // =====================================================================

  List<CreneauCommun> _creneauxOu(bool Function(CreneauCommun) garder) {
    final List<CreneauCommun> liste = _creneaux.where(garder).toList();
    liste.sort((a, b) {
      final int parDate = a.date.compareTo(b.date);
      if (parDate != 0) {
        return parDate;
      }
      return a.heureDebut.compareTo(b.heureDebut);
    });
    return liste;
  }

  @override
  Stream<List<CreneauCommun>> ecouterCreneauxDeLaSemaine(DateTime dateDebut) {
    final DateTime debut = DateTime(dateDebut.year, dateDebut.month, dateDebut.day);
    final DateTime fin = DateTime(debut.year, debut.month, debut.day + 7);
    return _flux(
      () => _creneauxOu((c) => !c.date.isBefore(debut) && c.date.isBefore(fin)),
    );
  }

  @override
  Stream<List<CreneauCommun>> ecouterCreneauxParService(String serviceId) {
    return _flux(() => _creneauxOu((c) => c.serviceId == serviceId));
  }

  @override
  Stream<CreneauCommun?> ecouterCreneau(String id) {
    return _flux<CreneauCommun?>(() => creneauParId(id));
  }

  @override
  Future<Resultat<void>> inscrire(String creneauId, {bool rappelVeille = false}) {
    return _ecrire<void>((moi) async {
      final int index = _creneaux.indexWhere((c) => c.id == creneauId);
      if (index == -1) {
        throw _Refus('Ce créneau n\'existe plus');
      }
      final String? refus =
          ServiceRepository.refusInscription(_creneaux[index], moi.id);
      if (refus != null) {
        throw _Refus(refus);
      }
      final CreneauCommun ancien = _creneaux[index];
      _creneaux[index] = CreneauCommun(
        id: ancien.id,
        serviceId: ancien.serviceId,
        titre: ancien.titre,
        date: ancien.date,
        heureDebut: ancien.heureDebut,
        heureFin: ancien.heureFin,
        inscritId: moi.id,
        inscritNom: ServiceRepository.nomCourt(moi),
        rappelVeille: rappelVeille,
      );
    });
  }

  @override
  Future<Resultat<void>> desinscrire(String creneauId) {
    return _ecrire<void>((moi) async {
      final int index = _creneaux.indexWhere((c) => c.id == creneauId);
      if (index == -1) {
        throw _Refus('Ce créneau n\'existe plus');
      }
      final String? refus =
          ServiceRepository.refusDesinscription(_creneaux[index], moi.id);
      if (refus != null) {
        throw _Refus(refus);
      }
      final CreneauCommun ancien = _creneaux[index];
      _creneaux[index] = CreneauCommun(
        id: ancien.id,
        serviceId: ancien.serviceId,
        titre: ancien.titre,
        date: ancien.date,
        heureDebut: ancien.heureDebut,
        heureFin: ancien.heureFin,
      );
    });
  }
}

class _Refus implements Exception {
  final String message;

  _Refus(this.message);
}

class _EvaluationStockee {
  final String demandeId;
  final String evalueId;
  final int note;

  _EvaluationStockee({
    required this.demandeId,
    required this.evalueId,
    required this.note,
  });
}
