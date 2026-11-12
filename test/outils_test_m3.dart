import 'dart:io';

import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/adresse_m3.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/connexion_m3.dart';
import 'package:houmani/data/services/liens_m3.dart';
import 'package:houmani/data/services/localisation.dart';
import 'package:houmani/data/services/photos_m3.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fausse_connexion_m3.dart';

bool _sqlitePret = false;
Directory? _dossierPhotos;

// Le vrai GPS du module 1, gardé pour le remettre après chaque test
Future<Resultat<PointGps>> Function()? _gpsOriginal;

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
  _gpsOriginal ??= Localisation.positionActuelle;
  // Les photos du test vont dans un dossier temporaire neuf
  final Directory dossier = Directory.systemTemp.createTempSync('m3_photos_');
  _dossierPhotos = dossier;
  PhotosM3.dossierApplication = () async => dossier;
  BaseLocaleM3.instance = BaseLocaleM3(chemin: inMemoryDatabasePath);
  final FausseConnexionM3 connexion = FausseConnexionM3();
  ConnexionM3.instance = connexion;
  SyncSignalementsM3.instance = SyncSignalementsM3();
  return connexion;
}

/// Ferme la base en mémoire (elle disparaît), arrête l'écoute du réseau,
/// remet le vrai GPS et le vrai service d'adresse.
Future<void> nettoyerHorsLigneM3(FausseConnexionM3 connexion) async {
  await SyncSignalementsM3.instance.arreter();
  await BaseLocaleM3.instance.fermer();
  await connexion.fermer();
  final Future<Resultat<PointGps>> Function()? gps = _gpsOriginal;
  if (gps != null) {
    Localisation.positionActuelle = gps;
  }
  AdresseM3.reinitialiser();
  PhotosM3.reinitialiser();
  LiensM3.reinitialiser();
  try {
    _dossierPhotos?.deleteSync(recursive: true);
  } catch (erreur) {
    // déjà supprimé
  }
  _dossierPhotos = null;
}

/// Le dossier temporaire des photos du test en cours.
Directory dossierPhotosTest() => _dossierPhotos!;

/// Crée une fausse photo de [taille] octets dans le dossier temporaire
/// (comme si image_picker l'avait choisie) et renvoie son chemin.
String faussePhoto({int taille = 1000, String nom = 'choisie.jpg'}) {
  final File fichier = File('${dossierPhotosTest().path}/$nom');
  fichier.writeAsBytesSync(List<int>.filled(taille, 7));
  return fichier.path;
}

/// Un faux GPS qui répond toujours [point].
void fauxGps(PointGps point) {
  Localisation.positionActuelle = () async => Resultat.succes(point);
}

/// Un faux service d'adresse qui répond toujours [adresse].
void fausseAdresse(String adresse) {
  AdresseM3.adresseDe = (point) async => Resultat.succes(adresse);
}
