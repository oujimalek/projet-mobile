import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// En-tête blanc aux coins arrondis en bas, utilisé par les écrans
/// de détail ou de formulaire (ex : "Nouveau signalement", "Sondage").
/// La flèche retour bleue n'apparaît que s'il y a un écran précédent.
///
/// Exemple : AppHeader(titre: 'Sondage')
/// Un widget optionnel (ex : un bouton "Enregistrer") peut être placé à droite :
///   AppHeader(titre: 'Modifier le profil', action: TextButton(...))
class AppHeader extends StatelessWidget {
  final String titre;
  final Widget? action; // affiché à droite du titre (optionnel)

  const AppHeader({super.key, required this.titre, this.action});

  @override
  Widget build(BuildContext context) {
    final bool peutRevenir = Navigator.of(context).canPop();

    return Container(
      width: double.infinity,
      // Le haut de l'écran (barre d'état) est inclus dans l'en-tête
      padding: EdgeInsets.fromLTRB(
        peutRevenir ? 8 : 24,
        MediaQuery.of(context).padding.top + 12,
        24,
        16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          if (peutRevenir)
            IconButton(
              onPressed: () {
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back, color: AppColors.primary),
            ),
          Expanded(
            child: Text(
              titre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          ?action, // "?" : ajouté seulement s'il n'est pas null
        ],
      ),
    );
  }
}
