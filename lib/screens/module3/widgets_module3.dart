import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';

/// M3 - Petits widgets et outils partagés par les écrans des signalements.

/// Ouvre un écran du module 3 par-dessus l'écran actuel (Navigator.push)
/// et renvoie ce que l'écran a donné à Navigator.pop (ex : true = publié).
Future<T?> ouvrirEcranM3<T>(BuildContext context, Widget ecran) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (context) => ecran),
  );
}

/// Affiche un message en bas de l'écran (SnackBar). L'ancien message est
/// d'abord fermé : les messages ne font pas la queue.
void afficherMessageM3(BuildContext context, String texte) {
  final ScaffoldMessengerState messager = ScaffoldMessenger.of(context);
  messager.hideCurrentSnackBar();
  messager.showSnackBar(SnackBar(content: Text(texte)));
}

/// Depuis quand : "5 min", "3 h", "hier", sinon "1/10".
String depuisQuandM3(DateTime date) {
  final Duration ecart = DateTime.now().difference(date);
  if (ecart.inMinutes < 60) {
    final int minutes = ecart.inMinutes < 1 ? 1 : ecart.inMinutes;
    return '$minutes min';
  }
  if (ecart.inHours < 24) {
    return '${ecart.inHours} h';
  }
  if (ecart.inHours < 48) {
    return tr('hier', 'lbere7');
  }
  return '${date.day}/${date.month}';
}

/// Heure courte : "14:05" aujourd'hui, sinon "1/10 à 14:05".
String heureM3(DateTime date) {
  final String heure =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  final DateTime maintenant = DateTime.now();
  if (date.year == maintenant.year &&
      date.month == maintenant.month &&
      date.day == maintenant.day) {
    return heure;
  }
  return '${date.day}/${date.month} ${tr('à', 'm3a')} $heure';
}

/// Bandeau orange en haut d'une liste (ex : "Hors ligne — ...").
class BandeauM3 extends StatelessWidget {
  final IconData icone;
  final String texte;

  const BandeauM3({super.key, required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(icone, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Date complète : "1/10/2026 à 14:05".
String dateCompleteM3(DateTime date) {
  final String heure = date.hour.toString().padLeft(2, '0');
  final String minute = date.minute.toString().padLeft(2, '0');
  return '${date.day}/${date.month}/${date.year} ${tr('à', 'm3a')} $heure:$minute';
}

/// Le texte d'un statut (le même que StatusBadge), pour les filtres.
String texteStatut(StatutSignalement statut) {
  switch (statut) {
    case StatutSignalement.enAttente:
      return tr('En attente', 'Yestanna');
    case StatutSignalement.enCours:
      return tr('En cours', '9a3din nekhdmou');
    case StatutSignalement.resolu:
      return tr('Résolu', 'Tsalle7');
    case StatutSignalement.refuse:
      return tr('Refusé', 'Martoud');
  }
}

/// Badge d'urgence : pastille de couleur + texte.
/// Vert = faible, orange = normal, rouge = urgent (couleurs du thème).
class BadgeUrgence extends StatelessWidget {
  final NiveauUrgence niveau;

  const BadgeUrgence({super.key, required this.niveau});

  @override
  Widget build(BuildContext context) {
    String texte;
    Color couleur;
    switch (niveau) {
      case NiveauUrgence.faible:
        texte = tr('Faible', 'Khfif');
        couleur = AppColors.success;
      case NiveauUrgence.normal:
        texte = tr('Normal', '3adi');
        couleur = AppColors.warning;
      case NiveauUrgence.urgent:
        texte = tr('Urgent', 'Mosta3jel');
        couleur = AppColors.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            texte,
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

/// Icône de la catégorie dans un rond de sa couleur claire.
class PastilleCategorie extends StatelessWidget {
  final CategorieSignalement categorie;
  final double taille;

  const PastilleCategorie({
    super.key,
    required this.categorie,
    this.taille = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: categorie.couleurClaire,
        shape: BoxShape.circle,
      ),
      child: Icon(
        categorie.icone,
        color: categorie.couleur,
        size: taille * 0.5,
      ),
    );
  }
}

/// Petite étiquette rouge "Danger".
class EtiquetteDanger extends StatelessWidget {
  const EtiquetteDanger({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
          const SizedBox(width: 4),
          Text(
            tr('Danger', 'Khatar'),
            style: TextStyle(
              color: AppColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Message centré (liste vide, erreur), avec un bouton optionnel.
class MessageEtatM3 extends StatelessWidget {
  final IconData icone;
  final String texte;
  final String? texteBouton;
  final Function()? onBouton;

  const MessageEtatM3({
    super.key,
    required this.icone,
    required this.texte,
    this.texteBouton,
    this.onBouton,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> enfants = [
      Icon(icone, size: 48, color: AppColors.textSecondary),
      const SizedBox(height: 12),
      Text(
        texte,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
      ),
    ];
    final String? bouton = texteBouton;
    if (bouton != null && onBouton != null) {
      enfants.add(const SizedBox(height: 8));
      enfants.add(TextButton(onPressed: onBouton, child: Text(bouton)));
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: enfants,
      ),
    );
  }
}
