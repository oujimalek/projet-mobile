import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

// main est async : on attend que Firebase soit prêt avant d'afficher l'app.
Future<void> main() async {
  // Obligatoire avant d'utiliser un plugin (Firebase) avant runApp
  WidgetsFlutterBinding.ensureInitialized();
  // Connexion au projet Firebase "houmani-235bb"
  // (firebase_options.dart est généré par `flutterfire configure`)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const HoumaniApp());
}

/// Point de départ de l'application Houmani.
class HoumaniApp extends StatelessWidget {
  const HoumaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp.router : les écrans sont choisis par le routeur
    // (go_router), défini dans lib/router/app_router.dart
    return MaterialApp.router(
      title: 'Houmani', // nom affiché de l'application
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light, // couleurs et police définies dans app_theme.dart
      routerConfig: appRouter,
    );
  }
}
