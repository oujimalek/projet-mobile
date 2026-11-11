import 'dart:async';

import 'package:houmani/data/services/connexion_m3.dart';

/// M3 - Fausse connexion pour les TESTS : on décide si le téléphone a du
/// réseau, et on peut simuler son retour (`reseauRevient()`).
class FausseConnexionM3 implements ConnexionM3 {
  bool enLigne;

  FausseConnexionM3({this.enLigne = true});

  final StreamController<bool> _changements =
      StreamController<bool>.broadcast();

  @override
  Future<bool> estEnLigne() async {
    return enLigne;
  }

  @override
  Stream<bool> ecouter() {
    return _changements.stream;
  }

  /// Simule la perte du réseau.
  void coupure() {
    enLigne = false;
    _changements.add(false);
  }

  /// Simule le retour du réseau (SyncSignalementsM3 envoie alors la file).
  void reseauRevient() {
    enLigne = true;
    _changements.add(true);
  }

  Future<void> fermer() async {
    await _changements.close();
  }
}
