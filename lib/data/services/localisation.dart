import 'package:geolocator/geolocator.dart';

import '../models/quartier.dart';
import '../resultat.dart';

/// M1 - La position GPS du téléphone (paquet geolocator).
///
/// Sert à "Me localiser" : trouver le quartier dont le contour contient
/// la position. Remplaçable dans les tests (pas de GPS) :
///   Localisation.positionActuelle = () async => Resultat.succes(...);
class Localisation {
  static Future<Resultat<PointGps>> Function() positionActuelle = _gps;

  static Future<Resultat<PointGps>> _gps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const Resultat.echec('Active la localisation du téléphone');
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // La fenêtre "Autoriser Houmani à accéder à ta position ?"
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const Resultat.echec('Autorise Houmani à utiliser ta position');
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return Resultat.succes(PointGps(position.latitude, position.longitude));
    } catch (e) {
      return const Resultat.echec('Position introuvable, réessaie dehors');
    }
  }
}
