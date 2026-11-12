import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/quartier.dart' show PointGps;
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/services/firestore_commun.dart';
import 'package:houmani/data/services/liens_m3.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/carte_signalements_screen.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/signalements_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

/// Un signalement avec un point GPS dans la Résidence El Yasmine (q1).
Signalement avecGps(
  String id,
  String titre, {
  String categorieId = 'eau',
  StatutSignalement statut = StatutSignalement.enAttente,
  bool danger = false,
  int nbConfirmations = 0,
  double latitude = 36.8625,
  double longitude = 10.1700,
}) {
  return Signalement(
    id: id,
    titre: titre,
    description: 'Description assez longue',
    categorieId: categorieId,
    statut: statut,
    date: DateTime.now().subtract(const Duration(hours: 1)),
    lieu: 'Bloc A',
    auteurId: 'u21',
    auteurNom: 'Salma G.',
    nbConfirmations: nbConfirmations,
    danger: danger,
    position: PointGps(latitude, longitude),
  );
}

void main() {
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository(); // Amira, q1
    depot = MockSignalementRepository(); // r1..r4 : sans point GPS
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
    depot.ajouterTelQuel(avecGps('fuite', 'Fuite au parking'));
    // Électricité + danger + 12 confirmations : urgent
    depot.ajouterTelQuel(avecGps('cable', 'Câble par terre',
        categorieId: 'electricite',
        danger: true,
        nbConfirmations: 12,
        latitude: 36.8630,
        longitude: 10.1705));
    depot.ajouterTelQuel(avecGps('trou', 'Trou dans la rue',
        categorieId: 'travaux',
        statut: StatutSignalement.resolu,
        latitude: 36.8620,
        longitude: 10.1695));
  });

  tearDown(() async {
    AppColors.sombre = false;
    await nettoyerHorsLigneM3(connexion);
  });

  Finder repere(String id) => find.byKey(ValueKey('repere_$id'));

  group('Carte des signalements', () {
    testWidgets('Un repère par signalement avec un point GPS ; contour du quartier',
        (WidgetTester tester) async {
      await afficher(tester, const CarteSignalementsScreen());
      expect(repere('fuite'), findsOneWidget);
      expect(repere('cable'), findsOneWidget);
      expect(repere('trou'), findsOneWidget);
      expect(repere('r1'), findsNothing); // pas de point GPS
      expect(find.text('3 sur la carte · 4 sans point GPS'), findsOneWidget);
      // Contour rouge de Résidence El Yasmine (module 1)
      expect(find.byType(PolygonLayer), findsOneWidget);
    });

    testWidgets('Les urgents sont plus grands', (WidgetTester tester) async {
      await afficher(tester, const CarteSignalementsScreen());
      expect(tester.getSize(repere('cable')).width, 46);
      expect(tester.getSize(repere('fuite')).width, 36);
    });

    testWidgets('Mêmes filtres que la liste (statut, catégorie)',
        (WidgetTester tester) async {
      await afficher(tester, const CarteSignalementsScreen());
      await toucher(tester, find.text('Résolu').first);
      await tester.pumpAndSettle();
      expect(repere('trou'), findsOneWidget);
      expect(repere('fuite'), findsNothing);

      await toucher(tester, find.text('Tous les statuts'));
      await tester.pumpAndSettle();
      await toucher(tester, find.text('Électricité'));
      await tester.pumpAndSettle();
      expect(repere('cable'), findsOneWidget);
      expect(repere('fuite'), findsNothing);
    });

    testWidgets('Filtres reçus de la liste', (WidgetTester tester) async {
      await afficher(tester,
          const CarteSignalementsScreen(statut: StatutSignalement.enAttente));
      expect(repere('fuite'), findsOneWidget);
      expect(repere('trou'), findsNothing);
    });

    testWidgets('Toucher un repère : fiche, puis le détail',
        (WidgetTester tester) async {
      await afficher(tester, const CarteSignalementsScreen());
      expect(find.byKey(const ValueKey('fiche_repere')), findsNothing);

      await tester.tap(repere('fuite'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche_repere')), findsOneWidget);
      expect(find.text('Fuite au parking'), findsOneWidget);

      await tester.tap(find.text('Voir le détail'));
      await tester.pumpAndSettle();
      expect(find.byType(SignalementDetailScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(CarteSignalementsScreen), findsOneWidget);
    });

    testWidgets('La croix ferme la fiche', (WidgetTester tester) async {
      await afficher(tester, const CarteSignalementsScreen());
      await tester.tap(repere('cable'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche_repere')), findsNothing);
    });

    testWidgets('Aucun point GPS : message sur la carte',
        (WidgetTester tester) async {
      SignalementRepository.instance = MockSignalementRepository();
      await afficher(tester, const CarteSignalementsScreen());
      expect(find.text('Aucun signalement avec un point GPS ici'), findsOneWidget);
    });

    testWidgets('Hors ligne : le cache SQLite et le message sur le fond de carte',
        (WidgetTester tester) async {
      await SyncSignalementsM3.instance.chargerSignalements(); // cache rempli
      connexion.enLigne = false;
      await afficher(tester, const CarteSignalementsScreen());
      expect(find.textContaining('le fond de carte a besoin d\'Internet'),
          findsOneWidget);
      expect(repere('fuite'), findsOneWidget);
      expect(repere('cable'), findsOneWidget);
    });

    testWidgets('Erreur sans cache : message et "Réessayer"',
        (WidgetTester tester) async {
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      await afficher(tester, const CarteSignalementsScreen());
      expect(find.text(FirestoreCommun.messageErreur('unavailable')),
          findsOneWidget);
      depot.erreurReseau = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(repere('fuite'), findsOneWidget);
    });

    testWidgets('Mode sombre, 360 px : affichage sans erreur',
        (WidgetTester tester) async {
      AppColors.sombre = true;
      await afficher(tester, const CarteSignalementsScreen());
      await tester.tap(repere('cable'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Accès à la carte', () {
    testWidgets('Icône carte de la liste : ouvre la carte avec ses filtres',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      await toucher(tester, find.text('Résolu').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Carte des signalements'));
      await tester.pumpAndSettle();
      expect(find.byType(CarteSignalementsScreen), findsOneWidget);
      expect(repere('trou'), findsOneWidget);
      expect(repere('fuite'), findsNothing);
    });

    testWidgets('Détail "Voir sur la carte" : ma carte, centrée, fiche ouverte',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'cable'));
      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(find.byType(CarteSignalementsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche_repere')), findsOneWidget);
      expect(find.text('Câble par terre'), findsWidgets);
      // Centrée sur le signalement (zoom 17)
      final FlutterMap carte = tester.widget(find.byType(FlutterMap));
      expect(carte.options.initialCenter.latitude, 36.8630);
      expect(carte.options.initialZoom, 17);
    });

    testWidgets('Détail : l\'application de cartes reste en action secondaire',
        (WidgetTester tester) async {
      final List<Uri> ouverts = [];
      LiensM3.ouvrirUrl = (url) async {
        ouverts.add(url);
        return true;
      };
      await afficher(tester, const SignalementDetailScreen(signalementId: 'fuite'));
      await tester.tap(find.text('Application de cartes'));
      await tester.pumpAndSettle();
      expect(ouverts.single.scheme, 'geo');
      expect(find.byType(CarteSignalementsScreen), findsNothing);
    });
  });
}

/// Fait défiler jusqu'au widget (filtre caché à droite), puis le touche.
Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
}
