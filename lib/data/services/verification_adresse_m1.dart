import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/quartier.dart';
import '../resultat.dart';
import 'cache_local.dart';

/// Résultat de la vérification d'une adresse.
enum EtatAdresse {
  dansLeQuartier, // le point trouvé est dans le contour du quartier
  horsDuQuartier, // trouvé, mais en dehors du contour
  introuvable, // Nominatim ne connaît pas cette adresse
  sansContour, // trouvée, mais le quartier n'a pas de limites tracées
}

class VerdictAdresse {
  final EtatAdresse etat;
  final PointGps? point; // où l'adresse a été trouvée (null : introuvable)
  final double? distanceMetres; // distance au centre du quartier

  const VerdictAdresse(this.etat, {this.point, this.distanceMetres});
}

/// M1 - L'admin vérifie l'adresse donnée avec une demande d'adhésion :
/// est-elle vraiment dans la houma ?
///
/// Service web externe GRATUIT : Nominatim (OpenStreetMap), recherche
/// d'adresse (« géocodage ») :
///   GET https://nominatim.openstreetmap.org/search?format=jsonv2
///       &q=12 rue des Jasmins, Ennasr 2, Ariana&countrycodes=tn&limit=1
/// puis le point trouvé est testé dans le contour du quartier
/// (Quartier.contient, méthode du rayon).
///
/// Politique Nominatim respectée (comme AdresseM3, module 3) :
/// User-Agent de l'app, 1 requête par seconde au plus, réponses en cache.
///
/// Ordre suivi par [verifier] :
///   1. cache SQLite (table geocodage, 30 jours) : aucune requête ;
///   2. requête HTTP (10 s maximum), puis mise en cache (même "introuvable") ;
///   3. pas de réseau / erreur serveur → échec (rien n'est gardé).
class VerificationAdresseM1 {
  VerificationAdresseM1._(); // que des static

  /// Le client HTTP (les tests mettent un MockClient de package:http/testing).
  static http.Client client = http.Client();
  static CacheLocal cache = CacheLocal();

  static const String userAgent = 'tn.esprit.houmani';
  static Duration delaiMax = const Duration(seconds: 10);
  static Duration intervalle = const Duration(seconds: 1); // 1 requête/s

  static const String messageIndisponible =
      'Vérification impossible pour l\'instant (pas de réseau ?)';

  static DateTime? _derniereRequete;

  /// Remet à zéro (tests).
  static void reinitialiser() {
    client = http.Client();
    cache = CacheLocal();
    delaiMax = const Duration(seconds: 10);
    intervalle = const Duration(seconds: 1);
    _derniereRequete = null;
  }

  /// Le texte cherché : l'adresse + la localisation du quartier (aide
  /// Nominatim quand le membre n'a écrit que la rue).
  static String requetePour(String adresse, Quartier quartier) {
    final String rue = adresse.trim();
    final String lieu = quartier.localisation.trim();
    if (lieu.isEmpty || rue.toLowerCase().contains(lieu.toLowerCase())) {
      return rue;
    }
    return '$rue, $lieu';
  }

  /// La clé du cache : le texte cherché, en minuscules, sans espaces doubles.
  static String cleCache(String requete) {
    return requete.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// L'adresse URL de la recherche. Avec un centre connu, les résultats
  /// proches du quartier passent en premier (viewbox de ±0,1°, ~10 km).
  static Uri urlPour(String requete, {PointGps? autour}) {
    final Map<String, String> parametres = {
      'format': 'jsonv2',
      'q': requete,
      'countrycodes': 'tn',
      'limit': '1',
      'accept-language': 'fr',
    };
    if (autour != null) {
      final double lat = autour.latitude;
      final double lng = autour.longitude;
      // gauche, haut, droite, bas
      parametres['viewbox'] = '${(lng - 0.1).toStringAsFixed(4)},'
          '${(lat + 0.1).toStringAsFixed(4)},'
          '${(lng + 0.1).toStringAsFixed(4)},'
          '${(lat - 0.1).toStringAsFixed(4)}';
    }
    return Uri.https('nominatim.openstreetmap.org', '/search', parametres);
  }

  /// Le premier point de la réponse (une liste JSON), null si vide.
  static PointGps? depuisReponse(Object? json) {
    if (json is! List || json.isEmpty || json.first is! Map) {
      return null;
    }
    final Map premier = json.first as Map;
    final double? lat = double.tryParse('${premier['lat']}');
    final double? lng = double.tryParse('${premier['lon']}');
    if (lat == null || lng == null) {
      return null;
    }
    return PointGps(lat, lng);
  }

  /// Distance en mètres entre deux points (formule de haversine).
  static double distanceMetres(PointGps a, PointGps b) {
    const double rayonTerre = 6371000;
    double radians(double degres) => degres * math.pi / 180;
    final double dLat = radians(b.latitude - a.latitude);
    final double dLng = radians(b.longitude - a.longitude);
    final double h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(radians(a.latitude)) *
            math.cos(radians(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * rayonTerre * math.asin(math.sqrt(h));
  }

  /// Le verdict pour un point trouvé (ou non) dans ce quartier.
  static VerdictAdresse juger(PointGps? point, Quartier quartier) {
    if (point == null) {
      return const VerdictAdresse(EtatAdresse.introuvable);
    }
    final PointGps? centre = quartier.centre;
    final double? distance =
        centre == null ? null : distanceMetres(point, centre);
    final EtatAdresse etat;
    if (quartier.contour.length < 3) {
      etat = EtatAdresse.sansContour;
    } else if (quartier.contient(point)) {
      etat = EtatAdresse.dansLeQuartier;
    } else {
      etat = EtatAdresse.horsDuQuartier;
    }
    return VerdictAdresse(etat, point: point, distanceMetres: distance);
  }

  /// Au moins [intervalle] entre deux requêtes (place réservée avant
  /// d'attendre : deux vérifications lancées ensemble restent espacées).
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

  /// Vérifie l'adresse d'un membre pour ce quartier (voir l'ordre en haut).
  static Future<Resultat<VerdictAdresse>> verifier(
    String adresse,
    Quartier quartier,
  ) async {
    final String requete = requetePour(adresse, quartier);
    final String cle = cleCache(requete);

    // 1. Déjà cherchée ces 30 derniers jours ?
    final ({PointGps? point})? enCache = await cache.lireGeocodage(cle);
    if (enCache != null) {
      return Resultat.succes(juger(enCache.point, quartier));
    }

    // 2. Requête HTTP
    await _attendreSonTour();
    final http.Response reponse;
    try {
      reponse = await client.get(
        urlPour(requete, autour: quartier.centre),
        headers: {'User-Agent': userAgent, 'Accept-Language': 'fr'},
      ).timeout(delaiMax);
    } catch (e) {
      return const Resultat.echec(messageIndisponible);
    }
    if (reponse.statusCode != 200) {
      return const Resultat.echec(messageIndisponible);
    }

    final PointGps? point;
    try {
      point = depuisReponse(jsonDecode(utf8.decode(reponse.bodyBytes)));
    } catch (e) {
      return const Resultat.echec(messageIndisponible);
    }

    // 3. On garde la réponse (même "introuvable" : inutile de redemander)
    await cache.enregistrerGeocodage(cle, point);
    return Resultat.succes(juger(point, quartier));
  }
}
