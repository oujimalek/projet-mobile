import 'package:flutter/material.dart';

import '../../widgets/coming_soon.dart';

/// M4 - Événements : sondage entre voisins.
///
/// PLACEHOLDER : remplacer le contenu de ce fichier en phase 2
/// (garder le nom de la classe SondageScreen).
///
/// À utiliser pour le vrai écran :
///   - transformer en StatefulWidget (le choix du vote change l'écran)
///   - données : EvenementRepository().getSondageActif()
///   - ArchDateBlock pour la date, NailDivider, PrimaryButton "Voter"
class SondageScreen extends StatelessWidget {
  const SondageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sondage')),
      body: const ComingSoon(module: 'Module 4 - Événements\nSondage'),
    );
  }
}
