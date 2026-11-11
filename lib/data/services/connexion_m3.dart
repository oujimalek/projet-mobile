import 'package:connectivity_plus/connectivity_plus.dart';

/// M3 - Le téléphone a-t-il du réseau ?
///
/// Pourquoi le demander AVANT d'écrire dans Firestore : hors ligne,
/// `await collection.add(...)` ne se termine jamais (Firestore attend le
/// serveur). L'écran resterait bloqué sur « Envoi... ». On vérifie donc le
/// réseau d'abord : sans réseau, le signalement part dans la file SQLite
/// (voir SyncSignalementsM3).
///
/// Même modèle que les repositories : une classe abstraite, une version
/// réelle (connectivity_plus) et une fausse version dans les tests
/// (`ConnexionM3.instance = FausseConnexionM3()`).
abstract class ConnexionM3 {
  /// La version utilisée par l'application.
  static ConnexionM3 instance = ConnexionPlusM3();

  /// `ConnexionM3()` renvoie l'instance ci-dessus.
  factory ConnexionM3() {
    return instance;
  }

  /// true = Wi-Fi, données mobiles ou Ethernet actifs.
  Future<bool> estEnLigne();

  /// Prévient à chaque changement (true = le réseau revient).
  Stream<bool> ecouter();
}

/// Version réelle, avec le package connectivity_plus.
///
/// Limite : connectivity_plus sait si une interface réseau est active, pas
/// si Internet répond vraiment (Wi-Fi sans Internet). C'est pourquoi
/// SyncSignalementsM3 ajoute aussi un délai maximum à chaque envoi.
class ConnexionPlusM3 implements ConnexionM3 {
  final Connectivity _connectivity = Connectivity();

  /// Au moins une interface autre que "none".
  static bool _aUnReseau(List<ConnectivityResult> resultats) {
    for (final ConnectivityResult resultat in resultats) {
      if (resultat != ConnectivityResult.none) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> estEnLigne() async {
    try {
      // 3 s maximum : si le plugin ne répond pas, on n'attend pas sans fin
      final List<ConnectivityResult> resultats = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      return _aUnReseau(resultats);
    } catch (erreur) {
      // Plugin absent ou muet (tests, ordinateur) : on essaie comme si on
      // était en ligne ; le délai maximum de l'envoi protège l'écran.
      return true;
    }
  }

  @override
  Stream<bool> ecouter() {
    try {
      return _connectivity.onConnectivityChanged
          .map(_aUnReseau)
          .handleError((Object erreur) {});
    } catch (erreur) {
      return const Stream<bool>.empty();
    }
  }
}
