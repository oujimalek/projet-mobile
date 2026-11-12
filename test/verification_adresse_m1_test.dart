import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/cache_local.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/data/services/verification_adresse_m1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// M1 - Vérification de l'adresse d'une demande (Nominatim + contour du
// quartier). Le réseau est remplacé par un MockClient (aucune vraie requête).

// Un carré d'environ 1 km autour de (36.85, 10.18)
const Quartier _quartier = Quartier(
  id: 'q1',
  nom: 'Résidence El Yasmine',
  localisation: 'Ennasr 2, Ariana',
  contour: [
    PointGps(36.845, 10.175),
    PointGps(36.845, 10.185),
    PointGps(36.855, 10.185),
    PointGps(36.855, 10.175),
  ],
);

String _trouve(double lat, double lng) {
  return jsonEncode([
    {'lat': '$lat', 'lon': '$lng', 'display_name': '12 rue des Jasmins'},
  ]);
}

void main() {
  late Directory dossier;
  late CacheLocal cache;
  late int requetes;
  late Uri? derniereUrl;
  late String reponse;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('houmani_adresse_');
    cache = CacheLocal(dossier: dossier.path);
    requetes = 0;
    derniereUrl = null;
    reponse = _trouve(36.85, 10.18); // dans le carré
    VerificationAdresseM1.cache = cache;
    VerificationAdresseM1.intervalle = Duration.zero; // tests rapides
    VerificationAdresseM1.client = MockClient((requete) async {
      requetes++;
      derniereUrl = requete.url;
      expect(requete.headers['User-Agent'], VerificationAdresseM1.userAgent);
      return http.Response(reponse, 200);
    });
  });

  tearDown(() async {
    await cache.fermer();
    VerificationAdresseM1.reinitialiser();
    try {
      dossier.deleteSync(recursive: true);
    } catch (e) {
      // Windows garde parfois le fichier verrouillé : sans importance
    }
  });

  group('fonctions pures', () {
    test('la recherche ajoute la localisation du quartier', () {
      expect(
        VerificationAdresseM1.requetePour(' 12 rue des Jasmins ', _quartier),
        '12 rue des Jasmins, Ennasr 2, Ariana',
      );
      // Déjà dans l'adresse : pas ajoutée deux fois
      expect(
        VerificationAdresseM1.requetePour(
            '12 rue des Jasmins, ennasr 2, ariana', _quartier),
        '12 rue des Jasmins, ennasr 2, ariana',
      );
    });

    test('la clé du cache ignore majuscules et espaces', () {
      expect(
        VerificationAdresseM1.cleCache('  12  Rue des JASMINS '),
        '12 rue des jasmins',
      );
    });

    test('l\'URL vise la Tunisie, 1 résultat, autour du quartier', () {
      final Uri url = VerificationAdresseM1.urlPour(
        'rue X',
        autour: const PointGps(36.85, 10.18),
      );
      expect(url.host, 'nominatim.openstreetmap.org');
      expect(url.path, '/search');
      expect(url.queryParameters['countrycodes'], 'tn');
      expect(url.queryParameters['limit'], '1');
      expect(url.queryParameters['viewbox'], '10.0800,36.9500,10.2800,36.7500');
    });

    test('lecture de la réponse', () {
      final PointGps? point =
          VerificationAdresseM1.depuisReponse(jsonDecode(_trouve(36.8, 10.1)));
      expect(point!.latitude, 36.8);
      expect(point.longitude, 10.1);
      expect(VerificationAdresseM1.depuisReponse([]), isNull);
      expect(VerificationAdresseM1.depuisReponse({'error': 'x'}), isNull);
      expect(
        VerificationAdresseM1.depuisReponse([
          {'lat': 'abc', 'lon': '10'},
        ]),
        isNull,
      );
    });

    test('distance : 0,01° de latitude ≈ 1,1 km', () {
      final double d = VerificationAdresseM1.distanceMetres(
        const PointGps(36.85, 10.18),
        const PointGps(36.86, 10.18),
      );
      expect(d, closeTo(1112, 5));
    });

    test('verdicts', () {
      expect(
        VerificationAdresseM1.juger(null, _quartier).etat,
        EtatAdresse.introuvable,
      );
      expect(
        VerificationAdresseM1.juger(const PointGps(36.85, 10.18), _quartier)
            .etat,
        EtatAdresse.dansLeQuartier,
      );
      final VerdictAdresse loin =
          VerificationAdresseM1.juger(const PointGps(36.80, 10.18), _quartier);
      expect(loin.etat, EtatAdresse.horsDuQuartier);
      expect(loin.distanceMetres, closeTo(5560, 20));
      const Quartier sansContour = Quartier(
        id: 'q2',
        nom: 'Sans limites',
        localisation: 'Tunis',
        position: PointGps(36.85, 10.18),
      );
      expect(
        VerificationAdresseM1.juger(const PointGps(36.85, 10.18), sansContour)
            .etat,
        EtatAdresse.sansContour,
      );
    });
  });

  group('verifier (réseau simulé)', () {
    test('adresse dans le quartier', () async {
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      expect(r.estSucces, isTrue);
      expect(r.donnee!.etat, EtatAdresse.dansLeQuartier);
      expect(requetes, 1);
      expect(derniereUrl!.queryParameters['q'],
          '12 rue des Jasmins, Ennasr 2, Ariana');
    });

    test('adresse hors du quartier', () async {
      reponse = _trouve(36.80, 10.18);
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('Rue de Marseille', _quartier);
      expect(r.donnee!.etat, EtatAdresse.horsDuQuartier);
    });

    test('adresse introuvable (liste vide)', () async {
      reponse = '[]';
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('zzz', _quartier);
      expect(r.donnee!.etat, EtatAdresse.introuvable);
    });

    test('2e vérification : depuis le cache, sans requête', () async {
      await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      final Resultat<VerdictAdresse> r = await VerificationAdresseM1.verifier(
          '12  RUE des jasmins', _quartier);
      expect(requetes, 1);
      expect(r.donnee!.etat, EtatAdresse.dansLeQuartier);
    });

    test('"introuvable" est aussi gardé en cache', () async {
      reponse = '[]';
      await VerificationAdresseM1.verifier('zzz', _quartier);
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('zzz', _quartier);
      expect(requetes, 1);
      expect(r.donnee!.etat, EtatAdresse.introuvable);
    });

    test('hors ligne sans cache : échec, rien de gardé', () async {
      VerificationAdresseM1.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      expect(r.estSucces, isFalse);
      expect(r.erreur, VerificationAdresseM1.messageIndisponible);
      expect(
        await cache.lireGeocodage('12 rue des jasmins, ennasr 2, ariana'),
        isNull,
      );
    });

    test('hors ligne avec cache : le verdict est quand même donné', () async {
      await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      VerificationAdresseM1.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      expect(r.donnee!.etat, EtatAdresse.dansLeQuartier);
    });

    test('erreur serveur (503) : échec', () async {
      VerificationAdresseM1.client = MockClient((requete) async {
        return http.Response('busy', 503);
      });
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      expect(r.estSucces, isFalse);
    });

    test('réponse trop lente : échec après le délai', () async {
      VerificationAdresseM1.delaiMax = const Duration(milliseconds: 50);
      VerificationAdresseM1.client = MockClient((requete) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response(reponse, 200);
      });
      final Resultat<VerdictAdresse> r =
          await VerificationAdresseM1.verifier('12 rue des Jasmins', _quartier);
      expect(r.estSucces, isFalse);
    });

    test('1 requête par seconde au plus (politique Nominatim)', () async {
      VerificationAdresseM1.intervalle = const Duration(milliseconds: 200);
      final Stopwatch chrono = Stopwatch()..start();
      await VerificationAdresseM1.verifier('rue A', _quartier);
      await VerificationAdresseM1.verifier('rue B', _quartier);
      await VerificationAdresseM1.verifier('rue C', _quartier);
      expect(requetes, 3);
      expect(chrono.elapsedMilliseconds, greaterThanOrEqualTo(380));
    });
  });

  group('cache SQLite (table geocodage)', () {
    test('expire après 30 jours', () async {
      final DateTime avant = DateTime(2026, 1, 1);
      await cache.enregistrerGeocodage('x', const PointGps(1, 2), date: avant);
      expect(
        await cache.lireGeocodage('x', maintenant: avant.add(
            const Duration(days: 29))),
        isNotNull,
      );
      expect(
        await cache.lireGeocodage('x', maintenant: avant.add(
            const Duration(days: 31))),
        isNull,
      );
    });

    test('un téléphone en version 1 reçoit la table (onUpgrade)', () async {
      await cache.fermer();
      final String chemin = p.join(dossier.path, CacheLocal.nomFichier);
      if (File(chemin).existsSync()) {
        File(chemin).deleteSync();
      }
      // Base "version 1" : sans la table geocodage
      final Database v1 = await openDatabase(
        chemin,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE profil (id TEXT PRIMARY KEY)');
        },
      );
      await v1.close();

      cache = CacheLocal(dossier: dossier.path);
      VerificationAdresseM1.cache = cache;
      await cache.enregistrerGeocodage('y', null);
      final ({PointGps? point})? lu = await cache.lireGeocodage('y');
      expect(lu, isNotNull);
      expect(lu!.point, isNull); // "introuvable" gardé
    });
  });

  group('règle de saisie de l\'adresse', () {
    test('vide accepté, trop courte ou trop longue refusée', () {
      expect(UtilisateurRepository.refusAdresse(''), isNull);
      expect(UtilisateurRepository.refusAdresse('   '), isNull);
      expect(UtilisateurRepository.refusAdresse('ab'), isNotNull);
      expect(UtilisateurRepository.refusAdresse('12 rue des Jasmins'), isNull);
      expect(UtilisateurRepository.refusAdresse('a' * 151), isNotNull);
    });
  });
}
