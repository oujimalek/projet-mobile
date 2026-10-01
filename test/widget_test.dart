import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/main.dart';
import 'package:houmani/router/app_router.dart';
import 'package:houmani/screens/accueil_screen.dart';
import 'package:houmani/screens/demo_screen.dart';
import 'package:houmani/screens/module1/connexion_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module4/sondage_screen.dart';
import 'package:houmani/screens/profil_screen.dart';

/// Touche un onglet de la barre du bas (et pas un autre texte identique).
Future<void> toucherOnglet(WidgetTester tester, String nom) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(nom),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Le routeur est global : on revient sur l'Accueil avant chaque test
  setUp(() {
    appRouter.go('/accueil');
  });

  testWidgets('L\'app démarre sur l\'onglet Accueil avec la barre du bas',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());
    await tester.pumpAndSettle();

    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('Chaque onglet ouvre son écran et garde la barre du bas',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());
    await tester.pumpAndSettle();

    await toucherOnglet(tester, 'Services');
    expect(find.byType(ServicesListScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    await toucherOnglet(tester, 'Signalements');
    expect(find.byType(CreateSignalementScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    await toucherOnglet(tester, 'Événements');
    expect(find.byType(SondageScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    await toucherOnglet(tester, 'Profil');
    expect(find.byType(ProfilScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    await toucherOnglet(tester, 'Accueil');
    expect(find.byType(AccueilScreen), findsOneWidget);
  });

  testWidgets('Profil ouvre l\'écran de connexion en plein écran',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());
    await tester.pumpAndSettle();

    await toucherOnglet(tester, 'Profil');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnexionScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('Accueil ouvre la démo, qui ouvre le module 1',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voir la démo des modules'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoScreen), findsOneWidget);
    expect(find.text('Ahla bik !'), findsOneWidget);

    await tester.tap(find.text('M1 · Utilisateurs'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });
}
