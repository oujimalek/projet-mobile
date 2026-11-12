import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/services/liens_m3.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  late FausseConnexionM3 connexion;
  late List<Uri> ouverts; // les liens que l'app a voulu ouvrir
  late bool telephonePresent;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository();
    // Signalements de démo : r1 électricité, r2 ordures, r3 eau, r4 travaux
    SignalementRepository.instance = MockSignalementRepository();
    connexion = installerHorsLigneM3();
    ouverts = [];
    telephonePresent = true;
    LiensM3.ouvrirUrl = (url) async {
      ouverts.add(url);
      return telephonePresent;
    };
  });

  tearDown(() async {
    await nettoyerHorsLigneM3(connexion);
  });

  group('Les numéros (constante)', () {
    test('Exactement 3 numéros : STEG, SONEDE, Protection civile', () {
      expect(SignalementRepository.numerosUtiles.length, 3);
      final electricite = SignalementRepository.numeroUtile('electricite')!;
      expect(electricite.nom, 'STEG – urgences');
      expect(electricite.numero, '80100444');
      final eau = SignalementRepository.numeroUtile('eau')!;
      expect(eau.nom, 'SONEDE – numéro vert');
      expect(eau.numero, '80100319');
      final incident = SignalementRepository.numeroUtile('incident')!;
      expect(incident.nom, 'Protection civile');
      expect(incident.numero, '198');
    });

    test('Travaux et ordures : pas de numéro national', () {
      expect(SignalementRepository.numeroUtile('travaux'), isNull);
      expect(SignalementRepository.numeroUtile('ordures'), isNull);
      expect(SignalementRepository.numeroUtile('inconnue'), isNull);
    });

    test('Affichage lisible : 80 100 444 ; 198 tel quel', () {
      expect(SignalementRepository.numeroUtile('electricite')!.numeroLisible,
          '80 100 444');
      expect(SignalementRepository.numeroUtile('eau')!.numeroLisible,
          '80 100 319');
      expect(SignalementRepository.numeroUtile('incident')!.numeroLisible, '198');
    });

    test('Lien tel: ; pas d\'application téléphone : message', () async {
      expect(LiensM3.urlAppel('80100444').toString(), 'tel:80100444');
      expect((await LiensM3.appeler('198')).estSucces, isTrue);
      expect(ouverts.single.toString(), 'tel:198');

      telephonePresent = false;
      expect((await LiensM3.appeler('198')).erreur, LiensM3.messageAppel);
    });
  });

  group('Détail : bouton "Appeler"', () {
    testWidgets('Électricité : STEG, appel au 80100444',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r1'));
      expect(find.text('STEG – urgences'), findsOneWidget);
      expect(find.text('80 100 444'), findsOneWidget);

      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();
      expect(ouverts.single.toString(), 'tel:80100444');
    });

    testWidgets('Eau : SONEDE, appel au 80100319', (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.text('SONEDE – numéro vert'), findsOneWidget);
      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();
      expect(ouverts.single.toString(), 'tel:80100319');
    });

    testWidgets('Incident : Protection civile 198', (WidgetTester tester) async {
      await SignalementRepository().ajouterSignalement(
        (await SignalementRepository().getSignalement('r3'))
            .donnee!
            .copyWith(id: 'inc', categorieId: 'incident'),
      );
      await afficher(tester, const SignalementDetailScreen(signalementId: 'inc'));
      expect(find.text('Protection civile'), findsOneWidget);
      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();
      expect(ouverts.single.toString(), 'tel:198');
    });

    testWidgets('Travaux et ordures : pas de bouton', (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r4'));
      expect(find.text('Appeler'), findsNothing);
      expect(find.text('Numéro utile'), findsNothing);

      await afficher(tester, const SignalementDetailScreen(signalementId: 'r2'));
      expect(find.text('Appeler'), findsNothing);
    });

    testWidgets('Hors ligne (version du cache) : le bouton reste',
        (WidgetTester tester) async {
      await SyncSignalementsM3.instance.chargerSignalements(); // cache rempli
      connexion.enLigne = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r1'));
      expect(find.text('Hors ligne : version enregistrée sur le téléphone'),
          findsOneWidget);
      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();
      expect(ouverts.single.toString(), 'tel:80100444');
    });

    testWidgets('Pas d\'application téléphone : message',
        (WidgetTester tester) async {
      telephonePresent = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r1'));
      await tester.tap(find.text('Appeler'));
      await tester.pumpAndSettle();
      expect(find.text(LiensM3.messageAppel), findsOneWidget);
    });
  });
}
