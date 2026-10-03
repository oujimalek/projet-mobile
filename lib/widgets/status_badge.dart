import 'package:flutter/material.dart';

import '../data/models/signalement.dart';
import '../theme/app_theme.dart';

/// Petit badge coloré qui affiche le statut d'un signalement.
///
/// Exemple : StatusBadge(statut: StatutSignalement.enCours)
class StatusBadge extends StatelessWidget {
  final StatutSignalement statut;

  const StatusBadge({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    // On choisit le texte et les couleurs selon le statut
    String texte;
    Color couleur;
    Color fond;
    switch (statut) {
      case StatutSignalement.enAttente:
        texte = 'En attente';
        couleur = AppColors.badgeEnAttente;
        fond = AppColors.badgeEnAttenteFond;
      case StatutSignalement.enCours:
        texte = 'En cours';
        couleur = AppColors.badgeEnCours;
        fond = AppColors.badgeEnCoursFond;
      case StatutSignalement.resolu:
        texte = 'Résolu';
        couleur = AppColors.badgeResolu;
        fond = AppColors.badgeResoluFond;
      case StatutSignalement.refuse:
        texte = 'Refusé';
        couleur = AppColors.badgeRefuse;
        fond = AppColors.badgeRefuseFond;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: couleur,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
