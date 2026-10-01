import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carte blanche à bordure beige, coins arrondis.
/// Si onTap est donné, la carte devient cliquable.
///
/// Exemple : AppCard(child: Text('Bonjour'), onTap: () {})
class AppCard extends StatelessWidget {
  final Widget child;
  final Function()? onTap; // fonction appelée au clic (null = pas cliquable)
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias, // pour que l'effet du clic suive les coins
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
