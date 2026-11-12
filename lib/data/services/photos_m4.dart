import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../resultat.dart';

/// M4 - Les photos des événements, hébergées sur Cloudinary (offre gratuite).
///
/// Firebase Storage demande le plan payant Blaze : on envoie donc la photo
/// à Cloudinary, et on garde seulement son adresse (https) dans Firestore.
///
/// Envoi « unsigned » : l'app n'a AUCUNE clé secrète (le dépôt est public).
/// Le preset `houmani_evenements` (console Cloudinary → Settings → Upload)
/// range les photos dans le dossier houmani/evenements.
class PhotosM4 {
  PhotosM4._();

  static const String cloudName = 'pu3lxdrf';
  static const String preset = 'houmani_evenements';

  /// Le début de toutes nos adresses de photos (vérifié aussi par les règles).
  static const String prefixeUrl = 'https://res.cloudinary.com/$cloudName/';

  static const int tailleMax = 5 * 1024 * 1024; // 5 Mo

  /// true si [url] est bien une photo de notre compte Cloudinary.
  static bool estPhotoValide(String url) {
    return url.startsWith(prefixeUrl);
  }

  /// La version optimisée pour l'écran : recadrée en largeur [largeur],
  /// format et qualité choisis par Cloudinary (WebP/AVIF, plus léger).
  /// Ex : .../image/upload/v1/x.jpg → .../image/upload/c_fill,w_800,h_400,q_auto,f_auto/v1/x.jpg
  static String miniature(String url, {int largeur = 800, int hauteur = 400}) {
    const String marque = '/image/upload/';
    final int position = url.indexOf(marque);
    if (position < 0) {
      return url;
    }
    final int apres = position + marque.length;
    return '${url.substring(0, apres)}c_fill,w_$largeur,h_$hauteur,q_auto,f_auto/'
        '${url.substring(apres)}';
  }

  /// Envoie l'image à Cloudinary et renvoie son adresse https.
  static Future<Resultat<String>> envoyer(Uint8List octets, String nomFichier) async {
    if (octets.length > tailleMax) {
      return const Resultat.echec('Photo trop lourde (5 Mo au maximum)');
    }
    try {
      final http.MultipartRequest requete = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
      );
      requete.fields['upload_preset'] = preset;
      requete.files.add(
        http.MultipartFile.fromBytes('file', octets, filename: nomFichier),
      );
      final http.StreamedResponse reponse =
          await requete.send().timeout(const Duration(seconds: 60));
      final String corps = await reponse.stream.bytesToString();
      if (reponse.statusCode != 200) {
        return const Resultat.echec('L\'envoi de la photo a échoué, réessaie');
      }
      final Object? url = (jsonDecode(corps) as Map<String, dynamic>)['secure_url'];
      if (url is! String || !estPhotoValide(url)) {
        return const Resultat.echec('Réponse inattendue de Cloudinary');
      }
      return Resultat.succes(url);
    } catch (erreur) {
      return const Resultat.echec(
          'Impossible d\'envoyer la photo : vérifie ta connexion Internet');
    }
  }
}
