import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_donnees;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/evenement.dart';

/// M4 - Les rappels sur le téléphone avant un événement où je participe :
/// la veille (24 h avant) et 1 heure avant. Programmés sur le téléphone
/// lui-même (package flutter_local_notifications) : pas de serveur, ça
/// marche avec le plan gratuit de Firebase.
///
/// Que des static ; ne lève jamais d'exception (tests, permission refusée).
class NotificationsM4 {
  NotificationsM4._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _pret = false;

  /// Les moments des rappels encore à venir : 24 h avant, puis 1 h avant.
  static List<DateTime> momentsRappel(DateTime debut, DateTime maintenant) {
    final List<DateTime> moments = [];
    for (final Duration avant in const [Duration(days: 1), Duration(hours: 1)]) {
      final DateTime moment = debut.subtract(avant);
      if (moment.isAfter(maintenant)) {
        moments.add(moment);
      }
    }
    return moments;
  }

  /// Deux numéros de notification par événement (veille, 1 h avant).
  static int _numero(String evenementId, int rang) {
    return (evenementId.hashCode & 0x3fffffff) * 2 + rang;
  }

  static Future<void> _preparer() async {
    if (_pret) {
      return;
    }
    tz_donnees.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Tunis')); // l'app est tunisienne
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    // Android 13+ : demander la permission d'afficher des notifications
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _pret = true;
  }

  /// (C4) Affiche tout de suite une notification (push reçue pendant que
  /// l'application est ouverte).
  static Future<void> afficher(String titre, String texte) async {
    try {
      await _preparer();
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch & 0x3fffffff,
        titre,
        texte,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'evenements_m4',
            'Nouveaux événements',
            channelDescription: 'Les événements publiés dans ta houma',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      // permission refusée, tests... : on ne montre rien
    }
  }

  /// Programme les rappels de cet événement (je viens de m'inscrire).
  static Future<void> programmer(Evenement evenement) async {
    try {
      await _preparer();
      await annuler(evenement.id); // pas de doublon si on se réinscrit
      final List<DateTime> moments =
          momentsRappel(evenement.date, DateTime.now());
      for (final DateTime moment in moments) {
        final bool veille = evenement.date.difference(moment).inHours >= 24;
        await _plugin.zonedSchedule(
          _numero(evenement.id, veille ? 0 : 1),
          veille ? 'Demain : ${evenement.titre}' : 'Dans 1 heure : ${evenement.titre}',
          evenement.lieu,
          tz.TZDateTime.from(moment, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'rappels_evenements',
              'Rappels d\'événements',
              channelDescription: 'Rappels avant les événements où tu participes',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // Moment approximatif (quelques minutes près) : pas besoin de la
          // permission « alarmes exactes »
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (erreur) {
      // Notifications indisponibles (tests, refus) : pas grave
    }
  }

  /// Annule les rappels de cet événement (je me retire, il est annulé...).
  static Future<void> annuler(String evenementId) async {
    try {
      await _preparer();
      await _plugin.cancel(_numero(evenementId, 0));
      await _plugin.cancel(_numero(evenementId, 1));
    } catch (erreur) {
      // Rien à annuler
    }
  }
}
