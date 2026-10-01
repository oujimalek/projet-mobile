import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bloc de date en forme d'arc de porte tunisienne (haut arrondi).
/// Affiche le jour et le mois abrégé, par exemple "17 / OCT".
/// Utilisé dans les cartes d'événements (M4).
class ArchDateBlock extends StatelessWidget {
  final DateTime date;

  const ArchDateBlock({super.key, required this.date});

  // Mois abrégés en français (index 0 = janvier)
  static const List<String> _mois = [
    'JAN', 'FÉV', 'MAR', 'AVR', 'MAI', 'JUIN',
    'JUIL', 'AOÛT', 'SEP', 'OCT', 'NOV', 'DÉC',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 66,
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        // Haut très arrondi = forme d'arc ; bas légèrement arrondi
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _mois[date.month - 1],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
