import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart : ce fichier compile même sans
// lib/firebase_options.dart (fichier Firebase absent du dépôt).
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/models/quartier.dart' show PointGps;
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/signalements_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

/// Affiche un écran dans une MaterialApp avec le thème Houmani.
/// Par défaut : largeur d'un téléphone (360), assez haut pour tout voir.
Future<void> afficher(
  WidgetTester tester,
  Widget ecran, {
  Size taille = const Size(360, 1600),
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

/// Fait défiler jusqu'au widget (ex : un filtre caché à droite), puis le touche.
Future<void> toucher(WidgetTester tester, Finder cible) async {
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
}

/// Un voisin actif du quartier q1 (comme Amira, le compte du mock du module 1).
Utilisateur voisin(String id, String prenom, String nom) {
  return Utilisateur(
    id: id,
    prenom: prenom,
    nom: nom,
    email: '$prenom@houmani.tn'.toLowerCase(),
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc A',
  );
}

/// Un signalement de test (les champs non donnés ont une valeur simple).
Signalement exemple({
  String id = 'x',
  String categorieId = 'travaux',
  StatutSignalement statut = StatutSignalement.enAttente,
  DateTime? date,
  int nbConfirmations = 0,
  bool danger = false,
}) {
  return Signalement(
    id: id,
    titre: 'Titre de test',
    description: 'Une description assez longue',
    categorieId: categorieId,
    statut: statut,
    date: date ?? DateTime(2026, 10, 1),
    lieu: 'Bloc A',
    auteurId: 'u99',
    auteurNom: 'Test T.',
    nbConfirmations: nbConfirmations,
    danger: danger,
  );
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion; // en ligne par défaut

  // Les auteurs des signalements de démo du mock :
  //   r1 (enCours, électricité, danger) : Amira u1, admin, connectée par défaut
  //   r2 (resolu, ordures)              : Youssef u22
  //   r3 (enAttente, eau)               : Salma u21
  //   r4 (refuse, travaux)              : Karim u20
  final Utilisateur salma = voisin('u21', 'Salma', 'Gharbi');
  final Utilisateur karim = voisin('u20', 'Karim', 'Mansour');
  final Utilisateur youssef = voisin('u22', 'Youssef', 'Trabelsi');

  // Pas de téléchargement de police pendant les tests (pas d'Internet)
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Chaque test repart des données de démo, avec Amira connectée.
  setUp(() {
    utilisateurs = MockUtilisateurRepository();
    UtilisateurRepository.instance = utilisateurs;
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    utilisateurs.ajouterCompte(salma, 'pw');
    utilisateurs.ajouterCompte(karim, 'pw');
    utilisateurs.ajouterCompte(youssef, 'pw');
    // SQLite en mémoire + fausse connexion (voir outils_test_m3.dart)
    connexion = installerHorsLigneM3();
  });

  tearDown(() async {
    await nettoyerHorsLigneM3(connexion);
  });

  /// Change l'utilisateur connecté.
  Future<void> devenir(Utilisateur utilisateur) async {
    await utilisateurs.connexion(utilisateur.email, 'pw');
  }

  /// Le signalement [id] tel qu'il est dans le mock.
  Signalement lire(String id) {
    return depot.tous.firstWhere((s) => s.id == id);
  }

  // =====================================================================
  group('Modèle : Firestore', () {
    test('toMap écrit exactement les champs du schéma, sans l\'id', () {
      final Map<String, dynamic> map = exemple(id: 'abc', danger: true).toMap();
      expect(map.keys.toSet(), {
        'titre',
        'description',
        'categorieId',
        'statut',
        'date',
        'lieu',
        'auteurId',
        'auteurNom',
        'nbConfirmations',
        'danger',
      });
      expect(map['statut'], 'enAttente');
      expect(map['danger'], true);
    });

    test('toMap puis fromMap redonne le même signalement', () {
      final Signalement depart = exemple(
        id: 's1',
        categorieId: 'eau',
        statut: StatutSignalement.enCours,
        date: DateTime(2026, 10, 1, 14, 30),
        nbConfirmations: 7,
        danger: true,
      );
      final Map<String, dynamic> map = depart.toMap();
      // Firestore range un DateTime en Timestamp
      map['date'] = Timestamp.fromDate(map['date']);

      final Signalement relu = Signalement.fromMap('s1', map);
      expect(relu.id, 's1');
      expect(relu.titre, depart.titre);
      expect(relu.description, depart.description);
      expect(relu.categorieId, 'eau');
      expect(relu.statut, StatutSignalement.enCours);
      expect(relu.date, DateTime(2026, 10, 1, 14, 30));
      expect(relu.lieu, 'Bloc A');
      expect(relu.auteurId, 'u99');
      expect(relu.auteurNom, 'Test T.');
      expect(relu.nbConfirmations, 7);
      expect(relu.danger, isTrue);
      expect(relu.photoUrl, isNull);
      expect(relu.position, isNull);
      expect(map.containsKey('position'), isFalse); // champ optionnel
    });

    test('Position : écrite en GeoPoint, relue en PointGps', () {
      final Signalement avecPoint =
          exemple().copyWith(position: const PointGps(36.8625, 10.17));
      final Map<String, dynamic> map = avecPoint.toMap();
      expect(map['position'], isA<GeoPoint>());
      expect((map['position'] as GeoPoint).latitude, 36.8625);

      final Signalement relu = Signalement.fromMap('s1', map);
      expect(relu.position!.latitude, 36.8625);
      expect(relu.position!.longitude, 10.17);
    });

    test('fromMap d\'un document incomplet : valeurs par défaut', () {
      final Signalement relu = Signalement.fromMap('vide', {
        'statut': 'inconnu',
        'nbConfirmations': 'pas un nombre',
      });
      expect(relu.titre, '');
      expect(relu.categorieId, 'incident');
      expect(relu.statut, StatutSignalement.enAttente);
      expect(relu.nbConfirmations, 0);
      expect(relu.danger, isFalse);
    });

    test('copyWith ne change que les champs donnés', () {
      final Signalement copie = exemple().copyWith(
        statut: StatutSignalement.resolu,
        nbConfirmations: 3,
      );
      expect(copie.statut, StatutSignalement.resolu);
      expect(copie.nbConfirmations, 3);
      expect(copie.titre, 'Titre de test');
      expect(copie.estCloture, isTrue);
    });
  });

  // =====================================================================
  group('Règles métier (static)', () {
    test('refusSignalement : un message par erreur, null si tout va bien', () {
      String? refus({
        String titre = 'Lampadaire',
        String description = 'Le lampadaire est en panne',
        String lieu = 'Bloc C',
        String? categorieId = 'electricite',
      }) {
        return SignalementRepository.refusSignalement(
          titre: titre,
          description: description,
          lieu: lieu,
          categorieId: categorieId,
        );
      }

      expect(refus(), isNull);
      expect(refus(categorieId: null), 'Choisis une catégorie');
      expect(refus(categorieId: 'piscine'), 'Choisis une catégorie');
      expect(refus(titre: ' ab '), 'Le titre doit avoir au moins 3 caractères');
      expect(refus(titre: 'a' * 81), 'Le titre doit avoir au plus 80 caractères');
      expect(refus(description: 'court'),
          'La description doit avoir au moins 10 caractères');
      expect(refus(lieu: ' '), 'Indique le lieu du problème');
    });

    test('Catégories : 5, et "incident" pour un id inconnu', () {
      expect(SignalementRepository.categories.length, 5);
      expect(SignalementRepository.getCategorieParId('eau').nom, 'Eau');
      expect(SignalementRepository.getCategorieParId('???').id, 'incident');
    });

    test('Score d\'urgence : catégorie + danger + confirmations', () {
      int score(String categorie, {bool danger = false, int nb = 0}) {
        return SignalementRepository.scoreUrgence(
          exemple(categorieId: categorie, danger: danger, nbConfirmations: nb),
        );
      }

      expect(score('travaux'), 1);
      expect(score('ordures'), 1);
      expect(score('eau'), 2);
      expect(score('incident', danger: true), 4);
      expect(score('travaux', nb: 2), 1);
      expect(score('travaux', nb: 3), 2);
      expect(score('travaux', nb: 9), 2);
      expect(score('travaux', nb: 10), 3);
      expect(score('electricite', danger: true, nb: 12), 6);
    });

    test('Niveau d\'urgence : 0-1 faible, 2-3 normal, 4+ urgent', () {
      NiveauUrgence niveau(String categorie, {bool danger = false, int nb = 0}) {
        return SignalementRepository.niveauUrgence(
          exemple(categorieId: categorie, danger: danger, nbConfirmations: nb),
        );
      }

      expect(niveau('travaux'), NiveauUrgence.faible);
      expect(niveau('eau'), NiveauUrgence.normal);
      expect(niveau('travaux', nb: 10), NiveauUrgence.normal);
      expect(niveau('eau', nb: 10), NiveauUrgence.urgent);
      expect(niveau('ordures', danger: true), NiveauUrgence.normal);
      expect(niveau('incident', danger: true), NiveauUrgence.urgent);
    });

    test('Tri par urgence, puis du plus récent au plus ancien', () {
      final List<Signalement> tries = SignalementRepository.trierParUrgence([
        exemple(id: 'faible', categorieId: 'travaux'),
        exemple(id: 'normal-ancien', categorieId: 'eau', date: DateTime(2026, 1, 1)),
        exemple(id: 'urgent', categorieId: 'incident', danger: true),
        exemple(id: 'normal-recent', categorieId: 'eau', date: DateTime(2026, 12, 1)),
      ]);
      expect(tries.map((s) => s.id).toList(),
          ['urgent', 'normal-recent', 'normal-ancien', 'faible']);
    });

    test('Confirmation refusée : son propre signalement, clôturé, déjà fait', () {
      final Signalement ouvert = exemple();
      expect(SignalementRepository.refusConfirmation(ouvert, 'u1', false), isNull);
      expect(SignalementRepository.refusConfirmation(ouvert, 'u99', false),
          'Tu ne peux pas confirmer ton propre signalement');
      expect(SignalementRepository.refusConfirmation(ouvert, 'u1', true),
          'Tu as déjà confirmé ce signalement');
      for (final StatutSignalement statut in [
        StatutSignalement.resolu,
        StatutSignalement.refuse,
      ]) {
        expect(
          SignalementRepository.refusConfirmation(
              exemple(statut: statut), 'u1', false),
          'Ce signalement est déjà clôturé',
        );
      }
    });

    test('Compte non validé : refusé', () {
      final Utilisateur enAttente = voisin('u30', 'Nour', 'B')
          .copier(statut: StatutUtilisateur.enAttente);
      expect(SignalementRepository.refusUtilisateur(enAttente),
          'Ton compte doit être validé par l\'admin');
      expect(SignalementRepository.refusUtilisateur(salma), isNull);
    });
  });

  // =====================================================================
  group('Repository (mock) : lecture et filtres', () {
    test('Tous les signalements, du plus récent au plus ancien', () async {
      final Resultat<List<Signalement>> resultat =
          await SignalementRepository().getSignalements();
      expect(resultat.estSucces, isTrue);
      expect(resultat.donnee!.map((s) => s.id).toList(), ['r1', 'r2', 'r3', 'r4']);
    });

    test('Filtre par statut, par catégorie, et les deux', () async {
      final SignalementRepository repository = SignalementRepository();
      final enAttente =
          await repository.getSignalements(statut: StatutSignalement.enAttente);
      expect(enAttente.donnee!.map((s) => s.id), ['r3']);

      final eau = await repository.getSignalements(categorieId: 'eau');
      expect(eau.donnee!.map((s) => s.id), ['r3']);

      final rien = await repository.getSignalements(
        statut: StatutSignalement.resolu,
        categorieId: 'eau',
      );
      expect(rien.donnee, isEmpty);
    });

    test('Mes signalements : seulement ceux de l\'utilisateur connecté', () async {
      final mesAmira = await SignalementRepository().getMesSignalements();
      expect(mesAmira.donnee!.map((s) => s.id), ['r1']);

      await devenir(salma);
      final mesSalma = await SignalementRepository().getMesSignalements();
      expect(mesSalma.donnee!.map((s) => s.id), ['r3']);
    });

    test('Un signalement supprimé : message d\'erreur', () async {
      final Resultat<Signalement> resultat =
          await SignalementRepository().getSignalement('nexistepas');
      expect(resultat.erreur, 'Ce signalement n\'existe plus');
    });

    test('Sans réseau : échec avec le message', () async {
      depot.erreurReseau = 'Pas de connexion Internet';
      final resultat = await SignalementRepository().getSignalements();
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, 'Pas de connexion Internet');
    });
  });

  // =====================================================================
  group('Repository (mock) : écriture', () {
    test('Créer : auteur, statut, date et compteur imposés', () async {
      final Resultat<void> resultat =
          await SignalementRepository().ajouterSignalement(exemple(
        statut: StatutSignalement.resolu, // ignoré
        nbConfirmations: 50, // ignoré
        danger: true,
      ));
      expect(resultat.estSucces, isTrue);

      final Signalement cree = depot.tous.last;
      expect(cree.auteurId, 'u1');
      expect(cree.auteurNom, 'Amira B.');
      expect(cree.statut, StatutSignalement.enAttente);
      expect(cree.nbConfirmations, 0);
      expect(cree.danger, isTrue);
      expect(DateTime.now().difference(cree.date).inMinutes, lessThan(1));
    });

    test('Créer : formulaire invalide ou compte non validé refusé', () async {
      final invalide = await SignalementRepository()
          .ajouterSignalement(exemple(categorieId: 'piscine'));
      expect(invalide.erreur, 'Choisis une catégorie');

      await utilisateurs.simulerStatut(StatutUtilisateur.enAttente);
      final enAttente =
          await SignalementRepository().ajouterSignalement(exemple());
      expect(enAttente.erreur, 'Ton compte doit être validé par l\'admin');
      expect(depot.tous.length, 4);
    });

    test('Modifier : l\'auteur, tant que c\'est en attente', () async {
      await devenir(salma);
      final Resultat<void> resultat = await SignalementRepository()
          .modifierSignalement(lire('r3').copyWith(
        titre: 'Grosse fuite',
        danger: true,
        nbConfirmations: 99, // ignoré : seuls les champs autorisés changent
      ));
      expect(resultat.estSucces, isTrue);
      expect(lire('r3').titre, 'Grosse fuite');
      expect(lire('r3').danger, isTrue);
      expect(lire('r3').nbConfirmations, 3);
    });

    test('Modifier : refusé pour un autre, ou après prise en charge', () async {
      // Amira (même admin) ne modifie pas le contenu d'un autre
      final autre = await SignalementRepository()
          .modifierSignalement(lire('r3').copyWith(titre: 'Changé'));
      expect(autre.erreur, 'Seul l\'auteur peut modifier ce signalement');

      // Amira, autrice de r1, mais r1 est "en cours"
      final enCours = await SignalementRepository()
          .modifierSignalement(lire('r1').copyWith(titre: 'Changé'));
      expect(enCours.erreur,
          'Ce signalement est déjà pris en charge, il ne peut plus être modifié');
      expect(lire('r1').titre, 'Coupure d\'électricité');
    });

    test('Supprimer : l\'auteur en attente, ou l\'admin', () async {
      await devenir(karim); // r4 est refusé : Karim ne peut plus le supprimer
      final refuse = await SignalementRepository().supprimerSignalement('r4');
      expect(refuse.erreur,
          'Ce signalement est déjà pris en charge, il ne peut plus être supprimé');

      await devenir(salma);
      final autre = await SignalementRepository().supprimerSignalement('r4');
      expect(autre.erreur, 'Seul l\'auteur peut supprimer ce signalement');
      expect((await SignalementRepository().supprimerSignalement('r3')).estSucces,
          isTrue);

      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      ); // retour à Amira, admin
      expect((await SignalementRepository().supprimerSignalement('r4')).estSucces,
          isTrue);
      expect(depot.tous.map((s) => s.id), ['r1', 'r2']);
    });

    test('Confirmer : une seule fois, compteur + 1', () async {
      final SignalementRepository repository = SignalementRepository();
      expect((await repository.aConfirme('r3')).donnee, isFalse);

      expect((await repository.confirmer('r3')).estSucces, isTrue);
      expect(lire('r3').nbConfirmations, 4);
      expect((await repository.aConfirme('r3')).donnee, isTrue);

      final encore = await repository.confirmer('r3');
      expect(encore.erreur, 'Tu as déjà confirmé ce signalement');
      expect(lire('r3').nbConfirmations, 4);

      // Un autre voisin peut confirmer aussi
      await devenir(karim);
      expect((await repository.confirmer('r3')).estSucces, isTrue);
      expect(lire('r3').nbConfirmations, 5);
    });

    test('Confirmer : jamais son propre signalement ni un clôturé', () async {
      final propre = await SignalementRepository().confirmer('r1');
      expect(propre.erreur, 'Tu ne peux pas confirmer ton propre signalement');

      final resolu = await SignalementRepository().confirmer('r2');
      expect(resolu.erreur, 'Ce signalement est déjà clôturé');
      expect(lire('r2').nbConfirmations, 5);
    });

    test('Changer le statut : l\'admin seulement', () async {
      await devenir(salma);
      final resident = await SignalementRepository()
          .changerStatut('r3', StatutSignalement.enCours);
      expect(resident.erreur, 'Seul l\'admin du quartier peut changer le statut');
      expect(lire('r3').statut, StatutSignalement.enAttente);

      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      final admin = await SignalementRepository()
          .changerStatut('r3', StatutSignalement.enCours);
      expect(admin.estSucces, isTrue);
      expect(lire('r3').statut, StatutSignalement.enCours);
    });
  });

  // =====================================================================
  group('Écran : liste ouverte depuis un autre module', () {
    testWidgets('mesSignalements : directement sur "Mes signalements"',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen(mesSignalements: true));
      expect(find.text('1 signalement'), findsOneWidget);
      expect(find.text('Coupure d\'électricité'), findsOneWidget); // r1 d'Amira
      expect(find.text('Fuite d\'eau devant l\'entrée'), findsNothing);

      // On peut toujours revenir sur "Tous"
      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('4 signalements'), findsOneWidget);
    });

    testWidgets('ouvrirCreation : la création s\'ouvre, puis retour à la liste',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen(ouvrirCreation: true));
      expect(find.text('Nouveau signalement'), findsOneWidget);

      await tester.tap(find.text('Eau'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fuite au parking');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Une fuite au niveau du parking');
      await tester.enterText(find.byType(TextFormField).at(2), 'Parking');
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      // Retour sur la liste, avec le message et le nouveau signalement
      expect(find.text('Yaatik saha ! Signalement publié.'), findsOneWidget);
      expect(find.text('5 signalements'), findsOneWidget);
      expect(find.text('Nouveau signalement'), findsNothing);
    });

    testWidgets('Sans paramètre : "Tous", pas de création',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      expect(find.text('4 signalements'), findsOneWidget);
      expect(find.text('Nouveau signalement'), findsNothing);
    });
  });

  group('Écran : liste', () {
    testWidgets('Affiche les 4 signalements et filtre par statut',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      expect(find.text('4 signalements'), findsOneWidget);
      expect(find.text('Coupure d\'électricité'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget); // r1 : électricité + danger + 12

      await toucher(tester, find.text('En attente').first);
      await tester.pumpAndSettle();
      expect(find.text('1 signalement'), findsOneWidget);
      expect(find.text('Fuite d\'eau devant l\'entrée'), findsOneWidget);
      expect(find.text('Coupure d\'électricité'), findsNothing);
    });

    testWidgets('Filtre par catégorie, puis aucun résultat',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      await toucher(tester, find.text('Ordures'));
      await tester.pumpAndSettle();
      expect(find.text('1 signalement'), findsOneWidget);

      await toucher(tester, find.text('En attente').first);
      await tester.pumpAndSettle();
      expect(find.text('Aucun signalement avec ces filtres'), findsOneWidget);
    });

    testWidgets('Mes signalements et tri "Plus urgents"',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Mes signalements'));
      await tester.pumpAndSettle();
      expect(find.text('1 signalement'), findsOneWidget);
      expect(find.text('Coupure d\'électricité'), findsOneWidget);

      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plus récents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plus urgents').last);
      await tester.pumpAndSettle();

      // r1 (score 6) avant r3 (score 3), avant r4 (score 1)
      final double y1 = tester.getTopLeft(find.text('Coupure d\'électricité')).dy;
      final double y3 =
          tester.getTopLeft(find.text('Fuite d\'eau devant l\'entrée')).dy;
      final double y4 = tester.getTopLeft(find.text('Travaux de voirie')).dy;
      expect(y1 < y3 && y3 < y4, isTrue);
    });

    testWidgets('Liste vide : message', (WidgetTester tester) async {
      SignalementRepository.instance =
          MockSignalementRepository(avecDonneesDemo: false);
      await afficher(tester, const SignalementsScreen());
      expect(
        find.text('Aucun signalement pour l\'instant. Tout va bien dans la houma !'),
        findsOneWidget,
      );
    });

    testWidgets('Erreur réseau puis "Réessayer"', (WidgetTester tester) async {
      depot.erreurReseau = 'Pas de connexion Internet';
      await afficher(tester, const SignalementsScreen());
      expect(find.text('Pas de connexion Internet'), findsOneWidget);

      depot.erreurReseau = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('4 signalements'), findsOneWidget);
    });
  });

  // =====================================================================
  group('Écran : création et modification', () {
    testWidgets('Formulaire vide : messages d\'erreur',
        (WidgetTester tester) async {
      await afficher(tester, const CreateSignalementScreen());
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
      expect(find.text('Choisis une catégorie'), findsOneWidget);
      expect(find.text('Le titre doit avoir au moins 3 caractères'), findsOneWidget);
      expect(find.text('La description doit avoir au moins 10 caractères'),
          findsOneWidget);
      expect(find.text('Indique le lieu du problème'), findsOneWidget);
      expect(depot.tous.length, 4);
    });

    testWidgets('"+ Signaler" puis publier : retour à la liste',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau signalement'), findsOneWidget);

      await tester.tap(find.text('Eau'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Lampadaire');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Le lampadaire ne marche plus');
      await tester.tap(find.text('Danger pour les personnes'));
      // GPS et adresse simulés (voir outils_test_m3.dart)
      fauxGps(const PointGps(36.8625, 10.17));
      fausseAdresse('Rue Hédi Nouira, Ennasr 2');
      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      expect(find.text('5 signalements'), findsOneWidget);
      expect(find.text('Yaatik saha ! Signalement publié.'), findsOneWidget);
      final Signalement cree = depot.tous.last;
      expect(cree.titre, 'Lampadaire');
      expect(cree.categorieId, 'eau');
      expect(cree.danger, isTrue);
      expect(cree.lieu, 'Rue Hédi Nouira, Ennasr 2');
      expect(cree.position!.latitude, 36.8625);
    });

    testWidgets('Mode modification : champs pré-remplis',
        (WidgetTester tester) async {
      await afficher(tester, CreateSignalementScreen(signalement: lire('r3')));
      expect(find.text('Modifier le signalement'), findsOneWidget);
      expect(find.text('Fuite d\'eau devant l\'entrée'), findsOneWidget);
      expect(find.text('Entrée bloc A'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    });
  });

  // =====================================================================
  group('Écran : détail', () {
    testWidgets('Un voisin confirme : compteur + 1, bouton désactivé',
        (WidgetTester tester) async {
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.text('3 voisins ont confirmé'), findsOneWidget);

      await tester.tap(find.text('Sa7, ena zeda'));
      await tester.pumpAndSettle();
      expect(find.text('4 voisins ont confirmé'), findsOneWidget);
      expect(find.text('Tu as confirmé'), findsOneWidget);
      expect(find.text('Sa7, ena zeda'), findsNothing);
    });

    testWidgets('Son propre signalement : pas de bouton ; admin : statut',
        (WidgetTester tester) async {
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'r1'));
      expect(find.text('Sa7, ena zeda'), findsNothing);
      expect(find.text('Modifier'), findsNothing); // r1 est en cours
      expect(find.text('Changer le statut (admin)'), findsOneWidget);

      await tester.tap(find.text('Résolu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider')); // fenêtre de la note (optionnelle)
      await tester.pumpAndSettle();
      expect(lire('r1').statut, StatutSignalement.resolu);
    });

    testWidgets('Signalement clôturé : plus de confirmation',
        (WidgetTester tester) async {
      await devenir(salma);
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'r2'));
      expect(find.text('Sa7, ena zeda'), findsNothing);
      expect(find.text('Ce signalement est clôturé : il ne peut plus être confirmé.'),
          findsOneWidget);
      expect(find.text('Changer le statut (admin)'), findsNothing);
    });

    testWidgets('L\'auteur modifie puis supprime (avec confirmation)',
        (WidgetTester tester) async {
      await devenir(salma);
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Fuite d\'eau devant l\'entrée'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Grosse fuite');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Grosse fuite'), findsOneWidget);

      // "Annuler" ne supprime rien
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer ce signalement ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(depot.tous.length, 4);

      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(find.text('Signalement supprimé'), findsOneWidget);
      expect(find.text('3 signalements'), findsOneWidget);
    });

    testWidgets('Signalement introuvable : message et "Réessayer"',
        (WidgetTester tester) async {
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'nexistepas'));
      expect(find.text('Ce signalement n\'existe plus'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}
