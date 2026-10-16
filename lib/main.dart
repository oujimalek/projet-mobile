import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/preference_theme.dart';

// main est async : on attend que Firebase soit prêt avant d'afficher l'app.
Future<void> main() async {
  // Obligatoire avant d'utiliser un plugin (Firebase) avant runApp
  WidgetsFlutterBinding.ensureInitialized();
  // Connexion au projet Firebase "houmani-235bb"
  // (firebase_options.dart est généré par `flutterfire configure`)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Le thème choisi la dernière fois (clair, sombre ou système)
  await PreferenceTheme.charger();
  runApp(const HoumaniApp());
}

/// Point de départ de l'application Houmani.
///
/// Mode sombre : on écoute deux choses
/// - le choix fait dans Paramètres (PreferenceTheme.mode) ;
/// - le réglage du téléphone (didChangePlatformBrightness), pour "Système".
/// À chaque changement, on règle AppColors.sombre puis on reconstruit
/// tous les écrans ouverts (ils lisent AppColors directement).
class HoumaniApp extends StatefulWidget {
  const HoumaniApp({super.key});

  @override
  State<HoumaniApp> createState() {
    return _HoumaniAppState();
  }
}

class _HoumaniAppState extends State<HoumaniApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // écoute le téléphone
    PreferenceTheme.mode.addListener(_appliquerTheme); // écoute Paramètres
    // Premier affichage : on règle seulement la palette (rien à redessiner)
    AppColors.sombre = _doitEtreSombre();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PreferenceTheme.mode.removeListener(_appliquerTheme);
    super.dispose();
  }

  /// Le téléphone vient de passer en clair ou en sombre.
  @override
  void didChangePlatformBrightness() {
    _appliquerTheme();
  }

  bool _doitEtreSombre() {
    final bool telephoneSombre =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    return PreferenceTheme.estSombre(
      PreferenceTheme.mode.value,
      telephoneSombre,
    );
  }

  void _appliquerTheme() {
    final bool sombre = _doitEtreSombre();
    if (sombre == AppColors.sombre || !mounted) {
      return; // rien ne change
    }
    setState(() {
      AppColors.sombre = sombre;
    });
    reconstruireTout(context);
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp.router : les écrans sont choisis par le routeur
    // (go_router), défini dans lib/router/app_router.dart
    return MaterialApp.router(
      title: 'Houmani', // nom affiché de l'application
      debugShowCheckedModeBanner: false,
      theme: AppTheme.actuel, // couleurs (claires ou sombres) et police
      routerConfig: appRouter,
    );
  }
}

/// Demande à TOUS les widgets sous [context] de se redessiner.
///
/// Nécessaire car les écrans lisent AppColors sans passer par le thème :
/// sans ça, un écran `const` garderait ses anciennes couleurs.
/// Les écrans restent ouverts et gardent leur état (champs remplis...).
void reconstruireTout(BuildContext context) {
  void marquer(Element element) {
    element.markNeedsBuild();
    element.visitChildren(marquer);
  }

  (context as Element).visitChildren(marquer);
}
