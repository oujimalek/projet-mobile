import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/firestore_commun.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/signalements_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

/// Un repository dont l'envoi ne se termine JAMAIS : comme
/// `await collection.add()` de Firestore quand le réseau ne répond pas.
class RepositoryMuet extends MockSignalementRepository {
  @override
  Future<Resultat<void>> ajouterSignalement(Signalement signalement) {
    return Completer<Resultat<void>>().future;
  }
}

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

/// Un signalement à publier (formulaire valable).
Signalement saisie({String titre = 'Lampadaire en panne'}) {
  return Signalement(
    id: '',
    titre: titre,
    description: 'Le lampadaire ne s\'allume plus',
    categorieId: 'electricite',
    statut: StatutSignalement.enAttente,
    date: DateTime(2026, 11, 1),
    lieu: 'Bloc C',
    auteurId: '',
    auteurNom: '',
    danger: true,
  );
}

/// Un envoi en attente (pour remplir la table directement).
EnvoiEnAttente envoi({
  String idDocument = 'doc1',
  String utilisateurId = 'u1',
  String quartierId = 'q1',
  DateTime? date,
}) {
  return EnvoiEnAttente(
    idDocument: idDocument,
    utilisateurId: utilisateurId,
    quartierId: quartierId,
    titre: 'Fuite',
    description: 'Une fuite au sous-sol',
    categorieId: 'eau',
    lieu: 'Sous-sol',
    photoLocale: '/photos/fuite.jpg',
    dateCreation: date ?? DateTime(2026, 11, 1, 10),
  );
}

