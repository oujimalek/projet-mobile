import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/creneau_commun.dart';
import '../models/demande_service.dart';
import '../models/service.dart';
import '../models/statut_demande.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firestore_commun.dart';
import 'service_repository.dart';
import 'utilisateur_repository.dart';

/// M2 - Un refus métier (pas connecté, pas ton service...) : le message est
/// en français, prêt à afficher. Jamais levé vers les écrans : les
/// repositories le rangent dans un `Resultat.echec` ou un `Stream.error`.
class RefusM2 implements Exception {
  final String message;

  const RefusM2(this.message);
}

/// M2 - Ce que les repositories Firebase du module Services ont en commun :
/// l'utilisateur connecté, les collections du quartier et le rangement des
/// erreurs. Le module 2 LIT l'utilisateur du module 1 et n'écrit jamais dans
/// ses collections.
class ContexteM2 {
  ContexteM2._(); // pas d'instance

  /// L'utilisateur connecté, tel que le module 1 le garde en mémoire.
  static Utilisateur moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// L'utilisateur connecté, avec un quartier. Sinon un refus en français.
  static Utilisateur connecte() {
    final Utilisateur utilisateur = moi();
    if (utilisateur.id.isEmpty) {
      throw const RefusM2('Tu n\'es pas connecté');
    }
    if ((utilisateur.quartierId ?? '').isEmpty) {
      throw const RefusM2('Choisis d\'abord ton quartier');
    }
    return utilisateur;
  }

  /// quartiers/{quartierId}/{nom} pour le quartier de l'utilisateur connecté.
  static CollectionReference<Map<String, dynamic>> collection(String nom) {
    return FirestoreCommun.collectionDuQuartier(connecte().quartierId!, nom);
  }

  /// Le message à afficher pour une erreur quelconque.
  static String message(Object erreur) {
    if (erreur is RefusM2) {
      return erreur.message;
    }
    if (erreur is FirebaseException) {
      return FirestoreCommun.messageErreur(erreur.code);
    }
    return 'Une erreur est survenue';
  }

  /// Comme FirestoreCommun.executer, mais range aussi les refus métier et
  /// toute autre erreur dans un Resultat en échec : jamais d'exception.
  static Future<Resultat<T>> executer<T>(Future<T> Function() action) async {
    try {
      return await FirestoreCommun.executer(action);
    } catch (erreur) {
      return Resultat.echec(message(erreur));
    }
  }

  /// Construit un Stream de lecture. Si on ne peut pas même le créer (pas
  /// connecté, Firebase absent), ou si Firestore échoue, le Stream porte une
  /// erreur dont la valeur est le message en français (un String).
  static Stream<T> proteger<T>(Stream<T> Function() creer) {
    final Stream<T> source;
    try {
      source = creer();
    } catch (erreur) {
      return Stream<T>.error(message(erreur));
    }
    return source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (erreur, trace, sink) {
          sink.addError(message(erreur));
        },
      ),
    );
  }
}

/// M2 - Version Cloud Firestore de ServiceRepository (celle de l'application).
///
/// Écrit UNIQUEMENT dans quartiers/{q}/services, demandes, evaluations et
/// creneaux. Les formats des documents sont dans docs/schema_firestore.md.
class FirebaseServiceRepository implements ServiceRepository {
  // Cache de getServices() (l'accueil l'appelle sans attendre)
  List<Service> _cache = const [];
  StreamSubscription<List<Service>>? _abonnement;
  String? _quartierEcoute;

  // =====================================================================
  // Utilisateur connecté
  // =====================================================================

  @override
  String getMonNom() {
    return ServiceRepository.nomCourt(ContexteM2.moi());
  }

  @override
  String getMonId() {
    return ContexteM2.moi().id;
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

  static List<Service> _lireServices(QuerySnapshot<Map<String, dynamic>> s) {
    final List<Service> liste = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs) {
      liste.add(Service.fromMap(d.id, d.data()));
    }
    return liste;
  }

  @override
  Stream<List<Service>> ecouterServices() {
    return ContexteM2.proteger(() {
      return ContexteM2.collection('services')
          .orderBy('datePublication', descending: true)
          .snapshots()
          .map(_lireServices);
    });
  }

  @override
  Stream<Service?> ecouterService(String id) {
    return ContexteM2.proteger(() {
      return ContexteM2.collection('services').doc(id).snapshots().map((d) {
        if (!d.exists) {
          return null;
        }
        return Service.fromMap(d.id, d.data()!);
      });
    });
  }

