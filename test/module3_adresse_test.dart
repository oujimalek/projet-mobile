import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as chemin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/adresse_m3.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/liens_m3.dart';
import 'package:houmani/data/services/localisation.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

const PointGps ennasr = PointGps(36.86251, 10.17003);

/// Une réponse JSON de Nominatim (encodée en UTF-8, comme le vrai serveur).
http.Response reponseJson(Map<String, dynamic> json, {int code = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(json)),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;
  late List<http.Request> requetes; // ce que le faux serveur a reçu

  /// Faux serveur Nominatim qui répond toujours [reponse].
  void fauxServeur(http.Response reponse) {
    AdresseM3.client = MockClient((requete) async {
      requetes.add(requete);
      return reponse;
    });
  }

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository(); // Amira, q1
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
    requetes = [];
    AdresseM3.intervalle = Duration.zero; // pas d'attente entre les tests
  });

  tearDown(() async {
    await nettoyerHorsLigneM3(connexion);
  });

  // =====================================================================
  group('Adresse courte (réponse Nominatim)', () {
    test('Rue + quartier', () {
      expect(
        AdresseM3.adresseCourte({
          'address': {
            'road': 'Rue Hédi Nouira',
            'suburb': 'Ennasr 2',
            'city': 'Ariana',
          },
        }),
        'Rue Hédi Nouira, Ennasr 2',
      );
    });

    test('Le quartier le plus précis d\'abord (neighbourhood avant suburb)', () {
      expect(
        AdresseM3.adresseCourte({
          'address': {
            'pedestrian': 'Passage du marché',
            'neighbourhood': 'Cité El Wafa',
            'suburb': 'Ennasr 1',
          },
        }),
        'Passage du marché, Cité El Wafa',
      );
    });

    test('Pas de rue : seulement le quartier ; rien : null', () {
      expect(
        AdresseM3.adresseCourte({
          'address': {'suburb': 'Ennasr 2', 'city': 'Ariana'},
        }),
        'Ennasr 2',
      );
      expect(AdresseM3.adresseCourte({'error': 'Unable to geocode'}), isNull);
      expect(AdresseM3.adresseCourte({'address': {}}), isNull);
    });

    test('Clé du cache : arrondie à 4 décimales (environ 11 m)', () {
      expect(AdresseM3.cleCache(ennasr), '36.8625,10.1700');
      expect(AdresseM3.cleCache(const PointGps(36.86249, 10.17004)),
          '36.8625,10.1700');
    });
  });

  // =====================================================================
  group('Nominatim (faux client HTTP)', () {
    test('Succès : bonne requête, adresse avec accents, mise en cache',
        () async {
      fauxServeur(reponseJson({
        'address': {'road': 'Avenue de l\'Indépendance', 'suburb': 'Ennasr 2'},
      }));
      final Resultat<String> resultat = await AdresseM3.nominatim(ennasr);
      expect(resultat.donnee, 'Avenue de l\'Indépendance, Ennasr 2');

      final http.Request requete = requetes.single;
      expect(requete.url.host, 'nominatim.openstreetmap.org');
      expect(requete.url.path, '/reverse');
      expect(requete.url.queryParameters['format'], 'jsonv2');
      expect(requete.url.queryParameters['lat'], '36.86251');
      expect(requete.url.queryParameters['lon'], '10.17003');
      expect(requete.url.queryParameters['accept-language'], 'fr');
      expect(requete.headers['User-Agent'], 'tn.esprit.houmani');

      expect(await BaseLocaleM3.instance.lireAdresse('36.8625,10.1700'),
          'Avenue de l\'Indépendance, Ennasr 2');
    });

    test('Pas de rue dans la réponse : le quartier', () async {
      fauxServeur(reponseJson({
        'address': {'suburb': 'Ennasr 2', 'city': 'Ariana'},
      }));
      expect((await AdresseM3.nominatim(ennasr)).donnee, 'Ennasr 2');
    });

    test('Aucune adresse : échec, rien en cache', () async {
      fauxServeur(reponseJson({'error': 'Unable to geocode'}));
      expect((await AdresseM3.nominatim(ennasr)).erreur,
          AdresseM3.messageIntrouvable);
      expect(await BaseLocaleM3.instance.lireAdresse('36.8625,10.1700'), isNull);
    });

    test('Erreur HTTP (500, 429...) : échec', () async {
      fauxServeur(http.Response('Trop de requêtes', 429));
      expect((await AdresseM3.nominatim(ennasr)).erreur,
          AdresseM3.messageIntrouvable);
    });

    test('Réponse illisible : échec', () async {
      fauxServeur(http.Response('<html>pas du JSON</html>', 200));
      expect((await AdresseM3.nominatim(ennasr)).erreur,
          AdresseM3.messageIntrouvable);
    });

    test('Le serveur ne répond pas : échec après le délai', () async {
      AdresseM3.delaiMax = const Duration(milliseconds: 50);
      AdresseM3.client = MockClient((requete) {
        return Completer<http.Response>().future; // jamais de réponse
      });
      expect((await AdresseM3.nominatim(ennasr)).erreur, AdresseM3.messageDelai);
    });

    test('Cache : le même endroit n\'est demandé qu\'une fois', () async {
      fauxServeur(reponseJson({
        'address': {'road': 'Rue de Marseille', 'suburb': 'Ennasr 2'},
      }));
      await AdresseM3.nominatim(ennasr);
      // 2 m plus loin : même clé
      final second = await AdresseM3.nominatim(const PointGps(36.86249, 10.17001));
      expect(second.donnee, 'Rue de Marseille, Ennasr 2');
      expect(requetes.length, 1);
    });

    test('Hors ligne : pas de requête ; le cache marche quand même', () async {
      fauxServeur(reponseJson({
        'address': {'road': 'Rue de Marseille'},
      }));
      connexion.enLigne = false;
      expect((await AdresseM3.nominatim(ennasr)).erreur,
          AdresseM3.messageHorsLigne);
      expect(requetes, isEmpty);

      await BaseLocaleM3.instance.enregistrerAdresse('36.8625,10.1700', 'Rue X');
      expect((await AdresseM3.nominatim(ennasr)).donnee, 'Rue X');
      expect(requetes, isEmpty);
    });

    test('Au plus 1 requête par intervalle, même demandées ensemble',
        () async {
      AdresseM3.intervalle = const Duration(milliseconds: 300);
      final List<DateTime> heures = [];
      AdresseM3.client = MockClient((requete) async {
        heures.add(DateTime.now());
        return reponseJson({'address': {'road': 'Rue'}});
      });
      await Future.wait([
        AdresseM3.nominatim(const PointGps(36.80, 10.10)),
        AdresseM3.nominatim(const PointGps(36.81, 10.11)),
      ]);
      expect(heures.length, 2);
      expect(heures[1].difference(heures[0]).inMilliseconds,
          greaterThanOrEqualTo(280));
    });
  });

  // =====================================================================
  group('SQLite : version 2 (position + adresses)', () {
    test('Un téléphone en version 1 passe à la version actuelle sans perdre ses données',
        () async {
      final Directory dossier = Directory.systemTemp.createTempSync('m3_');
      final String fichier = chemin.join(dossier.path, 'houmani_m3.db');

      // Base créée par l'ancienne version de l'application
      final Database ancienne = await openDatabase(
        fichier,
        version: 1,
        onCreate: (db, version) => BaseLocaleM3.creerTablesVersion1(db),
      );
      await ancienne.insert('brouillons', {
        'utilisateur_id': 'u1',
        'titre': 'Brouillon d\'avant',
        'date_modification': DateTime(2026, 11, 1).millisecondsSinceEpoch,
      });
      await ancienne.close();

      // La nouvelle version ouvre la même base : onUpgrade (1 → 2 → 3)
      final BaseLocaleM3 base = BaseLocaleM3(chemin: fichier);
      final Brouillon garde = (await base.lireBrouillon('u1'))!;
      expect(garde.titre, 'Brouillon d\'avant');
      expect(garde.position, isNull);

      await base.enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'Avec GPS',
        position: ennasr,
        dateModification: DateTime.now(),
      ));
      expect((await base.lireBrouillon('u1'))!.position!.latitude, 36.86251);
      await base.enregistrerAdresse('cle', 'Rue Y');
      expect(await base.lireAdresse('cle'), 'Rue Y');
      expect((await (await base.base).getVersion()), BaseLocaleM3.version);

      await base.fermer();
      dossier.deleteSync(recursive: true);
    });

    test('La position passe par la file et le cache', () async {
      final BaseLocaleM3 base = BaseLocaleM3.instance;
      await base.ajouterEnvoi(EnvoiEnAttente(
        idDocument: 'd1',
        utilisateurId: 'u1',
        quartierId: 'q1',
        titre: 'T',
        description: 'Description',
        categorieId: 'eau',
        lieu: 'L',
        position: ennasr,
        dateCreation: DateTime.now(),
      ));
      expect((await base.lireEnvois('u1')).single.position!.longitude, 10.17003);

      await base.remplacerCache('q1', [
        depot.tous.first.copyWith(position: ennasr),
      ], DateTime.now());
      expect((await base.lireDuCache('q1', 'r1'))!.position!.latitude, 36.86251);
    });

    test('Publié hors ligne avec GPS : le point arrive dans Firestore',
        () async {
      connexion.enLigne = false;
      await SyncSignalementsM3.instance.publier(Signalement(
        id: '',
        titre: 'Câble par terre',
        description: 'Un câble électrique traîne par terre',
        categorieId: 'electricite',
        statut: StatutSignalement.enAttente,
        date: DateTime.now(),
        lieu: 'Rue Hédi Nouira',
        auteurId: '',
        auteurNom: '',
        position: ennasr,
      ));
      connexion.enLigne = true;
      await SyncSignalementsM3.instance.envoyerFile();
      expect(depot.tous.last.position!.latitude, 36.86251);
    });
  });

  // =====================================================================
  group('Écrans : "Utiliser ma position"', () {
    testWidgets('GPS + adresse : le lieu est rempli, le point gardé',
        (WidgetTester tester) async {
      fauxGps(ennasr);
      fausseAdresse('Rue Hédi Nouira, Ennasr 2');
      await afficher(tester, const CreateSignalementScreen());

      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
      expect(find.text('Rue Hédi Nouira, Ennasr 2'), findsOneWidget);
      expect(find.text('Position GPS enregistrée (36.86251, 10.17003)'),
          findsOneWidget);

      // La croix retire le point, le texte du lieu reste
      await tester.tap(find.byTooltip('Retirer la position'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Position GPS enregistrée'), findsNothing);
      expect(find.text('Rue Hédi Nouira, Ennasr 2'), findsOneWidget);
    });

    testWidgets('Pendant la recherche : indicateur, bouton désactivé',
        (WidgetTester tester) async {
      final Completer<Resultat<PointGps>> gps = Completer();
      Localisation.positionActuelle = () => gps.future;
      fausseAdresse('Rue X');
      await afficher(tester, const CreateSignalementScreen());

      await tester.tap(find.text('Utiliser ma position'));
      await tester.pump();
      expect(find.text('Localisation...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gps.complete(const Resultat.succes(ennasr));
      await tester.pumpAndSettle();
      expect(find.text('Utiliser ma position'), findsOneWidget);
      expect(find.text('Rue X'), findsOneWidget);
    });

    testWidgets('GPS refusé : le message du module 1',
        (WidgetTester tester) async {
      Localisation.positionActuelle = () async =>
          const Resultat.echec('Autorise Houmani à utiliser ta position');
      await afficher(tester, const CreateSignalementScreen());

      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
      expect(find.text('Autorise Houmani à utiliser ta position'), findsOneWidget);
      expect(find.textContaining('Position GPS enregistrée'), findsNothing);
    });

    testWidgets('Hors ligne : point gardé, pas de requête, lieu à écrire',
        (WidgetTester tester) async {
      fauxGps(ennasr);
      fauxServeur(reponseJson({'address': {'road': 'Rue'}}));
      connexion.enLigne = false;
      await afficher(tester, const CreateSignalementScreen());

      await tester.tap(find.text('Utiliser ma position'));
      await tester.pumpAndSettle();
      expect(find.text(AdresseM3.messageHorsLigne), findsOneWidget);
      expect(find.textContaining('Position GPS enregistrée'), findsOneWidget);
      expect(requetes, isEmpty);
    });

    testWidgets('"Voir sur la carte" : l\'application de cartes (lien geo:)',
        (WidgetTester tester) async {
      final List<Uri> ouverts = [];
      LiensM3.ouvrirUrl = (url) async {
        ouverts.add(url);
        return true; // une application de cartes répond
      };
      // Un signalement avec un point GPS (copie de r3)
      final Signalement r3 = depot.tous.firstWhere((s) => s.id == 'r3');
      await depot.ajouterSignalement(r3.copyWith(id: 'avecgps', position: ennasr));
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'avecgps'));

      expect(find.text('36.86251, 10.17003'), findsOneWidget);
      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(ouverts.single.scheme, 'geo');
      expect(ouverts.single.toString(),
          'geo:36.86251,10.17003?q=36.86251,10.17003(Fuite%20d\'eau%20devant%20l\'entr%C3%A9e)');
    });

    testWidgets('Pas d\'application de cartes : OpenStreetMap ; rien : message',
        (WidgetTester tester) async {
      final List<Uri> ouverts = [];
      bool navigateur = true;
      LiensM3.ouvrirUrl = (url) async {
        ouverts.add(url);
        return url.scheme == 'https' && navigateur;
      };
      final Signalement r3 = depot.tous.firstWhere((s) => s.id == 'r3');
      await depot.ajouterSignalement(r3.copyWith(id: 'avecgps', position: ennasr));
      await afficher(
          tester, const SignalementDetailScreen(signalementId: 'avecgps'));

      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(ouverts.map((u) => u.scheme), ['geo', 'https']);
      final Uri osm = ouverts.last;
      expect(osm.host, 'www.openstreetmap.org');
      expect(osm.queryParameters['mlat'], '36.86251');
      expect(osm.queryParameters['mlon'], '10.17003');
      expect(osm.fragment, 'map=18/36.86251/10.17003');
      expect(find.text(LiensM3.messageCarte), findsNothing);

      navigateur = false;
      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(find.text(LiensM3.messageCarte), findsOneWidget);
    });

    testWidgets('Détail sans point GPS : pas de ligne de carte',
        (WidgetTester tester) async {
      await afficher(tester, const SignalementDetailScreen(signalementId: 'r3'));
      expect(find.text('Voir sur la carte'), findsNothing);
    });
  });
}
