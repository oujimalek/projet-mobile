import 'package:url_launcher/url_launcher.dart';

import '../models/quartier.dart' show PointGps;
import '../resultat.dart';

/// M3 - Ouvrir une autre application du téléphone (package url_launcher) :
///   - l'application de cartes, sur le point GPS d'un signalement ;
///   - (étape 7) le téléphone, pour appeler un numéro utile.
///
/// On n'appelle PAS canLaunchUrl : on essaie d'ouvrir, et si ça échoue on
/// passe au plan B. Remplaçable dans les tests :
///   LiensM3.ouvrirUrl = (url) async { ouvertes.add(url); return true; };
class LiensM3 {
  LiensM3._(); // que des static

  /// Ouvre [url] dans une autre application. false : rien n'a pu l'ouvrir.
  static Future<bool> Function(Uri url) ouvrirUrl = _ouvrirExterne;

  static Future<bool> _ouvrirExterne(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (erreur) {
      return false; // pas d'application pour ce lien
    }
  }

  static const String messageCarte =
      'Impossible d\'ouvrir une carte sur ce téléphone';

  /// Lien « geo: » (Google Maps, OsmAnd, Maps.me...) avec un repère nommé :
  /// geo:36.8625,10.17?q=36.8625,10.17(Fuite%20d'eau)
  static Uri urlGeo(PointGps point, String libelle) {
    final String coordonnees = '${point.latitude},${point.longitude}';
    return Uri.parse(
      'geo:$coordonnees?q=$coordonnees(${Uri.encodeComponent(libelle)})',
    );
  }

  /// Plan B : la carte OpenStreetMap dans le navigateur, avec un repère.
  static Uri urlOpenStreetMap(PointGps point) {
    return Uri.https(
      'www.openstreetmap.org',
      '/',
      {
        'mlat': point.latitude.toString(),
        'mlon': point.longitude.toString(),
      },
    ).replace(fragment: 'map=18/${point.latitude}/${point.longitude}');
  }

  /// "Voir sur la carte" : l'application de cartes, sinon le navigateur.
  static Future<Resultat<void>> ouvrirCarte(PointGps point, String libelle) async {
    if (await ouvrirUrl(urlGeo(point, libelle))) {
      return const Resultat.succes(null);
    }
    if (await ouvrirUrl(urlOpenStreetMap(point))) {
      return const Resultat.succes(null);
    }
    return const Resultat.echec(messageCarte);
  }

  /// Remet le vrai lanceur (tests).
  static void reinitialiser() {
    ouvrirUrl = _ouvrirExterne;
  }
}
