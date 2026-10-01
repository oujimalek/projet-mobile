import '../models/service.dart';

/// M2 - Accès aux services entre voisins.
///
/// Données en dur pour l'instant. Plus tard, seul l'intérieur de ces
/// méthodes changera (appel à une API), pas les écrans.
class ServiceRepository {
  /// Les catégories utilisées pour les filtres de la liste des services.
  /// "Tous" est le filtre par défaut.
  List<String> getCategories() {
    return const ['Tous', 'Bricolage', 'Cours', 'Courses', 'Garde', 'Covoiturage'];
  }

  /// Tous les services du quartier.
  List<Service> getServices() {
    return const [
      Service(
        id: 's1',
        titre: 'Réparation de robinets',
        description: 'Je peux réparer les fuites et changer les joints.',
        categorie: 'Bricolage',
        auteur: 'Youssef T.',
        estOffre: true,
        prix: '15 DT',
      ),
      Service(
        id: 's2',
        titre: 'Cours de maths (collège)',
        description: 'Soutien scolaire le soir, niveau 7e à 9e année.',
        categorie: 'Cours',
        auteur: 'Salma G.',
        estOffre: true,
        prix: '20 DT / h',
      ),
      Service(
        id: 's3',
        titre: 'Qui va au marché samedi ?',
        description: 'Je cherche quelqu\'un pour me ramener des légumes.',
        categorie: 'Courses',
        auteur: 'Amira B.',
        estOffre: false,
      ),
      Service(
        id: 's4',
        titre: 'Covoiturage vers Ariana',
        description: 'Départ chaque matin à 7h30, 2 places libres.',
        categorie: 'Covoiturage',
        auteur: 'Karim M.',
        estOffre: true,
      ),
      Service(
        id: 's5',
        titre: 'Nettoyage des escaliers',
        description: 'Service commun : on nettoie ensemble les escaliers du bloc.',
        categorie: 'Bricolage',
        auteur: 'Syndic Bloc B',
        estOffre: true,
        estCommun: true,
        jour: 'Samedi',
      ),
      Service(
        id: 's6',
        titre: 'Achat groupé du pain',
        description: 'Service commun : un voisin passe à la boulangerie pour tous.',
        categorie: 'Courses',
        auteur: 'Résidence Yasmine',
        estOffre: true,
        estCommun: true,
        jour: 'Dimanche',
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
