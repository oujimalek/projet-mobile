import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Champ de saisie au style Houmani, à utiliser dans un Form.
///
/// Exemple :
///   AppTextField(
///     label: 'Email',
///     icone: Icons.email_outlined,
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
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: motDePasse,
      keyboardType: clavier,
      maxLines: lignes,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icone != null
            ? Icon(icone, color: AppColors.textSecondary)
            : null,
      ),
    );
  }
}
