import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Toutes les couleurs de Houmani (issues de la maquette Figma).
/// Utilisation : AppColors.primary, AppColors.secondary, ...
/// Le nom de la variable Figma correspondante est indiqué en commentaire.
class AppColors {
  // Couleurs de marque
  static const Color primary = Color(0xFF1E4FB8); // brand/primary : bleu cobalt (headers, boutons)
  static const Color secondary = Color(0xFFC9A227); // brand/secondary : doré (onglet actif, focus, liens)

  // Fonds et cartes
  static const Color background = Color(0xFFFBF6EE); // bg/primary : fond crème des écrans
  static const Color backgroundSecondary = Color(0xFFF4EBDD); // bg/secondary : fond beige (onglets, avatars)
  static const Color card = Color(0xFFFFFFFF); // fond des cartes
  static const Color border = Color(0xFFEADFCC); // border/default : bordure des cartes et champs

  // Textes
  static const Color textPrimary = Color(0xFF1B1B1B); // text/primary
  static const Color textSecondary = Color(0xFF7A6E5E); // text/secondary

  // Teintes claires de la marque
  static const Color primaryLight = Color(0xFFEAF1FB); // bg/brand : bleu très clair
  static const Color secondaryLight = Color(0xFFFBF3DE); // bg/brand-secondary-soft : doré très clair

  // Statuts (indépendants de la marque)
  static const Color success = Color(0xFF30A46C); // status/success
  static const Color warning = Color(0xFFF5A623); // status/warning
  static const Color error = Color(0xFFE5484D); // status/error

  // Badges de statut (composant Badge de Figma) : texte + fond
  static const Color badgeEnCours = Color(0xFF8D5A3B);
  static const Color badgeEnCoursFond = Color(0xFFFBEBC8);
  static const Color badgeResolu = Color(0xFF1E7268);
  static const Color badgeResoluFond = Color(0xFFFBF3DE);
  static const Color badgeRefuse = Color(0xFFC0392B);
  static const Color badgeRefuseFond = Color(0xFFFBE7E5);
  static const Color badgeEnAttente = Color(0xFFB8441C);
  static const Color badgeEnAttenteFond = Color(0xFFFFF3EC);

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
          // Désactivé : le même bouton à 40 % d'opacité (comme sur Figma)
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Boutons texte (liens) : doré
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
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
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
        ),
        // Erreur : bordure rouge (status/error)
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: const TextStyle(color: AppColors.error),
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
