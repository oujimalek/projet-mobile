import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

/// M4 - Camembert des résultats d'un sondage (package fl_chart), avec une
/// légende : une couleur par choix, le pourcentage dans chaque part.
class GraphiqueSondage extends StatelessWidget {
  final List<String> choix;
  final List<int> votes;

  const GraphiqueSondage({super.key, required this.choix, required this.votes});

  /// Une couleur par choix (on reprend au début s'il y en a plus).
  List<Color> get _couleurs => [
        AppColors.primary,
        AppColors.secondary,
        AppColors.success,
        AppColors.incident,
        AppColors.eau,
        AppColors.travaux,
      ];

  @override
  Widget build(BuildContext context) {
    int total = 0;
    for (final int nombre in votes) {
      total += nombre;
    }
    if (total == 0) {
      return const SizedBox.shrink(); // rien à dessiner
    }

    final List<PieChartSectionData> parts = [];
    final List<Widget> legende = [];
    for (int i = 0; i < choix.length && i < votes.length; i++) {
      final Color couleur = _couleurs[i % _couleurs.length];
      final double pourcent = votes[i] * 100 / total;
      if (votes[i] > 0) {
        parts.add(PieChartSectionData(
          value: votes[i].toDouble(),
          color: couleur,
          radius: 56,
          title: '${pourcent.round()} %',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      legende.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(choix[i])),
            Text('${pourcent.round()} %',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ));
    }

    return AppCard(
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: PieChart(
              PieChartData(
                sections: parts,
                centerSpaceRadius: 28,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...legende,
        ],
      ),
    );
  }
}
