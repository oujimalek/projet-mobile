import 'dart:async';

import '../../screens/module4/notifications_m4.dart';
import '../../screens/module4/push_m4.dart';
import 'base_locale_m2.dart';
import 'base_locale_m4.dart';
import 'sync_signalements_m3.dart';

/// Une étape du nettoyage : efface les données locales d'UN module pour
/// l'utilisateur [uid] qui quitte le téléphone.
typedef EtapeNettoyage = Future<void> Function(String uid);

/// Commun - Efface les données LOCALES de l'utilisateur qui quitte le
/// téléphone : à la déconnexion, et quand l'application découvre que son
/// compte est bloqué, refusé ou supprimé.
///
/// Le téléphone peut être prêté ou partagé : le compte suivant ne doit voir
/// ni les brouillons, ni les favoris, ni l'historique, ni les annonces du
/// quartier de l'ancien.
///
/// Chaque module fournit sa propre méthode « vider » ; ici, on les appelle
/// seulement, l'une après l'autre. Une étape en échec (ou trop lente) ne
/// bloque pas les suivantes, et rien ne remonte à l'écran.
class NettoyageLocal {
  NettoyageLocal._();

  /// Temps maximum par étape (ex. se désabonner sans réseau).
  static Duration delaiMax = const Duration(seconds: 5);

  /// Les étapes, une par module. Les tests peuvent les remplacer.
  static List<EtapeNettoyage> etapes = etapesParDefaut();

  static List<EtapeNettoyage> etapesParDefaut() {
    return [
      // M2 : favoris, consultations, brouillon d'annonce
      (uid) => BaseLocaleM2.vider(),
      // M3 : brouillon, file d'envoi, cache des signalements, photos locales
      (uid) => SyncSignalementsM3.instance.viderUtilisateur(uid),
      // M4 : brouillons et historique
      (uid) => BaseLocaleM4.vider(),
      // M4 : rappels programmés (veille, 1 h avant)
      (uid) => NotificationsM4.annulerTout(),
      // M4 : sujets push quartier_{q} et leaders_{q}
      (uid) => PushM4.desabonner(),
    ];
  }

  /// Lance toutes les étapes pour [uid]. Ne lève jamais d'exception.
  static Future<void> viderTout(String uid) async {
    for (final EtapeNettoyage etape in etapes) {
      try {
        await etape(uid).timeout(delaiMax);
      } catch (e) {
        // étape impossible (pas de base, pas de réseau...) : on continue
      }
    }
  }
}
