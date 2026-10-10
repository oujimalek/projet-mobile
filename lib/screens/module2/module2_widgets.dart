import 'package:flutter/material.dart';

import '../../data/models/statut_demande.dart';
import '../../theme/app_theme.dart';
import 'module2_outils.dart';

/// M2 - Petits composants partagés par les écrans du module Services.

/// Rond avec les initiales d'un nom (avatar).
class AvatarInitiales extends StatelessWidget {
  final String nom;
  final double taille;

  const AvatarInitiales({super.key, required this.nom, this.taille = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        initiales(nom),
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: taille * 0.34,
        ),
      ),
    );
  }
}

/// Petite pastille colorée (catégorie, type de service, "Créneau libre"...).
class PastilleTexte extends StatelessWidget {
  final String texte;
  final Color couleur;
  final Color fond;

  const PastilleTexte({
    super.key,
    required this.texte,
    required this.couleur,
    required this.fond,
  });

  @override
  Widget build(BuildContext context) {
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

/// Badge du statut d'une demande (mêmes couleurs que StatusBadge).
/// StatusBadge ne gère que les statuts de signalement, d'où ce badge à part.
class BadgeStatutDemande extends StatelessWidget {
  final StatutDemande statut;

  const BadgeStatutDemande({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    String texte;
    Color couleur;
    Color fond;
    switch (statut) {
      case StatutDemande.enAttente:
        texte = 'En attente';
        couleur = AppColors.badgeEnAttente;
        fond = AppColors.badgeEnAttenteFond;
      case StatutDemande.acceptee:
        texte = 'Acceptée';
        couleur = AppColors.badgeEnCours;
        fond = AppColors.badgeEnCoursFond;
      case StatutDemande.refusee:
        texte = 'Refusée';
        couleur = AppColors.badgeRefuse;
        fond = AppColors.badgeRefuseFond;
      case StatutDemande.realisee:
        texte = 'Réalisée';
        couleur = AppColors.badgeResolu;
        fond = AppColors.badgeResoluFond;
    }
    return PastilleTexte(texte: texte, couleur: couleur, fond: fond);
  }
}

/// Deux onglets côte à côte (même style que "Offres / Demandes").
/// premierActif = true : le premier onglet est sélectionné.
class DeuxOnglets extends StatelessWidget {
  final String premier;
  final String second;
  final bool premierActif;
  final Function(bool) onChoix; // reçoit true si on touche le premier onglet

  const DeuxOnglets({
    super.key,
    required this.premier,
    required this.second,
    required this.premierActif,
    required this.onChoix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(child: _onglet(premier, true)),
          Expanded(child: _onglet(second, false)),
        ],
      ),
    );
  }

  Widget _onglet(String texte, bool estPremier) {
    final bool actif = premierActif == estPremier;
    return InkWell(
      onTap: () {
        onChoix(estPremier);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: actif ? AppColors.card : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: actif ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Une pastille cliquable (doré quand elle est sélectionnée),
/// utilisée pour les catégories et les tags.
class PastilleChoix extends StatelessWidget {
  final String texte;
  final bool actif;
  final Function() onTap;

  const PastilleChoix({
    super.key,
    required this.texte,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? AppColors.secondary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? AppColors.secondary : AppColors.border,
          ),
        ),
        child: Text(
          texte,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: actif ? AppColors.card : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
