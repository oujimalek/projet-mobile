import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/utilisateur.dart';
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
import 'package:houmani/widgets/app_drawer.dart';

import 'mock_utilisateur_repository.dart';

/// Le faux repository injecté dans chaque test (voir setUp).
MockUtilisateurRepository get mock {
  return UtilisateurRepository.instance as MockUtilisateurRepository;
}

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

/// Fait défiler le menu latéral jusqu'au widget, puis le touche.
Future<void> toucherDansMenu(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first,
  );
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
  // L'application utilise Firebase par défaut : les tests injectent le mock
  // (pas de réseau, pas de vrai compte).
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
    await tester.enterText(
      find.byType(TextFormField).at(0),
      MockUtilisateurRepository.emailDemo,
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'mauvais1');
    await toucher(tester, find.text('Se connecter'));
    expect(find.text('E-mail ou mot de passe incorrect'), findsOneWidget);

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
      'Parcours complet : inscription, e-mail, quartier, attente, accueil',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    // 1. Connexion → Inscription
    await toucher(tester, find.text('S\'inscrire'));
    expect(find.byType(InscriptionScreen), findsOneWidget);

    // 2. Inscription : les conditions doivent être acceptées
    await tester.enterText(find.byType(TextFormField).at(0), 'Mohamed Zahi');
    await tester.enterText(find.byType(TextFormField).at(1), '+216 55 123 456');
    await tester.enterText(find.byType(TextFormField).at(2), 'mohamed@houmani.tn');
    await tester.enterText(find.byType(TextFormField).at(3), 'motdepasse');
    await toucher(tester, find.widgetWithText(ElevatedButton, 'S\'inscrire'));
    expect(
      find.text('Tu dois accepter les conditions d\'utilisation'),
      findsOneWidget,
    );
    await toucher(tester, find.byType(Checkbox));
    await toucher(tester, find.widgetWithText(ElevatedButton, 'S\'inscrire'));

    // 3. Vérification de l'adresse e-mail
    expect(find.byType(VerificationOtpScreen), findsOneWidget);
    expect(find.textContaining('mohamed@houmani.tn'), findsOneWidget);
    // Compte à rebours (texte en plusieurs morceaux : RichText)
    expect(
      find.textContaining('Renvoyer l\'e-mail dans', findRichText: true),
      findsOneWidget,
    );
    // Lien pas encore cliqué : message d'erreur
    await toucher(tester, find.text('J\'ai vérifié mon e-mail'));
    expect(
      find.text('E-mail pas encore vérifié : clique sur le lien reçu'),
      findsOneWidget,
    );
    // On simule le clic sur le lien reçu par e-mail, puis on revérifie
    await mock.simulerVerificationEmail();
    await toucher(tester, find.text('J\'ai vérifié mon e-mail'));

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

    // 6. L'admin valide (simulé), puis "Vérifier ma demande" → accueil
    await mock.simulerValidation();
    await toucher(tester, find.text('Vérifier ma demande'));
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.text('Ta demande a été acceptée !'), findsOneWidget);
  });

  testWidgets(
      'Module 1 de bout en bout : conditions, œil, inscription, accueil, '
      'profil, déconnexion, reconnexion', (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    // 1. Connexion : pied de page © et conditions en lecture seule
    await toucher(tester, find.text('Conditions d\'utilisation'));
    expect(find.text('1. Objet'), findsOneWidget);
    expect(find.text('J\'accepte'), findsNothing); // lecture seule
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('© 2026 Houmani. Tous droits réservés.'), findsOneWidget);

    // 2. Inscription
    await toucher(tester, find.text('S\'inscrire'));
    await tester.enterText(find.byType(TextFormField).at(0), 'Nour Trabelsi');
    await tester.enterText(find.byType(TextFormField).at(1), '+216 22 333 444');
    await tester.enterText(find.byType(TextFormField).at(2), 'nour@houmani.tn');
    await tester.enterText(find.byType(TextFormField).at(3), 'nour2026');

    // Le bouton œil affiche puis masque le mot de passe
    bool masque() {
      return tester.widget<EditableText>(find.byType(EditableText).at(3)).obscureText;
    }
    expect(masque(), isTrue);
    await toucher(tester, find.byTooltip('Afficher le mot de passe'));
    expect(masque(), isFalse);
    await toucher(tester, find.byTooltip('Masquer le mot de passe'));
    expect(masque(), isTrue);

    // Les conditions s'ouvrent depuis le lien, défilent jusqu'au ©,
    // et "J'accepte" coche la case
    await toucher(tester, find.text('conditions d\'utilisation'));
    await tester.scrollUntilVisible(
      find.text('9. Modification des conditions'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('conditions_texte')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('J\'accepte'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await toucher(tester, find.widgetWithText(ElevatedButton, 'S\'inscrire'));

    // 3. E-mail vérifié → code du quartier → attente → validée
    expect(find.byType(VerificationOtpScreen), findsOneWidget);
    await mock.simulerVerificationEmail();
    await toucher(tester, find.text('J\'ai vérifié mon e-mail'));
    await tester.enterText(find.byType(TextField).first, 'YAS72B');
    await tester.pump();
    await toucher(tester, find.text('Rejoindre la houma'));
    expect(find.byType(AttenteValidationScreen), findsOneWidget);
    await mock.simulerValidation();
    await toucher(tester, find.text('Vérifier ma demande'));

    // 4. Accueil : salutation et invitation à compléter le profil
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.text('Ahla Nour !'), findsOneWidget);
    // On laisse disparaître le message "Ta demande a été acceptée !"
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ton profil est complet à'), findsOneWidget);
    await toucher(tester, find.textContaining('Ton profil est complet à'));
    expect(find.byType(ProfilEditionScreen), findsOneWidget);
    await toucher(tester, find.text('+ Ajouter'));
    await tester.enterText(find.byType(TextField).last, 'Cuisine');
    await toucher(tester, find.text('Ajouter'));
    await toucher(tester, find.text('Enregistrer les modifications'));
    expect(
      UtilisateurRepository().getUtilisateurConnecte().competences,
      contains('Cuisine'),
    );

    // 5. Profil depuis le menu, puis déconnexion
    // (toucher a fait défiler l'accueil caché sous l'édition : on remonte)
    expect(find.byType(AccueilScreen), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await toucherDansMenu(
      tester,
      find.descendant(of: find.byType(Drawer), matching: find.text('Mon profil')),
    );
    expect(find.byType(ProfilScreen), findsOneWidget);
    expect(find.text('Nour Trabelsi'), findsOneWidget);
    expect(find.text('Cuisine'), findsOneWidget);
    cleCoquille.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);

    // 6. Reconnexion avec le nouveau compte : retour direct à l'accueil
    await tester.enterText(find.byType(TextFormField).at(0), 'nour@houmani.tn');
    await tester.enterText(find.byType(TextFormField).at(1), 'nour2026');
    await toucher(tester, find.text('Se connecter'));
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.text('Ahla Nour !'), findsOneWidget);
  });

  testWidgets('Mot de passe oublié : envoi du lien puis retour à la connexion',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    await toucher(tester, find.text('Mot de passe oublié ?'));
    expect(find.byType(MotDePasseOublieScreen), findsOneWidget);

    // Champ vide : message d'erreur, pas d'envoi
    await toucher(tester, find.text('Envoyer le lien'));
    expect(find.text('Saisis ton e-mail'), findsOneWidget);

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

  testWidgets('Accueil : salutation, raccourcis et demandes en attente',
      (WidgetTester tester) async {
    await lancerApp(tester);
    expect(find.text('Ahla Amira !'), findsOneWidget);
    expect(find.text('3 demandes d\'adhésion en attente'), findsOneWidget);

    // Un raccourci ouvre l'onglet du module
    await toucher(tester, find.text('Signaler'));
    expect(find.byType(CreateSignalementScreen), findsOneWidget);
  });

  testWidgets('Menu latéral : modules, sous-rubriques et déconnexion',
      (WidgetTester tester) async {
    await lancerApp(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Amira Ben Salah'), findsOneWidget);

    // Un module se déplie et montre ses sous-rubriques
    // (dans le menu, pas l'onglet "Services" de la barre du bas)
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Services')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offres et demandes'));
    await tester.pumpAndSettle();
    expect(find.byType(ServicesListScreen), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);

    // Déconnexion depuis la carte du bas
    cleCoquille.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  testWidgets('Le menu ouvre la démo, qui ouvre le module 1',
      (WidgetTester tester) async {
    await lancerApp(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await toucherDansMenu(tester, find.text('Démo des modules'));
    expect(find.byType(DemoScreen), findsOneWidget);
    expect(find.text('Ahla bik !'), findsOneWidget);

    await tester.tap(find.text('M1 · Utilisateurs'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // Le bon écran selon le statut du compte (actif, en attente, refusé,
  // bloqué) : après la connexion, au démarrage et sur l'écran d'attente
  // -------------------------------------------------------------------

  testWidgets('Connexion d\'un compte refusé : choisir un autre quartier',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.refuse), 'secret123');
    appRouter.go('/connexion');
    await lancerApp(tester);

    await seConnecter(tester, 'test@houmani.tn', 'secret123');
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
  });

  testWidgets('Connexion d\'un compte en attente : écran d\'attente',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.enAttente), 'secret123');
    appRouter.go('/connexion');
    await lancerApp(tester);

    await seConnecter(tester, 'test@houmani.tn', 'secret123');
    expect(find.byType(AttenteValidationScreen), findsOneWidget);
  });

  testWidgets('Connexion d\'un compte bloqué : message, reste sur la connexion',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.bloque), 'secret123');
    appRouter.go('/connexion');
    await lancerApp(tester);

    await seConnecter(tester, 'test@houmani.tn', 'secret123');
    expect(find.byType(ConnexionScreen), findsOneWidget);
    expect(
      find.text('Ton compte a été bloqué par l\'administrateur'),
      findsOneWidget,
    );
  });

  testWidgets('Splash : un membre actif resté connecté arrive sur l\'accueil',
      (WidgetTester tester) async {
    mock.sessionGardee = compteDeTest(StatutUtilisateur.actif);
    appRouter.go('/splash');
    await lancerApp(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(AccueilScreen), findsOneWidget);
  });

  testWidgets('Splash : une demande en attente rouvre l\'écran d\'attente',
      (WidgetTester tester) async {
    mock.sessionGardee = compteDeTest(StatutUtilisateur.enAttente);
    appRouter.go('/splash');
    await lancerApp(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(AttenteValidationScreen), findsOneWidget);
  });

  testWidgets('Attente : demande refusée → message et choix du quartier',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.enAttente), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/attente');
    await lancerApp(tester);

    await mock.simulerStatut(StatutUtilisateur.refuse);
    await toucher(tester, find.text('Vérifier ma demande'));
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    expect(
      find.text('Ta demande a été refusée : choisis un autre quartier'),
      findsOneWidget,
    );
  });

  testWidgets('Attente : compte bloqué → message et retour à la connexion',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.enAttente), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/attente');
    await lancerApp(tester);

    await mock.simulerStatut(StatutUtilisateur.bloque);
    await toucher(tester, find.text('Vérifier ma demande'));
    expect(find.byType(ConnexionScreen), findsOneWidget);
    expect(
      find.text('Ton compte a été bloqué par l\'administrateur'),
      findsOneWidget,
    );
  });

  testWidgets('Membres du quartier : erreur réseau affichée',
      (WidgetTester tester) async {
    mock.erreurMembres = 'Serveur injoignable, vérifie ta connexion Internet';
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');

    await toucher(tester, find.text('Membres du quartier'));
    expect(find.byType(AdminMembresScreen), findsOneWidget);
    expect(
      find.text('Serveur injoignable, vérifie ta connexion Internet'),
      findsOneWidget,
    );
    expect(find.text('Sarra Ben Ali'), findsNothing);
  });

  // -------------------------------------------------------------------
  // Corrections après le test sur Chrome
  // -------------------------------------------------------------------

  testWidgets('Code du quartier : le champ du code est accessible',
      (WidgetTester tester) async {
    final SemanticsHandle semantique = tester.ensureSemantics();
    appRouter.go('/code-quartier');
    await lancerApp(tester);

    // Le champ invisible (le 1er de l'écran) reste dans l'arbre
    // d'accessibilité : c'est bien un champ de texte, avec un nom
    final Finder champCode = find.byType(EditableText).first;
    final SemanticsNode noeud = tester.getSemantics(champCode);
    expect(noeud.getSemanticsData().flagsCollection.isTextField, isTrue);
    expect(noeud.label, 'Code d\'invitation');
    semantique.dispose();
  });

  testWidgets('Splash : un compte refusé voit pourquoi il choisit un quartier',
      (WidgetTester tester) async {
    mock.sessionGardee = compteDeTest(StatutUtilisateur.refuse);
    appRouter.go('/splash');
    await lancerApp(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    expect(
      find.textContaining('Ta dernière demande a été refusée'),
      findsOneWidget,
    );
  });

  testWidgets('Code du quartier : pas de bandeau de refus pour un nouveau compte',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteSansQuartier(), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/code-quartier');
    await lancerApp(tester);

    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    expect(
      find.textContaining('Ta dernière demande a été refusée'),
      findsNothing,
    );
  });

  testWidgets('Splash : e-mail déjà vérifié, sans quartier → choix du quartier',
      (WidgetTester tester) async {
    // ajouterCompte : e-mail déjà vérifié
    mock.ajouterCompte(compteSansQuartier(), 'secret123');
    mock.sessionGardee = compteSansQuartier();
    appRouter.go('/splash');
    await lancerApp(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
  });

  testWidgets('Splash : e-mail pas encore vérifié → écran de vérification',
      (WidgetTester tester) async {
    mock.sessionGardee = compteSansQuartier();
    appRouter.go('/splash');
    await lancerApp(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(VerificationOtpScreen), findsOneWidget);
  });

  testWidgets('Membres : refuser demande une confirmation',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Membres du quartier'));
    expect(find.text('En attente (3)'), findsOneWidget);

    // Annuler : rien ne change
    await toucher(tester, find.text('Refuser').first);
    expect(find.text('Refuser la demande ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Refuser la demande ?'), findsNothing);
    expect(find.text('En attente (3)'), findsOneWidget);

    // Confirmer : la demande quitte la liste
    await toucher(tester, find.text('Refuser').first);
    await tester.tap(find.widgetWithText(TextButton, 'Refuser'));
    await tester.pumpAndSettle();
    expect(find.text('En attente (2)'), findsOneWidget);
  });

  testWidgets('Membres : bloquer demande une confirmation',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Membres du quartier'));
    await toucher(tester, find.text('Actifs (4)'));

    await toucher(tester, find.text('Bloquer').first);
    expect(find.text('Bloquer ce membre ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bloquer'));
    await tester.pumpAndSettle();
    expect(find.text('Actifs (3)'), findsOneWidget);
    expect(find.text('Bloqués (2)'), findsOneWidget); // 1 au départ + 1
  });
}

/// Un compte vérifié ou non, inscrit mais sans quartier.
Utilisateur compteSansQuartier() {
  return compteDeTest(StatutUtilisateur.enAttente).copier(
    quartierId: '',
    quartier: '',
    residence: '',
  );
}

/// Un compte "test@houmani.tn" du quartier El Yasmine, avec ce statut.
Utilisateur compteDeTest(StatutUtilisateur statut) {
  return Utilisateur(
    id: 'test1',
    prenom: 'Test',
    nom: 'Houmani',
    email: 'test@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine',
    statut: statut,
    dateDemande: DateTime(2026, 10, 15, 9, 30),
  );
}

/// Remplit l'écran de connexion et appuie sur "Se connecter".
Future<void> seConnecter(
  WidgetTester tester,
  String email,
  String motDePasse,
) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), motDePasse);
  await toucher(tester, find.text('Se connecter'));
}
