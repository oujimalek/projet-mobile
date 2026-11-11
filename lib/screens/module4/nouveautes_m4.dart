import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../data/models/evenement.dart';
import '../../data/models/sondage.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/utilisateur_repository.dart';

/// M4 - Le petit point « nouveau » sur l'onglet Événements : le nombre
/// d'événements et de sondages publiés par d'autres voisins depuis ma
/// dernière visite de l'onglet.
///
/// La date de la dernière visite est gardée sur le téléphone (Hive, comme
/// CacheLocal du module 1). La barre du bas écoute [nombre].
class NouveautesM4 {
  NouveautesM4._(); // que des static

  /// Le nombre de nouveautés (0 : pas de point).
  static final ValueNotifier<int> nombre = ValueNotifier<int>(0);

  static const String _nomBoite = 'houmani_m4';
  static const String _cleVisite = 'derniereVisiteEvenements';

  /// Combien d'éléments sont plus récents que [derniereVisite] et publiés
  /// par quelqu'un d'autre que [moiId]. Sans date de création : ancien.
  static int compter(
    List<Evenement> evenements,
    List<Sondage> sondages,
    DateTime derniereVisite,
    String moiId,
  ) {
    int total = 0;
    for (final Evenement evenement in evenements) {
      final DateTime? creation = evenement.dateCreation;
      if (creation != null &&
          creation.isAfter(derniereVisite) &&
          evenement.organisateurId != moiId) {
        total++;
      }
    }
    for (final Sondage sondage in sondages) {
      final DateTime? creation = sondage.dateCreation;
      if (creation != null &&
          creation.isAfter(derniereVisite) &&
          sondage.proposeParId != moiId) {
        total++;
      }
    }
    return total;
  }

  /// Recalcule [nombre] (appelé depuis l'accueil). Ne lève jamais d'exception.
  static Future<void> calculer() async {
    try {
      final Box<dynamic> boite = await _boite();
      final int? visite = boite.get(_cleVisite);
      if (visite == null) {
        // Première fois : on part de maintenant (pas de faux « nouveau »)
        await boite.put(_cleVisite, DateTime.now().millisecondsSinceEpoch);
        return;
      }
      final EvenementRepository depot = EvenementRepository();
      final Resultat<List<Evenement>> evenements = await depot.chargerEvenements();
      final Resultat<List<Sondage>> sondages = await depot.chargerSondages();
      nombre.value = compter(
        evenements.donnee ?? [],
        sondages.donnee ?? [],
        DateTime.fromMillisecondsSinceEpoch(visite),
        UtilisateurRepository().getUtilisateurConnecte().id,
      );
    } catch (erreur) {
      // Pas de stockage (tests, erreur disque) : pas de point
    }
  }

  /// J'ouvre l'onglet Événements : plus rien de nouveau.
  static Future<void> marquerVu() async {
    nombre.value = 0;
    try {
      final Box<dynamic> boite = await _boite();
      await boite.put(_cleVisite, DateTime.now().millisecondsSinceEpoch);
    } catch (erreur) {
      // Pas grave : le point reviendra au prochain calcul
    }
  }

  static Future<Box<dynamic>> _boite() async {
    if (Hive.isBoxOpen(_nomBoite)) {
      return Hive.box<dynamic>(_nomBoite);
    }
    await Hive.initFlutter();
    return Hive.openBox<dynamic>(_nomBoite);
  }
}
