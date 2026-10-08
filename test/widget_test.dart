import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/services/mock_utilisateur_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/main.dart';
import 'package:houmani/router/app_router.dart';
import 'package:houmani/screens/accueil_screen.dart';
import 'package:houmani/screens/demo_screen.dart';
import 'package:houmani/screens/module1/admin_membres_screen.dart';
import 'package:houmani/screens/module1/attente_validation_screen.dart';
import 'package:houmani/screens/module1/code_quartier_screen.dart';
import 'package:houmani/screens/module1/connexion_screen.dart';
import 'package:houmani/screens/module1/inscription_screen.dart';
import 'package:houmani/screens/module1/mot_de_passe_oublie_screen.dart';
import 'package:houmani/screens/module1/profil_edition_screen.dart';
import 'package:houmani/screens/module1/profil_screen.dart';
import 'package:houmani/screens/module1/verification_otp_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module4/sondage_screen.dart';
import 'package:houmani/screens/splash_screen.dart';

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

/// Fait défiler jusqu'au widget (s'il est plus bas dans l'écran), puis le touche.
Future<void> toucher(WidgetTester tester, Finder finder) async {
  // Une ListView ne construit pas ce qui est loin en bas : on fait défiler
  // la liste jusqu'à ce que le widget existe
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lance l'application sur un écran de la taille d'un téléphone.
Future<void> lancerApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400); // 360 x 800
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const HoumaniApp());
  await tester.pumpAndSettle();
}

