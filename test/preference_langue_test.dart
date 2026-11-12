import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/services/cache_local.dart';
import 'package:houmani/theme/preference_langue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Le choix de langue est gardé sur le téléphone (SQLite, dossier temporaire).
void main() {
  late Directory dossier;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('houmani_langue_');
    PreferenceLangue.cache = CacheLocal(dossier: dossier.path);
  });

  tearDown(() async {
    PreferenceLangue.langue.value = Langue.francais;
    await PreferenceLangue.cache.fermer();
    try {
      dossier.deleteSync(recursive: true);
    } catch (e) {
      // Windows peut garder le fichier un moment : on ignore
    }
  });

  test('sans choix enregistré : français', () async {
    await PreferenceLangue.charger();
    expect(PreferenceLangue.langue.value, Langue.francais);
  });

  test('le choix est enregistré puis relu au lancement', () async {
    await PreferenceLangue.choisir(Langue.derja);
    PreferenceLangue.langue.value = Langue.francais; // "redémarrage"
    await PreferenceLangue.charger();
    expect(PreferenceLangue.langue.value, Langue.derja);
  });
}
