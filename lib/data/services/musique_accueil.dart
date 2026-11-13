import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Musique de lancement : un extrait de 31 secondes de "Houmani"
/// (Hamzaoui Med Amine ft. Kafon, de 0:35 à 1:06), joué une seule fois
/// au démarrage de l'application, depuis le splash.
///
/// - La musique continue sur l'écran suivant (connexion ou accueil),
///   puis s'arrête toute seule à la fin de l'extrait.
/// - Elle monte doucement au début et baisse doucement à la fin
///   (l'extrait est coupé au milieu de la chanson).
/// - Si l'utilisateur quitte l'application (bouton d'accueil, autre
///   application), la musique s'arrête et ne reprend pas.
/// - Téléphone en mode silencieux ou vibreur : aucun son.
class MusiqueAccueil {
  /// Les tests mettent false : pas de lecteur audio sur l'ordinateur.
  static bool active = true;

  static const String fichier = 'audio/houmani_splash.mp3';
  static const Duration duree = Duration(seconds: 31);
  static const Duration fondu = Duration(seconds: 2);

  static AudioPlayer? _lecteur;
  static Timer? _minuteur;
  static AppLifecycleListener? _cycleDeVie;
  static bool _dejaJouee = false;

  /// Lance la musique (une seule fois par lancement de l'application).
  static Future<void> jouer() async {
    if (!active || _dejaJouee) {
      return;
    }
    _dejaJouee = true;
    try {
      final AudioPlayer lecteur = AudioPlayer();
      _lecteur = lecteur;
      // respectSilence : téléphone en silencieux ou vibreur → pas de son.
      // (Android : volume de la sonnerie ; iOS : bouton silencieux.)
      await lecteur.setAudioContext(
        AudioContextConfig(respectSilence: true).build(),
      );
      await lecteur.setReleaseMode(ReleaseMode.stop);
      await lecteur.setVolume(0);
      await lecteur.play(AssetSource(fichier));
      // L'application passe en arrière-plan : on coupe la musique
      _cycleDeVie = AppLifecycleListener(onHide: arreter);
      _demarrerFondus();
    } catch (e) {
      // Pas de son (plugin absent, fichier illisible) : l'app continue
      debugPrint('Musique : $e');
      await arreter();
    }
  }

  /// Volume : de 0 à 1 pendant le fondu du début, 1 au milieu,
  /// de 1 à 0 pendant le fondu de la fin. Mis à jour 10 fois par seconde.
  static void _demarrerFondus() {
    final Stopwatch chrono = Stopwatch()..start();
    final int total = duree.inMilliseconds;
    final int pas = fondu.inMilliseconds;
    _minuteur = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final int ecoule = chrono.elapsedMilliseconds;
      if (ecoule >= total) {
        arreter();
        return;
      }
      double volume = 1;
      if (ecoule < pas) {
        volume = ecoule / pas;
      } else if (ecoule > total - pas) {
        volume = (total - ecoule) / pas;
      }
      _lecteur?.setVolume(volume.clamp(0, 1).toDouble());
    });
  }

  /// Arrête la musique et libère le lecteur.
  static Future<void> arreter() async {
    _minuteur?.cancel();
    _minuteur = null;
    _cycleDeVie?.dispose();
    _cycleDeVie = null;
    final AudioPlayer? lecteur = _lecteur;
    _lecteur = null;
    if (lecteur == null) {
      return;
    }
    try {
      await lecteur.stop();
      await lecteur.dispose();
    } catch (e) {
      debugPrint('Musique : $e');
    }
  }
}
