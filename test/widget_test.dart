import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/cache_local.dart';
import 'package:houmani/data/services/localisation.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/main.dart';
import 'package:houmani/router/app_router.dart';
import 'package:houmani/screens/accueil_screen.dart';
import 'package:houmani/screens/demo_screen.dart';
import 'package:houmani/screens/module1/admin_membres_screen.dart';
import 'package:houmani/screens/module1/annuaire_voisins_screen.dart';
import 'package:houmani/screens/module1/attente_validation_screen.dart';
import 'package:houmani/screens/module1/code_quartier_screen.dart';
import 'package:houmani/screens/module1/connexion_screen.dart';
import 'package:houmani/screens/module1/inscription_screen.dart';
import 'package:houmani/screens/module1/mon_quartier_screen.dart';
import 'package:houmani/screens/module1/mot_de_passe_oublie_screen.dart';
import 'package:houmani/screens/module1/parametres_screen.dart';
import 'package:houmani/screens/module1/profil_edition_screen.dart';
import 'package:houmani/screens/module1/profil_screen.dart';
import 'package:houmani/screens/module1/tracer_limites_screen.dart';
import 'package:houmani/screens/module1/verification_otp_screen.dart';
import 'package:houmani/screens/module2/services_list_screen.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module4/sondage_screen.dart';
import 'package:houmani/screens/splash_screen.dart';
import 'package:houmani/theme/app_theme.dart';
import 'package:houmani/theme/preference_langue.dart';
import 'package:houmani/theme/preference_theme.dart';
import 'package:houmani/widgets/app_drawer.dart';
import 'package:houmani/widgets/primary_button.dart';

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

  testWidgets('Connexion avec le numéro de téléphone : ouvre l\'accueil',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);

    // Numéro trop court : refusé par le formulaire
    await tester.enterText(find.byType(TextFormField).at(0), '1234');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      MockUtilisateurRepository.motDePasseDemo,
    );
    await toucher(tester, find.text('Se connecter'));
    expect(
      find.text('Numéro de téléphone invalide (8 chiffres)'),
      findsOneWidget,
    );

    // Bon numéro (avec +216 et espaces) : accueil
    await tester.enterText(
      find.byType(TextFormField).at(0),
      '+216 22 345 678',
    );
    await toucher(tester, find.text('Se connecter'));
    expect(find.byType(AccueilScreen), findsOneWidget);
  });

  testWidgets('Connexion par SMS : numéro, code à 6 chiffres, accueil',
      (WidgetTester tester) async {
    appRouter.go('/connexion');
    await lancerApp(tester);
    await toucher(tester, find.text('Se connecter par SMS'));
    expect(find.text('Connexion par SMS'), findsOneWidget);

    // Étape 1 : le numéro du compte de démo
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      '22 345 678',
    );
    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    expect(find.text('Renvoyer le code dans 30 s'), findsOneWidget);

    // Étape 2 : mauvais code, puis le bon
    final Finder champCode = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(champCode, '000000');
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Code incorrect'), findsOneWidget);

    await tester.enterText(champCode, MockUtilisateurRepository.codeSmsDemo);
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AccueilScreen), findsOneWidget);
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

  testWidgets('Profil : bouton Se déconnecter en bas de l\'écran',
      (WidgetTester tester) async {
    appRouter.go('/profil');
    await lancerApp(tester);
    expect(find.byType(ProfilScreen), findsOneWidget);
    await toucher(tester, find.text('Se déconnecter'));
    expect(find.byType(ConnexionScreen), findsOneWidget);
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

  testWidgets('Menu : ni démo ni "Modifier mon profil"',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await toucherDansMenu(tester, find.text('Paramètres'));
    expect(find.byType(ParametresScreen), findsOneWidget);
    expect(find.text('Démo des modules'), findsNothing);
    expect(find.text('Modifier mon profil'), findsNothing);
  });

  testWidgets('La démo (adresse /demo) ouvre le module 1',
      (WidgetTester tester) async {
    appRouter.go('/demo');
    await lancerApp(tester);
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

    // Confirmer sans motif : la fenêtre reste ouverte avec l'erreur
    await toucher(tester, find.text('Refuser').first);
    await tester.tap(find.widgetWithText(TextButton, 'Refuser'));
    await tester.pumpAndSettle();
    expect(find.text('Refuser la demande ?'), findsOneWidget);
    expect(
      find.text('Explique la raison en quelques mots (3 caractères minimum)'),
      findsOneWidget,
    );

    // Avec un motif : la demande quitte la liste, le motif est gardé
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motif (vu par le membre)'),
      'Logement introuvable',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Refuser'));
    await tester.pumpAndSettle();
    expect(find.text('En attente (2)'), findsOneWidget);
    final List<Utilisateur> refuses =
        (await mock.getMembres(StatutUtilisateur.refuse)).donnee!;
    expect(refuses.single.motif, 'Logement introuvable');
  });

  testWidgets('Membres : statistiques du quartier',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Membres du quartier'));

    expect(find.text('Refusés'), findsOneWidget);
    expect(find.text('Actifs'), findsOneWidget);
    // 4 actifs, 3 en attente, 1 bloqué, 0 refusé (données de démo)
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Membres : bloquer demande une confirmation',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Membres du quartier'));
    await toucher(tester, find.text('Actifs (4)'));

    await toucher(tester, find.text('Bloquer').first);
    expect(find.text('Bloquer ce membre ?'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motif (vu par le membre)'),
      'Insultes',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Bloquer'));
    await tester.pumpAndSettle();
    expect(find.text('Actifs (3)'), findsOneWidget);
    expect(find.text('Bloqués (2)'), findsOneWidget); // 1 au départ + 1

    // Onglet Bloqués : le motif est rappelé
    await toucher(tester, find.text('Bloqués (2)'));
    expect(find.textContaining('Motif : Insultes'), findsOneWidget);
  });

  testWidgets('Code du quartier : un quartier sans admin ne peut pas être rejoint',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteSansQuartier(), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/code-quartier');
    await lancerApp(tester);

    await tester.enterText(find.byType(EditableText).first, 'JAS33A');
    await tester.pumpAndSettle();
    expect(find.textContaining('n\'a pas encore d\'administrateur'),
        findsWidgets);
    // Bouton désactivé : toucher ne fait rien
    await toucher(tester, find.text('Rejoindre la houma'));
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    expect(mock.getUtilisateurConnecte().quartierId ?? '', isEmpty);
  });

  // -------------------------------------------------------------------
  // Paramètres (sécurité du compte)
  // -------------------------------------------------------------------

  testWidgets('Profil : le lien Paramètres ouvre l\'écran Paramètres',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Paramètres'));
    expect(find.byType(ParametresScreen), findsOneWidget);
    expect(find.text(MockUtilisateurRepository.emailDemo), findsOneWidget);
    // La version est tout en bas (sous la section Langue) : on défile
    await tester.scrollUntilVisible(
      find.text(versionHoumani),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(versionHoumani), findsOneWidget);
  });

  testWidgets('Menu : la rubrique Paramètres ouvre l\'écran Paramètres',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await toucherDansMenu(tester, find.text('Paramètres'));
    expect(find.byType(ParametresScreen), findsOneWidget);
  });

  testWidgets('Paramètres : changer le mot de passe',
      (WidgetTester tester) async {
    appRouter.go('/parametres');
    await lancerApp(tester);
    await toucher(tester, find.text('Changer le mot de passe'));

    // La confirmation ne correspond pas : la fenêtre reste ouverte
    await remplirDialogue(tester, [
      MockUtilisateurRepository.motDePasseDemo,
      'nouveau123',
      'autre1234',
    ]);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Les deux mots de passe ne sont pas identiques'),
      findsOneWidget,
    );

    // Confirmation corrigée : c'est enregistré
    await remplirDialogue(tester, [
      MockUtilisateurRepository.motDePasseDemo,
      'nouveau123',
      'nouveau123',
    ]);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Mot de passe modifié'), findsOneWidget);
  });

  testWidgets('Profil : annuaire des voisins, recherche et numéro copié',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Annuaire des voisins'));
    expect(find.byType(AnnuaireVoisinsScreen), findsOneWidget);

    // Les membres actifs, sans soi-même ni les bloqués / en attente
    expect(find.text('Youssef Trabelsi'), findsOneWidget);
    expect(find.text('Salma Gharbi'), findsOneWidget);
    expect(find.text('Karim Mansour'), findsOneWidget);
    expect(find.text('Amira Ben Salah'), findsNothing);
    expect(find.text('Walid Ferchichi'), findsNothing);
    expect(find.text('Sarra Ben Ali'), findsNothing);

    // Recherche par compétence
    await tester.enterText(find.byType(TextField), 'cuisine');
    await tester.pumpAndSettle();
    expect(find.text('Salma Gharbi'), findsOneWidget);
    expect(find.text('Youssef Trabelsi'), findsNothing);

    // Rien ne correspond
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun voisin trouvé'), findsOneWidget);

    // Recherche par nom, puis le numéro copié
    await tester.enterText(find.byType(TextField), 'youssef');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Youssef Trabelsi'));
    await tester.pumpAndSettle();
    expect(find.text('+216 22 111 111'), findsOneWidget);

    // Pas de vrai presse-papiers en test : on note ce qui y est copié
    String? copie;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall appel) async {
        if (appel.method == 'Clipboard.setData') {
          copie = (appel.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.text('Copier le numéro'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Numéro copié'), findsOneWidget);
    expect(copie, '+216 22 111 111');
  });

  testWidgets('Paramètres : vérifier son numéro par SMS',
      (WidgetTester tester) async {
    mock.ajouterCompte(
      compteDeTest(StatutUtilisateur.actif).copier(telephone: '+216 20 000 000'),
      'secret123',
    );
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/parametres');
    await lancerApp(tester);
    await toucher(tester, find.text('Vérifier mon numéro'));
    expect(find.textContaining('+216 20 000 000'), findsWidgets);

    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      MockUtilisateurRepository.codeSmsDemo,
    );
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('Numéro vérifié : tu peux te connecter par SMS'),
      findsOneWidget,
    );
    expect(find.text('Numéro vérifié'), findsOneWidget);
  });

  testWidgets('Paramètres : supprimer son compte → retour à la connexion',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteDeTest(StatutUtilisateur.actif), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/parametres');
    await lancerApp(tester);

    await toucher(tester, find.text('Supprimer mon compte'));
    await remplirDialogue(tester, ['secret123']);
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
    expect(find.text('Ton compte a été supprimé'), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // Navigation : flèches retour et bouton retour du téléphone
  // -------------------------------------------------------------------

  testWidgets('Retour du téléphone sur un onglet → Accueil',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    expect(find.byType(ProfilScreen), findsOneWidget);

    await retourTelephone(tester);
    expect(find.byType(AccueilScreen), findsOneWidget);
  });

  testWidgets('Retour du téléphone sur un écran ouvert → écran précédent',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await toucherOnglet(tester, 'Profil');
    await toucher(tester, find.text('Paramètres'));
    expect(find.byType(ParametresScreen), findsOneWidget);

    await retourTelephone(tester);
    expect(find.byType(ProfilScreen), findsOneWidget);
  });

  testWidgets('Menu → Membres du quartier : la flèche ramène à l\'Accueil',
      (WidgetTester tester) async {
    await lancerApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await toucherDansMenu(tester, find.text('Membres du quartier'));
    expect(find.byType(AdminMembresScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(AccueilScreen), findsOneWidget);
  });

  testWidgets('Vérification et code du quartier : pas de flèche, déconnexion',
      (WidgetTester tester) async {
    mock.ajouterCompte(compteSansQuartier(), 'secret123');
    await mock.connexion('test@houmani.tn', 'secret123');
    appRouter.go('/verification');
    await lancerApp(tester);
    await tester.pumpAndSettle();

    // E-mail déjà vérifié : on arrive au choix du quartier, sans flèche
    expect(find.byType(CodeQuartierScreen), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnexionScreen), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // Apparence : mode sombre
  // -------------------------------------------------------------------

  group('Mode sombre', () {
    late Directory dossier;

    setUp(() {
      // Le choix est enregistré dans un dossier temporaire
      dossier = Directory.systemTemp.createTempSync('houmani_theme_');
      PreferenceTheme.cache = CacheLocal(dossier: dossier.path);
    });

    // Les réglages sont globaux : on remet le thème clair pour les autres tests
    tearDown(() {
      PreferenceTheme.mode.value = ModeTheme.systeme;
      AppColors.sombre = false;
      PreferenceTheme.cache = CacheLocal();
    });

    test('Système suit le téléphone, Clair et Sombre l\'ignorent', () {
      expect(PreferenceTheme.estSombre(ModeTheme.systeme, true), isTrue);
      expect(PreferenceTheme.estSombre(ModeTheme.systeme, false), isFalse);
      expect(PreferenceTheme.estSombre(ModeTheme.clair, true), isFalse);
      expect(PreferenceTheme.estSombre(ModeTheme.sombre, false), isTrue);
    });

    test('les couleurs changent avec AppColors.sombre', () {
      AppColors.sombre = false;
      final Color fondClair = AppColors.background;
      AppColors.sombre = true;
      expect(AppColors.background, isNot(fondClair));
      expect(AppTheme.actuel.brightness, Brightness.dark);
    });

    testWidgets('Paramètres : choisir Sombre puis Clair change tout l\'écran',
        (WidgetTester tester) async {
      appRouter.go('/parametres');
      await lancerApp(tester);
      final Color fondClair = AppColors.background;

      await toucher(tester, find.text('Sombre'));
      expect(PreferenceTheme.mode.value, ModeTheme.sombre);
      expect(AppColors.sombre, isTrue);
      // L'écran ouvert (const) est bien redessiné avec les couleurs sombres :
      // le fond (thème) et les séparateurs (lus dans AppColors)
      final BuildContext ecran = tester.element(find.byType(ParametresScreen));
      expect(Theme.of(ecran).scaffoldBackgroundColor, AppColors.background);
      expect(AppColors.background, isNot(fondClair));
      expect(tester.widget<Divider>(find.byType(Divider).first).color,
          AppColors.border);
      // Deux coches : "Sombre" (thème) et "Français" (langue)
      expect(find.byIcon(Icons.check), findsNWidgets(2));

      await toucher(tester, find.text('Clair'));
      expect(AppColors.sombre, isFalse);
      expect(AppColors.background, fondClair);
    });
  });

  // -------------------------------------------------------------------
  // Langue : français / derja
  // -------------------------------------------------------------------

  group('Langue', () {
    late Directory dossier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('houmani_langue_');
      PreferenceLangue.cache = CacheLocal(dossier: dossier.path);
    });

    // Réglage global : on remet le français pour les autres tests
    tearDown(() {
      PreferenceLangue.langue.value = Langue.francais;
      PreferenceLangue.cache = CacheLocal();
    });

    test('tr donne le texte de la langue choisie', () {
      expect(tr('Bonjour', 'Aslema'), 'Bonjour');
      PreferenceLangue.langue.value = Langue.derja;
      expect(tr('Bonjour', 'Aslema'), 'Aslema');
    });

    testWidgets('Paramètres : choisir Derja traduit l\'écran ouvert',
        (WidgetTester tester) async {
      appRouter.go('/parametres');
      await lancerApp(tester);
      expect(find.text('Paramètres'), findsOneWidget); // titre en haut

      await toucher(tester, find.text('Derja (tounsi)'));
      expect(PreferenceLangue.langue.value, Langue.derja);
      // La liste a défilé jusqu'à la section Langue : on regarde le titre
      // (toujours visible) et les sections proches
      expect(find.text('El paramètres'), findsOneWidget);
      expect(find.text('LOUGHA'), findsOneWidget);
      expect(find.text('Mdhallem'), findsOneWidget);
      expect(find.text('LANGUE'), findsNothing);

      await toucher(tester, find.text('Français'));
      expect(find.text('LANGUE'), findsOneWidget);
      expect(find.text('Paramètres'), findsOneWidget);
    });

    testWidgets('Profil : les liens sont en derja', (WidgetTester tester) async {
      PreferenceLangue.langue.value = Langue.derja;
      appRouter.go('/profil');
      await lancerApp(tester);
      expect(find.text('El profil mte3i'), findsOneWidget);
      expect(find.text('Houmti'), findsOneWidget);
      expect(find.text('Jirani'), findsOneWidget);
    });

    testWidgets('Connexion : textes et erreurs en derja',
        (WidgetTester tester) async {
      PreferenceLangue.langue.value = Langue.derja;
      appRouter.go('/connexion');
      await lancerApp(tester);
      expect(find.text('Od5ol l houmtek'), findsOneWidget);

      // Champs vides : les messages du formulaire sont en derja
      await toucher(tester, find.text('Od5ol'));
      expect(
        find.text('Ekteb el e-mail wala el nouméro mte3ek'),
        findsOneWidget,
      );
      expect(find.text('Ekteb el mot de passe mte3ek'), findsOneWidget);
    });

    testWidgets('Mot de passe oublié : écran en derja',
        (WidgetTester tester) async {
      PreferenceLangue.langue.value = Langue.derja;
      appRouter.go('/mot-de-passe-oublie');
      await lancerApp(tester);
      expect(find.text('Nsit kelmet esser'), findsOneWidget);
      expect(find.text('Ab3ath el lien'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // Mon quartier et changement de quartier
  // -------------------------------------------------------------------

  group('Mon quartier', () {
    // Le vrai GPS, remis après chaque test qui le remplace
    final positionParDefaut = Localisation.positionActuelle;

    // Pas de vraie carte : elle téléchargerait des images sur Internet
    setUp(() {
      MonQuartierScreen.afficherCarte = false;
    });

    tearDown(() {
      MonQuartierScreen.afficherCarte = true;
      Localisation.positionActuelle = positionParDefaut;
    });

    // Connecte un résident actif du quartier El Yasmine
    Future<void> connecterResident() async {
      mock.ajouterCompte(compteDeTest(StatutUtilisateur.actif), 'secret123');
      await mock.connexion('test@houmani.tn', 'secret123');
    }

    testWidgets('Admin : infos, carte et code d\'invitation, pas de changement',
        (WidgetTester tester) async {
      await lancerApp(tester);
      await toucherOnglet(tester, 'Profil');
      await toucher(tester, find.text('Mon quartier'));

      expect(find.byType(MonQuartierScreen), findsOneWidget);
      expect(find.text('Résidence El Yasmine'), findsOneWidget);
      expect(find.text('Ennasr 2, Ariana'), findsOneWidget);
      expect(find.text('YAS72B'), findsOneWidget);
      expect(find.byKey(const Key('carteQuartier')), findsOneWidget);
      expect(find.text('Changer de quartier'), findsNothing);
    });

    testWidgets('Menu → Mon quartier ouvre l\'écran',
        (WidgetTester tester) async {
      await lancerApp(tester);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await toucherDansMenu(tester, find.text('Mon quartier'));
      expect(find.byType(MonQuartierScreen), findsOneWidget);
    });

    testWidgets('Résident : nombre de membres, pas de code',
        (WidgetTester tester) async {
      await connecterResident();
      appRouter.go('/profil/quartier');
      await lancerApp(tester);

      expect(find.textContaining('membres'), findsOneWidget);
      expect(find.text('YAS72B'), findsNothing);
      expect(find.text('Changer de quartier'), findsOneWidget);
      // Seul l'admin trace les limites
      expect(find.text('Modifier les limites'), findsNothing);
      expect(find.text('Tracer les limites'), findsNothing);
    });

    testWidgets('Admin : modifier les limites (annuler un coin, enregistrer)',
        (WidgetTester tester) async {
      appRouter.go('/profil/quartier');
      await lancerApp(tester);

      await toucher(tester, find.text('Modifier les limites'));
      expect(find.byType(TracerLimitesScreen), findsOneWidget);
      // On repart du contour actuel (4 coins)
      expect(find.text('4 coins placés.'), findsOneWidget);

      await toucher(tester, find.text('Annuler le dernier'));
      expect(find.text('3 coins placés.'), findsOneWidget);

      await toucher(tester, find.text('Enregistrer'));
      expect(find.byType(MonQuartierScreen), findsOneWidget);
      expect(find.text('Limites enregistrées'), findsOneWidget);
      final quartier = (await mock.getQuartierConnecte()).donnee!;
      expect(quartier.contour.length, 3);
    });

    testWidgets('Tracer les limites : impossible d\'enregistrer sous 3 coins',
        (WidgetTester tester) async {
      appRouter.go('/profil/quartier/limites');
      await lancerApp(tester);

      await toucher(tester, find.text('Tout effacer'));
      expect(find.textContaining('0/3 minimum'), findsOneWidget);
      final PrimaryButton enregistrer =
          tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(enregistrer.onPressed, isNull);
    });

    testWidgets('Me localiser : sélectionne le quartier qui contient ma position',
        (WidgetTester tester) async {
      // Un point à l'intérieur du contour d'El Yasmine
      Localisation.positionActuelle = () async {
        return const Resultat.succes(PointGps(36.8625, 10.1700));
      };
      mock.ajouterCompte(compteSansQuartier(), 'secret123');
      await mock.connexion('test@houmani.tn', 'secret123');
      appRouter.go('/code-quartier');
      await lancerApp(tester);

      await toucher(tester, find.text('Me localiser'));
      expect(find.text('Tu es dans Résidence El Yasmine'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      final PrimaryButton rejoindre =
          tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(rejoindre.onPressed, isNotNull);
    });

    testWidgets('Me localiser : aucun quartier à cette position',
        (WidgetTester tester) async {
      Localisation.positionActuelle = () async {
        return const Resultat.succes(PointGps(48.85, 2.35)); // Paris
      };
      mock.ajouterCompte(compteSansQuartier(), 'secret123');
      await mock.connexion('test@houmani.tn', 'secret123');
      appRouter.go('/code-quartier');
      await lancerApp(tester);

      await toucher(tester, find.text('Me localiser'));
      expect(find.textContaining('Aucun quartier trouvé à ta position'),
          findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    });

    testWidgets('Me localiser : GPS refusé → message',
        (WidgetTester tester) async {
      Localisation.positionActuelle = () async {
        return const Resultat.echec('Autorise Houmani à utiliser ta position');
      };
      mock.ajouterCompte(compteSansQuartier(), 'secret123');
      await mock.connexion('test@houmani.tn', 'secret123');
      appRouter.go('/code-quartier');
      await lancerApp(tester);

      await toucher(tester, find.text('Me localiser'));
      expect(find.text('Autorise Houmani à utiliser ta position'), findsOneWidget);
    });

    testWidgets('Quartier sans coordonnées : message à la place de la carte',
        (WidgetTester tester) async {
      mock.ajouterCompte(
        compteDeTest(StatutUtilisateur.actif)
            .copier(quartierId: 'q2', quartier: 'Cité El Wafa'),
        'secret123',
      );
      await mock.connexion('test@houmani.tn', 'secret123');
      appRouter.go('/profil/quartier');
      await lancerApp(tester);

      expect(find.byKey(const Key('carteQuartier')), findsNothing);
      expect(
        find.text('La carte du quartier n\'est pas encore disponible.'),
        findsOneWidget,
      );
    });

    testWidgets('Résident : changer de quartier demande une confirmation',
        (WidgetTester tester) async {
      await connecterResident();
      appRouter.go('/profil/quartier');
      await lancerApp(tester);

      await toucher(tester, find.text('Changer de quartier'));
      expect(find.byType(CodeQuartierScreen), findsOneWidget);
      // Mode changement : flèche retour, pas de déconnexion,
      // et le quartier actuel n'est pas proposé
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Se déconnecter'), findsNothing);
      expect(find.text('Résidence El Yasmine'), findsNothing);

      await toucher(tester, find.text('Cité El Wafa'));
      await toucher(tester, find.text('Rejoindre la houma'));
      expect(find.text('Changer de quartier ?'), findsOneWidget);

      // Annuler : rien ne change
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(CodeQuartierScreen), findsOneWidget);
      expect(mock.getUtilisateurConnecte().quartierId, 'q1');

      await toucher(tester, find.text('Rejoindre la houma'));
      await tester.tap(find.text('Changer'));
      await tester.pumpAndSettle();
      expect(find.byType(AttenteValidationScreen), findsOneWidget);
      expect(mock.getUtilisateurConnecte().quartierId, 'q2');
      expect(
        mock.getUtilisateurConnecte().statut,
        StatutUtilisateur.enAttente,
      );
    });
  });
}

/// Simule le bouton retour du téléphone.
Future<void> retourTelephone(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Remplit, dans l'ordre, les champs de la fenêtre ouverte.
Future<void> remplirDialogue(WidgetTester tester, List<String> valeurs) async {
  final Finder champs = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextFormField),
  );
  for (int i = 0; i < valeurs.length; i++) {
    await tester.enterText(champs.at(i), valeurs[i]);
  }
  await tester.pump();
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
