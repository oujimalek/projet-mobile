import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bouton d'action principal (orange), sur toute la largeur.
/// À utiliser UNE seule fois par écran pour l'action la plus importante.
///
/// Exemple : PrimaryButton(texte: 'Se connecter', onPressed: () {})
class PrimaryButton extends StatelessWidget {
  final String texte;
  final Function()? onPressed; // fonction appelée au clic (null = bouton désactivé)
  final IconData? icone; // icône optionnelle à gauche du texte

  const PrimaryButton({
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

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: contenu,
      ),
    );
  }
}