void main() {
  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Le routeur et les données sont globaux : avant chaque test, on repart
  // de données fictives neuves (compte de démo admin déjà connecté)
  // et on revient sur l'Accueil.
  // Les tests injectent toujours le mock : ils restent valables le jour
  // où l'application utilisera Firebase par défaut.
  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository();
    appRouter.go('/accueil');
  });

  testWidgets('Le splash affiche le logo puis ouvre la connexion',
      (WidgetTester tester) async {
    appRouter.go('/splash');
    await lancerApp(tester);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Houmani'), findsOneWidget);

    // Après 2 secondes : écran de connexion
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  testWidgets('Chaque onglet ouvre son écran et garde la barre du bas',
      (WidgetTester tester) async {
    await lancerApp(tester);
    expect(find.byType(AccueilScreen), findsOneWidget);

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

  testWidgets('Connexion avec le compte de démo : ouvre l\'accueil',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    // Mauvais mot de passe : message d'erreur
    await tester.enterText(find.byType(TextFormField).at(0), '+216 22 345 678');
    await tester.enterText(find.byType(TextFormField).at(1), 'mauvais1');
    await toucher(tester, find.text('Se connecter'));
    expect(find.text('Identifiant ou mot de passe incorrect'), findsOneWidget);

    // Bon mot de passe : accueil avec la barre du bas
    await tester.enterText(
      find.byType(TextFormField).at(1),
      MockUtilisateurRepository.motDePasseDemo,
    );
    await toucher(tester, find.text('Se connecter'));
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('Profil : l\'admin valide une demande dans la liste des membres',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    expect(find.text('Amira Ben Salah'), findsOneWidget);
    expect(find.text('Résident'), findsOneWidget);

    await toucher(tester, find.text('Membres du quartier'));
    expect(find.byType(AdminMembresScreen), findsOneWidget);
    // Toujours dans la coquille : la barre du bas reste visible
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('En attente (3)'), findsOneWidget);
    expect(find.text('Sarra Ben Ali'), findsOneWidget);

    await toucher(tester, find.text('Valider').first);
    expect(find.text('En attente (2)'), findsOneWidget);
    expect(find.text('Sarra Ben Ali'), findsNothing);

    await toucher(tester, find.text('Actifs (5)'));
    expect(find.text('Sarra Ben Ali'), findsOneWidget);
  });

  testWidgets('Profil : modifier le nom et ajouter une compétence',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');

    await toucher(tester, find.text('Modifier'));
    expect(find.byType(ProfilEditionScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Amira Ben Salem');
    await toucher(tester, find.text('+ Ajouter'));
    await tester.enterText(find.byType(TextField).last, 'Jardinage');
    await toucher(tester, find.text('Ajouter'));
    expect(find.text('Jardinage'), findsOneWidget);

    await toucher(tester, find.text('Enregistrer les modifications'));
    expect(find.byType(ProfilScreen), findsOneWidget);
    expect(find.text('Amira Ben Salem'), findsOneWidget);
    expect(find.text('Jardinage'), findsOneWidget);
  });

  testWidgets(
      'Parcours complet : inscription, code SMS, quartier, attente, accueil',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    // 1. Connexion → Inscription
    await toucher(tester, find.text('S\'inscrire'));
    expect(find.byType(InscriptionScreen), findsOneWidget);

    // 2. Inscription : les conditions doivent être acceptées
    await tester.enterText(find.byType(TextFormField).at(0), 'Mohamed Zahi');
    await tester.enterText(find.byType(TextFormField).at(1), '+216 55 123 456');
    await tester.enterText(find.byType(TextFormField).at(3), 'motdepasse');
    await toucher(tester, find.widgetWithText(ElevatedButton, 'S\'inscrire'));
    expect(
      find.text('Tu dois accepter les conditions d\'utilisation'),
      findsOneWidget,
    );
    await toucher(tester, find.byType(Checkbox));
    await toucher(tester, find.widgetWithText(ElevatedButton, 'S\'inscrire'));

    // 3. Vérification du code SMS
    expect(find.byType(VerificationOtpScreen), findsOneWidget);
    expect(find.textContaining('+216 •• ••• 456'), findsOneWidget);
    // Compte à rebours (texte en plusieurs morceaux : RichText)
    expect(
      find.textContaining('Renvoyer le code dans', findRichText: true),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await toucher(tester, find.text('Vérifier'));
    expect(find.text('Code incorrect, vérifie le SMS reçu'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      MockUtilisateurRepository.codeOtpDemo,
    );
    await tester.pump();
    await toucher(tester, find.text('Vérifier'));

    // 4. Code du quartier (6 caractères, en majuscules)
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'yas72b');
    await tester.pump();
    await toucher(tester, find.text('Rejoindre la houma'));

    // 5. Attente de validation
    expect(find.byType(AttenteValidationScreen), findsOneWidget);
    expect(find.text('Demande envoyée !'), findsOneWidget);
    expect(find.textContaining('Résidence El Yasmine'), findsWidgets);
    expect(
      UtilisateurRepository().getUtilisateurConnecte().nomComplet,
      'Mohamed Zahi',
    );

    // 6. Démo : l'admin valide → accueil, avec le message de démo
    await toucher(tester, find.text('Démo : simuler la validation'));
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.text('Notification envoyée (démo)'), findsOneWidget);
  });

  testWidgets('Mot de passe oublié : envoi du lien puis retour à la connexion',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    await toucher(tester, find.text('Mot de passe oublié ?'));
    expect(find.byType(MotDePasseOublieScreen), findsOneWidget);

    // Champ vide : message d'erreur, pas d'envoi
    await toucher(tester, find.text('Envoyer le lien'));
    expect(find.text('Saisis ton téléphone ou ton e-mail'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'demo@houmani.tn');
    await toucher(tester, find.text('Envoyer le lien'));
    expect(
      find.text('Si ce compte existe, un lien a été envoyé.'),
      findsOneWidget,
    );

    await toucher(tester, find.text('Retour à la connexion'));
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  testWidgets('Profil : changer la photo avec un avatar de la galerie',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    // Au départ : les initiales
    expect(find.text('AB'), findsOneWidget);

    await toucher(tester, find.text('Modifier'));
    // Tap direct (sans toucher) : le bouton est déjà visible, et faire
    // défiler la liste cacherait l'aperçu de l'avatar vérifié ensuite
    await tester.tap(find.text('Changer la photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choisis ton avatar'), findsOneWidget);

    await toucher(tester, find.byKey(const Key('avatar_chat')));
    // La galerie est fermée, l'aperçu montre le nouvel avatar
    expect(find.text('Choisis ton avatar'), findsNothing);
    expect(find.byIcon(Icons.pets), findsOneWidget);

    await toucher(tester, find.text('Enregistrer les modifications'));
    expect(find.byType(ProfilScreen), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(find.text('AB'), findsNothing);
    expect(UtilisateurRepository().getUtilisateurConnecte().avatar, 'chat');
  });

  testWidgets('Accueil ouvre la démo, qui ouvre le module 1',
      (WidgetTester tester) async {
    await lancerApp(tester);

    await tester.tap(find.text('Voir la démo des modules'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoScreen), findsOneWidget);
    expect(find.text('Ahla bik !'), findsOneWidget);

    await tester.tap(find.text('M1 · Utilisateurs'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });
}