Signalement pourCache(
  String id, {
  StatutSignalement statut = StatutSignalement.enAttente,
  String categorieId = 'eau',
  String auteurId = 'u1',
  DateTime? date,
}) {
  return Signalement(
    id: id,
    titre: 'Titre $id',
    description: 'Description $id',
    categorieId: categorieId,
    statut: statut,
    date: date ?? DateTime(2026, 11, 1),
    lieu: 'Bloc A',
    auteurId: auteurId,
    auteurNom: 'Nom',
    nbConfirmations: 2,
    danger: true,
    photoUrl: 'https://exemple.tn/p.jpg',
  );
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;

  BaseLocaleM3 base() => BaseLocaleM3.instance;
  SyncSignalementsM3 sync() => SyncSignalementsM3.instance;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    utilisateurs = MockUtilisateurRepository(); // Amira (u1, quartier q1)
    UtilisateurRepository.instance = utilisateurs;
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
  });

  tearDown(() async {
    SyncSignalementsM3.delaiReseau = const Duration(seconds: 15);
    await nettoyerHorsLigneM3(connexion);
  });

  // =====================================================================
  group('SQL : table brouillons', () {
    test('Enregistrer, relire, remplacer, supprimer', () async {
      await base().enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'Trou',
        categorieId: 'travaux',
        danger: true,
        dateModification: DateTime(2026, 11, 1, 9),
      ));
      Brouillon? lu = await base().lireBrouillon('u1');
      expect(lu!.titre, 'Trou');
      expect(lu.categorieId, 'travaux');
      expect(lu.danger, isTrue);
      expect(lu.dateModification, DateTime(2026, 11, 1, 9));

      // Un seul brouillon par utilisateur : le second remplace le premier
      await base().enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'Grand trou',
        dateModification: DateTime(2026, 11, 1, 10),
      ));
      lu = await base().lireBrouillon('u1');
      expect(lu!.titre, 'Grand trou');
      expect(lu.categorieId, isNull);
      expect(await base().lireBrouillon('u2'), isNull);

      await base().supprimerBrouillon('u1');
      expect(await base().lireBrouillon('u1'), isNull);
    });

    test('Un brouillon vide n\'est pas gardé', () async {
      final Brouillon vide =
          Brouillon(utilisateurId: 'u1', dateModification: DateTime.now());
      expect(vide.estVide, isTrue);
      await sync().enregistrerBrouillon(vide);
      expect(await base().lireBrouillon('u1'), isNull);
    });
  });

  // =====================================================================
  group('SQL : table envois_en_attente', () {
    test('Ajouter, lire dans l\'ordre, compter, supprimer', () async {
      final int id2 = await base().ajouterEnvoi(
          envoi(idDocument: 'b', date: DateTime(2026, 11, 2)));
      await base().ajouterEnvoi(envoi(idDocument: 'a', date: DateTime(2026, 11, 1)));
      await base().ajouterEnvoi(envoi(idDocument: 'c', utilisateurId: 'u2'));

      final List<EnvoiEnAttente> envois = await base().lireEnvois('u1');
      expect(envois.map((e) => e.idDocument), ['a', 'b']); // plus ancien d'abord
      expect(envois.first.etat, EtatEnvoi.enAttente);
      expect(envois.first.nbTentatives, 0);
      expect(envois.first.photoLocale, '/photos/fuite.jpg');
      expect(await base().compterEnvois('u1'), 2);

      await base().supprimerEnvoi(id2);
      expect(await base().compterEnvois('u1'), 1);
    });

    test('Échec : état "echec", un essai de plus, erreur gardée', () async {
      final int id = await base().ajouterEnvoi(envoi());
      await base().marquerEchec(id, 'Serveur injoignable');
      await base().marquerEchec(id, 'Encore injoignable');
      final EnvoiEnAttente lu = (await base().lireEnvoi(id))!;
      expect(lu.etat, EtatEnvoi.echec);
      expect(lu.nbTentatives, 2);
      expect(lu.derniereErreur, 'Encore injoignable');
    });

    test('Un même id de document ne peut pas être deux fois dans la file',
        () async {
      await base().ajouterEnvoi(envoi(idDocument: 'meme'));
      expect(
        () => base().ajouterEnvoi(envoi(idDocument: 'meme')),
        throwsA(anything),
      );
    });
  });

  // =====================================================================
  group('SQL : table signalements_cache', () {
    test('Remplacer le cache, relire tous les champs, date de mise à jour',
        () async {
      await base().remplacerCache('q1', [pourCache('s1')], DateTime(2026, 11, 1, 14, 5));
      final Signalement lu = (await base().lireDuCache('q1', 's1'))!;
      expect(lu.titre, 'Titre s1');
      expect(lu.statut, StatutSignalement.enAttente);
      expect(lu.danger, isTrue);
      expect(lu.nbConfirmations, 2);
      expect(lu.photoUrl, 'https://exemple.tn/p.jpg');
      expect(await base().dateMiseAJour('q1'), DateTime(2026, 11, 1, 14, 5));
      expect(await base().dateMiseAJour('q2'), isNull);

      // Un nouveau chargement complet efface les signalements disparus
      await base().remplacerCache('q1', [pourCache('s2')], DateTime(2026, 11, 2));
      expect(await base().lireDuCache('q1', 's1'), isNull);
      expect(await base().lireDuCache('q1', 's2'), isNotNull);
    });

    test('Filtres SQL : statut, catégorie, auteur, quartier ; tri par date',
        () async {
      await base().remplacerCache('q1', [
        pourCache('ancien', date: DateTime(2026, 1, 1)),
        pourCache('recent', date: DateTime(2026, 11, 1)),
        pourCache('resolu', statut: StatutSignalement.resolu),
        pourCache('travaux', categorieId: 'travaux', auteurId: 'u2'),
      ], DateTime.now());
      await base().remplacerCache('q2', [pourCache('autre')], DateTime.now());

      List<String> ids(List<Signalement> liste) => liste.map((s) => s.id).toList();

      expect((await base().lireCache('q1')).length, 4);
      expect(ids(await base().lireCache('q1', statut: StatutSignalement.resolu)),
          ['resolu']);
      expect(ids(await base().lireCache('q1', categorieId: 'travaux')), ['travaux']);
      expect(ids(await base().lireCache('q1', auteurId: 'u2')), ['travaux']);
      expect(
        ids(await base().lireCache('q1',
            statut: StatutSignalement.enAttente, categorieId: 'eau')),
        ['recent', 'ancien'], // plus récent d'abord
      );
      expect(ids(await base().lireCache('q2')), ['autre']);
    });

    test('Mise à jour partielle : les autres lignes restent', () async {
      await base().remplacerCache('q1', [pourCache('s1'), pourCache('s2')], DateTime.now());
      await base().mettreAJourCache('q1', [
        pourCache('s1', statut: StatutSignalement.resolu),
      ]);
      expect((await base().lireDuCache('q1', 's1'))!.statut, StatutSignalement.resolu);
      expect(await base().lireDuCache('q1', 's2'), isNotNull);

      await base().supprimerDuCache('q1', 's2');
      expect(await base().lireDuCache('q1', 's2'), isNull);
    });
  });

  // =====================================================================
  group('Sync : publier', () {
    test('En ligne : envoyé à Firestore, rien dans la file', () async {
      final Resultat<EtatPublicationM3> resultat = await sync().publier(saisie());
      expect(resultat.donnee, EtatPublicationM3.envoye);
      expect(depot.tous.length, 5);
      expect(depot.tous.last.id.length, 20); // id choisi sur le téléphone
      expect(await sync().getEnvois(), isEmpty);
    });

    test('Hors ligne : gardé dans SQLite, Firestore n\'est PAS appelé',
        () async {
      connexion.enLigne = false;
      final Resultat<EtatPublicationM3> resultat = await sync().publier(saisie());
      expect(resultat.donnee, EtatPublicationM3.misEnFile);
      expect(depot.nombreEnvois, 0);
      expect(depot.tous.length, 4);

      final List<EnvoiEnAttente> file = await sync().getEnvois();
      expect(file.length, 1);
      expect(file.first.titre, 'Lampadaire en panne');
      expect(file.first.danger, isTrue);
      expect(file.first.quartierId, 'q1');
      expect(file.first.etat, EtatEnvoi.enAttente);
    });

    test('Formulaire invalide : refusé, même hors ligne', () async {
      connexion.enLigne = false;
      final resultat = await sync().publier(saisie(titre: 'ab'));
      expect(resultat.erreur, 'Le titre doit avoir au moins 3 caractères');
      expect(await sync().getEnvois(), isEmpty);
    });

    test('Le réseau ne répond pas (envoi sans fin) : mis en file après le délai',
        () async {
      SignalementRepository.instance = RepositoryMuet();
      SyncSignalementsM3.delaiReseau = const Duration(milliseconds: 50);
      final resultat = await sync().publier(saisie());
      expect(resultat.donnee, EtatPublicationM3.misEnFile);
      final List<EnvoiEnAttente> file = await sync().getEnvois();
      expect(file.single.derniereErreur, SyncSignalementsM3.messageDelai);
    });

    test('Serveur injoignable : en file ; action refusée : erreur affichée',
        () async {
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      expect((await sync().publier(saisie())).donnee, EtatPublicationM3.misEnFile);

      depot.erreurReseau = FirestoreCommun.messageErreur('permission-denied');
      final refus = await sync().publier(saisie());
      expect(refus.erreur, 'Action non autorisée');
      expect((await sync().getEnvois()).length, 1); // seulement le premier
    });
  });

  // =====================================================================
  group('Sync : envoi de la file', () {
    test('Le réseau revient : la file part toute seule', () async {
      connexion.enLigne = false;
      await sync().publier(saisie(titre: 'Premier'));
      await sync().publier(saisie(titre: 'Second'));
      final String idPrevu = (await sync().getEnvois()).first.idDocument;

      sync().demarrer(); // écoute le réseau (fait par la liste dans l'app)
      connexion.reseauRevient();
      await pumpEventQueue();

      expect(await sync().getEnvois(), isEmpty);
      expect(depot.tous.length, 6);
      // Le document a l'id choisi hors ligne, et l'auteur est imposé
      final Signalement envoye = depot.tous.firstWhere((s) => s.id == idPrevu);
      expect(envoye.titre, 'Premier');
      expect(envoye.auteurId, 'u1');
      expect(envoye.statut, StatutSignalement.enAttente);
    });

    test('Échec : reste dans la file avec un essai de plus', () async {
      connexion.enLigne = false;
      await sync().publier(saisie());
      connexion.enLigne = true;
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');

      expect(await sync().envoyerFile(), 0);
      EnvoiEnAttente envoi = (await sync().getEnvois()).single;
      expect(envoi.etat, EtatEnvoi.echec);
      expect(envoi.nbTentatives, 1);
      expect(envoi.derniereErreur, FirestoreCommun.messageErreur('unavailable'));

      await sync().envoyerFile();
      await sync().envoyerFile();
      expect((await sync().getEnvois()).single.nbTentatives, 3);

      // Après 3 échecs : plus d'envoi automatique...
      await sync().envoyerFile();
      envoi = (await sync().getEnvois()).single;
      expect(envoi.nbTentatives, 3);

      // ... mais "Réessayer" marche quand le serveur répond
      depot.erreurReseau = null;
      expect((await sync().reessayer(envoi.id!)).estSucces, isTrue);
      expect(await sync().getEnvois(), isEmpty);
      expect(depot.tous.length, 5);
    });

    test('Déjà arrivé dans Firestore : retiré de la file, sans doublon',
        () async {
      // Comme si le premier envoi avait réussi malgré un délai dépassé
      await base().ajouterEnvoi(envoi(idDocument: 'r3'));
      expect(await sync().envoyerFile(), 1);
      expect(await sync().getEnvois(), isEmpty);
      expect(depot.tous.length, 4);
      expect(depot.nombreEnvois, 0);
    });

    test('Envoi d\'un autre quartier : pas envoyé ; "Annuler" le retire',
        () async {
      await base().ajouterEnvoi(envoi(quartierId: 'q2'));
      expect(await sync().envoyerFile(), 0);
      final EnvoiEnAttente reste = (await sync().getEnvois()).single;

      await sync().annuler(reste.id!);
      expect(await sync().getEnvois(), isEmpty);
    });

    test('"Réessayer" hors ligne : message', () async {
      final int id = await base().ajouterEnvoi(envoi());
      connexion.enLigne = false;
      expect((await sync().reessayer(id)).erreur, 'Pas de connexion Internet');
    });
  });

  // =====================================================================
  group('Sync : lecture avec cache', () {
    test('En ligne : remplit le cache ; hors ligne : relu avec les filtres',
        () async {
      final enLigne = await sync().chargerSignalements();
      expect(enLigne.donnee!.depuisCache, isFalse);
      expect(enLigne.donnee!.signalements.length, 4);
      expect(await base().dateMiseAJour('q1'), isNotNull);

      connexion.enLigne = false;
      final horsLigne = await sync().chargerSignalements();
      expect(horsLigne.donnee!.depuisCache, isTrue);
      expect(horsLigne.donnee!.horsLigne, isTrue);
      expect(horsLigne.donnee!.miseAJour, isNotNull);
      expect(horsLigne.donnee!.signalements.map((s) => s.id),
          ['r1', 'r2', 'r3', 'r4']);

      final enAttente =
          await sync().chargerSignalements(statut: StatutSignalement.enAttente);
      expect(enAttente.donnee!.signalements.map((s) => s.id), ['r3']);
      final ordures = await sync().chargerSignalements(categorieId: 'ordures');
      expect(ordures.donnee!.signalements.map((s) => s.id), ['r2']);
      final mes = await sync().chargerSignalements(mesSignalements: true);
      expect(mes.donnee!.signalements.map((s) => s.id), ['r1']);
    });

    test('Hors ligne sans rien en cache : liste vide, pas de date', () async {
      connexion.enLigne = false;
      final resultat = await sync().chargerSignalements();
      expect(resultat.donnee!.signalements, isEmpty);
      expect(resultat.donnee!.miseAJour, isNull);
    });

    test('Firestore en échec mais cache présent : on montre le cache',
        () async {
      await sync().chargerSignalements();
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      final resultat = await sync().chargerSignalements();
      expect(resultat.donnee!.depuisCache, isTrue);
      expect(resultat.donnee!.horsLigne, isFalse);
      expect(resultat.donnee!.signalements.length, 4);
    });

    test('Un signalement hors ligne : depuis le cache, sinon erreur', () async {
      await sync().lireSignalement('r3'); // en ligne : copié dans le cache
      connexion.enLigne = false;
      final lu = await sync().lireSignalement('r3');
      expect(lu.donnee!.depuisCache, isTrue);
      expect(lu.donnee!.signalement.titre, 'Fuite d\'eau devant l\'entrée');
      expect((await sync().lireSignalement('r1')).estSucces, isFalse);
    });
  });

  // =====================================================================
  group('Sync : nombre de mes signalements (Profil)', () {
    test('En ligne : le count() de Firestore (+ ma file d\'envoi)', () async {
      expect(await sync().compterMesSignalements(), 1); // r1 d'Amira
      expect((await depot.compterMesSignalements()).donnee, 1);

      connexion.enLigne = false;
      await sync().publier(saisie()); // gardé dans la file
      connexion.enLigne = true;
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      await sync().envoyerFile(); // échec : reste dans la file
      depot.erreurReseau = null;
      expect(await sync().compterMesSignalements(), 2);
    });

    test('Hors ligne : compté dans le cache SQLite', () async {
      await sync().chargerSignalements(); // cache rempli en ligne
      connexion.enLigne = false;
      expect(await sync().compterMesSignalements(), 1);
    });

    test('Firestore en échec : le cache ; sans cache : inconnu (null)',
        () async {
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      expect(await sync().compterMesSignalements(), isNull);
      depot.erreurReseau = null;
      await sync().chargerSignalements();
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      expect(await sync().compterMesSignalements(), 1);
    });
  });

  // =====================================================================
  group('Écrans hors ligne', () {
    testWidgets('Liste hors ligne : bandeau et signalements du cache',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen()); // en ligne : cache rempli
      connexion.enLigne = false;
      await tester.fling(find.text('Coupure d\'électricité'),
          const Offset(0, 400), 1000); // tirer pour actualiser
      await tester.pumpAndSettle();

      expect(find.textContaining('Hors ligne — dernière mise à jour à'),
          findsOneWidget);
      expect(find.text('4 signalements'), findsOneWidget);
    });

    testWidgets('Jamais chargé et hors ligne : message clair',
        (WidgetTester tester) async {
      connexion.enLigne = false;
      await afficher(tester, const SignalementsScreen());
      expect(
        find.textContaining('aucune donnée enregistrée sur ce téléphone'),
        findsOneWidget,
      );
    });

    testWidgets('Publier hors ligne → "En attente d\'envoi" → part au retour',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      connexion.enLigne = false;

      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eau'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Fuite au parking');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Une fuite au niveau du parking');
      await tester.enterText(find.byType(TextFormField).at(2), 'Parking');
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      expect(find.text('Pas de connexion : ton signalement sera envoyé automatiquement.'),
          findsOneWidget);
      expect(find.text('Fuite au parking'), findsOneWidget);
      expect(find.text('En attente d\'envoi'), findsOneWidget);
      expect(depot.tous.length, 4);

      // Le réseau revient : envoyé, la carte d'attente disparaît
      connexion.reseauRevient();
      await tester.pumpAndSettle();
      expect(find.text('En attente d\'envoi'), findsNothing);
      expect(find.text('5 signalements'), findsOneWidget);
      expect(find.text('Fuite au parking'), findsOneWidget);
    });

    testWidgets('Carte en échec : erreur affichée, "Annuler" avec confirmation',
        (WidgetTester tester) async {
      final int id = await base().ajouterEnvoi(envoi());
      await base().marquerEchec(id, 'Action non autorisée');
      connexion.enLigne = false; // pas d'envoi automatique
      await afficher(tester, const SignalementsScreen());

      expect(find.text('Échec de l\'envoi · 1 essai(s)'), findsOneWidget);
      expect(find.text('Action non autorisée'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Pas de connexion Internet'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler l\'envoi'));
      await tester.pumpAndSettle();
      expect(find.text('Fuite'), findsNothing);
      expect(await sync().getEnvois(), isEmpty);
    });

    testWidgets('Brouillon : gardé en quittant, proposé à la réouverture',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travaux'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Trou dans la rue');
      await tester.pump(const Duration(seconds: 2)); // enregistrement auto

      expect((await base().lireBrouillon('u1'))!.titre, 'Trou dans la rue');

      // On quitte sans publier, puis on revient
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      expect(find.text('Tu as un brouillon'), findsOneWidget);

      await tester.tap(find.text('Reprendre le brouillon'));
      await tester.pumpAndSettle();
      expect(find.text('Tu as un brouillon'), findsNothing);
      expect(find.text('Trou dans la rue'), findsOneWidget);
    });

    testWidgets('Brouillon supprimé après publication',
        (WidgetTester tester) async {
      await base().enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'Lampadaire',
        description: 'Le lampadaire ne marche plus',
        categorieId: 'electricite',
        lieu: 'Bloc C',
        dateModification: DateTime.now(),
      ));
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reprendre le brouillon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      expect(find.text('5 signalements'), findsOneWidget);
      expect(await base().lireBrouillon('u1'), isNull);
    });

    testWidgets('Détail hors ligne : version du cache, sans actions',
        (WidgetTester tester) async {
      await sync().chargerSignalements(); // cache rempli en ligne
      connexion.enLigne = false;
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));

      expect(find.text('Hors ligne : version enregistrée sur le téléphone'),
          findsOneWidget);
      expect(find.text('Fuite d\'eau devant l\'entrée'), findsOneWidget);
      expect(find.text('Sa7, ena zeda'), findsNothing);
      expect(find.text('Changer le statut (admin)'), findsNothing);
    });

    testWidgets('Modifier hors ligne : refusé avec un message',
        (WidgetTester tester) async {
      final Signalement r3 = depot.tous.firstWhere((s) => s.id == 'r3');
      connexion.enLigne = false;
      // Le réseau est vérifié avant d'appeler Firestore
      await afficher(tester, CreateSignalementScreen(signalement: r3));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pas de connexion Internet : la modification se fait en ligne'),
        findsOneWidget,
      );
    });
  });
}
