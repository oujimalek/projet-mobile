import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo officiel Houmani (image assets/images/logo.png).
/// Si avecNom est true, le nom "Houmani" est affiché sous le logo.
class HoumaniLogo extends StatelessWidget {
  final double taille;
  final bool avecNom;
  final Color couleurNom;

  const HoumaniLogo({
    super.key,
    this.taille = 80,
    this.avecNom = false,
    this.couleurNom = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    // D'abord l'image du logo
    final List<Widget> contenu = [
      Image.asset(
        'assets/images/logo.png',
        width: taille,
        height: taille,
      ),
    ];

    // Puis le nom, seulement si on l'a demandé
    if (avecNom) {
      contenu.add(const SizedBox(height: 8));
      contenu.add(
        Text(
          'Houmani',
          style: TextStyle(
            color: couleurNom,
            fontSize: taille * 0.3,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: contenu,
    );
  }
}
