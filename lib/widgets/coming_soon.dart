import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'nail_divider.dart';

/// Contenu temporaire "À venir" affiché par les écrans pas encore codés.
/// Chaque membre le remplacera par le vrai contenu de son écran.
class ComingSoon extends StatelessWidget {
  final String module; // ex : "Module 1 - Utilisateurs"

  const ComingSoon({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'À venir',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const NailDivider(),
            Text(
              module,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
