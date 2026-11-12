import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/quartier.dart' show PointGps;
import '../resultat.dart';
import 'cache_local.dart';

/// M1 - La météo du moment au centre du quartier.
class Meteo {
  final double temperature; // °C, maintenant
  final double? max; // °C, aujourd'hui
  final double? min;
  final int code; // code météo WMO (0 = ciel clair, 61 = pluie...)
  final DateTime recueLe; // quand le serveur a répondu
  final double latitude;
  final double longitude;

  const Meteo({
    required this.temperature,
    required this.code,
    required this.recueLe,
    required this.latitude,
    required this.longitude,
    this.max,
    this.min,
  });

  Map<String, Object?> toJson() {
    return {
      'temperature': temperature,
      'max': max,
      'min': min,
      'code': code,
      'recueLe': recueLe.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Meteo.fromJson(Map<String, dynamic> json) {
    return Meteo(
      temperature: (json['temperature'] as num).toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      min: (json['min'] as num?)?.toDouble(),
      code: (json['code'] as num).toInt(),
      recueLe: DateTime.fromMillisecondsSinceEpoch(json['recueLe'] as int),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

/// M1 - Service web externe GRATUIT et sans clé : Open-Meteo.
///   GET https://api.open-meteo.com/v1/forecast?latitude=36.86&longitude=10.17
///       &current=temperature_2m,weather_code
///       &daily=temperature_2m_max,temperature_2m_min&timezone=auto
///
/// Ordre suivi par [meteoDe] :
///   1. cache SQLite (CacheLocal, table preferences) de moins de 30 min
///      au même endroit : pas de requête ;
///   2. requête HTTP (8 s maximum), puis mise en cache ;
///   3. échec réseau : on renvoie la dernière météo gardée (marquée
///      ancienne par sa date), sinon un échec.
///
/// Remplaçable dans les tests : `MeteoM1.client = MockClient(...)`.
class MeteoM1 {
  MeteoM1._(); // que des static

  static http.Client client = http.Client();
  static CacheLocal cache = CacheLocal();
  static Duration delaiMax = const Duration(seconds: 8);
  static const Duration fraicheur = Duration(minutes: 30);

  static const String messageIndisponible = 'Météo indisponible';

  /// Remet à zéro (tests).
  static void reinitialiser() {
    client = http.Client();
    cache = CacheLocal();
    delaiMax = const Duration(seconds: 8);
  }

  static Uri urlPour(PointGps point) {
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': point.latitude.toStringAsFixed(4),
      'longitude': point.longitude.toStringAsFixed(4),
      'current': 'temperature_2m,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'timezone': 'auto',
      'forecast_days': '1',
    });
  }

  /// Lit la réponse d'Open-Meteo. null si elle n'a pas la forme attendue.
  static Meteo? depuisReponse(
    Map<String, dynamic> json,
    PointGps point,
    DateTime maintenant,
  ) {
    final Object? actuel = json['current'];
    if (actuel is! Map) {
      return null;
    }
    final Object? temperature = actuel['temperature_2m'];
    final Object? code = actuel['weather_code'];
    if (temperature is! num || code is! num) {
      return null;
    }
    double? premier(String cle) {
      final Object? jour = json['daily'];
      if (jour is! Map) {
        return null;
      }
      final Object? liste = jour[cle];
      if (liste is List && liste.isNotEmpty && liste.first is num) {
        return (liste.first as num).toDouble();
      }
      return null;
    }

    return Meteo(
      temperature: temperature.toDouble(),
      code: code.toInt(),
      max: premier('temperature_2m_max'),
      min: premier('temperature_2m_min'),
      recueLe: maintenant,
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }

  /// La météo gardée est-elle au même endroit (à ~1 km près) ?
  static bool memeEndroit(Meteo meteo, PointGps point) {
    return (meteo.latitude - point.latitude).abs() < 0.01 &&
        (meteo.longitude - point.longitude).abs() < 0.01;
  }

  static Future<Meteo?> _lireCache(PointGps point) async {
    try {
      final String? texte = await cache.lireMeteo();
      if (texte == null) {
        return null;
      }
      final Meteo meteo =
          Meteo.fromJson(jsonDecode(texte) as Map<String, dynamic>);
      return memeEndroit(meteo, point) ? meteo : null;
    } catch (e) {
      return null; // cache abîmé : on l'ignore
    }
  }

  /// La météo au point donné (voir l'ordre en haut de la classe).
  static Future<Resultat<Meteo>> meteoDe(
    PointGps point, {
    DateTime? maintenant,
  }) async {
    final DateTime instant = maintenant ?? DateTime.now();
    final Meteo? enCache = await _lireCache(point);

    // 1. Assez récente : pas de requête
    if (enCache != null && instant.difference(enCache.recueLe) < fraicheur) {
      return Resultat.succes(enCache);
    }

    // 2. Requête HTTP
    Meteo? recue;
    try {
      final http.Response reponse =
          await client.get(urlPour(point)).timeout(delaiMax);
      if (reponse.statusCode == 200) {
        final Object? json = jsonDecode(utf8.decode(reponse.bodyBytes));
        if (json is Map<String, dynamic>) {
          recue = depuisReponse(json, point, instant);
        }
      }
    } catch (e) {
      recue = null; // hors ligne, délai dépassé ou réponse illisible
    }

    if (recue != null) {
      await cache.enregistrerMeteo(jsonEncode(recue.toJson()));
      return Resultat.succes(recue);
    }

    // 3. Échec : la dernière météo connue vaut mieux que rien
    if (enCache != null) {
      return Resultat.succes(enCache);
    }
    return const Resultat.echec(messageIndisponible);
  }

  /// Le texte et l'icône (emoji) d'un code météo WMO.
  /// https://open-meteo.com/en/docs (section « WMO Weather interpretation codes »)
  static (String, String) description(int code) {
    if (code == 0) return ('Ciel dégagé', '☀️');
    if (code <= 2) return ('Peu nuageux', '🌤️');
    if (code == 3) return ('Couvert', '☁️');
    if (code == 45 || code == 48) return ('Brouillard', '🌫️');
    if (code >= 51 && code <= 57) return ('Bruine', '🌦️');
    if (code >= 61 && code <= 67) return ('Pluie', '🌧️');
    if (code >= 71 && code <= 77) return ('Neige', '❄️');
    if (code >= 80 && code <= 82) return ('Averses', '🌦️');
    if (code >= 85 && code <= 86) return ('Averses de neige', '🌨️');
    if (code >= 95) return ('Orage', '⛈️');
    return ('Météo variable', '🌡️');
  }

  /// Un conseil de voisinage selon le temps (affiché sous la météo).
  static String conseil(Meteo meteo) {
    if (meteo.code >= 95) {
      return 'Orage : rentre le linge et vérifie les gouttières.';
    }
    if (meteo.code >= 51 && meteo.code <= 82) {
      return 'Pluie : pense aux voisins âgés pour les courses.';
    }
    if ((meteo.max ?? meteo.temperature) >= 35) {
      return 'Forte chaleur : prends des nouvelles des voisins seuls.';
    }
    if (meteo.temperature <= 5) {
      return 'Il fait froid : couvre-toi bien.';
    }
    return 'Beau temps pour un service entre voisins !';
  }
}
