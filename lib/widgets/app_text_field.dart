import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Champ de saisie au style Houmani, à utiliser dans un Form.
/// Le libellé est affiché au-dessus du champ (composant Input Field de Figma).
///
/// Si motDePasse est true, le texte est masqué et un bouton "œil"
/// permet de l'afficher ou de le masquer.
///
/// Exemple :
///   AppTextField(
///     label: 'Email',
///     hint: 'exemple@mail.com',
///     validator: (valeur) {
///       if (valeur == null || valeur.isEmpty) {
///         return 'Champ obligatoire'; // message d'erreur affiché
///       }
///       return null; // null = le champ est valide
///     },
///   )
class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final IconData? icone;
  final TextEditingController? controller;
  // Règle de validation du Form : une fonction qui reçoit le texte saisi
  // et renvoie un message d'erreur, ou null si tout est correct.
  final String? Function(String?)? validator;
  final bool motDePasse; // true = texte masqué (avec le bouton œil)
  final TextInputType clavier;
  final int lignes; // > 1 pour une description

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.icone,
    this.controller,
    this.validator,
    this.motDePasse = false,
    this.clavier = TextInputType.text,
    this.lignes = 1,
  });

  @override
  State<AppTextField> createState() {
    return _AppTextFieldState();
  }
}

class _AppTextFieldState extends State<AppTextField> {
  // true = le mot de passe est caché (au départ)
  bool _masque = true;

  @override
  Widget build(BuildContext context) {
    // Bouton œil, seulement pour un mot de passe
    Widget? boutonOeil;
    if (widget.motDePasse) {
      boutonOeil = IconButton(
        tooltip: _masque ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
        onPressed: () {
          setState(() {
            _masque = !_masque;
          });
        },
        icon: Icon(
          _masque ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Libellé au-dessus du champ, comme sur la maquette
        Text(
          widget.label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          obscureText: widget.motDePasse && _masque,
          keyboardType: widget.clavier,
          maxLines: widget.lignes,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.icone != null
                ? Icon(widget.icone, color: AppColors.textSecondary)
                : null,
            suffixIcon: boutonOeil,
          ),
        ),
      ],
    );
  }
}
