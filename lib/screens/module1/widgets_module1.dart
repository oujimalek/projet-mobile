import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';

// Petits widgets utilisés par plusieurs écrans du module 1.
// (Les composants communs à toute l'app restent dans lib/widgets/.)

/// L'écran à ouvrir pour un utilisateur connecté, selon son statut
/// (utilisé après la connexion et au démarrage, dans le splash).
/// null : compte bloqué, il reste sur l'écran de connexion.
String? cheminSelonStatut(Utilisateur utilisateur) {
  switch (utilisateur.statut) {
    case StatutUtilisateur.actif:
      return '/accueil';
    case StatutUtilisateur.enAttente:
      // Pas encore de quartier : vérifier l'e-mail, puis en choisir un
      if (utilisateur.quartier.isEmpty) {
        return '/verification';
      }
      return '/attente';
    case StatutUtilisateur.refuse:
      // Demande refusée : il peut choisir un autre quartier
      return '/code-quartier';
    case StatutUtilisateur.bloque:
      return null;
  }
}

/// Bouton "Se déconnecter" des écrans de l'inscription (vérification,
/// code du quartier, attente) : ils n'ont ni menu ni flèche retour,
/// c'est leur seule sortie vers la connexion.
class BoutonDeconnexion extends StatelessWidget {
  const BoutonDeconnexion({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        // On garde le routeur avant l'attente (l'écran peut changer)
        final GoRouter routeur = GoRouter.of(context);
        await UtilisateurRepository().deconnexion();
        routeur.go('/connexion'); // go : pas de retour possible
      },
      child: Text(
        tr('Se déconnecter', 'O5rej'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Roue de chargement affichée sous un bouton pendant qu'on attend
/// la réponse du serveur.
class IndicateurChargement extends StatelessWidget {
  const IndicateurChargement({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Petite étiquette arrondie (ex : "Résident", "Admin", une compétence).
/// Si onSupprimer est donné, une croix permet de la retirer.
class Pastille extends StatelessWidget {
  final String texte;
  final Color? couleur; // couleur du texte (par défaut : bleu)
  final Color? fond; // couleur du fond (par défaut : bleu très clair)
  final Function()? onSupprimer;

  const Pastille({
    super.key,
    required this.texte,
    this.couleur,
    this.fond,
    this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    // Couleur choisie, sinon celle par défaut (selon le thème clair/sombre)
    final Color couleurTexte = couleur ?? AppColors.primary;
    final List<Widget> contenu = [
      Text(
        texte,
        style: TextStyle(
          color: couleurTexte,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
    if (onSupprimer != null) {
      contenu.add(const SizedBox(width: 6));
      contenu.add(
        GestureDetector(
          onTap: onSupprimer,
          child: Icon(Icons.close, size: 14, color: couleurTexte),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fond ?? AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: contenu),
    );
  }
}

/// Pastille blanche "+ Ajouter" (ajout d'une compétence).
class BoutonAjouter extends StatelessWidget {
  final Function() onTap;

  const BoutonAjouter({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          tr('+ Ajouter', '+ Zid'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}

/// Avatar rond avec les initiales (ex : "AB").
class AvatarInitiales extends StatelessWidget {
  final String initiales;
  final double taille;
  final Color? couleur; // couleur des lettres (par défaut : bleu)
  final Color? fond; // (par défaut : bleu très clair)

  const AvatarInitiales({
    super.key,
    required this.initiales,
    this.taille = 48,
    this.couleur,
    this.fond,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fond ?? AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        initiales,
        style: TextStyle(
          color: couleur ?? AppColors.primary,
          fontSize: taille * 0.36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Un avatar de la galerie (bouton "Changer la photo").
/// Pas encore d'envoi de vraie photo : on choisit parmi ces dessins.
class AvatarGalerie {
  final String id; // enregistré dans Utilisateur.avatar
  final IconData icone;
  final Color couleur; // couleur du dessin
  final Color fond;

  const AvatarGalerie({
    required this.id,
    required this.icone,
    required this.couleur,
    required this.fond,
  });
}

/// Les 6 avatars proposés dans la galerie.
/// Un `get` (et non une variable) : les couleurs suivent le thème actuel.
List<AvatarGalerie> get avatarsGalerie => [
  AvatarGalerie(
    id: 'chat',
    icone: Icons.pets,
    couleur: AppColors.primary,
    fond: AppColors.primaryLight,
  ),
  AvatarGalerie(
    id: 'fleur',
    icone: Icons.local_florist,
    couleur: AppColors.secondary,
    fond: AppColors.secondaryLight,
  ),
  AvatarGalerie(
    id: 'soleil',
    icone: Icons.wb_sunny,
    couleur: AppColors.secondary,
    fond: AppColors.backgroundSecondary,
  ),
  AvatarGalerie(
    id: 'cafe',
    icone: Icons.local_cafe,
    couleur: AppColors.textSecondary,
    fond: AppColors.backgroundSecondary,
  ),
  AvatarGalerie(
    id: 'velo',
    icone: Icons.pedal_bike,
    couleur: AppColors.primary,
    fond: AppColors.secondaryLight,
  ),
  AvatarGalerie(
    id: 'maison',
    icone: Icons.home,
    couleur: Colors.white,
    fond: AppColors.primary,
  ),
];

/// Retrouve un avatar de la galerie par son id (null si aucun).
AvatarGalerie? trouverAvatar(String id) {
  for (final AvatarGalerie avatar in avatarsGalerie) {
    if (avatar.id == id) {
      return avatar;
    }
  }
  return null;
}

/// Avatar d'un utilisateur : le dessin choisi dans la galerie s'il y en a un,
/// sinon ses initiales (avec les couleurs données).
class AvatarUtilisateur extends StatelessWidget {
  final String avatar; // Utilisateur.avatar
  final String initiales;
  final double taille;
  final Color? couleur; // couleurs des initiales (voir AvatarInitiales)
  final Color? fond;

  const AvatarUtilisateur({
    super.key,
    required this.avatar,
    required this.initiales,
    this.taille = 48,
    this.couleur,
    this.fond,
  });

  @override
  Widget build(BuildContext context) {
    final AvatarGalerie? choisi = trouverAvatar(avatar);
    if (choisi == null) {
      return AvatarInitiales(
        initiales: initiales,
        taille: taille,
        couleur: couleur,
        fond: fond,
      );
    }
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: choisi.fond, shape: BoxShape.circle),
      child: Icon(choisi.icone, color: choisi.couleur, size: taille * 0.5),
    );
  }
}

/// Saisie d'un code en 6 cases (code SMS ou code d'invitation).
///
/// Un seul champ de texte invisible reçoit le clavier ; les cases
/// affichent simplement les caractères déjà tapés.
/// - chiffresSeulement: true  → seulement des chiffres (code SMS)
/// - chiffresSeulement: false → lettres et chiffres, en majuscules
/// - libelle : le nom du champ lu par les lecteurs d'écran
class SaisieCode extends StatefulWidget {
  final int longueur;
  final bool chiffresSeulement;
  final String libelle;
  final Function(String code) onChanged; // appelée à chaque caractère tapé

  const SaisieCode({
    super.key,
    this.longueur = 6,
    this.chiffresSeulement = true,
    this.libelle = 'Code',
    required this.onChanged,
  });

  @override
  State<SaisieCode> createState() {
    return _SaisieCodeState();
  }
}

class _SaisieCodeState extends State<SaisieCode> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // On redessine les cases quand le champ gagne ou perd le focus
    _focus.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Une case : le caractère tapé, un curseur (case active) ou rien.
  Widget _case(int index) {
    final String code = _controller.text;
    final bool active = _focus.hasFocus && index == code.length;

    Widget contenu = const SizedBox();
    if (index < code.length) {
      contenu = Text(
        code[index],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      );
    } else if (active) {
      contenu = Container(width: 2, height: 22, color: AppColors.primary);
    }

    return Expanded(
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: contenu,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> cases = [];
    for (int i = 0; i < widget.longueur; i++) {
      cases.add(_case(i));
    }

    // Règles de saisie : nombre de caractères et caractères autorisés
    final List<TextInputFormatter> regles = [
      LengthLimitingTextInputFormatter(widget.longueur),
    ];
    if (widget.chiffresSeulement) {
      regles.add(FilteringTextInputFormatter.digitsOnly);
    } else {
      regles.add(FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')));
    }

    return GestureDetector(
      onTap: () {
        _focus.requestFocus();
      },
      // Stack : le champ invisible est posé SOUS les cases
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              // Invisible, mais toujours présent pour l'accessibilité
              // (lecteur d'écran, version web)
              alwaysIncludeSemantics: true,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                decoration: InputDecoration(
                  hintText: widget.libelle,
                  border: InputBorder.none,
                ),
                inputFormatters: regles,
                keyboardType: widget.chiffresSeulement
                    ? TextInputType.number
                    : TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                onChanged: (texte) {
                  // Code d'invitation : toujours en majuscules
                  final String code = texte.toUpperCase();
                  if (code != texte) {
                    _controller.value = TextEditingValue(
                      text: code,
                      selection: TextSelection.collapsed(offset: code.length),
                    );
                  }
                  setState(() {});
                  widget.onChanged(code);
                },
              ),
            ),
          ),
          IgnorePointer(child: Row(children: cases)),
        ],
      ),
    );
  }
}

/// Grand titre bleu + sous-titre, en haut des écrans d'inscription.
class TitreEcran extends StatelessWidget {
  final String titre;
  final String sousTitre;

  const TitreEcran({super.key, required this.titre, required this.sousTitre});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sousTitre,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
