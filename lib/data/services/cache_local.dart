import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/quartier.dart';
import '../models/utilisateur.dart';

/// M1 - Cache local : garde sur le téléphone le profil connecté et son
/// quartier (package hive_ce, une petite base clé → valeur).
///
/// À quoi ça sert :
/// - au redémarrage, le profil s'affiche tout de suite, avant la réponse
///   de Firebase ;
/// - sans Internet, l'app montre la dernière version connue.
///
/// Pas de génération de code : on enregistre des Map (toMap/fromMap).
/// Le cache n'est qu'une copie : en cas d'erreur, on fait comme s'il était
/// vide, il ne doit jamais faire planter l'app.
class CacheLocal {
  static const String _nomBoite = 'houmani_cache';
  static const String _cleUtilisateur = 'utilisateur';
  static const String _cleQuartier = 'quartier';
  static const String _cleTheme = 'theme';

  /// Dossier des fichiers Hive. null = dossier de l'application (cas normal).
  /// Les tests donnent un dossier temporaire.
  final String? dossier;

  CacheLocal({this.dossier});

  Box<dynamic>? _boite;

  /// Ouvre la "boîte" Hive au premier usage, puis la réutilise.
  Future<Box<dynamic>> _ouvrir() async {
    final Box<dynamic>? boite = _boite;
    if (boite != null && boite.isOpen) {
      return boite;
    }
    if (dossier != null) {
      Hive.init(dossier);
    } else {
      await Hive.initFlutter();
    }
    final Box<dynamic> ouverte = await Hive.openBox<dynamic>(_nomBoite);
    _boite = ouverte;
    return ouverte;
  }

  // =====================================================================
  // Utilisateur connecté
  // =====================================================================

  Future<void> enregistrerUtilisateur(Utilisateur utilisateur) async {
    try {
      final Map<String, dynamic> map = utilisateur.toMap();
      map['id'] = utilisateur.id;
      // Hive garde les nombres : la date devient des millisecondes
      map['dateDemande'] = utilisateur.dateDemande?.millisecondsSinceEpoch;
      final Box<dynamic> boite = await _ouvrir();
      await boite.put(_cleUtilisateur, map);
    } catch (e) {
      // Cache indisponible : tant pis, les données sont aussi sur Firebase.
      // On l'écrit quand même dans la console pour ne pas cacher un bug.
      debugPrint('CacheLocal : $e');
    }
  }

  /// Le profil gardé, ou null s'il n'y en a pas.
  Future<Utilisateur?> lireUtilisateur() async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      final dynamic brut = boite.get(_cleUtilisateur);
      if (brut is! Map) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(brut);
      final dynamic millisecondes = map['dateDemande'];
      // fromMap attend un Timestamp (comme dans Firestore)
      map['dateDemande'] = millisecondes is int
          ? Timestamp.fromMillisecondsSinceEpoch(millisecondes)
          : null;
      return Utilisateur.fromMap(map['id'] ?? '', map);
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null; // cache abîmé : comme s'il était vide
    }
  }

  // =====================================================================
  // Quartier de l'utilisateur connecté
  // =====================================================================

  Future<void> enregistrerQuartier(Quartier quartier) async {
    try {
      final Map<String, dynamic> map = quartier.toMap();
      map['id'] = quartier.id;
      final Box<dynamic> boite = await _ouvrir();
      await boite.put(_cleQuartier, map);
    } catch (e) {
      debugPrint('CacheLocal : $e'); // voir enregistrerUtilisateur
    }
  }

  Future<Quartier?> lireQuartier() async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      final dynamic brut = boite.get(_cleQuartier);
      if (brut is! Map) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(brut);
      return Quartier.fromMap(map['id'] ?? '', map);
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  /// Efface seulement le quartier (il a été supprimé sur le serveur).
  Future<void> oublierQuartier() async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      await boite.delete(_cleQuartier);
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  // =====================================================================
  // Apparence (thème clair / sombre / système)
  // =====================================================================

  /// Enregistre le thème choisi dans Paramètres (ex : "sombre").
  Future<void> enregistrerTheme(String mode) async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      await boite.put(_cleTheme, mode);
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Le thème enregistré, ou null s'il n'y en a pas.
  Future<String?> lireTheme() async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      final dynamic brut = boite.get(_cleTheme);
      return brut is String ? brut : null;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  // =====================================================================
  // Nettoyage
  // =====================================================================

  /// Efface le profil et le quartier (à la déconnexion : le téléphone peut
  /// être partagé). Le thème est gardé : c'est un réglage du téléphone.
  Future<void> vider() async {
    try {
      final Box<dynamic> boite = await _ouvrir();
      await boite.deleteAll([_cleUtilisateur, _cleQuartier]);
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Ferme la boîte (utile dans les tests).
  Future<void> fermer() async {
    await _boite?.close();
    _boite = null;
  }
}
