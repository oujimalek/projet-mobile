import 'package:flutter/foundation.dart';

import '../data/services/cache_local.dart';

/// Les deux choix de l'écran Paramètres → Langue.
enum Langue {
  francais, // par défaut
  derja, // derja tunisienne, écrite en lettres latines
}

/// M1 - La langue choisie par l'utilisateur, gardée sur le téléphone.
///
/// Même principe que PreferenceTheme : [langue] est un ValueNotifier,
/// HoumaniApp (main.dart) l'écoute et redessine les écrans ouverts.
class PreferenceLangue {
  static final ValueNotifier<Langue> langue =
      ValueNotifier<Langue>(Langue.francais);

  /// Où le choix est enregistré. Les tests peuvent en donner un autre.
  static CacheLocal cache = CacheLocal();

  /// Au lancement : relit le choix enregistré (français s'il n'y en a pas).
  static Future<void> charger() async {
    final String? enregistre = await cache.lireLangue();
    for (final Langue valeur in Langue.values) {
      if (valeur.name == enregistre) {
        langue.value = valeur;
      }
    }
  }

  /// Applique tout de suite le nouveau choix, puis l'enregistre.
  static Future<void> choisir(Langue nouvelle) async {
    langue.value = nouvelle;
    await cache.enregistrerLangue(nouvelle.name);
  }
}

/// Le texte dans la langue choisie : tr('Paramètres', 'Réglages').
///
/// Pas de fichier de traduction : chaque écran donne ses deux versions
/// côte à côte, c'est plus simple à relire et à corriger.
String tr(String francais, String derja) {
  if (PreferenceLangue.langue.value == Langue.derja) {
    return derja;
  }
  return francais;
}
