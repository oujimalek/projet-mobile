import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';

/// Texte du copyright, affiché sous les conditions et sur la connexion.
const String copyrightHoumani = '© 2026 Houmani. Tous droits réservés.';

/// Les conditions d'utilisation : une liste de (titre, paragraphe).
const List<List<String>> _articles = [
  [
    '1. Objet',
    'Houmani met en relation les habitants d\'un même quartier ou d\'une '
        'même résidence pour s\'entraider (services entre voisins), signaler '
        'les problèmes du quartier et participer à sa vie (événements, '
        'sondages). En créant un compte, tu acceptes les présentes conditions.',
  ],
  [
    '2. Inscription et accès',
    'Tu dois donner des informations exactes (nom, téléphone, e-mail) et '
        'n\'avoir qu\'un seul compte. L\'accès à un quartier se fait avec son '
        'code d\'invitation, puis la demande est validée par l\'administrateur '
        'du quartier. Il peut refuser une demande ou bloquer un compte qui ne '
        'respecte pas ces règles. Garde ton mot de passe secret : tu es '
        'responsable de ce qui est fait avec ton compte.',
  ],
  [
    '3. Données personnelles',
    'Nous enregistrons ton nom, ton téléphone, ton e-mail, ton quartier, '
        'ton logement, tes compétences et ta photo de profil, uniquement pour '
        'faire fonctionner l\'application. Les membres actifs de ton quartier '
        'voient ton nom, ta photo et tes compétences ; ton logement et ton '
        'téléphone ne sont visibles que par l\'administrateur. Tes données '
        'sont hébergées par Google Firebase et ne sont jamais vendues. '
        'Conformément à la loi organique n° 2004-63 du 27 juillet 2004 '
        'relative à la protection des données à caractère personnel, tu peux '
        'les consulter, les corriger depuis ton profil ou demander leur '
        'suppression.',
  ],
  [
    '4. Règles de bonne conduite',
    'Reste respectueux : pas d\'insultes, de harcèlement, de propos '
        'discriminatoires ni de contenus illégaux. Ne publie pas de photo ou '
        'd\'information sur un voisin sans son accord. Pas de publicité '
        'abusive. Les signalements doivent être sincères : les fausses '
        'alertes nuisent à tout le quartier.',
  ],
  [
    '5. Services entre voisins',
    'Les services sont proposés de particulier à particulier. Houmani '
        'n\'intervient pas dans l\'échange : le prix éventuel, les horaires et '
        'la qualité sont convenus entre voisins. Sois prudent, surtout '
        'lorsqu\'un service a lieu chez toi ou chez quelqu\'un d\'autre.',
  ],
  [
    '6. Signalements et urgences',
    'Un signalement informe le quartier et son administrateur, il ne '
        'remplace pas les secours. En cas d\'urgence, appelle le 190 (SAMU), '
        'le 197 (police) ou le 198 (protection civile).',
  ],
  [
    '7. Modération',
    'L\'administrateur du quartier peut retirer un contenu qui ne respecte '
        'pas ces conditions, et bloquer le compte de son auteur.',
  ],
  [
    '8. Responsabilité',
    'L\'application est fournie telle quelle et peut évoluer. Houmani ne '
        'peut pas être tenue responsable des échanges entre voisins ni des '
        'contenus publiés par les membres.',
  ],
  [
    '9. Modification des conditions',
    'Ces conditions peuvent être mises à jour. Tu en seras informé dans '
        'l\'application ; continuer à l\'utiliser vaut acceptation de la '
        'nouvelle version.',
  ],
];

/// Ouvre les conditions d'utilisation dans une fenêtre qu'on fait défiler.
///
/// - avecAcceptation true (inscription) : boutons "Fermer" et "J'accepte".
///   Renvoie true si l'utilisateur a touché "J'accepte".
/// - avecAcceptation false (lecture seule) : un seul bouton "Fermer".
Future<bool> afficherConditions(
  BuildContext context, {
  bool avecAcceptation = true,
}) async {
  // Le contenu : chaque article = un titre en gras + son paragraphe
  // (le texte juridique reste en français, c'est la version officielle)
  final List<Widget> contenu = [
    Text(
      tr(
        'Dernière mise à jour : 16 octobre 2026',
        'E5er tabdil : 16 octobre 2026',
      ),
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
    const SizedBox(height: 12),
  ];
  for (final List<String> article in _articles) {
    contenu.add(
      Text(
        article[0],
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
    contenu.add(const SizedBox(height: 4));
    contenu.add(
      Text(
        article[1],
        style: TextStyle(height: 1.45, color: AppColors.textPrimary),
      ),
    );
    contenu.add(const SizedBox(height: 14));
  }
  contenu.add(Divider(color: AppColors.border));
  contenu.add(
    Center(
      child: Text(
        copyrightHoumani,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ),
  );

  // Les boutons en bas de la fenêtre
  final List<Widget> boutons = [
    TextButton(
      onPressed: () {
        Navigator.of(context).pop(false);
      },
      child: Text(tr('Fermer', 'Sakker')),
    ),
  ];
  if (avecAcceptation) {
    boutons.add(
      ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
        onPressed: () {
          Navigator.of(context).pop(true);
        },
        child: Text(tr('J\'accepte', 'Na9bel')),
      ),
    );
  }

  final bool? accepte = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(
          tr('Conditions d\'utilisation', 'Chourout el isti3mel'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        // Hauteur limitée à 60 % de l'écran : le texte défile à l'intérieur
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const Key('conditions_texte'),
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: contenu,
              ),
            ),
          ),
        ),
        actions: boutons,
      );
    },
  );
  return accepte ?? false; // fermée en touchant à côté : pas acceptée
}
