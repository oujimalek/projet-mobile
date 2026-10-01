import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/coming_soon.dart';
import '../widgets/secondary_button.dart';

/// Onglet "Profil" (placeholder).
///
/// L'écran de profil n'existe pas encore.
/// En attendant, un bouton ouvre l'écran de connexion (module 1).
class ProfilScreen extends StatelessWidget {
  const ProfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Column(
        children: [
          const Expanded(
            child: ComingSoon(module: 'Profil\nMes informations et ma résidence'),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SecondaryButton(
              texte: 'Se connecter',
              onPressed: () {
                // push : ouvre l'écran par-dessus, avec une flèche retour
                context.push('/connexion');
              },
            ),
          ),
        ],
      ),
    );
  }
}
