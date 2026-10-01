import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/coming_soon.dart';
import '../widgets/secondary_button.dart';

/// Onglet "Accueil" (placeholder).
///
/// L'écran d'accueil (fil d'actualité du quartier) n'existe pas encore.
/// En attendant, un bouton ouvre l'écran de démo des 4 modules.
class AccueilScreen extends StatelessWidget {
  const AccueilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: Column(
        children: [
          const Expanded(
            child: ComingSoon(module: 'Accueil\nFil d\'actualité du quartier'),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SecondaryButton(
              texte: 'Voir la démo des modules',
              onPressed: () {
                // push : ouvre l'écran par-dessus, avec une flèche retour
                context.push('/demo');
              },
            ),
          ),
        ],
      ),
    );
  }
}
