import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Toutes les couleurs de Houmani (issues de la maquette Figma).
/// Utilisation : AppColors.primary, AppColors.secondary, ...
/// Le nom de la variable Figma correspondante est indiqué en commentaire.
class AppColors {
  // Couleurs de marque
  static const Color primary = Color(0xFF1E4FB8); // brand/primary : bleu cobalt (headers, boutons)
  static const Color secondary = Color(0xFFC9A227); // brand/secondary : doré (onglet actif, bordures focus)

  // Fonds et cartes
  static const Color background = Color(0xFFFBF6EE); // fond crème des écrans
  static const Color card = Color(0xFFFFFFFF); // fond des cartes
  static const Color border = Color(0xFFEADFCC); // bordure des cartes

  // Textes
  static const Color textPrimary = Color(0xFF1B1B1B);
  static const Color textSecondary = Color(0xFF7A6E5E);

  // Teintes claires de la marque
  static const Color primaryLight = Color(0xFFEAF1FB); // bg/brand : bleu très clair
  static const Color secondaryLight = Color(0xFFFBF3DE); // bg/brand-secondary-soft : doré très clair

  // Statuts (indépendants de la marque)
  static const Color success = Color(0xFF2A9D8F); // status/success
  static const Color successLight = Color(0xFFEAF7F5);
  static const Color warning = Color(0xFFE85D2C); // status/warning
  static const Color warningLight = Color(0xFFFFF3EC);
  static const Color error = incident; // status/error
  static const Color errorLight = incidentLight;

  // Catégories de signalement (couleur + version très claire pour les fonds)
  static const Color electricite = Color(0xFFE9A03B);
  static const Color electriciteLight = Color(0xFFFDF3E3);
  static const Color eau = Color(0xFF2F7FC1);
  static const Color eauLight = Color(0xFFE6F0F8);
  static const Color ordures = Color(0xFF6B8E23);
  static const Color orduresLight = Color(0xFFEEF3E4);
  static const Color travaux = Color(0xFF8D5A3B);
  static const Color travauxLight = Color(0xFFF3EBE5);
  static const Color incident = Color(0xFFC0392B);
  static const Color incidentLight = Color(0xFFF9E6E4);
}

/// Le thème global de l'application, utilisé dans MaterialApp (main.dart).
class AppTheme {
  // Rayon des coins arrondis (la maquette utilise 14 à 16)
  static const double radius = 16;
  static const double radiusSmall = 14;

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      // Police Inter pour tous les textes de l'application
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary, // couleur du texte principal
      ),
      scaffoldBackgroundColor: AppColors.background,

      // Barre du haut : bleu cobalt avec texte blanc
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      // Boutons principaux : bleu cobalt
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Boutons texte : bleu cobalt
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),

      // Cartes : blanches avec bordure beige
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // Champs de saisie (TextFormField)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.secondary, width: 2),
        ),
      ),

      // Barre de navigation du bas : onglet actif doré
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
