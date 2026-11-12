import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as chemins;
import 'package:path_provider/path_provider.dart';

import '../resultat.dart';

/// M3 - Les photos des signalements, hébergées sur Cloudinary (offre
/// gratuite), comme les photos du module 4 (Firebase Storage demande le
/// plan payant Blaze). Firestore ne garde que l'adresse https.
///
/// Envoi « unsigned » : l'application n'a AUCUNE clé secrète (dépôt public).
/// Le preset `houmani_signalements` (console Cloudinary → Settings →
/// Upload) range les photos dans houmani/signalements, choisit lui-même le
/// nom du fichier, et limite le format et la taille (voir
/// docs/module3_photos.md). L'application n'envoie QUE `upload_preset` et le
/// fichier : jamais de `public_id` (sinon on pourrait écraser une photo).
///
/// Cycle d'une photo choisie :
///   1. image_picker (appareil photo / galerie), réduite à 1600 px ;
///   2. copiée dans le dossier de l'application (photos_m3/) : le cache
///      d'image_picker peut être vidé par Android, or la photo doit
///      attendre si le signalement part plus tard (file d'envoi SQLite) ;
///   3. envoyée à Cloudinary au moment de publier ;
///   4. le fichier local est supprimé une fois le signalement envoyé.
///
/// Remplaçable dans les tests : [envoi], [choisir], [dossierApplication],
/// [client].
class PhotosM3 {
  PhotosM3._(); // que des static

  static const String cloudName = 'pu3lxdrf';
  static const String preset = 'houmani_signalements';
  static const String dossierCloudinary = 'houmani/signalements';

  /// Le début de toutes nos adresses de photos (vérifié aussi par les règles).
  static const String prefixeUrl = 'https://res.cloudinary.com/$cloudName/';

  static const int tailleMax = 5 * 1024 * 1024; // 5 Mo

  static const String messageTropLourde = 'Photo trop lourde (5 Mo au maximum)';
  static const String messageReseau =
      'Impossible d\'envoyer la photo : vérifie ta connexion Internet';
  static const String messageEchec = 'L\'envoi de la photo a échoué, réessaie';
  static const String messageReponse = 'Réponse inattendue de Cloudinary';
  static const String messageIntrouvable =
      'La photo n\'est plus sur le téléphone';

  /// Envoie des octets à Cloudinary → adresse https (remplaçable).
  static Future<Resultat<String>> Function(Uint8List octets, String nomFichier)
      envoi = cloudinary;

  /// Ouvre l'appareil photo ou la galerie → chemin du fichier choisi
  /// (succès null : l'utilisateur a annulé). Remplaçable.
  static Future<Resultat<String?>> Function(ImageSource source) choisir =
      _imagePicker;

  /// Le dossier de l'application (remplaçable : dossier temporaire en test).
  static Future<Directory> Function() dossierApplication =
      getApplicationDocumentsDirectory;

  static http.Client client = http.Client();
  static Duration delaiMax = const Duration(seconds: 60);

  /// Remet tout comme dans l'application (tests).
  static void reinitialiser() {
    envoi = cloudinary;
    choisir = _imagePicker;
    dossierApplication = getApplicationDocumentsDirectory;
    client = http.Client();
    delaiMax = const Duration(seconds: 60);
  }

  /// true si [url] est bien une photo de notre compte Cloudinary.
  static bool estPhotoValide(String url) {
    return url.startsWith(prefixeUrl);
  }

  /// La version optimisée pour l'écran : recadrée en [largeur] × [hauteur],
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

  // =====================================================================
  // Choisir une photo
  // =====================================================================

