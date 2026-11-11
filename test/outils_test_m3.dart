import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/connexion_m3.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fausse_connexion_m3.dart';

bool _sqlitePret = false;

/// M3 - Prépare le hors ligne pour un test :
///   - SQLite sur l'ordinateur (sqflite_common_ffi), base NEUVE en mémoire ;
///   - fausse connexion (en ligne au départ) ;
///   - SyncSignalementsM3 neuf.
/// À appeler dans setUp ; [nettoyerHorsLigneM3] dans tearDown.
///
/// "NoIsolate" : SQLite tourne dans le même fil que le test, ce qui marche
/// aussi dans testWidgets (temps simulé).
FausseConnexionM3 installerHorsLigneM3() {
  if (!_sqlitePret) {
    // Une seule fois par fichier de test (sqflite affiche un avertissement
    // à chaque changement de fabrique)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    _sqlitePret = true;
  }
  BaseLocaleM3.instance = BaseLocaleM3(chemin: inMemoryDatabasePath);
  final FausseConnexionM3 connexion = FausseConnexionM3();
  ConnexionM3.instance = connexion;
  SyncSignalementsM3.instance = SyncSignalementsM3();
  return connexion;
}

/// Ferme la base en mémoire (elle disparaît) et arrête l'écoute du réseau.
Future<void> nettoyerHorsLigneM3(FausseConnexionM3 connexion) async {
  await SyncSignalementsM3.instance.arreter();
  await BaseLocaleM3.instance.fermer();
  await connexion.fermer();
}
