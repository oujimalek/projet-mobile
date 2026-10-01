import 'package:flutter/material.dart';

import 'screens/demo_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HoumaniApp());
}

/// Point de départ de l'application Houmani.
class HoumaniApp extends StatelessWidget {
  const HoumaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Houmani', // nom affiché de l'application
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light, // couleurs et police définies dans app_theme.dart
      home: const DemoScreen(),
    );
  }
}
