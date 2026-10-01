import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Séparateur "en clous", inspiré des portes tunisiennes :
/// une rangée de 7 petits points, celui du centre est orange et plus gros.
class NailDivider extends StatelessWidget {
  const NailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    // On construit les 7 clous avec une boucle
    final List<Widget> clous = [];
    for (int i = 0; i < 7; i++) {
      final bool estCentre = i == 3;
      clous.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: estCentre ? 9 : 5,
          height: estCentre ? 9 : 5,
          decoration: BoxDecoration(
            color: estCentre ? AppColors.accent : AppColors.border,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: clous,
      ),
    );
  }
}
