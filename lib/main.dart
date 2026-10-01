import 'package:flutter/material.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() {
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
