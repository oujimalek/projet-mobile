import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/accueil_screen.dart';
import '../screens/demo_screen.dart';
import '../screens/module1/admin_membres_screen.dart';
import '../screens/module1/attente_validation_screen.dart';
import '../screens/module1/code_quartier_screen.dart';
import '../screens/module1/connexion_screen.dart';
import '../screens/module1/inscription_screen.dart';
import '../screens/module1/mot_de_passe_oublie_screen.dart';
import '../screens/module1/profil_edition_screen.dart';
import '../screens/module1/profil_screen.dart';
import '../screens/module1/verification_otp_screen.dart';
import '../screens/module2/services_list_screen.dart';
import '../screens/module3/create_signalement_screen.dart';
import '../screens/module4/sondage_screen.dart';
import '../screens/splash_screen.dart';
import '../widgets/app_bottom_nav.dart';

/// Les chemins (adresses) des 5 onglets, dans l'ordre de la barre du bas.
/// L'index dans cette liste = l'index de l'onglet dans AppBottomNav.
const List<String> cheminsOnglets = [
  '/accueil', // 0
  '/services', // 1
  '/signalements', // 2
  '/evenements', // 3
  '/profil', // 4
];

/// Le routeur de l'application : il associe chaque chemin à un écran.
///
/// - Les 5 onglets sont dans un ShellRoute : ils s'affichent DANS la même
///   coquille (AppShell), qui garde la barre du bas visible.
/// - Les autres écrans (splash, connexion, inscription, démo...) sont en
///   dehors du ShellRoute : ils s'ouvrent en plein écran, sans barre du bas.
///
/// Parcours du module 1 (M1) :
///   /splash → /connexion → /inscription → /verification → /code-quartier
///   → /attente → /accueil
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash', // écran affiché au lancement
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        // child = l'écran de l'onglet actif
        return AppShell(chemin: state.uri.path, child: child);
      },
      routes: [
        GoRoute(
          path: '/accueil',
          builder: (context, state) {
            return const AccueilScreen();
          },
        ),
        GoRoute(
          path: '/services',
          builder: (context, state) {
            return const ServicesListScreen(); // M2
          },
        ),
        GoRoute(
          path: '/signalements',
          builder: (context, state) {
            return const CreateSignalementScreen(); // M3
          },
        ),
        GoRoute(
          path: '/evenements',
          builder: (context, state) {
            return const SondageScreen(); // M4
          },
        ),
        GoRoute(
          path: '/profil',
          builder: (context, state) {
            return const ProfilScreen(); // M1
          },
          routes: [
            // /profil/membres : reste dans la coquille (onglet Profil actif)
            GoRoute(
              path: 'membres',
              builder: (context, state) {
                return const AdminMembresScreen(); // M1 (admin)
              },
            ),
          ],
        ),
      ],
    ),

    // ----- Écrans en plein écran (sans barre du bas) -----
    GoRoute(
      path: '/splash',
      builder: (context, state) {
        return const SplashScreen();
      },
    ),
    GoRoute(
      path: '/connexion',
      builder: (context, state) {
        return const ConnexionScreen(); // M1
      },
    ),
    GoRoute(
      path: '/mot-de-passe-oublie',
      builder: (context, state) {
        return const MotDePasseOublieScreen(); // M1
      },
    ),
    GoRoute(
      path: '/inscription',
      builder: (context, state) {
        return const InscriptionScreen(); // M1
      },
    ),
    GoRoute(
      path: '/verification',
      builder: (context, state) {
        return const VerificationOtpScreen(); // M1
      },
    ),
    GoRoute(
      path: '/code-quartier',
      builder: (context, state) {
        return const CodeQuartierScreen(); // M1
      },
    ),
    GoRoute(
      path: '/attente',
      builder: (context, state) {
        return const AttenteValidationScreen(); // M1
      },
    ),
    GoRoute(
      path: '/modifier-profil',
      builder: (context, state) {
        return const ProfilEditionScreen(); // M1
      },
    ),
    GoRoute(
      path: '/demo',
      builder: (context, state) {
        return const DemoScreen();
      },
    ),
  ],
);

/// La coquille commune aux 5 onglets : l'écran de l'onglet actif
/// en haut, et la barre de navigation du bas.
class AppShell extends StatelessWidget {
  final String chemin; // chemin actuel, ex : "/services"
  final Widget child; // écran de l'onglet actif

  const AppShell({super.key, required this.chemin, required this.child});

  /// Retrouve l'index de l'onglet actif à partir du chemin.
  int _indexActif() {
    for (int i = 0; i < cheminsOnglets.length; i++) {
      if (chemin.startsWith(cheminsOnglets[i])) {
        return i;
      }
    }
    return 0; // par défaut : Accueil
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNav(
        indexActif: _indexActif(),
        onTap: (index) {
          // go : remplace l'onglet affiché (pas de flèche retour entre onglets)
          context.go(cheminsOnglets[index]);
        },
      ),
    );
  }
}
