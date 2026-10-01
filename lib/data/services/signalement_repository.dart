import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/signalement.dart';

/// M3 - Accès aux signalements et à leurs catégories.
///
/// Données en dur pour l'instant. Plus tard, seul l'intérieur de ces
/// méthodes changera (appel à une API), pas les écrans.
class SignalementRepository {
  /// Les catégories affichées dans la GridView de création de signalement.
  List<CategorieSignalement> getCategories() {
    return const [
      CategorieSignalement(
        id: 'electricite',
        nom: 'Électricité',
        icone: Icons.bolt,
        couleur: AppColors.electricite,
        couleurClaire: AppColors.electriciteLight,
      ),
      CategorieSignalement(
        id: 'eau',
        nom: 'Eau',
        icone: Icons.water_drop,
        couleur: AppColors.eau,
        couleurClaire: AppColors.eauLight,
      ),
      CategorieSignalement(
        id: 'ordures',
        nom: 'Ordures',
        icone: Icons.delete_outline,
        couleur: AppColors.ordures,
        couleurClaire: AppColors.orduresLight,
      ),
      CategorieSignalement(
        id: 'travaux',
        nom: 'Travaux',
        icone: Icons.construction,
        couleur: AppColors.travaux,
        couleurClaire: AppColors.travauxLight,
      ),
      CategorieSignalement(
        id: 'incident',
        nom: 'Incident',
        icone: Icons.warning_amber_rounded,
        couleur: AppColors.incident,
        couleurClaire: AppColors.incidentLight,
      ),
    ];
  }

  /// Retrouve une catégorie à partir de son id.
  /// Si l'id n'existe pas, on renvoie la catégorie "Incident".
  CategorieSignalement getCategorieParId(String id) {
    final List<CategorieSignalement> categories = getCategories();
    for (final categorie in categories) {
      if (categorie.id == id) {
        return categorie;
      }
    }
    return categories.last;
  }

  /// Les signalements récents du quartier.
  List<Signalement> getSignalements() {
    return [
      Signalement(
        id: 'r1',
        titre: 'Coupure d\'électricité',
        description: 'Plus de courant dans tout le bloc B depuis 14h.',
        categorieId: 'electricite',
        statut: StatutSignalement.enCours,
        date: DateTime(2026, 10, 1, 14, 0),
        lieu: 'Bloc B',
        auteur: 'Amira B.',
        confirmations: 12,
      ),
      Signalement(
        id: 'r2',
        titre: 'Le camion d\'ordures est passé',
        description: 'Passage du camion ce matin, pensez aux poubelles.',
        categorieId: 'ordures',
        statut: StatutSignalement.resolu,
        date: DateTime(2026, 10, 1, 7, 30),
        lieu: 'Rue principale',
        auteur: 'Youssef T.',
        confirmations: 5,
      ),
      Signalement(
        id: 'r3',
        titre: 'Fuite d\'eau devant l\'entrée',
        description: 'Une canalisation fuit devant l\'entrée du bloc A.',
        categorieId: 'eau',
        statut: StatutSignalement.enAttente,
        date: DateTime(2026, 9, 30, 18, 15),
        lieu: 'Entrée bloc A',
        auteur: 'Salma G.',
        confirmations: 3,
      ),
      Signalement(
        id: 'r4',
        titre: 'Travaux de voirie',
        description: 'La rue sera fermée toute la semaine.',
        categorieId: 'travaux',
        statut: StatutSignalement.refuse,
        date: DateTime(2026, 9, 29, 9, 0),
        lieu: 'Avenue Hédi Nouira',
        auteur: 'Karim M.',
      ),
    ];
  }
}
