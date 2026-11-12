import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/cache_local.dart';
import 'package:houmani/data/services/meteo_m1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// M1 - Service web Open-Meteo : lecture de la réponse, cache SQLite,
// hors ligne. Le réseau est remplacé par un MockClient (aucune vraie requête).
const PointGps _tunis = PointGps(36.8065, 10.1815);

String _reponse({double temperature = 24.3, int code = 0}) {
  return jsonEncode({
    'latitude': 36.8,
    'longitude': 10.18,
    'current': {'temperature_2m': temperature, 'weather_code': code},
    'daily': {
      'temperature_2m_max': [27.1],
      'temperature_2m_min': [18.4],
    },
  });
}

void main() {
  late Directory dossier;
  late CacheLocal cache;
  late int requetes;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('houmani_meteo_');
    cache = CacheLocal(dossier: dossier.path);
    requetes = 0;
    MeteoM1.cache = cache;
    MeteoM1.client = MockClient((requete) async {
      requetes++;
      return http.Response(_reponse(), 200);
    });
  });

  tearDown(() async {
    await cache.fermer();
    MeteoM1.reinitialiser();
    try {
      dossier.deleteSync(recursive: true);
    } catch (e) {
      // Windows garde parfois le fichier verrouillé : sans importance
    }
  });

  group('lecture de la réponse', () {
    test('température, code, max et min', () {
      final Meteo? meteo = MeteoM1.depuisReponse(
        jsonDecode(_reponse()) as Map<String, dynamic>,
        _tunis,
        DateTime(2026, 7, 1, 12),
      );
      expect(meteo, isNotNull);
      expect(meteo!.temperature, 24.3);
      expect(meteo.code, 0);
      expect(meteo.max, 27.1);
      expect(meteo.min, 18.4);
    });

    test('réponse sans "current" : null', () {
      expect(
        MeteoM1.depuisReponse({'error': true}, _tunis, DateTime(2026)),
        isNull,
      );
    });

    test('toJson / fromJson aller-retour', () {
      final Meteo meteo = Meteo(
        temperature: 12.5,
        code: 61,
        recueLe: DateTime(2026, 1, 1, 8),
        latitude: 36.8,
        longitude: 10.18,
      );
      final Meteo copie = Meteo.fromJson(
        jsonDecode(jsonEncode(meteo.toJson())) as Map<String, dynamic>,
      );
      expect(copie.temperature, 12.5);
      expect(copie.code, 61);
      expect(copie.max, isNull);
      expect(copie.recueLe, DateTime(2026, 1, 1, 8));
    });

    test('description des codes WMO', () {
      expect(MeteoM1.description(0).$1, 'Ciel dégagé');
      expect(MeteoM1.description(63).$1, 'Pluie');
      expect(MeteoM1.description(95).$1, 'Orage');
    });
  });

  group('cache et hors ligne', () {
    test('la URL contient la position et les champs demandés', () {
      final Uri url = MeteoM1.urlPour(_tunis);
      expect(url.host, 'api.open-meteo.com');
      expect(url.queryParameters['latitude'], '36.8065');
      expect(url.queryParameters['current'], 'temperature_2m,weather_code');
    });

    test('deuxième appel dans les 30 min : pas de nouvelle requête', () async {
      final DateTime midi = DateTime(2026, 7, 1, 12);
      final Resultat<Meteo> premier =
          await MeteoM1.meteoDe(_tunis, maintenant: midi);
      final Resultat<Meteo> second = await MeteoM1.meteoDe(
        _tunis,
        maintenant: midi.add(const Duration(minutes: 10)),
      );
      expect(premier.estSucces, isTrue);
      expect(second.donnee!.temperature, 24.3);
      expect(requetes, 1);
    });

    test('après 30 min : nouvelle requête', () async {
      final DateTime midi = DateTime(2026, 7, 1, 12);
      await MeteoM1.meteoDe(_tunis, maintenant: midi);
      await MeteoM1.meteoDe(
        _tunis,
        maintenant: midi.add(const Duration(minutes: 45)),
      );
      expect(requetes, 2);
    });

    test('hors ligne : la dernière météo gardée est renvoyée', () async {
      final DateTime midi = DateTime(2026, 7, 1, 12);
      await MeteoM1.meteoDe(_tunis, maintenant: midi);

      MeteoM1.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<Meteo> resultat = await MeteoM1.meteoDe(
        _tunis,
        maintenant: midi.add(const Duration(hours: 3)),
      );
      expect(resultat.estSucces, isTrue);
      expect(resultat.donnee!.recueLe, midi); // marquée ancienne par sa date
    });

    test('hors ligne et rien en cache : échec', () async {
      MeteoM1.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<Meteo> resultat = await MeteoM1.meteoDe(_tunis);
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, MeteoM1.messageIndisponible);
    });

    test('autre quartier : le cache ne sert pas', () async {
      final DateTime midi = DateTime(2026, 7, 1, 12);
      await MeteoM1.meteoDe(_tunis, maintenant: midi);
      await MeteoM1.meteoDe(const PointGps(35.8256, 10.6084), maintenant: midi);
      expect(requetes, 2);
    });

    test('erreur serveur (500) : échec propre', () async {
      MeteoM1.client = MockClient((requete) async {
        return http.Response('oups', 500);
      });
      final Resultat<Meteo> resultat = await MeteoM1.meteoDe(_tunis);
      expect(resultat.estSucces, isFalse);
    });
  });
}
