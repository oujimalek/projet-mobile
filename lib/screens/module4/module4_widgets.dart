import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';

/// M4 - Petits outils partagés par les écrans du module Événements.

/// Ouvre un écran par-dessus la coquille (comme le module 2) et attend la
/// valeur qu'il renvoie avec `Navigator.pop(context, valeur)`.
Future<T?> ouvrirEcranM4<T>(BuildContext context, Widget ecran) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    MaterialPageRoute<T>(builder: (context) => ecran),
  );
}

// =======================================================================
// Catégories : icône et couleurs (restent dans le code, pas dans Firestore)
// =======================================================================

IconData iconeCategorie(CategorieEvenement categorie) {
  switch (categorie) {
    case CategorieEvenement.fete:
      return Icons.celebration_outlined;
    case CategorieEvenement.reunion:
      return Icons.groups_outlined;
    case CategorieEvenement.nettoyage:
      return Icons.cleaning_services_outlined;
    case CategorieEvenement.sport:
      return Icons.sports_soccer_outlined;
    case CategorieEvenement.culture:
      return Icons.theater_comedy_outlined;
    case CategorieEvenement.autre:
      return Icons.event_outlined;
  }
}

/// La couleur de la catégorie (icône, texte).
Color couleurCategorie(CategorieEvenement categorie) {
  switch (categorie) {
    case CategorieEvenement.fete:
      return AppColors.secondary;
    case CategorieEvenement.reunion:
      return AppColors.primary;
    case CategorieEvenement.nettoyage:
      return AppColors.ordures;
    case CategorieEvenement.sport:
      return AppColors.eau;
    case CategorieEvenement.culture:
      return AppColors.travaux;
    case CategorieEvenement.autre:
      return AppColors.textSecondary;
  }
}

/// Le fond clair de la catégorie (pastilles, bandeau).
Color fondCategorie(CategorieEvenement categorie) {
  switch (categorie) {
    case CategorieEvenement.fete:
      return AppColors.secondaryLight;
    case CategorieEvenement.reunion:
      return AppColors.primaryLight;
    case CategorieEvenement.nettoyage:
      return AppColors.orduresLight;
    case CategorieEvenement.sport:
      return AppColors.eauLight;
    case CategorieEvenement.culture:
      return AppColors.travauxLight;
    case CategorieEvenement.autre:
      return AppColors.backgroundSecondary;
  }
}

// =======================================================================
// Dates en français (sans package intl)
// =======================================================================

const List<String> _jours = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
];
const List<String> _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
  'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// "18:05"
String texteHeure(DateTime date) {
  final String heures = date.hour.toString().padLeft(2, '0');
  final String minutes = date.minute.toString().padLeft(2, '0');
  return '$heures:$minutes';
}

/// "samedi 15 novembre" (+ l'année si ce n'est pas l'année en cours)
String texteDate(DateTime date) {
  String texte = '${_jours[date.weekday - 1]} ${date.day} ${_mois[date.month - 1]}';
  if (date.year != DateTime.now().year) {
    texte = '$texte ${date.year}';
  }
  return texte;
}

/// "18:00 – 22:00", ou "18:00" s'il n'y a pas d'heure de fin.
String texteHoraire(Evenement evenement) {
  final DateTime? fin = evenement.dateFin;
  if (fin == null) {
    return texteHeure(evenement.date);
  }
  return '${texteHeure(evenement.date)} – ${texteHeure(fin)}';
}

/// "se termine dans 3 jours", "se termine aujourd'hui", "terminé".
String texteFin(DateTime fin) {
  final DateTime maintenant = DateTime.now();
  if (fin.isBefore(maintenant)) {
    return 'terminé';
  }
  final DateTime aujourdhui =
      DateTime(maintenant.year, maintenant.month, maintenant.day);
  final int jours =
      DateTime(fin.year, fin.month, fin.day).difference(aujourdhui).inDays;
  if (jours == 0) {
    return 'se termine aujourd\'hui';
  }
  if (jours == 1) {
    return 'se termine demain';
  }
  return 'se termine dans $jours jours';
}

// =======================================================================
// Widgets
// =======================================================================

/// Message au centre : liste vide, erreur (avec "Réessayer") ou chargement.
class MessageM4 extends StatelessWidget {
  final String texte;
  final IconData icone;
  final Function()? reessayer; // null = pas de bouton

  const MessageM4({
    super.key,
    required this.texte,
    this.icone = Icons.info_outline,
    this.reessayer,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> enfants = [
      Icon(icone, size: 40, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text(
        texte,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    ];
    if (reessayer != null) {
      enfants.add(
        TextButton(onPressed: reessayer, child: Text(tr('Réessayer', '3awed jarreb'))),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: enfants),
      ),
    );
  }
}

/// Pastille de catégorie : icône + nom, aux couleurs de la catégorie.
class PastilleCategorie extends StatelessWidget {
  final CategorieEvenement categorie;

  const PastilleCategorie({super.key, required this.categorie});

  @override
  Widget build(BuildContext context) {
    final Color couleur = couleurCategorie(categorie);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondCategorie(categorie),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconeCategorie(categorie), size: 14, color: couleur),
          const SizedBox(width: 4),
          Text(
            categorie.libelle,
            style: TextStyle(
              color: couleur,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustration d'un événement selon sa catégorie : bandeau coloré avec
/// une grande icône (pas de photo à envoyer).
class IllustrationCategorie extends StatelessWidget {
  final CategorieEvenement categorie;
  final double hauteur;

  const IllustrationCategorie({
    super.key,
    required this.categorie,
    this.hauteur = 140,
  });

  @override
  Widget build(BuildContext context) {
    final Color couleur = couleurCategorie(categorie);
    return Container(
      height: hauteur,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fondCategorie(categorie), couleur.withValues(alpha: 0.35)],
        ),
      ),
      child: Stack(
        children: [
          // Petites icônes en fond, pour un effet "motif"
          Positioned(
            left: 18,
            top: 14,
            child: Icon(iconeCategorie(categorie),
                size: 28, color: couleur.withValues(alpha: 0.25)),
          ),
          Positioned(
            right: 24,
            bottom: 12,
            child: Icon(iconeCategorie(categorie),
                size: 36, color: couleur.withValues(alpha: 0.25)),
          ),
          Center(
            child: Icon(iconeCategorie(categorie), size: 64, color: couleur),
          ),
        ],
      ),
    );
  }
}

/// Petit badge texte (ex : "Je participe", "Passé").
class BadgeM4 extends StatelessWidget {
  final String texte;
  final Color couleur;
  final Color fond;

  const BadgeM4({
    super.key,
    required this.texte,
    required this.couleur,
    required this.fond,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: couleur,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
