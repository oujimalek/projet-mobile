import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/quartier.dart' show PointGps;
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/signalements_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

final DateTime maintenant = DateTime(2026, 11, 12, 15, 0);
const PointGps ici = PointGps(36.8625, 10.1700);

/// Un signalement existant (Salma, eau, en attente, il y a 1 h, à [ici]).
Signalement existant({
  String id = 'proche',
  String categorieId = 'eau',
  StatutSignalement statut = StatutSignalement.enAttente,
  DateTime? date,
  PointGps? position = ici,
  String auteurId = 'u21',
}) {
  return Signalement(
    id: id,
    titre: 'Fuite près du parking',
    description: 'Description assez longue',
    categorieId: categorieId,
    statut: statut,
    date: date ?? maintenant.subtract(const Duration(hours: 1)),
    lieu: 'Parking',
    auteurId: auteurId,
    auteurNom: 'Salma G.',
    position: position,
  );
}

/// Le nouveau signalement, à [latitude] (même longitude que [ici]).
Signalement nouveau({double latitude = 36.8628, String categorieId = 'eau'}) {
  return existant(
    id: '',
    categorieId: categorieId,
    date: maintenant,
    position: PointGps(latitude, 10.1700),
    auteurId: 'u1',
  );
}

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  group('Distance (haversine)', () {
    test('Même point : 0 m ; 1° de latitude : environ 111 195 m', () {
      expect(SignalementRepository.distanceMetres(ici, ici), 0);
      expect(
        SignalementRepository.distanceMetres(
            const PointGps(36, 10), const PointGps(37, 10)),
        closeTo(111195, 1),
      );
    });

    test('Symétrique, et 0,0003° ≈ 33 m', () {
      const PointGps la = PointGps(36.8628, 10.1700);
      final double aller = SignalementRepository.distanceMetres(ici, la);
      expect(aller, closeTo(33.36, 0.05));
      expect(SignalementRepository.distanceMetres(la, ici), closeTo(aller, 1e-9));
    });

    test('Distance lisible : arrondie, au moins 1 m', () {
      expect(DoublonPossible(existant(), 33.4).distanceLisible, '33 m');
      expect(DoublonPossible(existant(), 0.2).distanceLisible, '1 m');
    });
  });

  group('Règle anti-doublon (fonction pure)', () {
    DoublonPossible? chercher(Signalement n, List<Signalement> liste) =>
        SignalementRepository.doublonProbable(n, liste, maintenant);

    test('Même catégorie, ouvert, 1 h, 33 m : trouvé', () {
      final DoublonPossible? d = chercher(nouveau(), [existant()]);
      expect(d!.signalement.id, 'proche');
      expect(d.distanceLisible, '33 m');
    });

    test('Rayon de 100 m : 89 m oui, 100,1 m non', () {
      expect(chercher(nouveau(latitude: 36.8633), [existant()]), isNotNull);
      expect(chercher(nouveau(latitude: 36.8634), [existant()]), isNull);
    });

    test('Autre catégorie, clôturé (résolu ou refusé) : non', () {
      expect(chercher(nouveau(categorieId: 'travaux'), [existant()]), isNull);
      expect(chercher(nouveau(), [existant(statut: StatutSignalement.resolu)]),
          isNull);
      expect(chercher(nouveau(), [existant(statut: StatutSignalement.refuse)]),
          isNull);
      expect(chercher(nouveau(), [existant(statut: StatutSignalement.enCours)]),
          isNotNull);
    });

    test('Plus de 24 h : non ; 23 h 59 : oui', () {
      expect(
        chercher(nouveau(), [
          existant(date: maintenant.subtract(const Duration(hours: 24, minutes: 1))),
        ]),
        isNull,
      );
      expect(
        chercher(nouveau(), [
          existant(date: maintenant.subtract(const Duration(hours: 23, minutes: 59))),
        ]),
        isNotNull,
      );
    });

    test('Sans point GPS (le nouveau ou l\'existant) : pas de vérification', () {
      final Signalement sansGps = Signalement(
        id: '',
        titre: 'Fuite',
        description: 'Description assez longue',
        categorieId: 'eau',
        statut: StatutSignalement.enAttente,
        date: maintenant,
        lieu: 'Parking',
        auteurId: 'u1',
        auteurNom: 'Amira B.',
      );
      expect(chercher(sansGps, [existant()]), isNull);
      expect(chercher(nouveau(), [existant(position: null)]), isNull);
    });

    test('Plusieurs : le plus proche', () {
      final DoublonPossible? d = chercher(nouveau(), [
        existant(id: 'loin', position: const PointGps(36.8633, 10.1700)),
        existant(id: 'pres', position: const PointGps(36.8627, 10.1700)),
      ]);
      expect(d!.signalement.id, 'pres');
    });
  });

  // =====================================================================
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;

  group('Avec le cache SQLite et l\'écran de création', () {
    setUpAll(() {
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    setUp(() {
      UtilisateurRepository.instance = MockUtilisateurRepository(); // Amira u1
      depot = MockSignalementRepository();
      SignalementRepository.instance = depot;
      connexion = installerHorsLigneM3();
      // Un signalement de Salma, il y a 1 h, au parking
      depot.ajouterTelQuel(existant(date: DateTime.now().subtract(const Duration(hours: 1))));
      fauxGps(const PointGps(36.8628, 10.1700)); // 33 m plus loin
      fausseAdresse('Rue du parking, Ennasr 2');
    });

    tearDown(() async {
      await nettoyerHorsLigneM3(connexion);
    });

    Signalement proche() => depot.tous.firstWhere((s) => s.id == 'proche');

    test('Sync : cherche dans le cache, aussi hors ligne ; sans cache : rien',
        () async {
      final Signalement n = nouveau().copyWith(date: DateTime.now());
      expect(await SyncSignalementsM3.instance.chercherDoublon(n), isNull);

      await SyncSignalementsM3.instance.chargerSignalements(); // cache rempli
      expect((await SyncSignalementsM3.instance.chercherDoublon(n))!.signalement.id,
          'proche');
      connexion.enLigne = false;
      expect(await SyncSignalementsM3.instance.chercherDoublon(n), isNotNull);
    });

    /// Liste → "Signaler" → formulaire "eau" avec "Utiliser ma position" →
    /// "Publier".
    Future<void> publierPres(WidgetTester tester,
        {String categorie = 'Eau', bool gps = true}) async {
      await afficher(tester, const SignalementsScreen()); // remplit le cache
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(categorie));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fuite au parking');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'De l\'eau coule sous le parking');
      if (gps) {
        await tester.tap(find.text('Utiliser ma position'));
        await tester.pumpAndSettle();
      } else {
        await tester.enterText(find.byType(TextFormField).at(2), 'Parking');
      }
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
    }

    const String question = 'Un signalement similaire existe à 33 m : '
        '« Fuite près du parking ». C\'est le même problème ?';

    testWidgets('"Oui, Sa7 ena zeda" : confirmé, détail ouvert, rien de publié',
        (WidgetTester tester) async {
      await publierPres(tester);
      expect(find.text(question), findsOneWidget);

      await tester.tap(find.text('Oui, Sa7 ena zeda'));
      await tester.pumpAndSettle();
      expect(proche().nbConfirmations, 1);
      expect(depot.tous.length, 5); // r1..r4 + proche : rien de nouveau
      expect(find.byType(SignalementDetailScreen), findsOneWidget);
      expect(find.text('Tu as confirmé'), findsOneWidget);
      expect(find.text('Merci ! Tu as confirmé le signalement existant.'),
          findsOneWidget);
      expect(await BaseLocaleM3.instance.lireBrouillon('u1'), isNull);

      // Retour : la liste (le formulaire a été remplacé par le détail)
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(SignalementsScreen), findsOneWidget);
      expect(find.text('Nouveau signalement'), findsNothing);
    });

    testWidgets('"Non, publier quand même" : publié normalement',
        (WidgetTester tester) async {
      await publierPres(tester);
      await tester.tap(find.text('Non, publier quand même'));
      await tester.pumpAndSettle();
      expect(depot.tous.length, 6);
      expect(proche().nbConfirmations, 0);
      expect(find.text('Yaatik saha ! Signalement publié.'), findsOneWidget);
    });

    testWidgets('Fenêtre fermée sans choisir : on reste sur le formulaire',
        (WidgetTester tester) async {
      await publierPres(tester);
      await tester.tapAt(const Offset(5, 5)); // en dehors de la fenêtre
      await tester.pumpAndSettle();
      expect(find.text('Nouveau signalement'), findsOneWidget);
      expect(find.text('Publier le signalement'), findsOneWidget); // réactivé
      expect(depot.tous.length, 5);
    });

    testWidgets('Mon propre signalement : on l\'ouvre, sans confirmer',
        (WidgetTester tester) async {
      depot.ajouterTelQuel(existant(
        id: 'mien',
        auteurId: 'u1',
        position: const PointGps(36.8627, 10.1700),
        date: DateTime.now().subtract(const Duration(minutes: 10)),
      ));
      await publierPres(tester);
      expect(find.text('Oui, voir mon signalement'), findsOneWidget);
      await tester.tap(find.text('Oui, voir mon signalement'));
      await tester.pumpAndSettle();
      expect(find.byType(SignalementDetailScreen), findsOneWidget);
      expect(depot.tous.firstWhere((s) => s.id == 'mien').nbConfirmations, 0);
    });

    testWidgets('Déjà confirmé : message, et le détail s\'ouvre quand même',
        (WidgetTester tester) async {
      await SignalementRepository().confirmer('proche');
      await publierPres(tester);
      await tester.tap(find.text('Oui, Sa7 ena zeda'));
      await tester.pumpAndSettle();
      expect(find.text('Tu as déjà confirmé ce signalement'), findsOneWidget);
      expect(find.byType(SignalementDetailScreen), findsOneWidget);
    });

    testWidgets('Hors ligne : pas de confirmation possible, message, détail du cache',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen()); // cache rempli
      connexion.enLigne = false;
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eau'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fuite au parking');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'De l\'eau coule sous le parking');
      await tester.tap(find.text('Utiliser ma position')); // adresse : faux service
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oui, Sa7 ena zeda'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pas de connexion : tu pourras le confirmer quand le réseau revient'),
        findsOneWidget,
      );
      expect(find.text('Hors ligne : version enregistrée sur le téléphone'),
          findsOneWidget);
      expect(proche().nbConfirmations, 0);
    });

    testWidgets('Sans point GPS : pas de question',
        (WidgetTester tester) async {
      await publierPres(tester, gps: false);
      expect(find.text(question), findsNothing);
      expect(depot.tous.length, 6);
    });

    testWidgets('Autre catégorie au même endroit : pas de question',
        (WidgetTester tester) async {
      await publierPres(tester, categorie: 'Travaux');
      expect(find.textContaining('Un signalement similaire'), findsNothing);
      expect(depot.tous.length, 6);
    });
  });
}
