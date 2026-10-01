import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/main.dart';
import 'package:houmani/screens/module1/connexion_screen.dart';

void main() {
  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('L\'écran de démo affiche l\'accueil et les 4 modules',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());

    expect(find.text('Ahla bik !'), findsOneWidget);
    expect(find.text('M1 · Utilisateurs'), findsOneWidget);
    expect(find.text('M2 · Services'), findsOneWidget);
    expect(find.text('M3 · Signalements'), findsOneWidget);
    expect(find.text('M4 · Événements'), findsOneWidget);
  });

  testWidgets('Toucher le module 1 ouvre l\'écran de connexion',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HoumaniApp());

    await tester.tap(find.text('M1 · Utilisateurs'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnexionScreen), findsOneWidget);
  });
}
