import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo officiel Houmani.
/// - Par défaut : version couleur (assets/images/logo_couleur.png), pour fond clair.
/// - blanc: true : version blanche (assets/images/logo_blanc.png), pour fond coloré ou sombre.
/// Si avecNom est true, le nom "Houmani" est affiché sous le logo.
class HoumaniLogo extends StatelessWidget {
  final double taille;
  final bool avecNom;
  final bool blanc;
  final Color couleurNom;

  const HoumaniLogo({
    super.key,
    this.taille = 80,
    this.avecNom = false,
    this.blanc = false,
    this.couleurNom = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    // D'abord l'image du logo
    final List<Widget> contenu = [
      Image.asset(
        blanc ? 'assets/images/logo_blanc.png' : 'assets/images/logo_couleur.png',
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
