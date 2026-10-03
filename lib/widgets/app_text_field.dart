import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Champ de saisie au style Houmani, à utiliser dans un Form.
/// Le libellé est affiché au-dessus du champ (composant Input Field de Figma).
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
class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData? icone;
  final TextEditingController? controller;
  // Règle de validation du Form : une fonction qui reçoit le texte saisi
  // et renvoie un message d'erreur, ou null si tout est correct.
  final String? Function(String?)? validator;
  final bool motDePasse; // true = texte masqué
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Libellé au-dessus du champ, comme sur la maquette
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          obscureText: motDePasse,
          keyboardType: clavier,
          maxLines: lignes,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icone != null
                ? Icon(icone, color: AppColors.textSecondary)
                : null,
          ),
        ),
      ],
    );
  }
}
