import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/quartier.dart' show PointGps;
import '../resultat.dart';
import 'base_locale_m3.dart';
import 'connexion_m3.dart';

/// M3 - Une adresse lisible à partir d'un point GPS (« géocodage inverse »).
///
/// Service web externe GRATUIT : Nominatim, d'OpenStreetMap.
///   GET https://nominatim.openstreetmap.org/reverse?format=jsonv2
///       &lat=36.8625&lon=10.17&accept-language=fr
/// Sa politique d'utilisation impose :
///   - un User-Agent qui identifie l'application ('tn.esprit.houmani') ;
///   - au maximum 1 requête par seconde ;
///   - de garder les réponses en cache (ne pas redemander le même endroit).
///
/// Ordre suivi par [nominatim] :
///   1. cache SQLite (table adresses_cache) : marche même hors ligne ;
///   2. hors ligne → échec (l'utilisateur écrit le lieu lui-même) ;
///   3. requête HTTP (10 s maximum, 1 par seconde), puis mise en cache.
///
/// Remplaçable dans les tests, comme Localisation.positionActuelle (M1) :
///   AdresseM3.adresseDe = (point) async => const Resultat.succes('Rue X');
/// Pour tester [nominatim] lui-même : `AdresseM3.client = MockClient(...)`.
class AdresseM3 {
  AdresseM3._(); // que des static

  /// La fonction utilisée par les écrans.
  static Future<Resultat<String>> Function(PointGps point) adresseDe =
      nominatim;

  /// Le client HTTP (les tests mettent un MockClient de package:http/testing).
  static http.Client client = http.Client();

  static const String userAgent = 'tn.esprit.houmani';
  static Duration delaiMax = const Duration(seconds: 10);
  static Duration intervalle = const Duration(seconds: 1); // 1 requête/s

  static const String messageHorsLigne =
      'Hors ligne : la position est gardée, écris le lieu toi-même';
  static const String messageDelai =
      'Le service d\'adresse ne répond pas : écris le lieu toi-même';
  static const String messageIntrouvable =
      'Adresse introuvable ici : écris le lieu toi-même';

  // Heure à laquelle la dernière requête est (ou sera) partie
  static DateTime? _derniereRequete;

  /// Remet à zéro (tests) : client réel, pas d'attente en cours.
  static void reinitialiser() {
    adresseDe = nominatim;
    client = http.Client();
    delaiMax = const Duration(seconds: 10);
    intervalle = const Duration(seconds: 1);
    _derniereRequete = null;
  }

  /// La clé du cache : latitude et longitude arrondies à 4 décimales
  /// (environ 11 m) : « 36.8625,10.1700 ».
  static String cleCache(PointGps point) {
    return '${point.latitude.toStringAsFixed(4)},'
        '${point.longitude.toStringAsFixed(4)}';
  }

  /// L'adresse URL de la requête.
  static Uri urlPour(PointGps point) {
    return Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'accept-language': 'fr',
    });
  }

  /// Adresse courte à partir de la réponse JSON : « rue, quartier ».
  /// Pas de rue : seulement le quartier (ou la ville). Rien : null.
  static String? adresseCourte(Map<String, dynamic> reponse) {
    final Object? adresse = reponse['address'];
    if (adresse is! Map) {
      return null;
    }
    String? premier(List<String> cles) {
      for (final String cle in cles) {
        final Object? valeur = adresse[cle];
        if (valeur is String && valeur.trim().isNotEmpty) {
          return valeur.trim();
        }
      }
      return null;
    }

    final String? rue = premier(['road', 'pedestrian', 'footway', 'residential']);
    final String? zone = premier([
      'neighbourhood',
      'suburb',
      'quarter',
      'city_district',
      'village',
      'town',
      'city',
    ]);
    if (rue != null && zone != null && rue != zone) {
      return '$rue, $zone';
    }
    return rue ?? zone;
  }

  /// Attend son tour : au moins [intervalle] entre deux requêtes, même si
  /// deux demandes arrivent en même temps (la place est réservée AVANT
  /// d'attendre).
  static Future<void> _attendreSonTour() async {
    final DateTime maintenant = DateTime.now();
    DateTime depart = maintenant;
    final DateTime? derniere = _derniereRequete;
    if (derniere != null && derniere.add(intervalle).isAfter(maintenant)) {
      depart = derniere.add(intervalle);
    }
    _derniereRequete = depart;
    final Duration attente = depart.difference(maintenant);
    if (attente > Duration.zero) {
      await Future<void>.delayed(attente);
    }
  }

  /// La vraie recherche (voir l'ordre en haut du fichier).
  static Future<Resultat<String>> nominatim(PointGps point) async {
    final String cle = cleCache(point);

    // 1. Déjà demandée ? (cache SQLite, marche hors ligne)
    try {
      final String? enCache = await BaseLocaleM3.instance.lireAdresse(cle);
      if (enCache != null) {
        return Resultat.succes(enCache);
      }
    } catch (e) {
      // pas de base locale : on demande au serveur
    }

    // 2. Hors ligne : pas de requête
    if (!await ConnexionM3().estEnLigne()) {
      return const Resultat.echec(messageHorsLigne);
    }

    // 3. Requête HTTP
    await _attendreSonTour();
    final http.Response reponse;
    try {
      reponse = await client.get(
        urlPour(point),
        headers: {'User-Agent': userAgent, 'Accept-Language': 'fr'},
      ).timeout(delaiMax);
    } on TimeoutException {
      return const Resultat.echec(messageDelai);
    } catch (e) {
      return const Resultat.echec(messageIntrouvable);
    }
    if (reponse.statusCode != 200) {
      return const Resultat.echec(messageIntrouvable);
    }

    final String? adresse;
    try {
      // utf8 : les accents (« Rue de l'Électricité ») restent corrects
      final Object? json = jsonDecode(utf8.decode(reponse.bodyBytes));
      adresse = json is Map<String, dynamic> ? adresseCourte(json) : null;
    } catch (e) {
      return const Resultat.echec(messageIntrouvable);
    }
    if (adresse == null) {
      return const Resultat.echec(messageIntrouvable);
    }

    try {
      await BaseLocaleM3.instance.enregistrerAdresse(cle, adresse);
    } catch (e) {
      // pas de cache : l'adresse est quand même donnée
    }
    return Resultat.succes(adresse);
  }
}
