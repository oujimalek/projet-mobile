import '../models/service.dart';

/// M2 - Accès aux services entre voisins.
///
/// Données en dur pour l'instant. Plus tard, seul l'intérieur de ces
/// méthodes changera (appel à une API), pas les écrans.
class ServiceRepository {
  /// Les catégories utilisées pour les filtres de la liste des services.
  /// "Tous" est le filtre par défaut.
  List<String> getCategories() {
    return const ['Tous', 'Bricolage', 'Prêt d\'outils', 'Garde d\'enfants', 'Courses'];
  }

  /// Tous les services du quartier.
  List<Service> getServices() {
    // Les dates sont calculées à partir de maintenant pour que la liste
    // affiche toujours "1 h", "3 h", "hier"... comme sur la maquette.
    final DateTime maintenant = DateTime.now();

    return [
      // ----- Offres (les 4 de la maquette) -----
      Service(
        id: 's1',
        titre: 'Perceuse à prêter',
        description: 'Perceuse avec forets, à rendre sous 3 jours.',
        categorie: 'Prêt d\'outils',
        auteur: 'Karim M.',
        bloc: 'Bloc A',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 1)),
      ),
      Service(
        id: 's2',
        titre: 'Garde d\'enfants le samedi',
        description: 'Je peux garder vos enfants le samedi après-midi.',
        categorie: 'Garde d\'enfants',
        auteur: 'Leila B.',
        bloc: 'Bloc C',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 3)),
      ),
      Service(
        id: 's3',
        titre: 'Petits travaux de plomberie',
        description: 'Fuites, joints, robinets : je passe chez vous.',
        categorie: 'Bricolage',
        auteur: 'Nizar H.',
        bloc: 'Bloc B',
        estOffre: true,
        prix: '15 DT',
        datePublication: maintenant.subtract(const Duration(hours: 26)),
      ),
      Service(
        id: 's4',
        titre: 'Courses au Carrefour',
        description: 'Je vais au Carrefour, je peux ramener vos courses.',
        categorie: 'Courses',
        auteur: 'Sarra A.',
        bloc: 'Bloc A',
        estOffre: true,
        datePublication: maintenant.subtract(const Duration(hours: 30)),
      ),

      // ----- Services communs hebdomadaires (offres) -----
      Service(
        id: 's5',
        titre: 'Nettoyage des escaliers',
        description: 'Service commun : on nettoie ensemble les escaliers du bloc.',
        categorie: 'Bricolage',
        auteur: 'Syndic',
        bloc: 'Bloc B',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
        datePublication: maintenant.subtract(const Duration(days: 3)),
      ),
      Service(
        id: 's6',
        titre: 'Achat groupé du pain',
        description: 'Service commun : un voisin passe à la boulangerie pour tous.',
        categorie: 'Courses',
        auteur: 'Résidence Yasmine',
        bloc: 'Tous les blocs',
        estOffre: true,
        estCommun: true,
        jour: 'Dimanche',
        datePublication: maintenant.subtract(const Duration(days: 4)),
      ),

      // ----- Demandes -----
      Service(
        id: 's7',
        titre: 'Qui va au marché samedi ?',
        description: 'Je cherche quelqu\'un pour me ramener des légumes.',
        categorie: 'Courses',
        auteur: 'Amira B.',
        bloc: 'Bloc B',
        estOffre: false,
        datePublication: maintenant.subtract(const Duration(hours: 5)),
      ),
      Service(
        id: 's8',
        titre: 'Cherche une échelle',
        description: 'Pour changer une ampoule au plafond, une heure seulement.',
        categorie: 'Prêt d\'outils',
        auteur: 'Youssef T.',
        bloc: 'Bloc A',
        estOffre: false,
        datePublication: maintenant.subtract(const Duration(days: 2)),
      ),
    ];
  }

  /// Les services d'une catégorie ("Tous" renvoie toute la liste).
  List<Service> getServicesParCategorie(String categorie) {
    if (categorie == 'Tous') {
      return getServices();
    }
    // On parcourt tous les services et on garde ceux de la bonne catégorie
    final List<Service> resultat = [];
    for (final service in getServices()) {
      if (service.categorie == categorie) {
        resultat.add(service);
      }
    }
    return resultat;
  }

  /// Uniquement les services communs hebdomadaires.
  List<Service> getServicesCommuns() {
    final List<Service> resultat = [];
    for (final service in getServices()) {
      if (service.estCommun) {
        resultat.add(service);
      }
    }
    return resultat;
  }
}
