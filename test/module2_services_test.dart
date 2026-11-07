import 'dart:async';
import 'dart:io';

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
import 'package:houmani/screens/module2/module2_outils.dart';
import 'package:houmani/screens/module2/participants_rotation_screen.dart';
import 'package:houmani/screens/module2/service_detail_screen.dart';
import 'package:houmani/screens/module2/service_form_screen.dart';
import 'package:houmani/screens/module2/services_communs_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/theme/app_theme.dart';
import 'package:houmani/widgets/primary_button.dart';
import 'package:houmani/widgets/secondary_button.dart';

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

  // ===================================================================
  // Rotation, « Fait », rappels, prolongation, corrections
  // ===================================================================

  // Lundi 9 novembre 2026
  final DateTime lundi9 = DateTime(2026, 11, 9);

  /// Un service commun en rotation (uids A, B, C par défaut).
  Service serviceRotation({
    List<String> ids = const ['A', 'B', 'C'],
    DateTime? depuis,
    int index = 0,
    Map<String, TourRotation> figes = const {},
    Map<String, FaitCreneau> faits = const {},
    bool rotation = true,
  }) {
    return Service(
      id: 's1',
      titre: 'Sortie des poubelles',
      description: 'Sortie des poubelles du bloc',
      categorie: 'Bricolage',
      auteurId: 'auteur',
      auteurNom: 'Amira B.',
      estOffre: true,
      estCommun: true,
      jour: 'Lundi',
      heureDebut: '20:00',
      heureFin: '20:30',
      modeRotation: rotation,
      participantsIds: ids,
      participantsNoms: [for (final String id in ids) 'Nom $id'],
      rotationDepuis: depuis,
      rotationIndex: index,
      toursFiges: figes,
      creneauxFaits: faits,
    );
  }

  /// [n] créneaux hebdomadaires du service s1 à partir de [premier].
  List<CreneauCommun> semaines(DateTime premier, int n, {String serviceId = 's1'}) {
    return [
      for (int i = 0; i < n; i++)
        CreneauCommun(
          id: ServiceRepository.idCreneau(
            serviceId,
            DateTime(premier.year, premier.month, premier.day + 7 * i),
          ),
          serviceId: serviceId,
          titre: 'Sortie des poubelles',
          date: DateTime(premier.year, premier.month, premier.day + 7 * i),
          heureDebut: '20:00',
          heureFin: '20:30',
        ),
    ];
  }

  String idDe(DateTime date) => ServiceRepository.idCreneau('s1', date);

  List<String> uidsDesTours(Map<String, TourRotation> tours, List<CreneauCommun> creneaux) {
    return [for (final CreneauCommun c in creneaux) tours[c.id]?.id ?? '-'];
  }

  group('Modèles : rotation et désistement', () {
    test('Service : un ancien document (sans rotation) reste lisible', () {
      final Service ancien = Service.fromMap('s1', {
        'titre': 'Escaliers',
        'estCommun': true,
        'jour': 'Samedi',
      });
      expect(ancien.modeRotation, isFalse);
      expect(ancien.participantsIds, isEmpty);
      expect(ancien.participants, isEmpty);
      expect(ancien.rotationDepuis, isNull);
      expect(ancien.rotationIndex, 0);
      expect(ancien.toursFiges, isEmpty);
      expect(ancien.creneauxFaits, isEmpty);
    });

    test('Service : la rotation est écrite puis relue', () {
      final Service service = serviceRotation(
        depuis: lundi9,
        index: 1,
        figes: const {'x': TourRotation(id: 'B', nom: 'Nom B')},
      );
      final Map<String, dynamic> map = service.toMap();
      expect(map['modeRotation'], isTrue);
      expect(map['participantsIds'], ['A', 'B', 'C']);
      expect(map['rotationIndex'], 1);
      map['rotationDepuis'] = Timestamp.fromDate(map['rotationDepuis']);
      map['creneauxFaits'] = {
        's1_20261102': {
          'faitLe': Timestamp.fromDate(DateTime(2026, 11, 2, 21)),
          'parId': 'A',
          'parNom': 'Nom A',
        },
      };
      final Service relu = Service.fromMap('s1', map);
      expect(relu.modeRotation, isTrue);
      expect(relu.participantsNoms, ['Nom A', 'Nom B', 'Nom C']);
      expect(relu.rotationDepuis, lundi9);
      expect(relu.rotationIndex, 1);
      expect(relu.toursFiges['x']!.id, 'B');
      expect(relu.creneauxFaits['s1_20261102']!.parNom, 'Nom A');
      expect(relu.creneauxFaits['s1_20261102']!.faitLe, DateTime(2026, 11, 2, 21));
    });

    test('Service : un service libre n\'écrit aucun champ de rotation', () {
      final Map<String, dynamic> map = serviceRotation(rotation: false).toMap();
      expect(map.containsKey('modeRotation'), isFalse);
      expect(map.containsKey('participantsIds'), isFalse);
      expect(map.containsKey('rotationDepuis'), isFalse);
    });

    test('Service.copyWith garde les champs de rotation', () {
      final Service service = serviceRotation(depuis: lundi9, index: 2);
      final Service copie = service.copyWith(titre: 'Autre titre');
      expect(copie.modeRotation, isTrue);
      expect(copie.participantsIds, ['A', 'B', 'C']);
      expect(copie.rotationIndex, 2);
      expect(copie.rotationDepuis, lundi9);
    });

    test('le marqueur de désistement : une constante unique, jamais affichée', () {
      expect(CreneauCommun.marqueDesiste, isNotEmpty);
      final CreneauCommun desiste = CreneauCommun(
        id: 'k1',
        serviceId: 's1',
        titre: 'Poubelles',
        date: lundi9,
        heureDebut: '20:00',
        heureFin: '20:30',
        inscritNom: CreneauCommun.marqueDesiste,
      );
      expect(desiste.estLibre, isTrue);
      expect(desiste.estDesiste, isTrue);
      expect(desiste.inscrit, isNull); // ce que lisent les écrans
      // Il est bien écrit dans Firestore tel quel
      expect(desiste.toMap()['inscritNom'], CreneauCommun.marqueDesiste);
      expect(desiste.toMap()['inscritId'], isNull);

      // Un créneau libre normal n'est pas « désisté »
      final CreneauCommun libre = CreneauCommun(
        id: 'k2',
        serviceId: 's1',
        titre: 'Poubelles',
        date: lundi9,
        heureDebut: '20:00',
        heureFin: '20:30',
      );
      expect(libre.estDesiste, isFalse);
      expect(libre.inscrit, isNull);
    });

    test('le marqueur n\'apparaît qu\'à un seul endroit du code, et les écrans ne lisent pas inscritNom', () {
      final List<String> avecLitteral = [];
      final List<String> ecransAvecInscritNom = [];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) {
          continue;
        }
        final String source = f.readAsStringSync();
        final String chemin = f.path.replaceAll('\\', '/');
        if (source.contains('__desiste__')) {
          avecLitteral.add(chemin);
        }
        if (chemin.contains('screens/module2/') && source.contains('inscritNom')) {
          ecransAvecInscritNom.add(chemin);
        }
      }
      expect(avecLitteral.length, 1);
      expect(avecLitteral.first, endsWith('data/models/creneau_commun.dart'));
      expect(ecransAvecInscritNom, isEmpty);
    });
  });

  group('Rotation : calcul des tours (fonction pure)', () {
    test('les créneaux sont attribués dans l\'ordre, puis on recommence', () {
      final List<CreneauCommun> creneaux = semaines(lundi9, 5);
      final Service service = serviceRotation(depuis: lundi9);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(service, creneaux);
      expect(uidsDesTours(tours, creneaux), ['A', 'B', 'C', 'A', 'B']);
      expect(tours[creneaux.first.id]!.nom, 'Nom A');
    });

    test('rotationIndex décale le départ du cycle', () {
      final List<CreneauCommun> creneaux = semaines(lundi9, 4);
      final Service service = serviceRotation(depuis: lundi9, index: 2);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(service, creneaux);
      expect(uidsDesTours(tours, creneaux), ['C', 'A', 'B', 'C']);
    });

    test('les créneaux avant rotationDepuis n\'ont pas de tour calculé', () {
      final List<CreneauCommun> creneaux = semaines(DateTime(2026, 11, 2), 4);
      final Service service = serviceRotation(depuis: lundi9);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(service, creneaux);
      expect(uidsDesTours(tours, creneaux), ['-', 'A', 'B', 'C']);
    });

    test('un tour figé garde son titulaire et ne compte pas dans le cycle', () {
      final List<CreneauCommun> creneaux = semaines(lundi9, 4);
      final Service service = serviceRotation(
        depuis: DateTime(2026, 11, 16),
        figes: {creneaux.first.id: const TourRotation(id: 'C', nom: 'Nom C')},
      );
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(service, creneaux);
      expect(uidsDesTours(tours, creneaux), ['C', 'A', 'B', 'C']);
    });

    test('mode libre ou aucun participant : aucun tour', () {
      final List<CreneauCommun> creneaux = semaines(lundi9, 3);
      expect(
        ServiceRepository.calculerTours(serviceRotation(rotation: false), creneaux),
        isEmpty,
      );
      expect(
        ServiceRepository.calculerTours(serviceRotation(ids: const []), creneaux),
        isEmpty,
      );
    });

    test('titulaire : fait, puis inscrit, puis tour ; un désistement ne laisse personne', () {
      final List<CreneauCommun> creneaux = semaines(lundi9, 1);
      final CreneauCommun libre = creneaux.first;
      final Service service = serviceRotation(depuis: lundi9);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(service, creneaux);

      expect(ServiceRepository.titulaire(service, libre, tours)!.id, 'A');

      final CreneauCommun inscrit = CreneauCommun(
        id: libre.id,
        serviceId: 's1',
        titre: libre.titre,
        date: libre.date,
        heureDebut: libre.heureDebut,
        heureFin: libre.heureFin,
        inscritId: 'Z',
        inscritNom: 'Zed',
      );
      expect(ServiceRepository.titulaire(service, inscrit, tours)!.id, 'Z');

      final Service fait = serviceRotation(
        depuis: lundi9,
        faits: {libre.id: const FaitCreneau(parId: 'B', parNom: 'Nom B')},
      );
      expect(ServiceRepository.titulaire(fait, inscrit, tours)!.id, 'B');

      final CreneauCommun desiste = CreneauCommun(
        id: libre.id,
        serviceId: 's1',
        titre: libre.titre,
        date: libre.date,
        heureDebut: libre.heureDebut,
        heureFin: libre.heureFin,
        inscritNom: CreneauCommun.marqueDesiste,
      );
      expect(ServiceRepository.titulaire(service, desiste, tours), isNull);
    });
  });

  group('Rotation : changer les participants (cycle repris, jour figé)', () {
    // Créneaux : 2/11 (passé), 9/11 (aujourd'hui), 16/11, 23/11, 30/11
    late List<CreneauCommun> creneaux;
    late Service depart;
    final DateTime aujourdhui = lundi9;

    setUp(() {
      creneaux = semaines(DateTime(2026, 11, 2), 5);
      depart = serviceRotation(depuis: DateTime(2026, 11, 2)); // 2/11 A, 9/11 B, 16/11 C...
    });

    /// Applique le nouvel ordre et renvoie le service obtenu.
    Service appliquer(List<String> ids) {
      final AncreRotation ancre = ServiceRepository.nouvelleAncre(
        depart,
        ids,
        creneaux,
        aujourdhui,
      );
      return depart.copyWith(
        participantsIds: ids,
        participantsNoms: [for (final String id in ids) 'Nom $id'],
        rotationDepuis: ancre.depuis,
        rotationIndex: ancre.index,
        toursFiges: ancre.toursFiges,
      );
    }

    test('avant le changement : A, B, C, A, B', () {
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(depart, creneaux);
      expect(uidsDesTours(tours, creneaux), ['A', 'B', 'C', 'A', 'B']);
    });

    test('ajout d\'un participant : le créneau du jour est figé, le cycle reprend après lui', () {
      final Service nouveau = appliquer(['A', 'B', 'C', 'D']);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(nouveau, creneaux);
      // 9/11 figé sur B ; ensuite C, D, A (le cycle reprend après B)
      expect(tours[idDe(DateTime(2026, 11, 9))]!.id, 'B');
      expect(uidsDesTours(tours, creneaux.sublist(2)), ['C', 'D', 'A']);
      expect(nouveau.toursFiges.keys, [idDe(DateTime(2026, 11, 9))]);
      expect(nouveau.rotationDepuis, DateTime(2026, 11, 16));
    });

    test('retrait d\'un participant : on saute le participant retiré', () {
      final Service nouveau = appliquer(['A', 'B']); // C part
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(nouveau, creneaux);
      expect(tours[idDe(DateTime(2026, 11, 9))]!.id, 'B'); // jour figé
      expect(uidsDesTours(tours, creneaux.sublist(2)), ['A', 'B', 'A']);
    });

    test('changement d\'ordre : le jour reste figé, le futur suit le nouvel ordre', () {
      final Service nouveau = appliquer(['C', 'B', 'A']);
      final Map<String, TourRotation> tours = ServiceRepository.calculerTours(nouveau, creneaux);
      expect(tours[idDe(DateTime(2026, 11, 9))]!.id, 'B');
      // après B (ancien ordre), le suivant est C, qui est en 1re position
      expect(uidsDesTours(tours, creneaux.sublist(2)), ['C', 'B', 'A']);
    });

    test('les créneaux passés ne changent jamais (ni leur titulaire, ni leur état)', () {
      final Service nouveau = appliquer(['D', 'A', 'B', 'C']);
      final Map<String, TourRotation> avant = ServiceRepository.calculerTours(depart, creneaux);
      final Map<String, TourRotation> apres = ServiceRepository.calculerTours(nouveau, creneaux);
      // Le créneau du 2/11 est antérieur à la nouvelle ancre : plus de tour calculé,
      // mais aucun créneau n'est modifié (rien n'est écrit dessus)
      expect(apres.containsKey(creneaux.first.id), isFalse);
      expect(avant[creneaux.first.id]!.id, 'A');
      // Le créneau du jour garde exactement son titulaire
      expect(apres[creneaux[1].id]!.id, avant[creneaux[1].id]!.id);
    });

    test('un créneau déjà fait reste attribué à celui qui l\'a fait', () {
      final Service avecFait = depart.copyWith(creneauxFaits: {
        creneaux[1].id: const FaitCreneau(parId: 'B', parNom: 'Nom B'),
      });
      expect(
        ServiceRepository.titulaire(
          avecFait,
          creneaux[1],
          ServiceRepository.calculerTours(avecFait, creneaux),
        )!.id,
        'B',
      );
      depart = avecFait;
      final Service nouveau = appliquer(['C', 'A']);
      // fait reste fait, avec son titulaire
      expect(nouveau.creneauxFaits.containsKey(creneaux[1].id), isTrue);
      expect(nouveau.creneauxFaits[creneaux[1].id]!.parId, 'B');
    });

    test('sans créneau aujourd\'hui, le cycle reprend après le dernier créneau passé', () {
      final AncreRotation ancre = ServiceRepository.nouvelleAncre(
        depart,
        ['A', 'B', 'C', 'D'],
        creneaux,
        DateTime(2026, 11, 10), // mardi : le créneau du 9/11 est passé
      );
      expect(ancre.toursFiges, isEmpty);
      expect(ancre.depuis, DateTime(2026, 11, 16));
      expect(ancre.index, 2); // après B (titulaire du 9/11) vient C
    });

    test('pas encore de créneau passé : le cycle commence au 1er participant', () {
      final List<CreneauCommun> futurs = semaines(DateTime(2026, 11, 16), 3);
      final Service neuf = serviceRotation(depuis: DateTime(2026, 11, 16));
      final AncreRotation ancre = ServiceRepository.nouvelleAncre(
        neuf,
        ['C', 'B', 'A'],
        futurs,
        aujourdhui,
      );
      expect(ancre.index, 0);
      expect(ancre.depuis, DateTime(2026, 11, 16));
    });
  });

  group('Marquage « Fait »', () {
    test('refusFait : seul l\'auteur, pas avant la date, une seule fois', () {
      final Service service = serviceRotation(depuis: lundi9);
      final CreneauCommun creneau = semaines(lundi9, 1).first;

      expect(
        ServiceRepository.refusFait(service, creneau, 'autre', lundi9),
        isNotNull,
      );
      expect(
        ServiceRepository.refusFait(service, creneau, 'auteur', DateTime(2026, 11, 8, 23, 59)),
        isNotNull, // la veille : trop tôt
      );
      expect(
        ServiceRepository.refusFait(service, creneau, 'auteur', DateTime(2026, 11, 9, 0, 1)),
        isNull, // le jour même, dès minuit
      );
      expect(
        ServiceRepository.refusFait(service, creneau, 'auteur', DateTime(2026, 11, 12)),
        isNull, // après
      );
      final Service dejaFait = serviceRotation(
        depuis: lundi9,
        faits: {creneau.id: const FaitCreneau()},
      );
      expect(
        ServiceRepository.refusFait(dejaFait, creneau, 'auteur', DateTime(2026, 11, 12)),
        isNotNull,
      );
    });

    test('refusInscription / refusDesinscription : un créneau fait n\'est plus modifiable', () {
      final CreneauCommun creneau = CreneauCommun(
        id: 'k1',
        serviceId: 's1',
        titre: 'P',
        date: DateTime.now().add(const Duration(days: 1)),
        heureDebut: '20:00',
        heureFin: '20:30',
        inscritId: 'u1',
        inscritNom: 'Moi',
      );
      expect(ServiceRepository.refusDesinscription(creneau, 'u1'), isNull);
      expect(ServiceRepository.refusDesinscription(creneau, 'u1', fait: true), isNotNull);
      final CreneauCommun libre = CreneauCommun(
        id: 'k2',
        serviceId: 's1',
        titre: 'P',
        date: DateTime.now().add(const Duration(days: 1)),
        heureDebut: '20:00',
        heureFin: '20:30',
      );
      expect(ServiceRepository.refusInscription(libre, 'u1'), isNull);
      expect(ServiceRepository.refusInscription(libre, 'u1', fait: true), isNotNull);
    });

    test('marquerFait : l\'auteur, le jour même ; enregistre la date et la personne', () async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Poubelles', estCommun: true, jour: 'Lundi');
      final CreneauCommun aujourdhui =
          depot.ajouterCreneau(serviceId: service.id, date: DateTime.now(), inscrit: salma);

      final Resultat<void> resultat = await depot.marquerFait(aujourdhui.id);
      expect(resultat.estSucces, isTrue);
      final FaitCreneau fait = depot.serviceParId(service.id)!.creneauxFaits[aujourdhui.id]!;
      expect(fait.parId, salma.id);
      expect(fait.parNom, 'Salma G.');
      expect(fait.faitLe, isNotNull);
      // Le créneau lui-même n'a pas changé
      expect(depot.creneauParId(aujourdhui.id)!.inscritId, salma.id);

      // Une seconde fois : refusé
      expect((await depot.marquerFait(aujourdhui.id)).estSucces, isFalse);
    });

    test('marquerFait : refusé avant la date et pour un autre que l\'auteur', () async {
      final Service service = depot.ajouterServiceDe(amira, titre: 'Poubelles', estCommun: true, jour: 'Lundi');
      final CreneauCommun demain = depot.ajouterCreneau(
        serviceId: service.id,
        date: DateTime.now().add(const Duration(days: 1)),
      );
      final CreneauCommun hier = depot.ajouterCreneau(
        serviceId: service.id,
        date: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect((await depot.marquerFait(demain.id)).estSucces, isFalse);
      expect(depot.serviceParId(service.id)!.creneauxFaits, isEmpty);

      // Une personne inscrite sur le créneau n'est PAS l'auteur : refusé
      await devenir(karim);
      expect((await depot.marquerFait(hier.id)).estSucces, isFalse);
      await redevenirAmira();

      // L'auteur peut marquer un créneau passé, même sans personne : parNom vide
      expect((await depot.marquerFait(hier.id)).estSucces, isTrue);
      final FaitCreneau fait = depot.serviceParId(service.id)!.creneauxFaits[hier.id]!;
      expect(fait.parNom, isEmpty);
      expect(fait.parId, isEmpty);
    });

    test('un créneau fait ne peut plus être désisté ni pris', () async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Poubelles', estCommun: true, jour: 'Lundi');
      final CreneauCommun creneau = depot.ajouterCreneau(
        serviceId: service.id,
        date: DateTime.now(),
        inscrit: amira,
      );
      final CreneauCommun libre = depot.ajouterCreneau(
        serviceId: service.id,
        date: DateTime.now().add(const Duration(days: 7)),
      );
      depot.mettreAJourService(service.copyWith(creneauxFaits: {
        creneau.id: const FaitCreneau(parId: 'x', parNom: 'x'),
        libre.id: const FaitCreneau(),
      }));

      final Resultat<void> desistement = await depot.desinscrire(creneau.id);
      expect(desistement.estSucces, isFalse);
      expect(depot.creneauParId(creneau.id)!.inscritId, amira.id);
      expect((await depot.inscrire(libre.id)).estSucces, isFalse);
      expect(depot.creneauParId(libre.id)!.estLibre, isTrue);
    });
  });

  group('Rotation : services en mémoire (mock)', () {
    /// Un service du jour, en rotation, créé par Amira avec les participants donnés.
    Future<Service> creerRotation(List<Utilisateur> participants) async {
      final String jourAujourdhui = ServiceRepository.jours[DateTime.now().weekday - 1];
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Sortie des poubelles',
        description: 'Sortie des poubelles du bloc',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: jourAujourdhui,
        heureDebut: '20:00',
        heureFin: '20:30',
        modeRotation: true,
        participantsIds: [for (final Utilisateur u in participants) u.id],
        participantsNoms: [for (final Utilisateur u in participants) ServiceRepository.nomCourt(u)],
      );
      return resultat.donnee!;
    }

    test('création : mode, participants, ancre au 1er créneau, créneaux libres', () async {
      final Service service = await creerRotation([karim, amira]);
      expect(service.modeRotation, isTrue);
      expect(service.participantsIds, [karim.id, amira.id]);
      expect(service.participantsNoms, ['Karim M.', 'Amira B.']);
      expect(depot.creneaux.length, 4);
      expect(depot.creneaux.every((c) => c.estLibre), isTrue);
      expect(service.rotationDepuis, depot.creneaux.first.date);
      // Les ids sont fixes : serviceId_AAAAMMJJ
      for (final CreneauCommun c in depot.creneaux) {
        expect(c.id, ServiceRepository.idCreneau(service.id, c.date));
      }
      final Map<String, TourRotation> tours =
          ServiceRepository.calculerTours(service, depot.creneaux);
      expect(
        [for (final CreneauCommun c in ServiceRepository.trierCreneaux(depot.creneaux)) tours[c.id]!.id],
        [karim.id, amira.id, karim.id, amira.id],
      );
    });

    test('rotation sans participant : refusée (minimum 1)', () async {
      final Resultat<Service> resultat = await depot.ajouterService(
        titre: 'Sortie des poubelles',
        description: 'Sortie des poubelles du bloc',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: 'Lundi',
        heureDebut: '20:00',
        heureFin: '20:30',
        modeRotation: true,
      );
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, contains('au moins un participant'));
      expect(depot.services, isEmpty);
      expect(depot.creneaux, isEmpty);
    });

    test('refusPublication : la rotation demande au moins 1 participant', () {
      String? refus(int n) => ServiceRepository.refusPublication(
            titre: 'Poubelles',
            description: 'Sortie des poubelles',
            categorie: 'Bricolage',
            estCommun: true,
            jour: 'Lundi',
            heureDebut: '20:00',
            heureFin: '20:30',
            modeRotation: true,
            nbParticipants: n,
          );
      expect(refus(0), isNotNull);
      expect(refus(1), isNull);
    });

    test('participants en double ou invalides : refusés', () {
      expect(ServiceRepository.refusParticipants(['a', 'a'], ['A', 'A']), isNotNull);
      expect(ServiceRepository.refusParticipants(['a', 'b'], ['A']), isNotNull);
      expect(ServiceRepository.refusParticipants(['a', ''], ['A', 'B']), isNotNull);
      expect(ServiceRepository.refusParticipants(['a', 'b'], ['A', 'B']), isNull);
    });

    test('modifierParticipants : l\'auteur seulement ; le jour est figé, le futur recalculé', () async {
      final Service service = await creerRotation([amira, karim]);
      final List<CreneauCommun> avant = ServiceRepository.trierCreneaux(depot.creneaux);

      // Un autre voisin ne peut pas
      await devenir(karim);
      expect(
        (await depot.modifierParticipants(service.id, [salma.id], ['Salma G.'])).estSucces,
        isFalse,
      );
      expect(depot.serviceParId(service.id)!.participantsIds, [amira.id, karim.id]);
      await redevenirAmira();

      final Resultat<void> ok = await depot.modifierParticipants(
        service.id,
        [amira.id, karim.id, salma.id],
        ['Amira B.', 'Karim M.', 'Salma G.'],
      );
      expect(ok.estSucces, isTrue);
      final Service nouveau = depot.serviceParId(service.id)!;
      expect(nouveau.participantsIds, [amira.id, karim.id, salma.id]);

      final Map<String, TourRotation> tours =
          ServiceRepository.calculerTours(nouveau, depot.creneaux);
      // Aujourd'hui (Amira) figé ; le cycle reprend après elle : Karim, Salma, Amira
      expect(
        [for (final CreneauCommun c in avant) tours[c.id]!.id],
        [amira.id, karim.id, salma.id, amira.id],
      );
      // Les créneaux eux-mêmes n'ont pas été touchés (rien n'est écrit dessus)
      expect(depot.creneaux.every((c) => c.estLibre), isTrue);
    });

    test('modifierParticipants : refusé pour un service en inscription libre', () async {
      final Service libre = depot.ajouterServiceDe(amira, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      final Resultat<void> resultat = await depot.modifierParticipants(libre.id, [amira.id], ['Amira B.']);
      expect(resultat.estSucces, isFalse);
    });

    test('un tour non confirmé est réservé à son titulaire, jusqu\'au désistement', () async {
      final Service service = await creerRotation([karim, amira]);
      final CreneauCommun premier = ServiceRepository.trierCreneaux(depot.creneaux).first; // tour de Karim

      // Amira ne peut pas prendre le tour de Karim
      final Resultat<void> refus = await depot.inscrire(premier.id);
      expect(refus.estSucces, isFalse);
      expect(refus.erreur, contains('Karim M.'));

      // Karim confirme son tour
      await devenir(karim);
      expect((await depot.inscrire(premier.id)).estSucces, isTrue);
      expect(depot.creneauParId(premier.id)!.inscritId, karim.id);

      // Il se désiste : le créneau est libre pour tous, avec le marqueur
      expect((await depot.desinscrire(premier.id)).estSucces, isTrue);
      final CreneauCommun libre = depot.creneauParId(premier.id)!;
      expect(libre.estLibre, isTrue);
      expect(libre.estDesiste, isTrue);
      expect(libre.inscrit, isNull);
      expect(libre.inscritNom, CreneauCommun.marqueDesiste);

      // Un autre voisin peut maintenant le prendre
      await redevenirAmira();
      expect((await depot.inscrire(premier.id)).estSucces, isTrue);
      expect(depot.creneauParId(premier.id)!.inscritId, amira.id);
      expect(depot.creneauParId(premier.id)!.inscrit, 'Amira B.');
      expect(depot.serviceParId(service.id)!.creneauxFaits, isEmpty);
    });

    test('service en inscription libre : le désistement ne laisse aucun marqueur', () async {
      final Service libre = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      final CreneauCommun creneau = depot.ajouterCreneau(
        serviceId: libre.id,
        date: DateTime.now().add(const Duration(days: 1)),
        inscrit: amira,
      );
      await depot.desinscrire(creneau.id);
      expect(depot.creneauParId(creneau.id)!.inscritNom, isNull);
      expect(depot.creneauParId(creneau.id)!.estDesiste, isFalse);
    });
  });

  group('Rappels dans l\'application', () {
    final DateTime aujourdhui = DateTime(2026, 11, 9, 8);
    final Service service = serviceRotation(depuis: lundi9);

    CreneauCommun creneauLe(
      DateTime jour, {
      String? inscritId,
      String? inscritNom,
      bool rappelVeille = false,
    }) {
      return CreneauCommun(
        id: ServiceRepository.idCreneau('s1', jour),
        serviceId: 's1',
        titre: 'Sortie des poubelles',
        date: jour,
        heureDebut: '20:00',
        heureFin: '20:30',
        inscritId: inscritId,
        inscritNom: inscritNom,
        rappelVeille: rappelVeille,
      );
    }

    List<RappelCreneau> rappels(
      List<CreneauCommun> creneaux, {
      Service? s,
      Map<String, TourRotation> tours = const {},
      String moi = 'u1',
    }) {
      return ServiceRepository.rappelsPour(
        services: [s ?? service],
        tours: tours,
        creneaux: creneaux,
        moiId: moi,
        maintenant: aujourdhui,
      );
    }

    test('aujourd\'hui : toujours, même sans « me rappeler la veille »', () {
      final List<RappelCreneau> liste =
          rappels([creneauLe(lundi9, inscritId: 'u1', inscritNom: 'Moi')]);
      expect(liste.length, 1);
      expect(liste.first.demain, isFalse);
      expect(
        liste.first.texte,
        'Rappel : aujourd\'hui, tu es de service pour Sortie des poubelles (20:00 - 20:30)',
      );
    });

    test('demain : seulement si « Me rappeler la veille » est coché', () {
      final DateTime demain = DateTime(2026, 11, 10);
      expect(
        rappels([creneauLe(demain, inscritId: 'u1', inscritNom: 'Moi')]),
        isEmpty,
      );
      final List<RappelCreneau> liste = rappels(
        [creneauLe(demain, inscritId: 'u1', inscritNom: 'Moi', rappelVeille: true)],
      );
      expect(liste.length, 1);
      expect(liste.first.demain, isTrue);
      expect(
        liste.first.texte,
        'Rappel : demain, tu es de service pour Sortie des poubelles (20:00 - 20:30)',
      );
    });

    test('tour calculé non confirmé : rappelé aujourd\'hui et la veille', () {
      final CreneauCommun demain = creneauLe(DateTime(2026, 11, 10));
      final CreneauCommun jour = creneauLe(lundi9);
      final Map<String, TourRotation> tours = {
        demain.id: const TourRotation(id: 'u1', nom: 'Moi'),
        jour.id: const TourRotation(id: 'u1', nom: 'Moi'),
      };
      final List<RappelCreneau> liste = rappels([jour, demain], tours: tours);
      expect(liste.length, 2);
      expect(liste.every((r) => r.tourNonConfirme), isTrue);
      expect(liste.map((r) => r.demain).toList(), [false, true]);
    });

    test('pas de rappel : créneau lointain, inscrit ailleurs, tour d\'un autre, désisté', () {
      final CreneauCommun lointain = creneauLe(DateTime(2026, 11, 12), inscritId: 'u1', inscritNom: 'Moi');
      expect(rappels([lointain]), isEmpty);

      final CreneauCommun autre = creneauLe(lundi9, inscritId: 'u2', inscritNom: 'Autre');
      expect(rappels([autre]), isEmpty);

      final CreneauCommun tourAutre = creneauLe(DateTime(2026, 11, 10));
      expect(
        rappels([tourAutre], tours: {tourAutre.id: const TourRotation(id: 'u2', nom: 'Autre')}),
        isEmpty,
      );

      final CreneauCommun desiste = creneauLe(
        DateTime(2026, 11, 10),
        inscritNom: CreneauCommun.marqueDesiste,
      );
      expect(
        rappels([desiste], tours: {desiste.id: const TourRotation(id: 'u1', nom: 'Moi')}),
        isEmpty,
      );
    });

    test('pas de rappel : créneau fait, ou personne de connecté', () {
      final CreneauCommun fait = creneauLe(lundi9, inscritId: 'u1', inscritNom: 'Moi');
      final Service avecFait = serviceRotation(
        depuis: lundi9,
        faits: {fait.id: const FaitCreneau(parId: 'u1')},
      );
      expect(rappels([fait], s: avecFait), isEmpty);
      expect(rappels([fait], moi: ''), isEmpty);
    });

    testWidgets('le bandeau s\'affiche en haut de l\'écran Services, avec « Voir »', (WidgetTester tester) async {
      final Service commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      final CreneauCommun creneau = depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now(),
        titre: 'Arrosage du jardin',
        inscrit: amira,
      );
      await afficher(tester, const ServicesListScreen());
      expect(
        find.text('Rappel : aujourd\'hui, tu es de service pour Arrosage du jardin (18:00 - 18:30)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Voir'));
      await tester.pumpAndSettle();
      expect(find.byType(InscriptionCreneauScreen), findsOneWidget);
      expect(creneau.id, isNotEmpty);
    });

    testWidgets('la veille : bandeau seulement si le rappel est coché (écran du planning)', (WidgetTester tester) async {
      final Service commun = depot.ajouterServiceDe(karim, titre: 'Arrosage', estCommun: true, jour: 'Mardi');
      depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().add(const Duration(days: 1)),
        titre: 'Arrosage du jardin',
        inscrit: amira,
      );
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.textContaining('Rappel :'), findsNothing);

      depot.ajouterCreneau(
        serviceId: commun.id,
        date: DateTime.now().add(const Duration(days: 1)),
        titre: 'Arrosage du soir',
        inscrit: amira,
        rappelVeille: true,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Rappel : demain, tu es de service pour Arrosage du soir (18:00 - 18:30)'),
        findsOneWidget,
      );
    });

    testWidgets('aucun rappel : pas de bandeau', (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());
      expect(find.textContaining('Rappel :'), findsNothing);
    });

    testWidgets('un tour calculé à mon nom donne un rappel, jamais le marqueur', (WidgetTester tester) async {
      final DateTime aujourdhuiJour = DateTime.now();
      final Service rot = depot.ajouterServiceDe(
        karim,
        titre: 'Poubelles',
        estCommun: true,
        jour: 'Lundi',
        modeRotation: true,
        participants: [amira, karim],
        rotationDepuis: aujourdhuiJour,
      );
      depot.ajouterCreneau(
        serviceId: rot.id,
        date: aujourdhuiJour,
        titre: 'Sortie des poubelles',
        id: ServiceRepository.idCreneau(rot.id, aujourdhuiJour),
      );
      await afficher(tester, const ServicesListScreen());
      expect(find.textContaining('Rappel : aujourd\'hui'), findsOneWidget);
      expect(find.textContaining(CreneauCommun.marqueDesiste), findsNothing);
    });
  });

  group('Prolonger le planning', () {
    test('creneauxAProlonger : 4 semaines après le dernier créneau, ids fixes, sans doublon', () {
      final Service service = serviceRotation(depuis: lundi9);
      final List<CreneauCommun> existants = semaines(lundi9, 4); // 9/11 ... 30/11
      final List<CreneauCommun> nouveaux = ServiceRepository.creneauxAProlonger(
        service: service,
        existants: existants,
        aujourdhui: lundi9,
      );
      expect(nouveaux.length, 4);
      expect(nouveaux.first.date, DateTime(2026, 12, 7));
      expect(nouveaux.last.date, DateTime(2026, 12, 28));
      for (final CreneauCommun c in nouveaux) {
        expect(c.estLibre, isTrue);
        expect(c.date.weekday, DateTime.monday);
        expect(c.id, ServiceRepository.idCreneau('s1', c.date));
      }
      final Set<String> ids = {...existants.map((c) => c.id), ...nouveaux.map((c) => c.id)};
      expect(ids.length, 8);

      // Appuyer deux fois avec les mêmes données donne les MÊMES identifiants :
      // Firestore les écrit au même endroit, pas de doublon
      final List<CreneauCommun> encore = ServiceRepository.creneauxAProlonger(
        service: service,
        existants: existants,
        aujourdhui: lundi9,
      );
      expect(encore.map((c) => c.id).toList(), nouveaux.map((c) => c.id).toList());

      // Si une date existe déjà (id aléatoire d'un ancien créneau), elle est sautée
      final CreneauCommun ancien = CreneauCommun(
        id: 'idAleatoire',
        serviceId: 's1',
        titre: 'P',
        date: DateTime(2026, 12, 7),
        heureDebut: '20:00',
        heureFin: '20:30',
      );
      final List<CreneauCommun> sansDoublon = ServiceRepository.creneauxAProlonger(
        service: service,
        existants: [ancien],
        aujourdhui: lundi9,
      );
      expect(sansDoublon.any((c) => c.date == DateTime(2026, 12, 7)), isFalse);
    });

    test('un service sans créneau : on part d\'aujourd\'hui', () {
      final Service service = serviceRotation(depuis: lundi9);
      final List<CreneauCommun> nouveaux = ServiceRepository.creneauxAProlonger(
        service: service,
        existants: const [],
        aujourdhui: lundi9,
      );
      expect(nouveaux.first.date, lundi9);
      expect(nouveaux.length, 4);
    });

    test('prolongerPlanning : l\'auteur seulement, en respectant la rotation', () async {
      final String jourAujourdhui = ServiceRepository.jours[DateTime.now().weekday - 1];
      final Service service = (await depot.ajouterService(
        titre: 'Sortie des poubelles',
        description: 'Sortie des poubelles du bloc',
        categorie: 'Bricolage',
        estOffre: true,
        estCommun: true,
        jour: jourAujourdhui,
        heureDebut: '20:00',
        heureFin: '20:30',
        modeRotation: true,
        participantsIds: [amira.id, karim.id, salma.id],
        participantsNoms: ['Amira B.', 'Karim M.', 'Salma G.'],
      )).donnee!;
      expect(depot.creneaux.length, 4);

      await devenir(karim);
      expect((await depot.prolongerPlanning(service.id)).estSucces, isFalse);
      expect(depot.creneaux.length, 4);
      await redevenirAmira();

      final Resultat<int> ok = await depot.prolongerPlanning(service.id);
      expect(ok.estSucces, isTrue);
      expect(ok.donnee, 4);
      expect(depot.creneaux.length, 8);

      // Pas de doublon : ids uniques, dates uniques, créneaux libres
      expect(depot.creneaux.map((c) => c.id).toSet().length, 8);
      expect(depot.creneaux.map((c) => c.date).toSet().length, 8);
      expect(depot.creneaux.every((c) => c.estLibre), isTrue);

      // La rotation continue : 8 créneaux, A K S A K S A K
      final List<CreneauCommun> tries = ServiceRepository.trierCreneaux(depot.creneaux);
      final Map<String, TourRotation> tours =
          ServiceRepository.calculerTours(depot.serviceParId(service.id)!, tries);
      expect(
        [for (final CreneauCommun c in tries) tours[c.id]!.id],
        [amira.id, karim.id, salma.id, amira.id, karim.id, salma.id, amira.id, karim.id],
      );

      // Une 2e prolongation continue plus loin, sans refaire les mêmes dates
      expect((await depot.prolongerPlanning(service.id)).donnee, 4);
      expect(depot.creneaux.map((c) => c.id).toSet().length, 12);
    });

    test('prolongerPlanning : un service sans type commun est refusé', () async {
      final Service simple = depot.ajouterServiceDe(amira, titre: 'Perceuse');
      expect((await depot.prolongerPlanning(simple.id)).estSucces, isFalse);
      expect((await depot.prolongerPlanning('inconnu')).estSucces, isFalse);
    });

    testWidgets('le bouton « Prolonger le planning » est réservé à l\'auteur', (WidgetTester tester) async {
      final Service mien = depot.ajouterServiceDe(
        amira,
        titre: 'Escaliers',
        estCommun: true,
        jour: 'Samedi',
        heureDebut: '09:00',
        heureFin: '10:00',
      );
      depot.ajouterCreneau(serviceId: mien.id, date: DateTime.now());
      await afficher(tester, ServiceDetailScreen(serviceId: mien.id));
      expect(find.text('Prolonger le planning (+4 semaines)'), findsOneWidget);

      await tester.tap(find.text('Prolonger le planning (+4 semaines)'));
      await tester.pumpAndSettle();
      expect(find.text('4 créneaux ajoutés'), findsOneWidget);
      expect(depot.creneaux.length, 5);
    });

    testWidgets('un autre voisin ne voit pas « Prolonger le planning »', (WidgetTester tester) async {
      final Service autre = depot.ajouterServiceDe(karim, titre: 'Escaliers', estCommun: true, jour: 'Samedi');
      await afficher(tester, ServiceDetailScreen(serviceId: autre.id));
      expect(find.text('Prolonger le planning (+4 semaines)'), findsNothing);
      expect(find.text('Voir le planning'), findsOneWidget);
    });
  });

  group('Corrections : avis, lignes vides, service personnel', () {
    test('resumeDepuisNotes : moyenne et nombre calculés dans l\'application', () {
      final ResumeAuteur vide = ServiceRepository.resumeDepuisNotes(const []);
      expect(vide.nombreAvis, 0);
      expect(vide.noteMoyenne, 0);
      final ResumeAuteur deux = ServiceRepository.resumeDepuisNotes(const [5, 4]);
      expect(deux.nombreAvis, 2);
      expect(deux.noteMoyenne, 4.5);
      expect(deux.servicesRendus, 2);
    });

    testWidgets('aucune évaluation : « Pas encore d\'avis », jamais « Note indisponible »', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Perceuse');
      await afficher(tester, ServiceDetailScreen(serviceId: service.id));
      expect(find.text('Pas encore d\'avis'), findsOneWidget);
      expect(find.text('Note indisponible'), findsNothing);
    });

    test('si le calcul échoue vraiment, le dépôt renvoie une erreur lisible', () async {
      depot.erreur = 'Serveur injoignable, vérifie ta connexion Internet';
      final Resultat<ResumeAuteur> resultat = await depot.getResumeAuteur(karim.id);
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, 'Serveur injoignable, vérifie ta connexion Internet');
    });

    Service avecInfos({String? dispo, String? duree, String? recup}) {
      return Service(
        id: 'sx',
        titre: 'Perceuse à prêter',
        description: 'Perceuse avec forets',
        categorie: 'Prêt d\'outils',
        auteurId: karim.id,
        auteurNom: 'Karim M.',
        estOffre: true,
        disponibilite: dispo,
        duree: duree,
        recuperation: recup,
      );
    }

    testWidgets('Disponibilité, Durée, Récupération vides : lignes masquées', (WidgetTester tester) async {
      final Service base = depot.ajouterServiceDe(karim, titre: 'Perceuse à prêter');
      final Service vide = Service(
        id: base.id,
        titre: base.titre,
        description: base.description,
        categorie: base.categorie,
        auteurId: base.auteurId,
        auteurNom: base.auteurNom,
        estOffre: true,
        disponibilite: '',
        duree: '   ',
        recuperation: '',
      );
      depot.mettreAJourService(vide);
      await afficher(tester, ServiceDetailScreen(serviceId: base.id));
      expect(find.text('Disponibilité'), findsNothing);
      expect(find.text('Durée'), findsNothing);
      expect(find.text('Récupération'), findsNothing);
    });

    testWidgets('lignes renseignées : affichées', (WidgetTester tester) async {
      final Service base = depot.ajouterServiceDe(karim, titre: 'Perceuse à prêter');
      final Service rempli = avecInfos(
        dispo: ' Ce week-end ',
        duree: '1 journée',
        recup: 'Bloc A · Appt 3',
      );
      depot.mettreAJourService(Service(
        id: base.id,
        titre: rempli.titre,
        description: rempli.description,
        categorie: rempli.categorie,
        auteurId: rempli.auteurId,
        auteurNom: rempli.auteurNom,
        estOffre: true,
        disponibilite: rempli.disponibilite,
        duree: rempli.duree,
        recuperation: rempli.recuperation,
      ));
      await afficher(tester, ServiceDetailScreen(serviceId: base.id));
      expect(find.text('Disponibilité'), findsOneWidget);
      expect(find.text('Ce week-end'), findsOneWidget);
      expect(find.text('Durée'), findsOneWidget);
      expect(find.text('Récupération'), findsOneWidget);
    });

    test('on ne peut jamais demander son propre service (règle métier)', () {
      final Service mien = avecInfos();
      expect(ServiceRepository.refusDemande(mien, karim.id, false), isNotNull);
      expect(ServiceRepository.refusDemande(mien, salma.id, false), isNull);
      // Un service sans auteur connu ne se demande pas
      const Service sansAuteur = Service(
        id: 'sy',
        titre: 'Sans auteur',
        description: 'Description',
        categorie: 'Courses',
        auteurNom: 'Quelqu\'un',
        estOffre: true,
      );
      expect(ServiceRepository.refusDemande(sansAuteur, salma.id, false), isNotNull);
    });

    test('même compte sur deux appareils : la demande est refusée sur les deux', () async {
      final Service mien = depot.ajouterServiceDe(amira, titre: 'Mon service');
      expect((await depot.envoyerDemande(mien.id)).estSucces, isFalse);

      // Le « deuxième appareil » : un autre dépôt, même compte (même uid)
      final MockServiceRepository appareil2 = MockServiceRepository();
      final Service memeService = appareil2.ajouterServiceDe(amira, titre: 'Mon service');
      ServiceRepository.instance = appareil2;
      final Resultat<void> resultat = await appareil2.envoyerDemande(memeService.id);
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, 'Tu ne peux pas demander ton propre service');
      expect(appareil2.demandes, isEmpty);
      expect(depot.demandes, isEmpty);
    });
  });

  group('Écran : choix des participants', () {
    Future<void> ouvrir(WidgetTester tester, {int minimum = 1}) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (contexte) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(contexte).push<List<ParticipantRotation>>(
                      MaterialPageRoute<List<ParticipantRotation>>(
                        builder: (_) => ParticipantsRotationScreen(minimum: minimum),
                      ),
                    );
                  },
                  child: const Text('ouvrir'),
                ),
              ),
            );
          },
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(ParticipantsRotationScreen), findsOneWidget);
    }

    testWidgets('« Moi » est en tête, une seule fois, avec les vrais voisins du quartier', (WidgetTester tester) async {
      await ouvrir(tester);
      expect(find.text('Moi · Amira B.'), findsOneWidget);
      // Rien d'inventé : exactement les membres actifs lus via le module 1
      final List<Utilisateur> voisins =
          (await UtilisateurRepository().getVoisins()).donnee ?? const [];
      expect(voisins, isNotEmpty);
      for (final Utilisateur u in voisins) {
        if (u.id != amira.id) {
          expect(find.text(ServiceRepository.nomCourt(u)), findsWidgets);
        }
      }
      // Un membre en attente (pas encore validé) n'est pas proposé
      expect(find.text('Sarra B.'), findsNothing);
    });

    testWidgets('minimum 1 : « Valider » grisé tant que personne n\'est choisi, ordre = ordre des taps', (WidgetTester tester) async {
      await ouvrir(tester);
      PrimaryButton bouton = tester.widget(find.widgetWithText(PrimaryButton, 'Valider (0)'));
      expect(bouton.onPressed, isNull);

      await tester.tap(find.text('Karim M.').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moi · Amira B.'));
      await tester.pumpAndSettle();

      bouton = tester.widget(find.widgetWithText(PrimaryButton, 'Valider (2)'));
      expect(bouton.onPressed, isNotNull);
      // Ordre de passage : 1 = Karim, 2 = Moi
      final double yKarim = tester.getTopLeft(find.text('Karim M.').first).dy;
      final double yMoi = tester.getTopLeft(find.text('Moi · Amira B.')).dy;
      expect(yKarim < yMoi, isTrue);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Retirer un participant
      await tester.tap(find.byTooltip('Retirer').first);
      await tester.pumpAndSettle();
      expect(find.text('Valider (1)'), findsOneWidget);
    });

    testWidgets('formulaire : choisir « Rotation automatique » propose les participants', (WidgetTester tester) async {
      await afficher(tester, const ServiceFormScreen());
      await tester.ensureVisible(find.text('Service commun hebdomadaire'));
      await tester.tap(find.text('Service commun hebdomadaire'));
      await tester.pumpAndSettle();
      expect(find.text('Inscription libre'), findsOneWidget);
      expect(find.text('Rotation automatique'), findsOneWidget);
      expect(find.text('Choisir les participants'), findsNothing);

      await tester.tap(find.text('Rotation automatique'));
      await tester.pumpAndSettle();
      expect(find.text('Choisir les participants'), findsOneWidget);
    });
  });

  group('Écrans : planning avec rotation', () {
    /// Service du jour en rotation (Karim auteur) : aujourd'hui = tour d'Amira,
    /// dans 7 jours = tour de Salma.
    Service installer({List<Utilisateur>? participants}) {
      final DateTime aujourdhui = DateTime.now();
      final Service rot = depot.ajouterServiceDe(
        karim,
        titre: 'Poubelles',
        estCommun: true,
        jour: ServiceRepository.jours[aujourdhui.weekday - 1],
        modeRotation: true,
        participants: participants ?? [amira, salma],
        rotationDepuis: aujourdhui,
      );
      for (int i = 0; i < 3; i++) {
        final DateTime date = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 7 * i);
        depot.ajouterCreneau(
          serviceId: rot.id,
          date: date,
          titre: 'Sortie des poubelles',
          id: ServiceRepository.idCreneau(rot.id, date),
        );
      }
      return rot;
    }

    testWidgets('mon tour : « C\'est ton tour » + Confirmer, qui m\'inscrit', (WidgetTester tester) async {
      installer();
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.text('C\'est ton tour'), findsOneWidget);
      expect(find.text('Confirmer'), findsOneWidget);
      expect(find.text('S\'inscrire'), findsNothing);

      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(find.byType(InscriptionCreneauScreen), findsOneWidget);
      expect(find.text('Confirmer mon tour'), findsOneWidget);
      await tester.tap(find.text('Confirmer mon tour'));
      await tester.pumpAndSettle();
      final CreneauCommun pris = ServiceRepository.trierCreneaux(depot.creneaux).first;
      expect(pris.inscritId, amira.id);
      expect(find.text('Toi'), findsOneWidget);
    });

    testWidgets('« Prochain tour de chacun » : tous les participants et leur date', (WidgetTester tester) async {
      installer();
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.text('Prochain tour de chacun'), findsOneWidget);
      expect(find.text('1. Amira B. (toi)'), findsOneWidget);
      expect(find.text('2. Salma G.'), findsOneWidget);
      final DateTime aujourdhui = DateTime.now();
      expect(find.text(dateCourte(aujourdhui)), findsWidgets);
      expect(
        find.text(dateCourte(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 7))),
        findsOneWidget,
      );
    });

    testWidgets('le tour d\'un autre est réservé : « Tour de … », pas de bouton', (WidgetTester tester) async {
      installer();
      await devenir(salma);
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.text('Tour de Amira B.'), findsOneWidget);
      expect(find.text('S\'inscrire'), findsNothing);
      expect(find.text('Confirmer'), findsNothing);
    });

    testWidgets('après le désistement : « Créneau libre » pour tous, le marqueur ne s\'affiche jamais', (WidgetTester tester) async {
      installer();
      final CreneauCommun premier = ServiceRepository.trierCreneaux(depot.creneaux).first;
      expect((await depot.inscrire(premier.id)).estSucces, isTrue);
      expect((await depot.desinscrire(premier.id)).estSucces, isTrue);
      expect(depot.creneauParId(premier.id)!.inscritNom, CreneauCommun.marqueDesiste);

      await devenir(salma);
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.text('Créneau libre'), findsOneWidget);
      expect(find.text('S\'inscrire'), findsOneWidget);
      expect(find.textContaining(CreneauCommun.marqueDesiste), findsNothing);
      expect(find.textContaining('desiste'), findsNothing);
      expect(find.textContaining('Tour de'), findsNothing);

      // L'écran d'inscription : « Libre », jamais le marqueur
      await tester.tap(find.text('S\'inscrire'));
      await tester.pumpAndSettle();
      expect(find.byType(InscriptionCreneauScreen), findsOneWidget);
      expect(find.text('Libre'), findsWidgets);
      expect(find.textContaining(CreneauCommun.marqueDesiste), findsNothing);
      expect(find.textContaining('desiste'), findsNothing);
    });

    testWidgets('créneau passé : « À faire » ; l\'auteur le marque « Fait ✓ »', (WidgetTester tester) async {
      final DateTime hier = DateTime.now().subtract(const Duration(days: 1));
      final Service mien = depot.ajouterServiceDe(amira, titre: 'Escaliers', estCommun: true, jour: 'Samedi');
      depot.ajouterCreneau(
        serviceId: mien.id,
        date: hier,
        titre: 'Nettoyage des escaliers',
        inscrit: karim,
      );
      await afficher(tester, ServicesCommunsScreen(jourInitial: hier));
      expect(find.text('À faire'), findsOneWidget);
      expect(find.text('Fait ✓'), findsNothing);
      expect(find.text('Marquer fait'), findsOneWidget);
      expect(find.text('S\'inscrire'), findsNothing);

      await tester.tap(find.text('Marquer fait'));
      await tester.pumpAndSettle();
      expect(find.text('Fait ✓'), findsOneWidget);
      expect(find.text('par Karim M.'), findsOneWidget);
      expect(find.text('À faire'), findsNothing);
      expect(find.text('Marquer fait'), findsNothing);
      expect(depot.serviceParId(mien.id)!.creneauxFaits.length, 1);
    });

    testWidgets('un voisin (pas l\'auteur) n\'a pas le bouton « Marquer fait »', (WidgetTester tester) async {
      final DateTime hier = DateTime.now().subtract(const Duration(days: 1));
      final Service autre = depot.ajouterServiceDe(karim, titre: 'Escaliers', estCommun: true, jour: 'Samedi');
      depot.ajouterCreneau(serviceId: autre.id, date: hier, inscrit: amira);
      await afficher(tester, ServicesCommunsScreen(jourInitial: hier));
      expect(find.text('À faire'), findsOneWidget);
      expect(find.text('Marquer fait'), findsNothing);
    });

    testWidgets('créneau fait : badge « Fait ✓ », plus de bouton, plus de désistement', (WidgetTester tester) async {
      final Service service = depot.ajouterServiceDe(karim, titre: 'Escaliers', estCommun: true, jour: 'Samedi');
      final CreneauCommun creneau = depot.ajouterCreneau(
        serviceId: service.id,
        date: DateTime.now(),
        inscrit: amira,
      );
      depot.mettreAJourService(service.copyWith(creneauxFaits: {
        creneau.id: const FaitCreneau(parId: 'x', parNom: 'Amira B.'),
      }));
      await afficher(tester, const ServicesCommunsScreen());
      expect(find.text('Fait ✓'), findsOneWidget);
      expect(find.text('Gérer'), findsNothing);
      expect(find.text('S\'inscrire'), findsNothing);

      await afficher(tester, InscriptionCreneauScreen(creneauId: creneau.id));
      expect(find.text('Fait ✓'), findsOneWidget);
      final SecondaryButton desister = tester.widget(
        find.widgetWithText(SecondaryButton, 'Se désister d\'un créneau'),
      );
      expect(desister.onPressed, isNull);
    });
  });
}
