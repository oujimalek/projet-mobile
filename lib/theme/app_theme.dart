import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Toutes les couleurs de Houmani (issues de la maquette Figma).
/// Utilisation : AppColors.primary, AppColors.secondary, ...
/// Le nom de la variable Figma correspondante est indiqué en commentaire.
///
/// Mode sombre : chaque couleur a deux versions, `_c(claire, sombre)`
/// choisit selon [sombre]. C'est pourquoi ce sont des `get` et non des
/// `const` : on ne peut plus écrire `const TextStyle(color: AppColors.x)`.
/// [sombre] est réglé par HoumaniApp (main.dart), qui reconstruit alors
/// toute l'application.
class AppColors {
  /// true = palette sombre. Ne pas changer à la main : voir PreferenceTheme.
  static bool sombre = false;

  static Color _c(int claire, int foncee) {
    return Color(sombre ? foncee : claire);
  }

  // Couleurs de marque
  static Color get primary => _c(0xFF1E4FB8, 0xFF3D6BD4); // brand/primary : bleu cobalt (headers, boutons)
  static Color get secondary => _c(0xFFC9A227, 0xFFD9B443); // brand/secondary : doré (onglet actif, focus, liens)

  // Fonds et cartes
  static Color get background => _c(0xFFFBF6EE, 0xFF15130F); // bg/primary : fond crème des écrans
  static Color get backgroundSecondary => _c(0xFFF4EBDD, 0xFF262119); // bg/secondary : fond beige (onglets, avatars)
  static Color get card => _c(0xFFFFFFFF, 0xFF1F1C17); // fond des cartes
  static Color get border => _c(0xFFEADFCC, 0xFF3A332A); // border/default : bordure des cartes et champs

  // Textes
  static Color get textPrimary => _c(0xFF1B1B1B, 0xFFF2EDE4); // text/primary
  static Color get textSecondary => _c(0xFF7A6E5E, 0xFFB5AA9A); // text/secondary

  // Teintes claires de la marque (foncées en mode sombre)
  static Color get primaryLight => _c(0xFFEAF1FB, 0xFF1C2943); // bg/brand : bleu très clair
  static Color get secondaryLight => _c(0xFFFBF3DE, 0xFF2E2716); // bg/brand-secondary-soft : doré très clair

  // Statuts (indépendants de la marque)
  static Color get success => _c(0xFF30A46C, 0xFF3DBE80); // status/success
  static Color get warning => _c(0xFFF5A623, 0xFFF5B347); // status/warning
  static Color get error => _c(0xFFE5484D, 0xFFF06A6E); // status/error

  // Badges de statut (composant Badge de Figma) : texte + fond
  static Color get badgeEnCours => _c(0xFF8D5A3B, 0xFFE0B48F);
  static Color get badgeEnCoursFond => _c(0xFFFBEBC8, 0xFF3A2C18);
  static Color get badgeResolu => _c(0xFF1E7268, 0xFF5CC2B4);
  static Color get badgeResoluFond => _c(0xFFFBF3DE, 0xFF173430);
  static Color get badgeRefuse => _c(0xFFC0392B, 0xFFF0887C);
  static Color get badgeRefuseFond => _c(0xFFFBE7E5, 0xFF3D1C19);
  static Color get badgeEnAttente => _c(0xFFB8441C, 0xFFF29A72);
  static Color get badgeEnAttenteFond => _c(0xFFFFF3EC, 0xFF3D2216);

  // Catégories de signalement (couleur + version très claire pour les fonds)
  static Color get electricite => _c(0xFFE9A03B, 0xFFF0B45E);
  static Color get electriciteLight => _c(0xFFFDF3E3, 0xFF3A2C16);
  static Color get eau => _c(0xFF2F7FC1, 0xFF5A9FDA);
  static Color get eauLight => _c(0xFFE6F0F8, 0xFF16283A);
  static Color get ordures => _c(0xFF6B8E23, 0xFF93B84A);
  static Color get orduresLight => _c(0xFFEEF3E4, 0xFF222D14);
  static Color get travaux => _c(0xFF8D5A3B, 0xFFC89470);
  static Color get travauxLight => _c(0xFFF3EBE5, 0xFF2E221B);
  static Color get incident => _c(0xFFC0392B, 0xFFE8695C);
  static Color get incidentLight => _c(0xFFF9E6E4, 0xFF3A1B18);
}

/// Le thème global de l'application, utilisé dans MaterialApp (main.dart).
class AppTheme {
  // Rayon des coins arrondis (la maquette utilise 14 à 16)
  static const double radius = 16;
  static const double radiusSmall = 14;

  /// Le thème correspondant à la palette actuelle (claire ou sombre,
  /// selon AppColors.sombre).
  static ThemeData get actuel {
    return ThemeData(
      useMaterial3: true,
      // Police Inter pour tous les textes de l'application
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: AppColors.sombre ? Brightness.dark : Brightness.light,
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
          side: BorderSide(color: AppColors.border),
        ),
      ),

      // Fenêtres (showDialog) et menu latéral : couleur des cartes
      dialogTheme: DialogThemeData(backgroundColor: AppColors.card),
      drawerTheme: DrawerThemeData(backgroundColor: AppColors.background),

      // Champs de saisie (TextFormField)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        hintStyle: TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
        ),
        // Erreur : bordure rouge (status/error)
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: TextStyle(color: AppColors.error),
      ),

      // Barre de navigation du bas : onglet actif doré
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  /// Le thème clair (gardé pour les fichiers qui l'utilisent déjà).
  static ThemeData get light {
    return actuel;
  }
}
