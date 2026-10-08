import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

// Petits widgets utilisés par plusieurs écrans du module 1.
// (Les composants communs à toute l'app restent dans lib/widgets/.)

/// Petite étiquette arrondie (ex : "Résident", "Admin", une compétence).
/// Si onSupprimer est donné, une croix permet de la retirer.
class Pastille extends StatelessWidget {
  final String texte;
  final Color couleur; // couleur du texte
  final Color fond; // couleur du fond
  final Function()? onSupprimer;

  const Pastille({
    super.key,
    required this.texte,
    this.couleur = AppColors.primary,
    this.fond = AppColors.primaryLight,
    this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> contenu = [
      Text(
        texte,
        style: TextStyle(
          color: couleur,
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
          child: Icon(Icons.close, size: 14, color: couleur),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fond,
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
        child: const Text(
          '+ Ajouter',
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
  final Color couleur; // couleur des lettres
  final Color fond;

  const AvatarInitiales({
    super.key,
    required this.initiales,
    this.taille = 48,
    this.couleur = AppColors.primary,
    this.fond = AppColors.primaryLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
      child: Text(
        initiales,
        style: TextStyle(
          color: couleur,
          fontSize: taille * 0.36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Saisie d'un code en 6 cases (code SMS ou code d'invitation).
///
/// Un seul champ de texte invisible reçoit le clavier ; les cases
/// affichent simplement les caractères déjà tapés.
/// - chiffresSeulement: true  → seulement des chiffres (code SMS)
/// - chiffresSeulement: false → lettres et chiffres, en majuscules
class SaisieCode extends StatefulWidget {
  final int longueur;
  final bool chiffresSeulement;
  final Function(String code) onChanged; // appelée à chaque caractère tapé

  const SaisieCode({
    super.key,
    this.longueur = 6,
    this.chiffresSeulement = true,
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
              child: TextField(
                controller: _controller,
                focusNode: _focus,
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
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sousTitre,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
