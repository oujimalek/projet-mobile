import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/quartier.dart' show PointGps;
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/services/liens_m3.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/widgets_module3.dart';
import 'package:houmani/theme/app_theme.dart';
import 'package:houmani/theme/preference_langue.dart';

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
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;
  late List<String> textes; // ce que l'app a voulu partager
  late List<String> sujets;
  late bool partagePossible;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository();
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
    textes = [];
    sujets = [];
    partagePossible = true;
    LiensM3.partagerTexte = (texte, sujet) async {
      textes.add(texte);
      sujets.add(sujet);
      return partagePossible;
    };
  });

  tearDown(() async {
    PreferenceLangue.langue.value = Langue.francais;
    AppColors.sombre = false;
    await nettoyerHorsLigneM3(connexion);
  });

  Signalement r3() => depot.tous.firstWhere((s) => s.id == 'r3');

  group('Texte partagé', () {
    test('Titre, catégorie, statut, lieu (sans point GPS : pas de lien)', () {
      expect(
        texteDePartageM3(r3()),
        'Signalement Houmani : Fuite d\'eau devant l\'entrée\n'
        'Catégorie : Eau\n'
        'Statut : En attente\n'
        'Lieu : Entrée bloc A',
      );
    });

    test('Avec point GPS : lien OpenStreetMap', () {
      final String texte = texteDePartageM3(
          r3().copyWith(position: const PointGps(36.8625, 10.17)));
      expect(texte.split('\n').last,
          'Carte : https://www.openstreetmap.org/?mlat=36.8625&mlon=10.17#map=18/36.8625/10.17');
    });

    test('En derja : les libellés suivent la langue choisie', () {
      PreferenceLangue.langue.value = Langue.derja;
      final String texte = texteDePartageM3(r3());
      expect(texte, startsWith('Tabligh Houmani : '));
      expect(texte, contains('El 7ala : Yestanna'));
    });

    test('Partage impossible : message', () async {
      partagePossible = false;
      expect((await LiensM3.partager('x', 'y')).erreur, LiensM3.messagePartage);
    });
  });

  group('Bouton "Partager" du détail', () {
    testWidgets('Partage le texte, avec le titre comme sujet',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.byTooltip('Partager'));
      await tester.pumpAndSettle();
      expect(textes.single, texteDePartageM3(r3()));
      expect(sujets.single, 'Fuite d\'eau devant l\'entrée');
    });

    testWidgets('Échec : message à l\'écran', (WidgetTester tester) async {
      partagePossible = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.byTooltip('Partager'));
      await tester.pumpAndSettle();
      expect(find.text(LiensM3.messagePartage), findsOneWidget);
    });

    testWidgets('Hors ligne (cache) : on peut toujours partager',
        (WidgetTester tester) async {
      await SyncSignalementsM3.instance.chargerSignalements();
      connexion.enLigne = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.byTooltip('Partager'));
      await tester.pumpAndSettle();
      expect(textes.length, 1);
    });

    testWidgets('Signalement introuvable : pas de bouton',
        (WidgetTester tester) async {
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'nexistepas'));
      expect(find.byTooltip('Partager'), findsNothing);
    });

    testWidgets('Mode sombre, 360 px : le détail s\'affiche sans erreur',
        (WidgetTester tester) async {
      AppColors.sombre = true;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r1'));
      expect(find.byTooltip('Partager'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
