import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../resultat.dart';
import 'base_locale_m2.dart';

/// M2 - Service web externe GRATUIT et sans clé : Nager.Date.
///   GET https://date.nager.at/api/v3/PublicHolidays/2026/TN
///
/// Sert au planning des services communs : un créneau qui tombe un jour
/// férié est signalé ("vérifie que le créneau est maintenu").
///
/// Limite connue : Nager.Date ne donne que les fêtes CIVILES tunisiennes
/// (dates fixes). Les fêtes religieuses (Aïd, Mouled, Ras el Am el Hijri)
/// suivent le calendrier lunaire et n'y sont pas : l'écran le précise.
///
/// Ordre : cache SQLite (table `jours_feries` de BaseLocaleM2) → requête
/// HTTP (8 s maximum) → mise en cache. Une année ne change pas : une seule
/// requête par année et par téléphone.
///
/// Remplaçable dans les tests : `JoursFeriesM2.client = MockClient(...)`.
class JoursFeriesM2 {
  JoursFeriesM2._(); // que des static

  static http.Client client = http.Client();
  static Duration delaiMax = const Duration(seconds: 8);

  static const String messageIndisponible = 'Jours fériés indisponibles';

  /// Remet à zéro (tests).
  static void reinitialiser() {
    client = http.Client();
    delaiMax = const Duration(seconds: 8);
  }

  static Uri urlPour(int annee) {
    return Uri.https('date.nager.at', '/api/v3/PublicHolidays/$annee/TN');
  }

  /// Les noms anglais de l'API, traduits en français.
  static const Map<String, String> _noms = {
    "New Year's Day": 'Jour de l\'An',
    'Independence Day': 'Fête de l\'Indépendance',
    "Martyrs' Day": 'Journée des Martyrs',
    'Labour Day': 'Fête du Travail',
    'Republic Day': 'Fête de la République',
    "Women's Day": 'Fête de la Femme',
    'Evacuation Day': 'Fête de l\'Évacuation',
    'Revolution and Youth Day': 'Fête de la Révolution',
    'Revolution Day': 'Fête de la Révolution',
  };

  /// Le nom français d'un jour férié (l'anglais si on ne le connaît pas).
  static String traduire(String nomAnglais) {
    return _noms[nomAnglais] ?? nomAnglais;
  }

  /// La clé d'un jour : 'AAAA-MM-JJ' (le format de l'API).
  static String cle(DateTime jour) {
    final String mois = jour.month.toString().padLeft(2, '0');
    final String j = jour.day.toString().padLeft(2, '0');
    return '${jour.year}-$mois-$j';
  }

  /// Lit la réponse de l'API : [{"date":"2026-03-20","name":"Independence
  /// Day",...}, ...] → {'2026-03-20': 'Fête de l'Indépendance', ...}.
  /// Les éléments mal formés sont ignorés.
  static Map<String, String> depuisReponse(Object? json) {
    final Map<String, String> jours = {};
    if (json is! List) {
      return jours;
    }
    for (final Object? element in json) {
      if (element is! Map) {
        continue;
      }
      final Object? date = element['date'];
      final Object? nom = element['name'];
      if (date is String && date.length == 10 && nom is String) {
        jours[date] = traduire(nom);
      }
    }
    return jours;
  }

  /// Les jours fériés de [annee] (voir l'ordre en haut de la classe).
  static Future<Resultat<Map<String, String>>> joursDe(int annee) async {
    final Map<String, String> enCache = await BaseLocaleM2.joursFeries(annee);
    if (enCache.isNotEmpty) {
      return Resultat.succes(enCache);
    }

    try {
      final http.Response reponse =
          await client.get(urlPour(annee)).timeout(delaiMax);
      if (reponse.statusCode == 200) {
        final Map<String, String> jours =
            depuisReponse(jsonDecode(utf8.decode(reponse.bodyBytes)));
        if (jours.isNotEmpty) {
          await BaseLocaleM2.enregistrerJoursFeries(annee, jours);
          return Resultat.succes(jours);
        }
      }
    } catch (e) {
      // hors ligne, délai dépassé ou réponse illisible
    }
    return const Resultat.echec(messageIndisponible);
  }
}
