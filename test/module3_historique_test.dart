import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/historique_signalement.dart';
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/models/utilisateur.dart';
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
  tester.view.physicalSize = const Size(360, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

/// Un texte DANS la carte de l'historique (le détail affiche aussi
/// "Signalé par ..." dans ses informations).
Finder dansHistorique(String texte) => find.descendant(
      of: find.byKey(const ValueKey('historique')),
      matching: find.text(texte),
    );

Signalement saisie() {
  return Signalement(
    id: '',
    titre: 'Lampadaire en panne',
    description: 'Le lampadaire ne s\'allume plus',
    categorieId: 'electricite',
    statut: StatutSignalement.enAttente,
    date: DateTime.now(),
    lieu: 'Bloc C',
    auteurId: '',
    auteurNom: '',
  );
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;
  final Utilisateur salma = Utilisateur(
    id: 'u21',
    prenom: 'Salma',
    nom: 'Gharbi',
    email: 'salma@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc A',
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    utilisateurs = MockUtilisateurRepository(); // Amira, admin
    UtilisateurRepository.instance = utilisateurs;
    utilisateurs.ajouterCompte(salma, 'pw');
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
  });

  tearDown(() async {
    AppColors.sombre = false;
    await nettoyerHorsLigneM3(connexion);
  });

  group('Modèle et règles', () {
    test('toMap puis fromMap redonne la même étape', () {
      final EntreeHistorique etape = EntreeHistorique(
        statut: StatutSignalement.refuse,
        note: 'Déjà signalé à la municipalité',
        date: DateTime(2026, 11, 12, 9, 30),
        parId: 'u1',
        parNom: 'Amira B.',
      );
      final Map<String, dynamic> map = etape.toMap();
      expect(map.keys.toSet(), {'statut', 'note', 'date', 'parId', 'parNom'});
      map['date'] = Timestamp.fromDate(map['date']);
      final EntreeHistorique relue = EntreeHistorique.fromMap('e1', map);
      expect(relue.id, 'e1');
      expect(relue.statut, StatutSignalement.refuse);
      expect(relue.note, 'Déjà signalé à la municipalité');
      expect(relue.date, DateTime(2026, 11, 12, 9, 30));
      expect(relue.parNom, 'Amira B.');
    });

    test('Document incomplet : valeurs par défaut', () {
      final EntreeHistorique relue = EntreeHistorique.fromMap('e', {'statut': '?'});
      expect(relue.statut, StatutSignalement.enAttente);
      expect(relue.note, '');
      expect(relue.parId, '');
    });

    test('Note : optionnelle, 200 caractères au plus ; obligatoire pour refuser', () {
      expect(SignalementRepository.refusNote(StatutSignalement.enCours, ''), isNull);
      expect(SignalementRepository.refusNote(StatutSignalement.resolu, 'a' * 200),
          isNull);
      expect(SignalementRepository.refusNote(StatutSignalement.resolu, 'a' * 201),
          'La note doit avoir au plus 200 caractères');
      const String explique =
          'Explique pourquoi le signalement est refusé (3 à 200 caractères)';
      expect(SignalementRepository.refusNote(StatutSignalement.refuse, ''), explique);
      expect(SignalementRepository.refusNote(StatutSignalement.refuse, '  ok  '),
          explique);
      expect(SignalementRepository.refusNote(StatutSignalement.refuse, 'Doublon'),
          isNull);
    });
  });

  group('Repository (mock)', () {
    test('Créer : 1re étape "en attente" par l\'auteur, avec la création',
        () async {
      await SignalementRepository().ajouterSignalement(saisie());
      final String id = depot.tous.last.id;
      final List<EntreeHistorique> etapes =
          (await SignalementRepository().getHistorique(id)).donnee!;
      expect(etapes.length, 1);
      expect(etapes.single.statut, StatutSignalement.enAttente);
      expect(etapes.single.parId, 'u1');
      expect(etapes.single.parNom, 'Amira B.');
    });

    test('Envoyé depuis la file hors ligne : la 1re étape aussi', () async {
      connexion.enLigne = false;
      await SyncSignalementsM3.instance.publier(saisie());
      connexion.enLigne = true;
      await SyncSignalementsM3.instance.envoyerFile();
      expect(depot.historiqueDe(depot.tous.last.id).single.statut,
          StatutSignalement.enAttente);
    });

    test('L\'admin change le statut : une étape avec sa note, dans l\'ordre',
        () async {
      await SignalementRepository().ajouterSignalement(saisie());
      final String id = depot.tous.last.id;
      await SignalementRepository().changerStatut(id, StatutSignalement.enCours,
          note: '  Intervention prévue jeudi  ');
      await SignalementRepository().changerStatut(id, StatutSignalement.resolu);
      final List<EntreeHistorique> etapes =
          (await SignalementRepository().getHistorique(id)).donnee!;
      expect(etapes.map((e) => e.statut), [
        StatutSignalement.enAttente,
        StatutSignalement.enCours,
        StatutSignalement.resolu,
      ]);
      expect(etapes[1].note, 'Intervention prévue jeudi'); // espaces enlevés
      expect(etapes[2].note, '');
    });

    test('Même statut : rien ne change ; refuser sans raison : refusé', () async {
      expect(
          (await SignalementRepository().changerStatut('r1', StatutSignalement.enCours))
              .estSucces,
          isTrue);
      expect(depot.historiqueDe('r1'), isEmpty);

      final resultat = await SignalementRepository()
          .changerStatut('r3', StatutSignalement.refuse);
      expect(resultat.erreur,
          'Explique pourquoi le signalement est refusé (3 à 200 caractères)');
      expect(depot.tous.firstWhere((s) => s.id == 'r3').statut,
          StatutSignalement.enAttente);
      expect(depot.historiqueDe('r3'), isEmpty);
    });

    test('Un résident ne change pas le statut (ni l\'historique)', () async {
      await utilisateurs.connexion('salma@houmani.tn', 'pw');
      final resultat = await SignalementRepository()
          .changerStatut('r3', StatutSignalement.enCours, note: 'Je m\'en occupe');
      expect(resultat.erreur, 'Seul l\'admin du quartier peut changer le statut');
      expect(depot.historiqueDe('r3'), isEmpty);
    });
  });

  group('Écran : historique et note de l\'admin', () {
    testWidgets('Signalement sans historique : sa création seulement',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.byKey(const ValueKey('historique')), findsOneWidget);
      expect(dansHistorique('Signalé par Salma G.'), findsOneWidget);
    });

    testWidgets('L\'admin passe "en cours" avec une note : nouvelle étape',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.text('En cours').last);
      await tester.pumpAndSettle();
      expect(find.text('Passer à « En cours »'), findsOneWidget);
      expect(find.text('Note pour les voisins (optionnelle)'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('note_statut')), 'Intervention prévue jeudi');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(depot.tous.firstWhere((s) => s.id == 'r3').statut,
          StatutSignalement.enCours);
      expect(find.text('« Intervention prévue jeudi »'), findsOneWidget);
      expect(dansHistorique('Par Amira B.'), findsOneWidget);
      // Signalement d'avant l'historique : sa création est refaite en 1er
      expect(dansHistorique('Signalé par Salma G.'), findsOneWidget);
    });

    testWidgets('Refuser : la raison est obligatoire', (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.text('Refusé').last);
      await tester.pumpAndSettle();
      expect(find.text('Raison du refus (obligatoire)'), findsOneWidget);

      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Explique pourquoi le signalement est refusé (3 à 200 caractères)'),
          findsOneWidget);
      expect(depot.tous.firstWhere((s) => s.id == 'r3').statut,
          StatutSignalement.enAttente);

      await tester.enterText(
          find.byKey(const ValueKey('note_statut')), 'Déjà signalé à la municipalité');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(depot.tous.firstWhere((s) => s.id == 'r3').statut,
          StatutSignalement.refuse);
      expect(find.text('« Déjà signalé à la municipalité »'), findsOneWidget);
    });

    testWidgets('Annuler : le statut ne change pas', (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      await tester.tap(find.text('Résolu').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(depot.tous.firstWhere((s) => s.id == 'r3').statut,
          StatutSignalement.enAttente);
      expect(depot.historiqueDe('r3'), isEmpty);
    });

    testWidgets('Signalement créé dans l\'app : toutes ses étapes, dans l\'ordre',
        (WidgetTester tester) async {
      await SignalementRepository().ajouterSignalement(saisie());
      final String id = depot.tous.last.id;
      await SignalementRepository()
          .changerStatut(id, StatutSignalement.enCours, note: 'On y va');
      await afficher(tester, SignalementDetailScreen(signalementId: id));
      final double yCreation =
          tester.getTopLeft(dansHistorique('Signalé par Amira B.')).dy;
      final double yNote = tester.getTopLeft(find.text('« On y va »')).dy;
      expect(yCreation < yNote, isTrue);
    });

    testWidgets('Hors ligne : message à la place de l\'historique',
        (WidgetTester tester) async {
      await SyncSignalementsM3.instance.chargerSignalements(); // cache rempli
      connexion.enLigne = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.text('L\'historique s\'affiche avec la connexion.'), findsOneWidget);
    });

    testWidgets('Mode sombre, 360 px : affichage sans erreur',
        (WidgetTester tester) async {
      AppColors.sombre = true;
      await SignalementRepository()
          .changerStatut('r3', StatutSignalement.refuse, note: 'Déjà traité hier');
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.text('« Déjà traité hier »'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
