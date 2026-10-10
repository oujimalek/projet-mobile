import 'package:flutter/material.dart';
// Evaluation existe aussi dans flutter_test : on la masque pour garder la nôtre
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/creneau_commun.dart';
import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/evaluation.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/models/statut_demande.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/main.dart';
import 'package:houmani/router/app_router.dart';
import 'package:houmani/screens/module2/evaluation_screen.dart';
import 'package:houmani/screens/module2/inscription_creneau_screen.dart';
import 'package:houmani/screens/module2/mes_demandes_screen.dart';
import 'package:houmani/screens/module2/service_detail_screen.dart';
import 'package:houmani/screens/module2/service_form_screen.dart';
import 'package:houmani/screens/module2/services_communs_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/theme/app_theme.dart';

/// Affiche un écran dans une MaterialApp avec le thème Houmani.
Future<void> afficher(WidgetTester tester, Widget ecran) async {
  // Écran haut : toute la liste est visible (ListView.builder construit à la demande)
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  final ServiceRepository repository = ServiceRepository();

  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Les listes du repository sont static : on les remet à zéro avant chaque test
  setUp(() {
    repository.reinitialiser();
  });

  group('Repository : services', () {
    test('garde les 8 services de départ', () {
      expect(repository.getServices().length, 8);
      expect(repository.getServicesCommuns().length, 2);
      expect(repository.getServicesParCategorie('Courses').length, 3);
    });

    test('ajouterService : auteur = utilisateur connecté, en haut de la liste', () {
      final Service service = repository.ajouterService(
        titre: 'Prêt de tondeuse',
        description: 'Tondeuse électrique, à rendre propre.',
        categorie: 'Prêt d\'outils',
        estOffre: true,
        disponibilite: 'Dimanche',
      );

      expect(service.auteur, repository.getMonNom());
      expect(service.disponibilite, 'Dimanche');
      expect(repository.getServices().length, 9);
      expect(repository.getServices().first.id, service.id);
      expect(repository.getServiceParId(service.id)?.titre, 'Prêt de tondeuse');
    });

    test('getServiceParId renvoie null si le service n\'existe pas', () {
      expect(repository.getServiceParId('inconnu'), isNull);
    });

    test('genererId ne renvoie jamais deux fois le même id', () {
      expect(repository.genererId('s'), isNot(repository.genererId('s')));
    });
  });

  group('Repository : demandes', () {
    test('données de départ : 3 envoyées et 2 reçues', () {
      expect(repository.getDemandesEnvoyees().length, 3);
      expect(repository.getDemandesRecues().length, 2);
    });

    test('envoyerDemande : crée une demande en attente', () {
      expect(repository.aDejaDemande('s4'), isFalse);
      expect(repository.envoyerDemande('s4'), isTrue);
      expect(repository.aDejaDemande('s4'), isTrue);

      final DemandeService nouvelle = repository.getDemandesEnvoyees().first;
      expect(nouvelle.serviceId, 's4');
      expect(nouvelle.auteurService, 'Sarra A.');
      expect(nouvelle.statut, StatutDemande.enAttente);
    });

    test('envoyerDemande : refus sur son propre service', () {
      expect(repository.envoyerDemande('s7'), isFalse); // s7 est à Amira B.
      expect(repository.getDemandesEnvoyees().length, 3);
    });

    test('envoyerDemande : refus en double et si le service n\'existe pas', () {
      expect(repository.envoyerDemande('s1'), isFalse); // déjà demandé (d1)
      expect(repository.envoyerDemande('inconnu'), isFalse);
      expect(repository.getDemandesEnvoyees().length, 3);
    });

    test('changerStatutDemande : seul l\'auteur accepte ou refuse', () {
      // d1 : demande que j'ai envoyée, je ne suis pas l'auteur du service
      expect(repository.changerStatutDemande('d1', StatutDemande.acceptee), isFalse);
      expect(repository.getDemandeParId('d1')!.statut, StatutDemande.enAttente);

      // d4 : demande reçue pour mon service
      expect(repository.changerStatutDemande('d4', StatutDemande.acceptee), isTrue);
      expect(repository.getDemandeParId('d4')!.statut, StatutDemande.acceptee);

      // On ne peut plus la refuser une fois traitée
      expect(repository.changerStatutDemande('d4', StatutDemande.refusee), isFalse);
    });

    test('changerStatutDemande : réalisée seulement depuis acceptée', () {
      expect(repository.changerStatutDemande('d1', StatutDemande.realisee), isFalse);
      expect(repository.changerStatutDemande('d2', StatutDemande.realisee), isTrue);
      expect(repository.getDemandeParId('d2')!.statut, StatutDemande.realisee);
    });
  });

  group('Repository : évaluations', () {
    Evaluation uneEvaluation(String demandeId, String serviceId, int note) {
      return Evaluation(
        id: repository.genererId('ev'),
        demandeId: demandeId,
        serviceId: serviceId,
        auteurEvalue: repository.getMonNom(),
        note: note,
        tags: const ['Sympa'],
        date: DateTime.now(),
      );
    }

    test('evaluer : une seule fois, et seulement une demande réalisée', () {
      // d3 est réalisée et pas encore évaluée
      expect(repository.evaluer(uneEvaluation('d3', 's2', 3)), isTrue);
      expect(repository.getDemandeParId('d3')!.evaluee, isTrue);

      // Deuxième évaluation de la même demande : refusée
      expect(repository.evaluer(uneEvaluation('d3', 's2', 5)), isFalse);

      // d2 est seulement acceptée : on ne peut pas l'évaluer
      expect(repository.evaluer(uneEvaluation('d2', 's3', 5)), isFalse);
    });

    test('evaluer : refuse une note hors de 1 à 5', () {
      expect(repository.evaluer(uneEvaluation('d3', 's2', 0)), isFalse);
      expect(repository.evaluer(uneEvaluation('d3', 's2', 6)), isFalse);
      expect(repository.getDemandeParId('d3')!.evaluee, isFalse);
    });

    test('la note moyenne et les services rendus se mettent à jour', () {
      // Leila B. a une note de 5 au départ
      expect(repository.getNoteMoyenne('Leila B.'), 5);
      repository.evaluer(uneEvaluation('d3', 's2', 3));
      expect(repository.getNoteMoyenne('Leila B.'), 4);
      expect(repository.getNombreEvaluations('Leila B.'), 2);

      // Karim M. : 2 services rendus, notes 5 et 4
      expect(repository.getNombreServicesRendus('Karim M.'), 2);
      expect(repository.getNoteMoyenne('Karim M.'), 4.5);

      // Personne n'a évalué ce voisin
      expect(repository.getNoteMoyenne('Inconnu'), 0);
    });

    test('getTagsEvaluation donne les 4 tags', () {
      expect(repository.getTagsEvaluation().length, 4);
    });
  });

  group('Repository : créneaux', () {
    /// Mon créneau de départ (Arrosage du jardin).
    CreneauCommun monCreneau() {
      for (final creneau in repository.getCreneauxParService('c2')) {
        if (creneau.inscrit == repository.getMonNom()) {
          return creneau;
        }
      }
      throw StateError('Aucun créneau à moi dans les données de départ');
    }

    /// Un créneau libre quelconque.
    CreneauCommun creneauLibre() {
      for (final creneau in repository.getCreneauxParService('c1')) {
        if (creneau.estLibre) {
          return creneau;
        }
      }
      throw StateError('Aucun créneau libre dans les données de départ');
    }

    test('la semaine contient des créneaux libres et un créneau à moi', () {
      final DateTime maintenant = DateTime.now();
      final DateTime lundi = DateTime(
        maintenant.year,
        maintenant.month,
        maintenant.day - (maintenant.weekday - 1),
      );
      final List<CreneauCommun> semaine = repository.getCreneauxDeLaSemaine(lundi);

      expect(semaine.length, 7);
      expect(semaine.where((c) => c.estLibre).isNotEmpty, isTrue);
      expect(semaine.where((c) => c.inscrit == repository.getMonNom()).length, 1);
      expect(repository.getCreneauxDuJour(lundi).length, 1);
    });

    test('inscrire : refuse un créneau déjà pris', () {
      final CreneauCommun libre = creneauLibre();

      expect(repository.inscrire(libre.id, rappelVeille: true), isTrue);
      final CreneauCommun apres = repository.getCreneauParId(libre.id)!;
      expect(apres.inscrit, repository.getMonNom());
      expect(apres.rappelVeille, isTrue);

      // Déjà pris (par moi maintenant) : refusé
      expect(repository.inscrire(libre.id), isFalse);

      // Pris par Karim M. au départ : refusé aussi
      expect(repository.inscrire('k1'), isFalse);
      expect(repository.inscrire('inconnu'), isFalse);
    });

    test('desinscrire : seulement mon créneau', () {
      final CreneauCommun mien = monCreneau();

      expect(repository.desinscrire('k1'), isFalse); // créneau de Karim M.
      expect(repository.desinscrire(mien.id), isTrue);
      expect(repository.getCreneauParId(mien.id)!.estLibre, isTrue);
      expect(repository.desinscrire(mien.id), isFalse); // déjà libre
    });
  });

  group('Écrans', () {
    testWidgets('la liste s\'affiche et le bouton + ouvre le formulaire',
        (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());

      expect(find.text('Services entre voisins'), findsOneWidget);
      expect(find.text('Perceuse à prêter'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceFormScreen), findsOneWidget);
      expect(find.text('Nouvelle publication'), findsOneWidget);
    });

    testWidgets('toucher une carte ouvre le détail', (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());

      await tester.tap(find.text('Courses au Carrefour'));
      await tester.pumpAndSettle();

      expect(find.byType(ServiceDetailScreen), findsOneWidget);
      expect(find.text('Demander ce service'), findsOneWidget);
    });

    testWidgets('un service déjà demandé affiche "Demande envoyée"',
        (WidgetTester tester) async {
      // s1 : j'ai déjà envoyé la demande d1 dans les données de départ
      await afficher(tester, const ServiceDetailScreen(serviceId: 's1'));

      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(find.text('Demander ce service'), findsNothing);
    });

    testWidgets('le formulaire refuse un titre trop court',
        (WidgetTester tester) async {
      await afficher(tester, const ServiceFormScreen());

      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();

      expect(find.text('Le titre doit avoir au moins 3 caractères'), findsOneWidget);
      expect(
        find.text('La description doit avoir au moins 10 caractères'),
        findsOneWidget,
      );
      expect(find.text('Choisis une catégorie'), findsOneWidget);
      expect(repository.getServices().length, 8); // rien n'a été publié
    });

    testWidgets('publier un service l\'affiche dans la liste',
        (WidgetTester tester) async {
      await afficher(tester, const ServicesListScreen());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bricolage'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Montage de meubles');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Je monte vos meubles en kit le week-end.',
      );
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();

      // Retour à la liste : le nouveau service est dans l'onglet "Offres"
      expect(find.byType(ServiceFormScreen), findsNothing);
      expect(find.text('Montage de meubles'), findsOneWidget);
      expect(repository.getServices().length, 9);
    });

    testWidgets('demander un service désactive le bouton',
        (WidgetTester tester) async {
      await afficher(tester, const ServiceDetailScreen(serviceId: 's4'));

      await tester.tap(find.text('Demander ce service'));
      await tester.pumpAndSettle();

      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(repository.aDejaDemande('s4'), isTrue);
    });

    testWidgets('sur son propre service : pas de bouton de demande',
        (WidgetTester tester) async {
      await afficher(tester, const ServiceDetailScreen(serviceId: 's7'));

      expect(find.text('Votre publication'), findsOneWidget);
      expect(find.text('Demander ce service'), findsNothing);
    });
  });

  group('Écrans : mes demandes et évaluation', () {
    testWidgets('les deux onglets affichent le nombre de demandes',
        (WidgetTester tester) async {
      await afficher(tester, const MesDemandesScreen());

      expect(find.text('Envoyées (3)'), findsOneWidget);
      expect(find.text('Reçues (2)'), findsOneWidget);
      // Onglet Envoyées : la demande réalisée peut être évaluée
      expect(find.text('Évaluer le service'), findsOneWidget);
    });

    testWidgets('accepter une demande reçue change son statut',
        (WidgetTester tester) async {
      await afficher(tester, const MesDemandesScreen());

      await tester.tap(find.text('Reçues (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Accepter'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);

      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();

      expect(repository.getDemandeParId('d4')!.statut, StatutDemande.acceptee);
      expect(find.text('Accepter'), findsNothing);
    });

    testWidgets('"Terminée" passe une demande acceptée à réalisée',
        (WidgetTester tester) async {
      await afficher(tester, const MesDemandesScreen());

      // d2 (envoyée, acceptée) est la seule demande acceptée de cet onglet
      await tester.tap(find.text('Terminée'));
      await tester.pumpAndSettle();

      expect(repository.getDemandeParId('d2')!.statut, StatutDemande.realisee);
      expect(find.text('Évaluer le service'), findsNWidgets(2));
    });

    testWidgets('évaluer : bouton désactivé sans étoile, puis envoi',
        (WidgetTester tester) async {
      await afficher(tester, const MesDemandesScreen());

      await tester.tap(find.text('Évaluer le service'));
      await tester.pumpAndSettle();
      expect(find.byType(EvaluationScreen), findsOneWidget);

      // Aucune étoile : le bouton d'envoi est désactivé
      final Finder boutonEnvoi =
          find.widgetWithText(ElevatedButton, 'Envoyer l\'évaluation');
      expect(tester.widget<ElevatedButton>(boutonEnvoi).onPressed, isNull);

      // 5 étoiles + un tag : le bouton devient actif
      await tester.tap(find.byTooltip('5 sur 5'));
      await tester.tap(find.text('Ponctuel'));
      await tester.pumpAndSettle();
      expect(find.text('Excellent'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(boutonEnvoi).onPressed, isNotNull);

      await tester.tap(boutonEnvoi);
      await tester.pumpAndSettle();

      // Retour à la liste : la demande est évaluée
      expect(find.byType(EvaluationScreen), findsNothing);
      expect(repository.getDemandeParId('d3')!.evaluee, isTrue);
      expect(find.text('Service évalué, merci !'), findsOneWidget);
    });
  });

  group('Dans la vraie app (go_router)', () {
    testWidgets('les écrans du module s\'ouvrent sans la barre du bas, et on revient',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appRouter.go('/services');

      await tester.pumpWidget(const HoumaniApp());
      await tester.pumpAndSettle();
      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      // Détail : plein écran
      await tester.tap(find.text('Courses au Carrefour'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDetailScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);

      // Retour : la liste et la barre du bas réapparaissent
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceDetailScreen), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);

      // Mes demandes et planning, depuis l'en-tête
      await tester.tap(find.byTooltip('Mes demandes'));
      await tester.pumpAndSettle();
      expect(find.byType(MesDemandesScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Planning des services communs'));
      await tester.pumpAndSettle();
      expect(find.byType(ServicesCommunsScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });
  });

  group('Écrans : planning et inscription', () {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);

    /// Un créneau d'aujourd'hui ou d'un jour à venir (pas encore passé).
    /// libre = true : un créneau libre ; false : un créneau pris par "inscrit".
    CreneauCommun creneauAVenir(String serviceId, {bool libre = true, String? inscrit}) {
      for (final creneau in repository.getCreneauxParService(serviceId)) {
        final bool avenir = !creneau.date.isBefore(aujourdhui);
        final bool convient = libre ? creneau.estLibre : creneau.inscrit == inscrit;
        if (avenir && convient) {
          return creneau;
        }
      }
      throw StateError('Aucun créneau à venir dans les données de départ');
    }

    /// Ouvre un écran PAR-DESSUS un écran de départ, comme dans l'app
    /// (ainsi le retour avec Navigator.pop fonctionne).
    Future<void> ouvrirPardessus(WidgetTester tester, Widget ecran) async {
      await afficher(
        tester,
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<bool>(builder: (context) => ecran),
                    );
                  },
                  child: const Text('Ouvrir'),
                ),
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('le planning affiche la semaine et la résidence',
        (WidgetTester tester) async {
      await afficher(tester, const ServicesCommunsScreen());

      expect(find.text('Services communs'), findsOneWidget);
      expect(find.text('Résidence Yasmine, Bloc B'), findsOneWidget);
      for (final jour in ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']) {
        expect(find.text(jour), findsOneWidget);
      }
    });

    testWidgets('choisir un jour affiche ses créneaux',
        (WidgetTester tester) async {
      await afficher(tester, const ServicesCommunsScreen());

      await tester.tap(find.text('Lun'));
      await tester.pumpAndSettle();
      expect(find.text('Sortie des poubelles'), findsOneWidget);
      expect(find.textContaining('Karim M.'), findsOneWidget);

      await tester.tap(find.text('Dim'));
      await tester.pumpAndSettle();
      expect(find.text('Arrosage du jardin'), findsOneWidget);
      expect(find.text('Créneau libre'), findsOneWidget);
      expect(find.text('S\'inscrire'), findsOneWidget);
    });

    testWidgets('S\'inscrire ouvre l\'inscription, puis le planning affiche "Toi"',
        (WidgetTester tester) async {
      await afficher(tester, const ServicesCommunsScreen());

      await tester.tap(find.text('Dim')); // dimanche : toujours aujourd'hui ou à venir
      await tester.pumpAndSettle();
      await tester.tap(find.text('S\'inscrire'));
      await tester.pumpAndSettle();
      expect(find.byType(InscriptionCreneauScreen), findsOneWidget);

      await tester.tap(find.text('Je m\'inscris'));
      await tester.pumpAndSettle();

      // Retour au planning mis à jour
      expect(find.byType(InscriptionCreneauScreen), findsNothing);
      expect(find.text('Toi'), findsOneWidget);
      expect(find.text('Gérer'), findsOneWidget);
    });

    testWidgets('inscription : le rappel de la veille est enregistré',
        (WidgetTester tester) async {
      final CreneauCommun libre = creneauAVenir('c1');
      await ouvrirPardessus(tester, InscriptionCreneauScreen(creneauId: libre.id));

      expect(find.text('Choisis ton créneau'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Je m\'inscris'));
      await tester.pumpAndSettle();

      final CreneauCommun apres = repository.getCreneauParId(libre.id)!;
      expect(apres.inscrit, repository.getMonNom());
      expect(apres.rappelVeille, isTrue);
      expect(find.byType(InscriptionCreneauScreen), findsNothing);
    });

    testWidgets('inscription : se désister de son créneau',
        (WidgetTester tester) async {
      final CreneauCommun libre = creneauAVenir('c2');
      repository.inscrire(libre.id);
      await ouvrirPardessus(tester, InscriptionCreneauScreen(creneauId: libre.id));

      // Mon créneau est sélectionné : on peut seulement se désister
      final Finder boutonInscrire = find.widgetWithText(ElevatedButton, 'Je m\'inscris');
      final Finder boutonDesister =
          find.widgetWithText(ElevatedButton, 'Se désister d\'un créneau');
      expect(tester.widget<ElevatedButton>(boutonInscrire).onPressed, isNull);
      expect(tester.widget<ElevatedButton>(boutonDesister).onPressed, isNotNull);

      await tester.tap(boutonDesister);
      await tester.pumpAndSettle();

      expect(repository.getCreneauParId(libre.id)!.estLibre, isTrue);
      expect(find.byType(InscriptionCreneauScreen), findsNothing);
    });

    testWidgets('inscription : un créneau pris par un voisin ne se choisit pas',
        (WidgetTester tester) async {
      final CreneauCommun pris = creneauAVenir('c1', libre: false, inscrit: 'Karim M.');
      await ouvrirPardessus(tester, InscriptionCreneauScreen(creneauId: pris.id));

      expect(find.text('Pris par Karim M.'), findsWidgets);
      final Finder boutonInscrire = find.widgetWithText(ElevatedButton, 'Je m\'inscris');
      expect(tester.widget<ElevatedButton>(boutonInscrire).onPressed, isNull);
    });
  });
}
