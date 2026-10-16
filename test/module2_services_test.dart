import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
// Evaluation existe aussi dans flutter_test : on la masque pour garder la nôtre
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/creneau_commun.dart';
import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/evaluation.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/models/statut_demande.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/chat_repository.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module2/evaluation_screen.dart';
import 'package:houmani/screens/module2/inscription_creneau_screen.dart';
import 'package:houmani/screens/module2/mes_demandes_screen.dart';
import 'package:houmani/screens/module2/service_detail_screen.dart';
import 'package:houmani/screens/module2/service_form_screen.dart';
import 'package:houmani/screens/module2/services_communs_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/theme/app_theme.dart';
import 'package:houmani/widgets/primary_button.dart';

import 'mock_chat_repository.dart';
import 'mock_service_repository.dart';
import 'mock_utilisateur_repository.dart';

/// Affiche un écran dans une MaterialApp avec le thème Houmani.
Future<void> afficher(WidgetTester tester, Widget ecran) async {
  // Écran haut : toute la liste est visible (ListView.builder construit à la demande)
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ecran));
  await tester.pumpAndSettle();
}

/// Un voisin du quartier q1 (comme Amira, le compte du mock du module 1).
Utilisateur voisin(String id, String prenom, String nom, {String bloc = 'Bloc A'}) {
  return Utilisateur(
    id: id,
    prenom: prenom,
    nom: nom,
    email: '$prenom@houmani.tn'.toLowerCase(),
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, $bloc',
  );
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockServiceRepository depot;
  late MockChatRepository chat;
  late Utilisateur amira; // le compte connecté par défaut
  final Utilisateur karim = voisin('u20', 'Karim', 'Mansour');
  final Utilisateur salma = voisin('u21', 'Salma', 'Gharbi', bloc: 'Bloc C');

  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Chaque test repart de dépôts VIDES (aucune donnée de démonstration).
  // Utilisateur connecté : Amira B. (mock du module 1). Sans ce mock,
  // l'app utiliserait Firebase.
  setUp(() {
    utilisateurs = MockUtilisateurRepository();
    UtilisateurRepository.instance = utilisateurs;
    depot = MockServiceRepository();
    ServiceRepository.instance = depot;
    chat = MockChatRepository();
    ChatRepository.instance = chat;
    amira = utilisateurs.getUtilisateurConnecte();
    utilisateurs.ajouterCompte(karim, 'pw');
    utilisateurs.ajouterCompte(salma, 'pw');
  });

  /// Change l'utilisateur connecté.
  Future<void> devenir(Utilisateur utilisateur) async {
    await utilisateurs.connexion(utilisateur.email, 'pw');
  }

  /// Revient sur le compte d'Amira (mot de passe du mock du module 1).
  Future<void> redevenirAmira() async {
    await utilisateurs.connexion(
      MockUtilisateurRepository.emailDemo,
      MockUtilisateurRepository.motDePasseDemo,
    );
  }

  group('Modèles : Firestore', () {
    test('Service : toMap puis fromMap redonne le même service', () {
      final Service service = Service(
        id: 's1',
        titre: 'Perceuse',
        description: 'Perceuse avec forets',
        categorie: 'Prêt d\'outils',
        auteurId: 'uid1',
        auteurNom: 'Karim M.',
        estOffre: true,
        bloc: 'Bloc A',
        datePublication: DateTime(2026, 10, 1, 9),
        disponibilite: 'Ce week-end',
      );
      final Map<String, dynamic> map = service.toMap();
      // Firestore range un DateTime en Timestamp
      map['datePublication'] = Timestamp.fromDate(map['datePublication']);

      final Service relu = Service.fromMap('s1', map);
      expect(relu.auteurId, 'uid1');
      expect(relu.auteurNom, 'Karim M.');
      expect(relu.auteur, 'Karim M.');
      expect(relu.bloc, 'Bloc A');
      expect(relu.disponibilite, 'Ce week-end');
      expect(relu.datePublication, DateTime(2026, 10, 1, 9));
      expect(map.containsKey('auteurBloc'), isTrue);
    });

    test('Service : les champs optionnels vides ne sont pas écrits', () {
      const Service service = Service(
        id: 's1',
        titre: 'Titre',
        description: 'Description',
        categorie: 'Courses',
        auteurNom: 'Karim M.',
        estOffre: false,
        disponibilite: '',
      );
      final Map<String, dynamic> map = service.toMap();
      expect(map.containsKey('disponibilite'), isFalse);
      expect(map.containsKey('prix'), isFalse);
      expect(map.containsKey('heureDebut'), isFalse);
    });

    test('Service : un document incomplet ne plante pas', () {
      final Service service = Service.fromMap('s9', {});
      expect(service.id, 's9');
      expect(service.titre, '');
      expect(service.auteurId, '');
      expect(service.estCommun, isFalse);
      expect(service.datePublication, isNull);
    });

    test('DemandeService : statut en texte et valeur par défaut', () {
      final DemandeService demande = DemandeService(
        id: 'd1',
        serviceId: 's1',
        serviceTitre: 'Perceuse',
        demandeurId: 'u1',
        demandeurNom: 'Amira B.',
        auteurServiceId: 'u2',
        auteurServiceNom: 'Karim M.',
        statut: StatutDemande.acceptee,
        dateDemande: DateTime(2026, 10, 1),
      );
      final Map<String, dynamic> map = demande.toMap();
      expect(map['statut'], 'acceptee');
      expect(map['evaluee'], false);
      map['dateDemande'] = Timestamp.fromDate(map['dateDemande']);
      final DemandeService relue = DemandeService.fromMap('d1', map);
      expect(relue.statut, StatutDemande.acceptee);
      expect(relue.demandeur, 'Amira B.');
      expect(relue.auteurService, 'Karim M.');

      // Statut inconnu : "en attente"
      expect(
        DemandeService.fromMap('d2', {'statut': 'bizarre'}).statut,
        StatutDemande.enAttente,
      );
    });

    test('Evaluation : l\'id est celui de la demande, le message est facultatif', () {
      final Evaluation evaluation = Evaluation(
        demandeId: 'd1',
        serviceId: 's1',
        auteurId: 'u1',
        evalueId: 'u2',
        evalueNom: 'Karim M.',
        note: 5,
        tags: const ['Sympa'],
        date: DateTime(2026, 10, 1),
      );
      expect(evaluation.id, 'd1');
      final Map<String, dynamic> map = evaluation.toMap();
      expect(map.containsKey('message'), isFalse);
      expect(map['evalueId'], 'u2');
      expect(map['note'], 5);
    });

    test('CreneauCommun : inscritId et inscritNom sont toujours écrits', () {
      final CreneauCommun libre = CreneauCommun(
        id: 'k1',
        serviceId: 's1',
        titre: 'Poubelles',
        date: DateTime(2026, 10, 5),
        heureDebut: '20:00',
        heureFin: '20:30',
      );
      final Map<String, dynamic> map = libre.toMap();
      expect(map.containsKey('inscritId'), isTrue);
      expect(map['inscritId'], isNull);
      expect(map['inscritNom'], isNull);
      expect(libre.estLibre, isTrue);

      map['date'] = Timestamp.fromDate(map['date']);
      map['inscritId'] = 'u1';
      map['inscritNom'] = 'Amira B.';
      final CreneauCommun pris = CreneauCommun.fromMap('k1', map);
      expect(pris.estLibre, isFalse);
      expect(pris.inscrit, 'Amira B.');
    });
  });

  group('Règles métier (sans réseau)', () {
    test('refusPublication : titre, description, catégorie', () {
      expect(
        ServiceRepository.refusPublication(
          titre: 'ab',
          description: 'Une description assez longue',
          categorie: 'Courses',
          estCommun: false,
        ),
        isNotNull,
      );
      expect(
        ServiceRepository.refusPublication(
          titre: 'Courses',
          description: 'court',
          categorie: 'Courses',
          estCommun: false,
        ),
        isNotNull,
      );
      expect(
        ServiceRepository.refusPublication(
          titre: 'Courses',
          description: 'Une description assez longue',
          categorie: 'Tous', // le filtre n'est pas une catégorie
          estCommun: false,
        ),
        isNotNull,
      );
      expect(
        ServiceRepository.refusPublication(
          titre: 'Courses',
          description: 'Une description assez longue',
          categorie: 'Courses',
          estCommun: false,
        ),
        isNull,
      );
    });

    test('refusPublication : un service commun veut jour et heures', () {
      String? refus({String? jour, String? debut, String? fin}) {
        return ServiceRepository.refusPublication(
          titre: 'Poubelles',
          description: 'Sortie des poubelles',
          categorie: 'Bricolage',
          estCommun: true,
          jour: jour,
          heureDebut: debut,
          heureFin: fin,
        );
      }

      expect(refus(), isNotNull);
      expect(refus(jour: 'Lundi'), isNotNull);
      expect(refus(jour: 'Lundi', debut: '20:00', fin: '19:00'), isNotNull);
      expect(refus(jour: 'Lundi', debut: '25:00', fin: '26:00'), isNotNull);
      expect(refus(jour: 'Lundi', debut: '20:00', fin: '20:30'), isNull);
    });

    test('genererCreneaux : 4 semaines, le bon jour, à partir d\'aujourd\'hui', () {
      // Mercredi 7 octobre 2026
      final DateTime mercredi = DateTime(2026, 10, 7);
      final List<CreneauCommun> samedis = ServiceRepository.genererCreneaux(
        serviceId: 's1',
        titre: 'Escaliers',
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
        aujourdhui: mercredi,
      );
      expect(samedis.length, 4);
      expect(samedis.first.date, DateTime(2026, 10, 10));
      expect(samedis.last.date, DateTime(2026, 10, 31));
      for (final CreneauCommun c in samedis) {
        expect(c.date.weekday, DateTime.saturday);
        expect(c.estLibre, isTrue);
      }

      // Même jour que aujourd'hui : il est compté
      final List<CreneauCommun> mercredis = ServiceRepository.genererCreneaux(
        serviceId: 's1',
        titre: 'Arrosage',
        jour: 'Mercredi',
        heureDebut: '18:00',
        heureFin: '18:30',
        aujourdhui: mercredi,
      );
      expect(mercredis.length, 4);
      expect(mercredis.first.date, mercredi);
    });

    test('nomCourt et blocDe', () {
      expect(ServiceRepository.nomCourt(amira), 'Amira B.');
      expect(ServiceRepository.blocDe(amira), 'Bloc B');
      expect(ServiceRepository.blocDe(voisin('x', 'A', 'B').copier(residence: 'Sans bloc')), '');
    });
  });

  group('Repository : services', () {
    test('au départ, aucune donnée : tout est vide', () async {
      expect(depot.getServices(), isEmpty);
      expect(await depot.ecouterServices().first, isEmpty);
      expect(await depot.ecouterDemandesEnvoyees().first, isEmpty);
      expect(await depot.ecouterDemandesRecues().first, isEmpty);
      expect(await depot.ecouterCreneauxDeLaSemaine(DateTime.now()).first, isEmpty);
    });

    test('ajouterService : l\'auteur est l\'utilisateur connecté (uid + nom)', () async {
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Prêt de tondeuse',
        description: 'Tondeuse électrique, à rendre propre.',
        categorie: 'Prêt d\'outils',
        estOffre: true,
        disponibilite: 'Dimanche',
      );

      expect(resultat.estSucces, isTrue);
      final Service service = resultat.donnee!;
      expect(service.auteurId, amira.id);
      expect(service.auteurNom, 'Amira B.');
      expect(service.bloc, 'Bloc B');
      expect(service.disponibilite, 'Dimanche');
      expect(depot.getServices().length, 1);
      expect(depot.getServices().first.id, service.id);
    });

    test('ajouterService : refuse un titre trop court', () async {
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'ab',
        description: 'Une description assez longue',
        categorie: 'Courses',
        estOffre: true,
      );
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, contains('titre'));
      expect(depot.services, isEmpty);
    });

    test('les services sont triés du plus récent au plus ancien', () async {
      depot.ajouterServiceDe(karim, titre: 'Ancien', date: DateTime(2026, 1, 1));
      depot.ajouterServiceDe(karim, titre: 'Récent', date: DateTime(2026, 6, 1));
      final List<Service> liste = await depot.ecouterServices().first;
      expect(liste.map((s) => s.titre).toList(), ['Récent', 'Ancien']);
    });

    test('un service commun crée les créneaux libres des 4 prochaines semaines', () async {
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Nettoyage des escaliers',
        description: 'On nettoie ensemble les escaliers.',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
      );

      expect(resultat.estSucces, isTrue);
      expect(resultat.donnee!.estCommun, isTrue);
      expect(resultat.donnee!.jour, 'Samedi');
      expect(resultat.donnee!.heureDebut, '09:00');
      expect(depot.creneaux.length, 4);
      for (final CreneauCommun c in depot.creneaux) {
        expect(c.serviceId, resultat.donnee!.id);
        expect(c.estLibre, isTrue);
        expect(c.date.weekday, DateTime.saturday);
        expect(c.heureFin, '10:00');
      }
    });

    test('service commun : si les créneaux échouent, le service est retiré', () async {
      depot.echecCreneaux = true;
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Nettoyage des escaliers',
        description: 'On nettoie ensemble les escaliers.',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
      );
      expect(resultat.estSucces, isFalse);
      expect(depot.services, isEmpty);
      expect(depot.creneaux, isEmpty);
    });

    test('modifierService : seul l\'auteur modifie', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');

      final Resultat<void> refus = await depot.modifierService(
        service.id,
        titre: 'Perceuse sans fil',
        description: 'Une description assez longue',
        categorie: 'Bricolage',
        estOffre: true,
      );
      expect(refus.estSucces, isFalse);
      expect(depot.services.first.titre, 'Perceuse');

      await devenir(karim);
      final Resultat<void> ok = await depot.modifierService(
        service.id,
        titre: 'Perceuse sans fil',
        description: 'Une description assez longue',
        categorie: 'Courses',
        estOffre: false,
        disponibilite: 'Lundi',
      );
      expect(ok.estSucces, isTrue);
      final Service modifie = depot.services.first;
      expect(modifie.titre, 'Perceuse sans fil');
      expect(modifie.categorie, 'Courses');
      expect(modifie.estOffre, isFalse);
      expect(modifie.disponibilite, 'Lundi');
      expect(modifie.auteurId, karim.id); // l'auteur ne change jamais
    });

    test('modifierService : le jour et les heures d\'un service commun ne changent pas', () async {
      await depot.ajouterService(
        titre: 'Escaliers',
        description: 'On nettoie ensemble.',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
      );
      final String id = depot.services.first.id;
      await depot.modifierService(
        id,
        titre: 'Escaliers du bloc',
        description: 'On nettoie ensemble.',
        categorie: 'Bricolage',
        estOffre: true,
      );
      final Service modifie = depot.services.first;
      expect(modifie.estCommun, isTrue);
      expect(modifie.jour, 'Samedi');
      expect(modifie.heureDebut, '09:00');
      expect(depot.creneaux.length, 4);
    });

    test('supprimerService : seul l\'auteur, demandes en attente refusées, créneaux supprimés', () async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Perceuse');
      final DemandeService enAttente = depot.ajouterDemandeDe(karim, service);
      final DemandeService acceptee = depot.ajouterDemandeDe(
        salma,
        service,
        statut: StatutDemande.acceptee,
      );
      depot.ajouterCreneau(serviceId: service.id, date: DateTime.now());

      // Un autre voisin ne peut pas supprimer
      await devenir(karim);
      expect((await depot.supprimerService(service.id)).estSucces, isFalse);
      expect(depot.services.length, 1);

      await redevenirAmira();
      final Resultat<void> ok = await depot.supprimerService(service.id);
      expect(ok.estSucces, isTrue);
      expect(depot.services, isEmpty);
      expect(depot.creneaux, isEmpty);
      expect(depot.demandeParId(enAttente.id)!.statut, StatutDemande.refusee);
      // Une demande déjà acceptée n'est pas touchée
      expect(depot.demandeParId(acceptee.id)!.statut, StatutDemande.acceptee);
    });
  });

  group('Repository : demandes', () {
    test('envoyerDemande : crée une demande en attente avec les uids et les noms', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final Resultat<void> resultat = await depot.envoyerDemande(service.id);

      expect(resultat.estSucces, isTrue);
      final DemandeService demande = (await depot.ecouterDemandesEnvoyees().first).first;
      expect(demande.statut, StatutDemande.enAttente);
      expect(demande.demandeurId, amira.id);
      expect(demande.demandeurNom, 'Amira B.');
      expect(demande.auteurServiceId, karim.id);
      expect(demande.serviceTitre, 'Perceuse');
      expect(demande.evaluee, isFalse);

      // Karim la voit dans ses demandes reçues
      await devenir(karim);
      expect((await depot.ecouterDemandesRecues().first).length, 1);
      expect(await depot.ecouterDemandesEnvoyees().first, isEmpty);
    });

    test('envoyerDemande : pas sur son propre service', () async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Mon service');
      final Resultat<void> resultat = await depot.envoyerDemande(service.id);
      expect(resultat.estSucces, isFalse);
      expect(depot.demandes, isEmpty);
    });

    test('envoyerDemande : pas deux fois la même demande', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      expect((await depot.envoyerDemande(service.id)).estSucces, isTrue);
      final Resultat<void> deuxieme = await depot.envoyerDemande(service.id);
      expect(deuxieme.estSucces, isFalse);
      expect(depot.demandes.length, 1);
    });

    test('envoyerDemande : service inconnu ou service commun refusés', () async {
      expect((await depot.envoyerDemande('inconnu')).estSucces, isFalse);
      final Service commun = depot.ajouterServiceDe(
        karim,
        titre: 'Escaliers',
        estCommun: true,
        jour: 'Samedi',
      );
      expect((await depot.envoyerDemande(commun.id)).estSucces, isFalse);
    });

    test('statut : seul l\'auteur du service accepte ou refuse', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final DemandeService demande = depot.ajouterDemandeDe(amira, service);

      // Le demandeur (Amira) ne peut pas accepter sa propre demande
      final Resultat<void> refus =
          await depot.changerStatutDemande(demande.id, StatutDemande.acceptee);
      expect(refus.estSucces, isFalse);
      expect(depot.demandeParId(demande.id)!.statut, StatutDemande.enAttente);

      await devenir(karim);
      expect(
        (await depot.changerStatutDemande(demande.id, StatutDemande.acceptee)).estSucces,
        isTrue,
      );
      expect(depot.demandeParId(demande.id)!.statut, StatutDemande.acceptee);
      // Déjà répondu : on ne peut plus refuser
      expect(
        (await depot.changerStatutDemande(demande.id, StatutDemande.refusee)).estSucces,
        isFalse,
      );
    });

    test('statut : "réalisée" seulement depuis "acceptée", par l\'un des deux', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final DemandeService attente = depot.ajouterDemandeDe(amira, service);
      final DemandeService acceptee = depot.ajouterDemandeDe(
        salma,
        service,
        statut: StatutDemande.acceptee,
      );

      // Depuis "en attente" : refusé
      await devenir(karim);
      expect(
        (await depot.changerStatutDemande(attente.id, StatutDemande.realisee)).estSucces,
        isFalse,
      );
      // Un tiers (Amira) n'est ni le demandeur ni l'auteur de la demande de Salma
      await redevenirAmira();
      expect(
        (await depot.changerStatutDemande(acceptee.id, StatutDemande.realisee)).estSucces,
        isFalse,
      );
      // Le demandeur (Salma) peut la terminer
      await devenir(salma);
      expect(
        (await depot.changerStatutDemande(acceptee.id, StatutDemande.realisee)).estSucces,
        isTrue,
      );
      expect(depot.demandeParId(acceptee.id)!.statut, StatutDemande.realisee);
      // On ne revient jamais à "en attente"
      expect(
        (await depot.changerStatutDemande(acceptee.id, StatutDemande.enAttente)).estSucces,
        isFalse,
      );
    });
  });

  group('Repository : évaluations', () {
    late Service service;
    late DemandeService realisee;

    setUp(() {
      service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      realisee = depot.ajouterDemandeDe(amira, service, statut: StatutDemande.realisee);
    });

    test('evaluer : une seule évaluation, par le demandeur d\'une demande réalisée', () async {
      final Resultat<void> resultat = await depot.evaluer(
        demandeId: realisee.id,
        note: 4,
        tags: const ['Sympa'],
        message: 'Merci !',
      );
      expect(resultat.estSucces, isTrue);
      expect(depot.nombreEvaluations, 1);
      expect(depot.demandeParId(realisee.id)!.evaluee, isTrue);

      // Une deuxième évaluation est refusée
      final Resultat<void> encore = await depot.evaluer(demandeId: realisee.id, note: 5);
      expect(encore.estSucces, isFalse);
      expect(depot.nombreEvaluations, 1);
    });

    test('evaluer : la note doit être entre 1 et 5', () async {
      expect((await depot.evaluer(demandeId: realisee.id, note: 0)).estSucces, isFalse);
      expect((await depot.evaluer(demandeId: realisee.id, note: 6)).estSucces, isFalse);
      expect(depot.nombreEvaluations, 0);
    });

    test('evaluer : refusé si la demande n\'est pas réalisée', () async {
      final DemandeService acceptee = depot.ajouterDemandeDe(
        salma,
        service,
        statut: StatutDemande.acceptee,
      );
      await devenir(salma);
      expect((await depot.evaluer(demandeId: acceptee.id, note: 5)).estSucces, isFalse);
    });

    test('evaluer : seul le demandeur évalue', () async {
      await devenir(karim); // l'auteur du service ne peut pas se noter
      expect((await depot.evaluer(demandeId: realisee.id, note: 5)).estSucces, isFalse);
    });

    test('getResumeAuteur : note moyenne calculée depuis les évaluations', () async {
      final DemandeService autre = depot.ajouterDemandeDe(
        salma,
        service,
        statut: StatutDemande.realisee,
      );
      await depot.evaluer(demandeId: realisee.id, note: 5);
      await devenir(salma);
      await depot.evaluer(demandeId: autre.id, note: 4);

      final ResumeAuteur resume = (await depot.getResumeAuteur(karim.id)).donnee!;
      expect(resume.nombreAvis, 2);
      expect(resume.noteMoyenne, 4.5);
      expect(resume.servicesRendus, 2);

      final ResumeAuteur vide = (await depot.getResumeAuteur('personne')).donnee!;
      expect(vide.nombreAvis, 0);
      expect(vide.noteMoyenne, 0);
    });
  });

  group('Repository : créneaux', () {
    late Service commun;
    late CreneauCommun creneau;

    setUp(() {
      commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      creneau = depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().add(const Duration(days: 1)),
      );
    });

    test('inscrire : le créneau est à moi, avec mon uid et mon nom', () async {
      final Resultat<void> resultat = await depot.inscrire(creneau.id, rappelVeille: true);
      expect(resultat.estSucces, isTrue);
      final CreneauCommun pris = depot.creneauParId(creneau.id)!;
      expect(pris.inscritId, amira.id);
      expect(pris.inscritNom, 'Amira B.');
      expect(pris.rappelVeille, isTrue);
    });

    test('inscrire : pas d\'inscription sur un créneau déjà pris', () async {
      await depot.inscrire(creneau.id);
      await devenir(salma);
      final Resultat<void> resultat = await depot.inscrire(creneau.id);
      expect(resultat.estSucces, isFalse);
      expect(depot.creneauParId(creneau.id)!.inscritId, amira.id);
    });

    test('inscrire : un créneau passé ne se réserve plus', () async {
      final CreneauCommun passe = depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect((await depot.inscrire(passe.id)).estSucces, isFalse);
    });

    test('desinscrire : seulement son propre créneau', () async {
      await depot.inscrire(creneau.id);

      await devenir(salma);
      expect((await depot.desinscrire(creneau.id)).estSucces, isFalse);
      expect(depot.creneauParId(creneau.id)!.inscritId, amira.id);

      await redevenirAmira();
      expect((await depot.desinscrire(creneau.id)).estSucces, isTrue);
      final CreneauCommun libre = depot.creneauParId(creneau.id)!;
      expect(libre.estLibre, isTrue);
      expect(libre.inscritNom, isNull);
    });

    test('le planning de la semaine donne les créneaux triés par date', () async {
      final DateTime lundi = DateTime(2026, 10, 5);
      depot.ajouterCreneau(serviceId: commun.id, date: DateTime(2026, 10, 7), heureDebut: '18:00');
      depot.ajouterCreneau(serviceId: commun.id, date: DateTime(2026, 10, 6), heureDebut: '20:00');
      depot.ajouterCreneau(serviceId: commun.id, date: DateTime(2026, 10, 6), heureDebut: '08:00');
      depot.ajouterCreneau(serviceId: commun.id, date: DateTime(2026, 10, 12)); // semaine suivante

      final List<CreneauCommun> semaine = await depot.ecouterCreneauxDeLaSemaine(lundi).first;
      expect(semaine.length, 3);
      expect(semaine.map((c) => c.heureDebut).toList(), ['08:00', '20:00', '18:00']);
    });
  });

  group('Repository : flux en direct, pas de connexion, erreurs', () {
    test('une liste se met à jour toute seule', () async {
      final Future<List<List<Service>>> listes = depot.ecouterServices().take(2).toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final List<List<Service>> recues = await listes;
      expect(recues[0], isEmpty);
      expect(recues[1].length, 1);
    });

    test('personne n\'est connecté : lectures et écritures échouent proprement', () async {
      // Karim supprime son compte : plus personne de connecté
      await devenir(karim);
      await utilisateurs.supprimerCompte('pw');
      expect(UtilisateurRepository().getUtilisateurConnecte().id, '');

      expect(depot.getServices(), isEmpty);
      await expectLater(depot.ecouterServices(), emitsError('Tu n\'es pas connecté'));
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Perceuse',
        description: 'Une description assez longue',
        categorie: 'Courses',
        estOffre: true,
      );
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, 'Tu n\'es pas connecté');
    });

    test('pas de quartier : message clair', () async {
      await utilisateurs.inscription(
        nomComplet: 'Nouveau Voisin',
        telephone: '22 000 000',
        email: 'nouveau@houmani.tn',
        motDePasse: 'pw',
      );
      await expectLater(
        depot.ecouterServices(),
        emitsError('Choisis d\'abord ton quartier'),
      );
      expect((await depot.envoyerDemande('s1')).erreur, 'Choisis d\'abord ton quartier');
    });

    test('une erreur de connexion arrive dans le Stream et dans le Resultat', () async {
      depot.erreur = 'Serveur injoignable, vérifie ta connexion Internet';
      await expectLater(depot.ecouterServices(), emitsError(depot.erreur));
      final Resultat<void> resultat = await depot.envoyerDemande('s1');
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, depot.erreur);
    });
  });

  group('Écran : liste des services', () {
    testWidgets('sans service : message vide clair', (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());
      expect(
        find.text('Aucun service pour l\'instant. Publie le premier !'),
        findsOneWidget,
      );
    });

    testWidgets('affiche les services, filtre par onglet et catégorie', (WidgetTester tester) async {
      depot.ajouterServiceDe(karim, titre: 'Perceuse à prêter', categorie: 'Prêt d\'outils');
      depot.ajouterServiceDe(salma, titre: 'Courses du samedi', categorie: 'Courses');
      depot.ajouterServiceDe(karim, titre: 'Cherche une échelle', estOffre: false);
      await afficher(tester, const ServicesListScreen());

      expect(find.text('Perceuse à prêter'), findsOneWidget);
      expect(find.text('Courses du samedi'), findsOneWidget);
      expect(find.text('Cherche une échelle'), findsNothing);

      await tester.tap(find.text('Courses').first);
      await tester.pumpAndSettle();
      expect(find.text('Courses du samedi'), findsOneWidget);
      expect(find.text('Perceuse à prêter'), findsNothing);

      await tester.tap(find.text('Demandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Cherche une échelle'), findsOneWidget);
    });

    testWidgets('un nouveau service apparaît tout seul', (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());
      expect(find.text('Perceuse'), findsNothing);
      depot.ajouterServiceDe(karim, titre: 'Perceuse');
      await tester.pumpAndSettle();
      expect(find.text('Perceuse'), findsOneWidget);
    });

    testWidgets('une erreur de connexion est lisible', (WidgetTester tester) async {
      depot.erreur = 'Serveur injoignable, vérifie ta connexion Internet';
      await afficher(tester, const ServicesListScreen());
      expect(find.text('Serveur injoignable, vérifie ta connexion Internet'), findsOneWidget);
    });

    testWidgets('personne de connecté : message clair', (WidgetTester tester) async {
      await devenir(karim);
      await utilisateurs.supprimerCompte('pw');
      await afficher(tester, const ServicesListScreen());
      expect(find.text('Tu n\'es pas connecté'), findsOneWidget);
    });

    testWidgets('toucher une carte ouvre le détail', (WidgetTester tester) async {
      depot.ajouterServiceDe(karim, titre: 'Perceuse à prêter');
      await afficher(tester, const ServicesListScreen());
      await tester.tap(find.text('Perceuse à prêter'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDetailScreen), findsOneWidget);
    });
  });

  group('Écran : détail d\'un service', () {
    testWidgets('demander un service : bouton désactivé, puis "Demande envoyée"', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse à prêter');
      await afficher(tester, ServiceDetailScreen(serviceId: service.id));

      expect(find.text('Perceuse à prêter'), findsOneWidget);
      expect(find.text('Demander ce service'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);

      // Pendant l'écriture, le bouton est désactivé
      depot.blocage = Completer<void>();
      await tester.tap(find.text('Demander ce service'));
      await tester.pump();
      final PrimaryButton pendant = tester.widget(
        find.widgetWithText(PrimaryButton, 'Demander ce service'),
      );
      expect(pendant.onPressed, isNull);

      depot.blocage!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(find.text('Demande envoyée à Karim M.'), findsOneWidget); // SnackBar
      expect(depot.demandes.length, 1);
    });

    testWidgets('mon service : Modifier et Supprimer, pas de demande', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Mon service');
      await afficher(tester, ServiceDetailScreen(serviceId: service.id));
      expect(find.text('Votre publication'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.text('Demander ce service'), findsNothing);
    });

    testWidgets('supprimer demande confirmation puis supprime', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Mon service');
      depot.ajouterDemandeDe(karim, service);
      await afficher(tester, ServiceDetailScreen(serviceId: service.id));

      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer ce service ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(depot.services.length, 1);

      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(depot.services, isEmpty);
      expect(depot.demandes.first.statut, StatutDemande.refusee);
    });

    testWidgets('service supprimé : message clair', (WidgetTester tester) async {
      await afficher(tester, const ServiceDetailScreen(serviceId: 'inconnu'));
      expect(find.text('Ce service n\'existe plus'), findsOneWidget);
    });

    testWidgets('la note de l\'auteur vient des évaluations', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final DemandeService demande =
          depot.ajouterDemandeDe(amira, service, statut: StatutDemande.realisee);
      await depot.evaluer(demandeId: demande.id, note: 4);
      await afficher(tester, ServiceDetailScreen(serviceId: service.id));
      expect(find.textContaining('4.0 (1 avis)'), findsOneWidget);
    });
  });

  group('Écran : formulaire', () {
    testWidgets('champs vides : messages d\'erreur, rien n\'est publié', (WidgetTester tester) async {
      await afficher(tester, const ServiceFormScreen());
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text('Le titre doit avoir au moins 3 caractères'), findsOneWidget);
      expect(find.text('Choisis une catégorie'), findsOneWidget);
      expect(depot.services, isEmpty);
    });

    testWidgets('publier un service', (WidgetTester tester) async {
      await afficher(tester, const ServiceFormScreen());
      await tester.tap(find.text('Courses'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Ex : Perceuse à prêter'), 'Courses du jeudi');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Explique en quelques mots'),
        'Je vais au marché le jeudi.',
      );
      await tester.pump();
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();

      expect(depot.services.length, 1);
      expect(depot.services.first.titre, 'Courses du jeudi');
      expect(depot.services.first.categorie, 'Courses');
      expect(depot.services.first.auteurId, amira.id);
    });

    testWidgets('service commun : le jour et les heures sont obligatoires', (WidgetTester tester) async {
      await afficher(tester, const ServiceFormScreen());
      await tester.tap(find.text('Courses'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Ex : Perceuse à prêter'), 'Escaliers');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Explique en quelques mots'),
        'On nettoie les escaliers.',
      );
      await tester.ensureVisible(find.text('Service commun hebdomadaire'));
      await tester.tap(find.text('Service commun hebdomadaire'));
      await tester.pumpAndSettle();
      expect(find.text('Heure de début'), findsOneWidget);

      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text('Choisis le jour du service commun'), findsOneWidget);
      expect(depot.services, isEmpty);
    });

    testWidgets('modifier : formulaire pré-rempli, enregistre les changements', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(
        amira,
        titre: 'Perceuse à prêter',
        categorie: 'Prêt d\'outils',
      );
      await afficher(tester, ServiceFormScreen(service: service));

      expect(find.text('Modifier le service'), findsOneWidget);
      expect(find.text('Perceuse à prêter'), findsOneWidget); // champ pré-rempli
      expect(find.text('Enregistrer'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Perceuse à prêter'), 'Perceuse sans fil');
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(depot.services.first.titre, 'Perceuse sans fil');
    });

    testWidgets('modifier un service commun : le jour et les heures sont affichés, pas modifiables', (WidgetTester tester) async {
      await depot.ajouterService(
        titre: 'Escaliers',
        description: 'On nettoie les escaliers.',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
      );
      await afficher(tester, ServiceFormScreen(service: depot.services.first));
      expect(find.textContaining('chaque Samedi'), findsOneWidget);
      expect(find.text('Heure de début'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('Écran : mes demandes', () {
    testWidgets('sans demande : messages vides', (WidgetTester tester) async {
      await afficher(tester, const MesDemandesScreen());
      expect(find.text('Envoyées (0)'), findsOneWidget);
      expect(find.text('Reçues (0)'), findsOneWidget);
      expect(find.text('Tu n\'as envoyé aucune demande'), findsOneWidget);
      await tester.tap(find.text('Reçues (0)'));
      await tester.pumpAndSettle();
      expect(find.text('Tu n\'as reçu aucune demande'), findsOneWidget);
    });

    testWidgets('onglets Envoyées / Reçues avec les compteurs', (WidgetTester tester) async {
      final Service mien = depot.ajouterServiceDe(amira, titre: 'Mon service');
      final Service sien = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      depot.ajouterDemandeDe(karim, mien);
      depot.ajouterDemandeDe(salma, mien);
      depot.ajouterDemandeDe(amira, sien);
      await afficher(tester, const MesDemandesScreen());

      expect(find.text('Envoyées (1)'), findsOneWidget);
      expect(find.text('Reçues (2)'), findsOneWidget);
      expect(find.text('Perceuse'), findsOneWidget);
      expect(find.text('Service de Karim M.'), findsNothing); // préfixe + date
      expect(find.textContaining('Service de Karim M.'), findsOneWidget);
    });

    testWidgets('accepter : les boutons sont désactivés pendant l\'écriture', (WidgetTester tester) async {
      final Service mien = depot.ajouterServiceDe(amira, titre: 'Mon service');
      final DemandeService demande = depot.ajouterDemandeDe(karim, mien);
      await afficher(tester, const MesDemandesScreen());
      await tester.tap(find.text('Reçues (1)'));
      await tester.pumpAndSettle();

      depot.blocage = Completer<void>();
      await tester.tap(find.text('Accepter'));
      await tester.pump();
      final PrimaryButton pendant = tester.widget(find.widgetWithText(PrimaryButton, 'Accepter'));
      expect(pendant.onPressed, isNull);

      depot.blocage!.complete();
      await tester.pumpAndSettle();
      expect(depot.demandeParId(demande.id)!.statut, StatutDemande.acceptee);
      expect(find.text('Demande acceptée'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
    });

    testWidgets('refuser une demande reçue', (WidgetTester tester) async {
      final Service mien = depot.ajouterServiceDe(amira, titre: 'Mon service');
      final DemandeService demande = depot.ajouterDemandeDe(karim, mien);
      await afficher(tester, const MesDemandesScreen());
      await tester.tap(find.text('Reçues (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(depot.demandeParId(demande.id)!.statut, StatutDemande.refusee);
    });

    testWidgets('demande réalisée : bouton Évaluer, puis "Service évalué"', (WidgetTester tester) async {
      final Service sien = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      depot.ajouterDemandeDe(amira, sien, statut: StatutDemande.realisee);
      await afficher(tester, const MesDemandesScreen());
      expect(find.text('Évaluer le service'), findsOneWidget);

      final Service autre = depot.ajouterServiceDe(salma, titre: 'Courses');
      depot.ajouterDemandeDe(amira, autre, statut: StatutDemande.realisee, evaluee: true);
      await tester.pumpAndSettle();
      expect(find.text('Service évalué, merci !'), findsOneWidget);
    });

    testWidgets('le badge compte les messages non lus', (WidgetTester tester) async {
      final Service sien = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final DemandeService demande =
          depot.ajouterDemandeDe(amira, sien, statut: StatutDemande.acceptee);
      chat.ajouterMessageDe(karim, demande.id, 'Salam Amira !');
      chat.ajouterMessageDe(karim, demande.id, 'Passe avant 19h');
      await afficher(tester, const MesDemandesScreen());
      expect(find.text('2'), findsOneWidget); // badge
      expect(find.textContaining('Passe avant 19h'), findsOneWidget); // aperçu
    });

    testWidgets('erreur de connexion lisible', (WidgetTester tester) async {
      depot.erreur = 'Action non autorisée';
      await afficher(tester, const MesDemandesScreen());
      expect(find.text('Action non autorisée'), findsOneWidget);
    });
  });

  group('Écran : évaluation', () {
    testWidgets('bouton désactivé tant qu\'aucune étoile, puis envoi', (WidgetTester tester) async {
      final Service sien = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      final DemandeService demande =
          depot.ajouterDemandeDe(amira, sien, statut: StatutDemande.realisee);
      await afficher(tester, EvaluationScreen(demandeId: demande.id));

      PrimaryButton bouton = tester.widget(find.widgetWithText(PrimaryButton, 'Envoyer l\'évaluation'));
      expect(bouton.onPressed, isNull);

      await tester.tap(find.byTooltip('4 sur 5'));
      await tester.pump();
      await tester.tap(find.text('Sympa'));
      await tester.pump();
      bouton = tester.widget(find.widgetWithText(PrimaryButton, 'Envoyer l\'évaluation'));
      expect(bouton.onPressed, isNotNull);

      await tester.tap(find.text('Envoyer l\'évaluation'));
      await tester.pumpAndSettle();
      expect(depot.nombreEvaluations, 1);
      expect(depot.demandeParId(demande.id)!.evaluee, isTrue);
    });

    testWidgets('demande inconnue : message clair', (WidgetTester tester) async {
      await afficher(tester, const EvaluationScreen(demandeId: 'inconnue'));
      expect(find.text('Cette demande n\'existe plus'), findsOneWidget);
    });
  });

  group('Écrans : services communs', () {
    testWidgets('sans service commun : message vide clair', (WidgetTester tester) async {
      await afficher(tester, const ServicesCommunsScreen());
      expect(
        find.text('Aucun service commun pour l\'instant. Publie le premier !'),
        findsOneWidget,
      );
    });

    testWidgets('planning du jour : créneau libre, inscription, puis "Toi"', (WidgetTester tester) async {
      final Service commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now(),
        titre: 'Arrosage du jardin',
      );
      await afficher(tester, const ServicesCommunsScreen());

      expect(find.text('Arrosage du jardin'), findsOneWidget);
      expect(find.text('Créneau libre'), findsOneWidget);

      await tester.tap(find.text('S\'inscrire'));
      await tester.pumpAndSettle();
      expect(find.byType(InscriptionCreneauScreen), findsOneWidget);

      await tester.tap(find.text('Je m\'inscris'));
      await tester.pumpAndSettle();
      expect(depot.creneaux.first.inscritId, amira.id);
      // Retour au planning, qui s'est mis à jour tout seul
      expect(find.byType(InscriptionCreneauScreen), findsNothing);
      expect(find.text('Toi'), findsOneWidget);
    });

    testWidgets('créneau pris par un autre : on ne peut pas le choisir', (WidgetTester tester) async {
      final Service commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      final CreneauCommun pris = depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().add(const Duration(days: 1)),
        inscrit: salma,
      );
      await afficher(tester, InscriptionCreneauScreen(creneauId: pris.id));
      expect(find.text('Pris par Salma G.'), findsOneWidget);
      final PrimaryButton bouton = tester.widget(find.widgetWithText(PrimaryButton, 'Je m\'inscris'));
      expect(bouton.onPressed, isNull);
    });

    testWidgets('se désister de son créneau', (WidgetTester tester) async {
      final Service commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      final CreneauCommun mien = depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().add(const Duration(days: 1)),
        inscrit: amira,
      );
      await afficher(tester, InscriptionCreneauScreen(creneauId: mien.id));
      await tester.tap(find.text('Se désister d\'un créneau'));
      await tester.pumpAndSettle();
      expect(depot.creneauParId(mien.id)!.estLibre, isTrue);
    });

    testWidgets('créneau inconnu : message clair', (WidgetTester tester) async {
      await afficher(tester, const InscriptionCreneauScreen(creneauId: 'inconnu'));
      expect(find.text('Ce créneau n\'existe plus'), findsOneWidget);
    });
  });
}
