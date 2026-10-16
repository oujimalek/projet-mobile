import 'package:flutter/foundation.dart';

import '../data/services/cache_local.dart';

/// Les trois choix de l'écran Paramètres → Apparence.
enum ModeTheme {
  systeme, // suit le réglage du téléphone (par défaut)
  clair,
  sombre,
}

/// M1 - Le thème choisi par l'utilisateur, gardé sur le téléphone.
///
/// [mode] est un ValueNotifier (fourni par Flutter) : HoumaniApp (main.dart)
/// l'écoute et reconstruit l'application quand il change.
class PreferenceTheme {
  static final ValueNotifier<ModeTheme> mode =
      ValueNotifier<ModeTheme>(ModeTheme.systeme);

  /// Où le choix est enregistré. Les tests peuvent en donner un autre.
  static CacheLocal cache = CacheLocal();

  /// Au lancement : relit le choix enregistré (systeme s'il n'y en a pas).
  static Future<void> charger() async {
    final String? enregistre = await cache.lireTheme();
    for (final ModeTheme valeur in ModeTheme.values) {
      if (valeur.name == enregistre) {
        mode.value = valeur;
      }
    }
  }

  /// Applique tout de suite le nouveau choix, puis l'enregistre.
  static Future<void> choisir(ModeTheme nouveau) async {
    mode.value = nouveau;
    await cache.enregistrerTheme(nouveau.name);
  }

  /// true si l'app doit être en sombre.
  /// [telephoneSombre] : le téléphone est-il réglé en thème sombre ?
  static bool estSombre(ModeTheme choix, bool telephoneSombre) {
    if (choix == ModeTheme.systeme) {
      return telephoneSombre;
    }
    return choix == ModeTheme.sombre;
  }
}