  @override
  List<Service> getServices() {
    // Ne lève jamais d'exception et ne garde aucun abonnement si l'écoute
    // est impossible (pas connecté, pas de quartier, Firebase absent).
    try {
      final Utilisateur utilisateur = ContexteM2.moi();
      final String quartierId = utilisateur.quartierId ?? '';
      if (utilisateur.id.isEmpty || quartierId.isEmpty) {
        _arreterEcoute();
        return const [];
      }
      if (_abonnement == null || _quartierEcoute != quartierId) {
        _arreterEcoute();
        final Stream<List<Service>> flux =
            FirestoreCommun.collectionDuQuartier(quartierId, 'services')
                .orderBy('datePublication', descending: true)
                .snapshots()
                .map(_lireServices);
        _quartierEcoute = quartierId;
        _abonnement = flux.listen(
          (liste) {
            _cache = liste;
          },
          onError: (Object erreur) {
            // cancelOnError : l'abonnement est déjà fermé
            _abonnement = null;
            _quartierEcoute = null;
            _cache = const [];
          },
          cancelOnError: true,
        );
      }
    } catch (_) {
      _arreterEcoute();
    }
    return _cache;
  }

  void _arreterEcoute() {
    _abonnement?.cancel();
    _abonnement = null;
    _quartierEcoute = null;
    _cache = const [];
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
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
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
        throw RefusM2(refus);
      }

      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('services').doc();
      final String dispo = (disponibilite ?? '').trim();
      final Service service = Service(
        id: reference.id,
        titre: titre.trim(),
        description: description.trim(),
        categorie: categorie,
        auteurId: utilisateur.id,
        auteurNom: ServiceRepository.nomCourt(utilisateur),
        estOffre: estOffre,
        estCommun: estCommun,
        jour: estCommun ? jour : null,
        heureDebut: estCommun ? heureDebut : null,
        heureFin: estCommun ? heureFin : null,
        bloc: ServiceRepository.blocDe(utilisateur),
        datePublication: DateTime.now(),
        disponibilite: dispo.isEmpty ? null : dispo,
      );
      // 1) le service d'abord : les règles vérifient l'auteur des créneaux
      //    dans le service déjà enregistré
      await reference.set(service.toMap());

      // 2) les créneaux des 4 prochaines semaines, en un seul batch
      if (estCommun) {
        try {
          final List<CreneauCommun> creneaux = ServiceRepository.genererCreneaux(
            serviceId: service.id,
            titre: service.titre,
            jour: jour!,
            heureDebut: heureDebut!,
            heureFin: heureFin!,
            aujourdhui: DateTime.now(),
          );
          final CollectionReference<Map<String, dynamic>> collection =
              ContexteM2.collection('creneaux');
          final WriteBatch batch = FirestoreCommun.base.batch();
          for (final CreneauCommun creneau in creneaux) {
            batch.set(collection.doc(), creneau.toMap());
          }
          await batch.commit();
        } catch (_) {
          // Pas de service commun sans créneaux : on retire le service
          try {
            await reference.delete();
          } catch (_) {}
          rethrow;
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
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('services').doc(id);
      final DocumentSnapshot<Map<String, dynamic>> document =
          await reference.get();
      if (!document.exists) {
        throw const RefusM2('Ce service n\'existe plus');
      }
      if (document.data()!['auteurId'] != utilisateur.id) {
        throw const RefusM2('Seul l\'auteur peut modifier ce service');
      }
      final String? refus = ServiceRepository.refusPublication(
        titre: titre,
        description: description,
        categorie: categorie,
        estCommun: false, // le jour et les heures ne changent pas
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
      final String dispo = (disponibilite ?? '').trim();
      await reference.update({
        'titre': titre.trim(),
        'description': description.trim(),
        'categorie': categorie,
        'estOffre': estOffre,
        'disponibilite': dispo.isEmpty ? FieldValue.delete() : dispo,
      });
    });
  }

  @override
  Future<Resultat<void>> supprimerService(String id) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('services').doc(id);
      final DocumentSnapshot<Map<String, dynamic>> document =
          await reference.get();
      if (!document.exists) {
        throw const RefusM2('Ce service n\'existe plus');
      }
      if (document.data()!['auteurId'] != utilisateur.id) {
        throw const RefusM2('Seul l\'auteur peut supprimer ce service');
      }

      // Ses demandes en attente (je suis l'auteur : je peux les lire)
      final QuerySnapshot<Map<String, dynamic>> enAttente =
          await ContexteM2.collection('demandes')
              .where('auteurServiceId', isEqualTo: utilisateur.id)
              .where('serviceId', isEqualTo: id)
              .where('statut', isEqualTo: StatutDemande.enAttente.name)
              .get();
      // Ses créneaux (services communs)
      final QuerySnapshot<Map<String, dynamic>> creneaux =
          await ContexteM2.collection('creneaux')
              .where('serviceId', isEqualTo: id)
              .get();

