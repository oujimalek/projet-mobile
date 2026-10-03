import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bouton secondaire : fond blanc, bordure et texte dorés, sur toute la largeur.
/// Même taille et mêmes paramètres que PrimaryButton : à utiliser pour une
/// action moins importante (ex : "Annuler", "Plus tard") à côté du bouton principal.
///
/// Exemple : SecondaryButton(texte: 'Annuler', onPressed: () {})
class SecondaryButton extends StatelessWidget {
  final String texte;
  final Function()? onPressed; // fonction appelée au clic (null = bouton désactivé)
  final IconData? icone; // icône optionnelle à gauche du texte

  const SecondaryButton({
    super.key,
    required this.texte,
    required this.onPressed,
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    // Contenu du bouton : l'icône (si elle existe) puis le texte
    final List<Widget> contenu = [];
    if (icone != null) {
      contenu.add(Icon(icone, size: 20));
      contenu.add(const SizedBox(width: 8));
    }
    // Flexible : si le texte est trop long (petit écran, grande police),
    // il passe à la ligne au lieu de déborder du bouton
    contenu.add(
      Flexible(
        child: Text(texte, textAlign: TextAlign.center),
      ),
    );

    // Même widget que PrimaryButton (ElevatedButton) : la taille, les coins
    // arrondis et le style du texte viennent du thème, seules les couleurs changent
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.secondary,
        // Désactivé : le même bouton à 40 % d'opacité (comme sur Figma)
        disabledBackgroundColor: AppColors.card.withValues(alpha: 0.4),
        disabledForegroundColor: AppColors.secondary.withValues(alpha: 0.4),
        elevation: 0,
        side: BorderSide(
          color: onPressed != null
              ? AppColors.secondary
              : AppColors.secondary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: contenu,
      ),
    );
  }
}