  static Future<Resultat<String?>> _imagePicker(ImageSource source) async {
    try {
      final XFile? image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600, // assez pour voir le problème, bien plus léger
        imageQuality: 80,
      );
      return Resultat.succes(image?.path);
    } on PlatformException catch (erreur) {
      if (erreur.code.contains('access_denied')) {
        return Resultat.echec(source == ImageSource.camera
            ? 'Autorise Houmani à utiliser l\'appareil photo'
            : 'Autorise Houmani à accéder à tes photos');
      }
      return const Resultat.echec('Impossible d\'ouvrir les photos');
    } catch (erreur) {
      return const Resultat.echec('Impossible d\'ouvrir les photos');
    }
  }

  // Les fichiers sont lus et écrits avec les méthodes "Sync" : une photo
  // réduite pèse quelques centaines de Ko, c'est immédiat, le code reste
  // simple, et il marche aussi dans les tests de widgets (temps simulé).

  /// Le dossier photos_m3/ de l'application (créé s'il n'existe pas).
  static Future<Directory> _dossierPhotos() async {
    final Directory dossier = Directory(
      chemins.join((await dossierApplication()).path, 'photos_m3'),
    );
    dossier.createSync(recursive: true);
    return dossier;
  }

  /// Copie la photo choisie dans le dossier de l'application
  /// (`photos_m3/photo_<heure>.jpg`) et renvoie son nouveau chemin.
  static Future<Resultat<String>> garderSurTelephone(String cheminChoisi) async {
    try {
      final File source = File(cheminChoisi);
      if (source.lengthSync() > tailleMax) {
        return const Resultat.echec(messageTropLourde);
      }
      final Directory dossier = await _dossierPhotos();
      String extension = chemins.extension(cheminChoisi).toLowerCase();
      if (extension.isEmpty) {
        extension = '.jpg';
      }
      final String nom =
          'photo_${DateTime.now().microsecondsSinceEpoch}$extension';
      final File copie = source.copySync(chemins.join(dossier.path, nom));
      return Resultat.succes(copie.path);
    } catch (erreur) {
      return const Resultat.echec('Impossible de garder la photo');
    }
  }

  /// Supprime une photo locale (déjà envoyée, annulée, remplacée).
  /// Ne lève jamais d'erreur.
  static Future<void> supprimerLocale(String? chemin) async {
    if (chemin == null) {
      return;
    }
    try {
      final File fichier = File(chemin);
      if (fichier.existsSync()) {
        fichier.deleteSync();
      }
    } catch (erreur) {
      // déjà supprimée, ou dossier inaccessible : rien à faire
    }
  }

  /// Supprime les photos de photos_m3/ que plus rien n'utilise (ni un
  /// brouillon, ni la file d'envoi). Renvoie le nombre supprimé.
  static Future<int> nettoyer(Set<String> cheminsUtilises) async {
    int supprimees = 0;
    try {
      final Directory dossier = await _dossierPhotos();
      for (final FileSystemEntity fichier in dossier.listSync()) {
        if (fichier is File && !cheminsUtilises.contains(fichier.path)) {
          fichier.deleteSync();
          supprimees++;
        }
      }
    } catch (erreur) {
      // dossier inaccessible : on réessaiera au prochain démarrage
    }
    return supprimees;
  }

  // =====================================================================
  // Envoyer à Cloudinary
  // =====================================================================

  /// Lit la photo locale et l'envoie ([envoi]).
  static Future<Resultat<String>> envoyerFichier(String chemin) async {
    final Uint8List octets;
    try {
      octets = File(chemin).readAsBytesSync();
    } catch (erreur) {
      return const Resultat.echec(messageIntrouvable);
    }
    return envoi(octets, chemins.basename(chemin));
  }

  /// Envoie l'image à Cloudinary et renvoie son adresse https.
  static Future<Resultat<String>> cloudinary(
    Uint8List octets,
    String nomFichier,
  ) async {
    if (octets.length > tailleMax) {
      return const Resultat.echec(messageTropLourde);
    }
    final http.MultipartRequest requete = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    );
    // Seulement le preset : le dossier, le nom (unique) et les limites sont
    // décidés par le preset côté Cloudinary. Jamais de public_id.
    requete.fields['upload_preset'] = preset;
    requete.files.add(
      http.MultipartFile.fromBytes('file', octets, filename: nomFichier),
    );

    final http.StreamedResponse reponse;
    final String corps;
    try {
      reponse = await client.send(requete).timeout(delaiMax);
      corps = await reponse.stream.bytesToString().timeout(delaiMax);
    } catch (erreur) {
      // délai dépassé, pas de réseau...
      return const Resultat.echec(messageReseau);
    }
    if (reponse.statusCode != 200) {
      return const Resultat.echec(messageEchec);
    }
    try {
      final Object? url = (jsonDecode(corps) as Map<String, dynamic>)['secure_url'];
      if (url is! String || !estPhotoValide(url)) {
        return const Resultat.echec(messageReponse);
      }
      return Resultat.succes(url);
    } catch (erreur) {
      return const Resultat.echec(messageReponse);
    }
  }
}