      // Une seule opération : demandes refusées, créneaux et service supprimés
      final WriteBatch batch = FirestoreCommun.base.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in enAttente.docs) {
        batch.update(d.reference, {'statut': StatutDemande.refusee.name});
      }
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in creneaux.docs) {
        batch.delete(d.reference);
      }
      batch.delete(reference);
      await batch.commit();
    });
  }

  // =====================================================================
  // Demandes
  // =====================================================================

  static List<DemandeService> _lireDemandes(
    QuerySnapshot<Map<String, dynamic>> s,
  ) {
    final List<DemandeService> liste = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs) {
      liste.add(DemandeService.fromMap(d.id, d.data()));
    }
    return liste;
  }

  @override
  Stream<List<DemandeService>> ecouterDemandesEnvoyees() {
    return ContexteM2.proteger(() {
      final Utilisateur utilisateur = ContexteM2.connecte();
      return ContexteM2.collection('demandes')
          .where('demandeurId', isEqualTo: utilisateur.id)
          .orderBy('dateDemande', descending: true)
          .snapshots()
          .map(_lireDemandes);
    });
  }

  @override
  Stream<List<DemandeService>> ecouterDemandesRecues() {
    return ContexteM2.proteger(() {
      final Utilisateur utilisateur = ContexteM2.connecte();
      return ContexteM2.collection('demandes')
          .where('auteurServiceId', isEqualTo: utilisateur.id)
          .orderBy('dateDemande', descending: true)
          .snapshots()
          .map(_lireDemandes);
    });
  }

  @override
  Stream<DemandeService?> ecouterDemande(String id) {
    return ContexteM2.proteger(() {
      return ContexteM2.collection('demandes').doc(id).snapshots().map((d) {
        if (!d.exists) {
          return null;
        }
        return DemandeService.fromMap(d.id, d.data()!);
      });
    });
  }

  @override
  Future<Resultat<void>> envoyerDemande(String serviceId) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final CollectionReference<Map<String, dynamic>> demandes =
          ContexteM2.collection('demandes');

      // Déjà demandé ? (la requête filtre demandeurId : les règles l'acceptent)
      final QuerySnapshot<Map<String, dynamic>> existantes = await demandes
          .where('demandeurId', isEqualTo: utilisateur.id)
          .where('serviceId', isEqualTo: serviceId)
          .limit(1)
          .get();
      final bool dejaDemande = existantes.docs.isNotEmpty;

      final DocumentReference<Map<String, dynamic>> serviceRef =
          ContexteM2.collection('services').doc(serviceId);
      // Id fixe (service + demandeur) : impossible de créer deux demandes
      final DocumentReference<Map<String, dynamic>> demandeRef =
          demandes.doc('${serviceId}_${utilisateur.id}');

      final String? refus = await FirestoreCommun.base.runTransaction<String?>(
        (transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> document =
              await transaction.get(serviceRef);
          if (!document.exists) {
            return 'Ce service n\'existe plus';
          }
          final Service service = Service.fromMap(document.id, document.data()!);
          final String? motif = ServiceRepository.refusDemande(
            service,
            utilisateur.id,
            dejaDemande,
          );
          if (motif != null) {
            return motif;
          }
          transaction.set(
            demandeRef,
            DemandeService(
              id: demandeRef.id,
              serviceId: service.id,
              serviceTitre: service.titre,
              demandeurId: utilisateur.id,
              demandeurNom: ServiceRepository.nomCourt(utilisateur),
              auteurServiceId: service.auteurId,
              auteurServiceNom: service.auteurNom,
              statut: StatutDemande.enAttente,
              dateDemande: DateTime.now(),
            ).toMap(),
          );
          return null;
        },
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
    });
  }

  @override
  Future<Resultat<void>> changerStatutDemande(
    String demandeId,
    StatutDemande statut,
  ) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('demandes').doc(demandeId);

      final String? refus = await FirestoreCommun.base.runTransaction<String?>(
        (transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> document =
              await transaction.get(reference);
          if (!document.exists) {
            return 'Cette demande n\'existe plus';
          }
          final DemandeService demande =
              DemandeService.fromMap(document.id, document.data()!);
          final String? motif =
              ServiceRepository.refusStatut(demande, statut, utilisateur.id);
          if (motif != null) {
            return motif;
          }
          transaction.update(reference, {'statut': statut.name});
          return null;
        },
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
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
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> demandeRef =
          ContexteM2.collection('demandes').doc(demandeId);
      // L'id de l'évaluation est l'id de la demande : une seule par demande
      final DocumentReference<Map<String, dynamic>> evaluationRef =
          ContexteM2.collection('evaluations').doc(demandeId);

      final String? refus = await FirestoreCommun.base.runTransaction<String?>(
        (transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> document =
              await transaction.get(demandeRef);
          if (!document.exists) {
            return 'Cette demande n\'existe plus';
          }
          final DemandeService demande =
              DemandeService.fromMap(document.id, document.data()!);
          final String? motif =
              ServiceRepository.refusEvaluation(demande, note, utilisateur.id);
          if (motif != null) {
            return motif;
          }
          final DocumentSnapshot<Map<String, dynamic>> existante =
              await transaction.get(evaluationRef);
          if (existante.exists) {
            return 'Tu as déjà évalué ce service';
          }
          final String texte = (message ?? '').trim();
          transaction.set(
            evaluationRef,
            {
              'serviceId': demande.serviceId,
              'auteurId': utilisateur.id,
              'evalueId': demande.auteurServiceId,
              'evalueNom': demande.auteurServiceNom,
              'note': note,
              'tags': tags,
              if (texte.isNotEmpty) 'message': texte,
              'date': DateTime.now(),
            },
          );
          transaction.update(demandeRef, {'evaluee': true});
          return null;
        },
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
    });
  }

  @override
  Future<Resultat<ResumeAuteur>> getResumeAuteur(String auteurId) {
    return ContexteM2.executer(() async {
      // average() et count() : Firebase calcule sur le serveur, sans
      // renvoyer toutes les évaluations
      final AggregateQuerySnapshot resultat = await ContexteM2.collection('evaluations')
          .where('evalueId', isEqualTo: auteurId)
          .aggregate(average('note'), count())
          .get();
      final int avis = resultat.count ?? 0;
      return ResumeAuteur(
        noteMoyenne: resultat.getAverage('note') ?? 0,
        nombreAvis: avis,
        servicesRendus: avis, // un service rendu est un service évalué
      );
    });
  }

  // =====================================================================
  // Créneaux des services communs
  // =====================================================================

  static List<CreneauCommun> _lireCreneaux(
    QuerySnapshot<Map<String, dynamic>> s,
  ) {
    final List<CreneauCommun> liste = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs) {
      liste.add(CreneauCommun.fromMap(d.id, d.data()));
    }
    // Par date (déjà triés par Firestore), puis par heure de début
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
    return ContexteM2.proteger(() {
      final DateTime debut = DateTime(dateDebut.year, dateDebut.month, dateDebut.day);
      final DateTime fin = DateTime(debut.year, debut.month, debut.day + 7);
      return ContexteM2.collection('creneaux')
          .where('date', isGreaterThanOrEqualTo: debut)
          .where('date', isLessThan: fin)
          .orderBy('date')
          .snapshots()
          .map(_lireCreneaux);
    });
  }

  @override
  Stream<List<CreneauCommun>> ecouterCreneauxParService(String serviceId) {
    return ContexteM2.proteger(() {
      return ContexteM2.collection('creneaux')
          .where('serviceId', isEqualTo: serviceId)
          .orderBy('date')
          .snapshots()
          .map(_lireCreneaux);
    });
  }

  @override
  Stream<CreneauCommun?> ecouterCreneau(String id) {
    return ContexteM2.proteger(() {
      return ContexteM2.collection('creneaux').doc(id).snapshots().map((d) {
        if (!d.exists) {
          return null;
        }
        return CreneauCommun.fromMap(d.id, d.data()!);
      });
    });
  }

  @override
  Future<Resultat<void>> inscrire(String creneauId, {bool rappelVeille = false}) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('creneaux').doc(creneauId);

      final String? refus = await FirestoreCommun.base.runTransaction<String?>(
        (transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> document =
              await transaction.get(reference);
          if (!document.exists) {
            return 'Ce créneau n\'existe plus';
          }
          final CreneauCommun creneau =
              CreneauCommun.fromMap(document.id, document.data()!);
          final String? motif =
              ServiceRepository.refusInscription(creneau, utilisateur.id);
          if (motif != null) {
            return motif;
          }
          transaction.update(reference, {
            'inscritId': utilisateur.id,
            'inscritNom': ServiceRepository.nomCourt(utilisateur),
            'rappelVeille': rappelVeille,
          });
          return null;
        },
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
    });
  }

  @override
  Future<Resultat<void>> desinscrire(String creneauId) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final DocumentReference<Map<String, dynamic>> reference =
          ContexteM2.collection('creneaux').doc(creneauId);

      final String? refus = await FirestoreCommun.base.runTransaction<String?>(
        (transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> document =
              await transaction.get(reference);
          if (!document.exists) {
            return 'Ce créneau n\'existe plus';
          }
          final CreneauCommun creneau =
              CreneauCommun.fromMap(document.id, document.data()!);
          final String? motif =
              ServiceRepository.refusDesinscription(creneau, utilisateur.id);
          if (motif != null) {
            return motif;
          }
          transaction.update(reference, {
            'inscritId': null,
            'inscritNom': null,
            'rappelVeille': false,
          });
          return null;
        },
      );
      if (refus != null) {
        throw RefusM2(refus);
      }
    });
  }
}
