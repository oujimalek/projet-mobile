import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/quartier.dart' show PointGps;
import '../resultat.dart';

/// M3 - Ouvrir une autre application du téléphone (package url_launcher) :
///   - l'application de cartes, sur le point GPS d'un signalement ;
///   - le téléphone, pour appeler un numéro utile (STEG, SONEDE...) ;
///   - la fenêtre de partage (WhatsApp, SMS...), pour partager un signalement.
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

  static const String messageAppel =
      'Impossible d\'ouvrir le téléphone sur cet appareil';

  /// Le lien d'appel : tel:80100444 (ouvre le clavier du téléphone avec le
  /// numéro ; l'utilisateur appuie lui-même sur "Appeler", pas besoin de
  /// permission).
  static Uri urlAppel(String numero) {
    return Uri(scheme: 'tel', path: numero);
  }

  /// "Appeler" un numéro utile.
  static Future<Resultat<void>> appeler(String numero) async {
    if (await ouvrirUrl(urlAppel(numero))) {
      return const Resultat.succes(null);
    }
    return const Resultat.echec(messageAppel);
  }

  // =====================================================================
  // Partager (package share_plus, même version que le module 4)
  // =====================================================================

  /// Ouvre la fenêtre de partage du téléphone (WhatsApp, SMS, e-mail...)
  /// avec [texte]. false : le partage n'est pas possible. Remplaçable.
  static Future<bool> Function(String texte, String sujet) partagerTexte =
      _sharePlus;

  static Future<bool> _sharePlus(String texte, String sujet) async {
    try {
      final ShareResult resultat = await SharePlus.instance.share(
        ShareParams(text: texte, subject: sujet),
      );
      // "dismissed" : l'utilisateur a fermé la fenêtre, ce n'est pas une erreur
      return resultat.status != ShareResultStatus.unavailable;
    } catch (erreur) {
      return false;
    }
  }

  static const String messagePartage = 'Impossible de partager sur ce téléphone';

  /// "Partager" : le texte du signalement.
  static Future<Resultat<void>> partager(String texte, String sujet) async {
    if (await partagerTexte(texte, sujet)) {
      return const Resultat.succes(null);
    }
    return const Resultat.echec(messagePartage);
  }

  /// Remet les vraies fonctions (tests).
  static void reinitialiser() {
    ouvrirUrl = _ouvrirExterne;
    partagerTexte = _sharePlus;
  }
}
