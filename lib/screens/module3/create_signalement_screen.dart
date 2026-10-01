import 'package:flutter/material.dart';

import '../../widgets/coming_soon.dart';

/// M3 - Signalements : création d'un signalement.
///
/// PLACEHOLDER : remplacer le contenu de ce fichier en phase 2
/// (garder le nom de la classe CreateSignalementScreen).
///
/// À utiliser pour le vrai écran :
///   - GridView des catégories : SignalementRepository().getCategories()
///     (chaque catégorie a icone, couleur et couleurClaire)
///   - AppTextField pour la description, PrimaryButton pour envoyer
///   - StatusBadge pour afficher le statut d'un signalement
class CreateSignalementScreen extends StatelessWidget {
  const CreateSignalementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau signalement')),
      body: const ComingSoon(
        module: 'Module 3 - Signalements\nCréation de signalement',
      ),
    );
  }
}
