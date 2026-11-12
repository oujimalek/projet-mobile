import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/base_locale_m2.dart';
import 'package:houmani/data/services/jours_feries_m2.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// M2 - Service web Nager.Date (jours fériés tunisiens) + cache SQLite.
// Le réseau est remplacé par un MockClient (aucune vraie requête).
final String _reponse2026 = jsonEncode([
  {
    'date': '2026-03-20',
    'localName': 'عيد الإستقلال',
    'name': 'Independence Day',
    'countryCode': 'TN',
  },
  {
    'date': '2026-07-25',
    'localName': 'عيد الجمهورية',
    'name': 'Republic Day',
    'countryCode': 'TN',
  },
]);

void main() {
  late int requetes;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await BaseLocaleM2.fermer();
    BaseLocaleM2.cheminPourTests = inMemoryDatabasePath;
    requetes = 0;
    JoursFeriesM2.client = MockClient((requete) async {
      requetes++;
      return http.Response.bytes(utf8.encode(_reponse2026), 200);
    });
  });

  tearDown(() async {
    await BaseLocaleM2.fermer();
    JoursFeriesM2.reinitialiser();
  });

  group('lecture de la réponse', () {
    test('dates et noms traduits en français', () {
      final Map<String, String> jours =
          JoursFeriesM2.depuisReponse(jsonDecode(_reponse2026));
      expect(jours, {
        '2026-03-20': 'Fête de l\'Indépendance',
        '2026-07-25': 'Fête de la République',
      });
    });

    test('nom inconnu : gardé tel quel ; éléments mal formés ignorés', () {
      final Map<String, String> jours = JoursFeriesM2.depuisReponse([
        {'date': '2026-05-01', 'name': 'Some New Day'},
        {'date': 12, 'name': 'Bad'},
        'pas un objet',
      ]);
      expect(jours, {'2026-05-01': 'Some New Day'});
    });

    test('réponse qui n\'est pas une liste : vide', () {
      expect(JoursFeriesM2.depuisReponse({'error': 'x'}), isEmpty);
    });

    test('clé d\'un jour au format AAAA-MM-JJ', () {
      expect(JoursFeriesM2.cle(DateTime(2026, 3, 9, 15, 30)), '2026-03-09');
    });

    test('URL de l\'API', () {
      expect(
        JoursFeriesM2.urlPour(2026).toString(),
        'https://date.nager.at/api/v3/PublicHolidays/2026/TN',
      );
    });
  });

  group('cache SQLite', () {
    test('une seule requête par année', () async {
      final Resultat<Map<String, String>> premier =
          await JoursFeriesM2.joursDe(2026);
      final Resultat<Map<String, String>> second =
          await JoursFeriesM2.joursDe(2026);
      expect(premier.donnee!.length, 2);
      expect(second.donnee!['2026-07-25'], 'Fête de la République');
      expect(requetes, 1);
    });

    test('hors ligne après un premier chargement : le cache répond',
        () async {
      await JoursFeriesM2.joursDe(2026);
      JoursFeriesM2.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<Map<String, String>> resultat =
          await JoursFeriesM2.joursDe(2026);
      expect(resultat.estSucces, isTrue);
      expect(resultat.donnee!.length, 2);
    });

    test('hors ligne sans cache : échec', () async {
      JoursFeriesM2.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<Map<String, String>> resultat =
          await JoursFeriesM2.joursDe(2026);
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, JoursFeriesM2.messageIndisponible);
    });

    test('les années sont gardées séparément', () async {
      await BaseLocaleM2.enregistrerJoursFeries(2025, {'2025-01-01': 'A'});
      await BaseLocaleM2.enregistrerJoursFeries(2026, {'2026-01-01': 'B'});
      await BaseLocaleM2.enregistrerJoursFeries(2026, {'2026-03-20': 'C'});
      expect(await BaseLocaleM2.joursFeries(2025), {'2025-01-01': 'A'});
      expect(await BaseLocaleM2.joursFeries(2026), {'2026-03-20': 'C'});
    });
  });
}
