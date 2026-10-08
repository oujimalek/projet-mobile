import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/houmani_logo.dart';

/// Écran de lancement : fond bleu cobalt, logo blanc et nom de l'app.
/// Après 2 secondes, on passe à l'écran de connexion.
///
/// (Avant cet écran, Android et iOS affichent déjà un lancement natif
/// avec le même fond et le même logo : voir launch_background.xml et
/// LaunchScreen.storyboard. L'enchaînement est donc invisible.)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer(const Duration(seconds: 2), () {
      // go : remplace le splash (pas de retour possible vers lui)
      context.go('/connexion');
    });
  }

  @override
  void dispose() {
    // Si l'écran est fermé avant la fin, on arrête le minuteur
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo blanc + nom "Houmani" en blanc dessous
            HoumaniLogo(
              taille: 112,
              blanc: true,
              avecNom: true,
              couleurNom: Colors.white,
            ),
            SizedBox(height: 6),
            Text(
              'L\'application de ta houma',
              style: TextStyle(color: AppColors.secondaryLight, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
