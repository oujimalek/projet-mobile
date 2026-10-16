import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/utilisateur.dart';
import '../data/services/utilisateur_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/houmani_logo.dart';
import 'module1/widgets_module1.dart';

/// Écran de lancement : fond bleu cobalt, logo blanc et nom de l'app.
/// Après 2 secondes, on passe à l'écran de connexion (ou directement à
/// l'accueil si l'utilisateur est resté connecté).
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
  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  /// M1 : pendant les 2 secondes du logo, on cherche si quelqu'un est
  /// resté connecté (Firebase + cache local), puis on ouvre le bon écran.
  Future<void> _demarrer() async {
    // Par défaut (personne de connecté, compte bloqué, erreur) : connexion
    String chemin = '/connexion';
    try {
      // Future.wait : les deux en même temps, on attend le plus long.
      // timeout : réseau trop lent, on n'attend pas plus de 8 secondes.
      final List<Object?> resultats = await Future.wait<Object?>([
        UtilisateurRepository()
            .restaurerSession()
            .timeout(const Duration(seconds: 8)),
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
      final Utilisateur? utilisateur = resultats[0] as Utilisateur?;
      if (utilisateur != null) {
        chemin = cheminSelonStatut(utilisateur) ?? '/connexion';
      }
    } catch (e) {
      // Erreur imprévue : on ne reste pas bloqué sur le logo
      debugPrint('Splash : $e');
    }
    if (!mounted) {
      return; // écran fermé pendant l'attente
    }
    // go : remplace le splash (pas de retour possible vers lui)
    context.go(chemin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
