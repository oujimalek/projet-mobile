import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/quartier.dart' show PointGps;
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/services/base_locale_m4.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module4/evenement_detail_screen.dart';
import 'package:houmani/screens/module4/evenement_form_screen.dart';
import 'package:houmani/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;

import 'fausse_connexion_m3.dart';
import 'mock_evenement_repository.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

Future<void> afficher(WidgetTester tester, Widget ecran,
    {Size taille = const Size(360, 2200)}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Écran vide d'abord : un 2e afficher() dans le même test crée un écran
  // neuf (sinon Flutter garderait l'état du précédent, même type)
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

const PointGps parking = PointGps(36.8625, 10.17);

/// Un signalement de Salma, ouvert, avec un point GPS.
Signalement signalement(
  String id,
  String categorieId, {
  StatutSignalement statut = StatutSignalement.enAttente,
  String titre = 'Sacs d\'ordures devant le bloc C',
}) {
  return Signalement(
    id: id,
    titre: titre,
    description: 'Description assez longue',
    categorieId: categorieId,
    statut: statut,
    date: DateTime.now().subtract(const Duration(hours: 2)),
    lieu: 'Devant le bloc C',
    auteurId: 'u21',
    auteurNom: 'Salma G.',
    position: parking,
  );
}

Utilisateur voisin(String id, String prenom, RoleUtilisateur role) {
  return Utilisateur(
    id: id,
    prenom: prenom,
    nom: 'Test',
    email: '${prenom.toLowerCase()}@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc A',
    role: role,
  );
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;
  late MockEvenementRepository evenements;
  final Utilisateur leila = voisin('u30', 'Leila', RoleUtilisateur.leader);
  final Utilisateur youssef = voisin('u31', 'Youssef', RoleUtilisateur.resident);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    utilisateurs = MockUtilisateurRepository(); // Amira, admin
    UtilisateurRepository.instance = utilisateurs;
    utilisateurs.ajouterCompte(leila, 'pw');
    utilisateurs.ajouterCompte(youssef, 'pw');
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3(); // installe aussi MockEvenementRepository
    evenements = EvenementRepository.instance as MockEvenementRepository;
    // Le formulaire du module 4 garde ses brouillons dans SA base SQLite :
    // en mémoire et neuve à chaque test (comme module4_sqlite_test.dart)
    BaseLocaleM4.cheminPourTests = inMemoryDatabasePath;
    depot.ajouterTelQuel(signalement('ord', 'ordures'));
    depot.ajouterTelQuel(signalement('trav', 'travaux', titre: 'Trottoir défoncé'));
    depot.ajouterTelQuel(signalement('eau', 'eau', titre: 'Fuite'));
  });

  tearDown(() async {
    AppColors.sombre = false;
    await BaseLocaleM4.fermer();
    await nettoyerHorsLigneM3(connexion);
  });

  Future<void> devenir(Utilisateur u) => utilisateurs.connexion(u.email, 'pw');

  /// Un événement déjà organisé pour le signalement [id].
  Evenement evenementLie(String id, {DateTime? date, bool annule = false}) {
    return evenements.ajouterEvenementDe(
      leila,
      titre: 'Nettoyage : Sacs d\'ordures devant le bloc C',
      categorie: CategorieEvenement.nettoyage,
      date: date,
      annule: annule,
      signalementId: id,
      signalementTitre: 'Sacs d\'ordures devant le bloc C',
    );
  }

  // =====================================================================
  group('M4 : modèle et dépôt', () {
    test('toMap / fromMap gardent le lien ; copyWith le garde', () {
      final Evenement fete = Evenement(
        id: 'e', titre: 'Nettoyage', description: '', lieu: 'Bloc C',
        date: DateTime(2026, 12, 1), organisateur: 'Leila T.',
        signalementId: 'ord', signalementTitre: 'Sacs d\'ordures',
      );
      final Map<String, dynamic> map = fete.toMap();
      expect(map['signalementId'], 'ord');
      expect(map['signalementTitre'], 'Sacs d\'ordures');
      final Evenement relu = Evenement.fromMap('e', map);
      expect(relu.signalementId, 'ord');
      expect(relu.signalementTitre, 'Sacs d\'ordures');
      expect(relu.copyWith(titre: 'Autre').signalementId, 'ord');
      expect(Evenement.fromMap('x', {}).signalementId, isNull);
    });

    test('créer avec le lien, puis les événements d\'un signalement (triés)',
        () async {
      await devenir(leila);
      final DateTime dans3 = DateTime.now().add(const Duration(days: 3));
      final DateTime dans1 = DateTime.now().add(const Duration(days: 1));
      for (final DateTime date in [dans3, dans1]) {
        expect(
          (await EvenementRepository().creerEvenement(
            titre: 'Nettoyage', description: '', date: date, lieu: 'Bloc C',
            categorie: CategorieEvenement.nettoyage,
            signalementId: 'ord', signalementTitre: 'Sacs d\'ordures',
          ))
              .estSucces,
          isTrue,
        );
      }
      await EvenementRepository().creerEvenement(
        titre: 'Fête', description: '', date: dans1, lieu: 'Jardin',
        categorie: CategorieEvenement.fete,
      );
      final List<Evenement> lies =
          (await EvenementRepository().getEvenementsDuSignalement('ord')).donnee!;
      expect(lies.length, 2);
      expect(lies.first.date, dans1);
      expect(lies.every((e) => e.signalementTitre == 'Sacs d\'ordures'), isTrue);
      expect((await EvenementRepository().getEvenementsDuSignalement('autre'))
          .donnee, isEmpty);
      // Sans lien : comme avant
      expect(evenements.evenements.last.signalementId, isNull);
    });

    test('dépôt en erreur : échec', () async {
      evenements.erreur = 'Pas de connexion Internet';
      expect((await EvenementRepository().getEvenementsDuSignalement('ord')).erreur,
          'Pas de connexion Internet');
    });
  });

  group('M4 : formulaire et détail', () {
    testWidgets('Formulaire pré-rempli (nouvel événement) et lien enregistré',
        (WidgetTester tester) async {
      await devenir(leila);
      await afficher(
        tester,
        EvenementFormScreen(
          titreInitial: 'Nettoyage : Sacs d\'ordures',
          categorieInitiale: CategorieEvenement.nettoyage,
          dateInitiale: DateTime.now().add(const Duration(days: 2)),
          lieuInitial: 'Devant le bloc C',
          positionInitiale: parking,
          signalementId: 'ord',
          signalementTitre: 'Sacs d\'ordures',
        ),
        taille: const Size(800, 2200),
      );
      expect(find.text('Nettoyage : Sacs d\'ordures'), findsOneWidget);
      expect(find.text('Devant le bloc C'), findsOneWidget);

      await tester.tap(find.text('Publier l\'événement'));
      await tester.pumpAndSettle();
      final Evenement cree = evenements.evenements.single;
      expect(cree.signalementId, 'ord');
      expect(cree.signalementTitre, 'Sacs d\'ordures');
      expect(cree.position!.latitude, 36.8625);
      expect(cree.categorie, CategorieEvenement.nettoyage);
    });

    testWidgets('Modification d\'un événement : le pré-remplissage est ignoré',
        (WidgetTester tester) async {
      final Evenement existant = evenements.ajouterEvenementDe(
          leila, titre: 'Fête', lieu: 'Jardin');
      await afficher(
        tester,
        EvenementFormScreen(evenement: existant, lieuInitial: 'Ailleurs'),
        taille: const Size(800, 2200),
      );
      expect(find.text('Jardin'), findsOneWidget);
      expect(find.text('Ailleurs'), findsNothing);
    });

    testWidgets('Détail : « Suite au signalement », qui ouvre le signalement',
        (WidgetTester tester) async {
      final Evenement lie = evenementLie('ord');
      await afficher(tester, EvenementDetailScreen(evenementId: lie.id),
          taille: const Size(800, 2200));
      expect(find.text('Suite au signalement : Sacs d\'ordures devant le bloc C'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lien_signalement')));
      await tester.pumpAndSettle();
      expect(find.byType(SignalementDetailScreen), findsOneWidget);
    });

    testWidgets('Détail sans lien : pas de ligne', (WidgetTester tester) async {
      final Evenement fete = evenements.ajouterEvenementDe(leila);
      await afficher(tester, EvenementDetailScreen(evenementId: fete.id),
          taille: const Size(800, 2200));
      expect(find.byKey(const ValueKey('lien_signalement')), findsNothing);
    });
  });

  // =====================================================================
  group('M3 : règle du bouton et correspondances', () {
    test('Ordures → nettoyage, travaux → réunion, sinon rien', () {
      expect(SignalementRepository.categorieEvenementPour('ordures'),
          CategorieEvenement.nettoyage);
      expect(SignalementRepository.categorieEvenementPour('travaux'),
          CategorieEvenement.reunion);
      for (final String autre in ['eau', 'electricite', 'incident']) {
        expect(SignalementRepository.categorieEvenementPour(autre), isNull);
      }
    });

    test('Titre : « Nettoyage : … », « Réunion : … », raccourci à 80', () {
      expect(SignalementRepository.titreEvenementPour(signalement('o', 'ordures')),
          'Nettoyage : Sacs d\'ordures devant le bloc C');
      expect(
          SignalementRepository.titreEvenementPour(
              signalement('t', 'travaux', titre: 'Trottoir défoncé')),
          'Réunion : Trottoir défoncé');
      final String long = SignalementRepository.titreEvenementPour(
          signalement('l', 'travaux', titre: 'a' * 80));
      expect(long.length, EvenementRepository.titreMax);
      expect(long, endsWith('…'));
      expect(long, startsWith('Réunion : '));
    });

    test('Visible : leader ou admin, ouvert, ordures ou travaux', () {
      final Utilisateur admin = utilisateurs.getUtilisateurConnecte();
      bool peut(Utilisateur u, Signalement s) =>
          SignalementRepository.peutOrganiserEvenement(u, s);

      expect(peut(admin, signalement('o', 'ordures')), isTrue);
      expect(peut(leila, signalement('t', 'travaux')), isTrue);
      expect(peut(leila,
              signalement('o', 'ordures', statut: StatutSignalement.enCours)),
          isTrue);
      expect(peut(youssef, signalement('o', 'ordures')), isFalse); // résident
      expect(peut(leila, signalement('e', 'eau')), isFalse); // catégorie
      expect(peut(leila, signalement('i', 'incident')), isFalse);
      expect(peut(leila,
              signalement('o', 'ordures', statut: StatutSignalement.resolu)),
          isFalse);
      expect(peut(admin,
              signalement('o', 'ordures', statut: StatutSignalement.refuse)),
          isFalse);
    });
  });

  group('M3 : détail du signalement', () {
    testWidgets('Leader : le bouton ouvre le formulaire pré-rempli',
        (WidgetTester tester) async {
      await devenir(leila);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      await tester.tap(find.byKey(const ValueKey('organiser_evenement')));
      await tester.pumpAndSettle();

      final EvenementFormScreen formulaire =
          tester.widget(find.byType(EvenementFormScreen));
      expect(formulaire.titreInitial, 'Nettoyage : Sacs d\'ordures devant le bloc C');
      expect(formulaire.categorieInitiale, CategorieEvenement.nettoyage);
      expect(formulaire.lieuInitial, 'Devant le bloc C');
      expect(formulaire.positionInitiale!.latitude, 36.8625);
      expect(formulaire.signalementId, 'ord');
      expect(formulaire.signalementTitre, 'Sacs d\'ordures devant le bloc C');
      expect(formulaire.evenement, isNull);
    });

    testWidgets('Après la création : message et section à jour',
        (WidgetTester tester) async {
      await devenir(leila);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('evenements_lies')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('organiser_evenement')));
      await tester.pumpAndSettle();

      // Comme une publication réussie : l'événement existe, le formulaire
      // se ferme avec "true"
      evenementLie('ord', date: DateTime.now().add(const Duration(days: 3)));
      Navigator.of(tester.element(find.byType(EvenementFormScreen))).pop(true);
      await tester.pumpAndSettle();

      expect(find.text('Événement organisé : les voisins sont prévenus.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('evenements_lies')), findsOneWidget);
      expect(find.text('Nettoyage : Sacs d\'ordures devant le bloc C'),
          findsOneWidget);
    });

    testWidgets('Résident, ou catégorie eau, ou résolu : pas de bouton',
        (WidgetTester tester) async {
      await devenir(youssef);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('organiser_evenement')), findsNothing);

      await devenir(leila);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'eau'));
      expect(find.byKey(const ValueKey('organiser_evenement')), findsNothing);

      depot.ajouterTelQuel(
          signalement('fini', 'travaux', statut: StatutSignalement.resolu));
      await afficher(tester, const SignalementDetailScreen(signalementId: 'fini'));
      expect(find.byKey(const ValueKey('organiser_evenement')), findsNothing);

      // Contrôle : le même leader voit bien le bouton sur un travaux ouvert
      await afficher(tester, const SignalementDetailScreen(signalementId: 'trav'));
      expect(find.byKey(const ValueKey('organiser_evenement')), findsOneWidget);
    });

    testWidgets('Admin, travaux en cours : bouton « réunion »',
        (WidgetTester tester) async {
      await depot.changerStatut('trav', StatutSignalement.enCours);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'trav'));
      await tester.tap(find.byKey(const ValueKey('organiser_evenement')));
      await tester.pumpAndSettle();
      final EvenementFormScreen formulaire =
          tester.widget(find.byType(EvenementFormScreen));
      expect(formulaire.categorieInitiale, CategorieEvenement.reunion);
      expect(formulaire.titreInitial, 'Réunion : Trottoir défoncé');
    });

    testWidgets('Section : date, titre, participants ; toucher → l\'événement',
        (WidgetTester tester) async {
      final Evenement lie =
          evenementLie('ord', date: DateTime(2026, 12, 5, 9, 30));
      await devenir(youssef); // un résident voit aussi la section
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.text('Événement organisé'), findsOneWidget);
      expect(find.text('5/12/2026 à 09:30 · 0 participant'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('evenement_lie_${lie.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(EvenementDetailScreen), findsOneWidget);
    });

    testWidgets('Hors ligne : section et bouton cachés',
        (WidgetTester tester) async {
      evenementLie('ord');
      await SyncSignalementsM3.instance.chargerSignalements(); // cache rempli
      connexion.enLigne = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('evenements_lies')), findsNothing);
      expect(find.byKey(const ValueKey('organiser_evenement')), findsNothing);
    });

    testWidgets('Module 4 en erreur : section cachée, le reste s\'affiche',
        (WidgetTester tester) async {
      evenementLie('ord');
      evenements.erreur = 'Pas de connexion Internet';
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('evenements_lies')), findsNothing);
      expect(find.byKey(const ValueKey('historique')), findsOneWidget);
    });

    testWidgets('Admin : événement passé, signalement ouvert → « marquer résolu »',
        (WidgetTester tester) async {
      evenementLie('ord', date: DateTime.now().subtract(const Duration(days: 1)));
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.text('L\'événement a eu lieu — marquer comme résolu ?'),
          findsOneWidget);

      await tester.tap(find.text('Marquer comme résolu'));
      await tester.pumpAndSettle();
      expect(find.text('Passer à « Résolu »'), findsOneWidget); // même fenêtre
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(depot.tous.firstWhere((s) => s.id == 'ord').statut,
          StatutSignalement.resolu);
      expect(find.byKey(const ValueKey('conseil_resolu')), findsNothing);
    });

    testWidgets('Pas de conseil : événement à venir, annulé, ou simple résident',
        (WidgetTester tester) async {
      evenementLie('ord', date: DateTime.now().add(const Duration(days: 2)));
      evenementLie('ord',
          date: DateTime.now().subtract(const Duration(days: 1)), annule: true);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('conseil_resolu')), findsNothing);

      evenementLie('ord', date: DateTime.now().subtract(const Duration(days: 1)));
      // Le leader gère le statut comme l'admin : il voit le conseil
      await devenir(leila);
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('conseil_resolu')), findsOneWidget);

      await devenir(youssef); // simple résident
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('conseil_resolu')), findsNothing);
    });

    testWidgets('Mode sombre, 360 px : section et bouton sans erreur',
        (WidgetTester tester) async {
      AppColors.sombre = true;
      evenementLie('ord', date: DateTime.now().subtract(const Duration(days: 1)));
      await afficher(tester, const SignalementDetailScreen(signalementId: 'ord'));
      expect(find.byKey(const ValueKey('organiser_evenement')), findsOneWidget);
      expect(find.byKey(const ValueKey('conseil_resolu')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
