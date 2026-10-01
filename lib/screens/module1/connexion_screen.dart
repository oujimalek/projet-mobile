import 'package:flutter/material.dart';

import '../../widgets/coming_soon.dart';

/// M1 - Utilisateurs : écran de connexion.
///
/// PLACEHOLDER : remplacer le contenu de ce fichier en phase 2
/// (garder le nom de la classe ConnexionScreen).
///
/// À utiliser pour le vrai écran :
///   - Form + `GlobalKey<FormState>` pour la validation
///   - AppTextField (email, mot de passe avec motDePasse: true)
///   - PrimaryButton "Se connecter", HoumaniLogo, texte "Ahla bik !"
///   - UtilisateurRepository().connexion(email, motDePasse)
class ConnexionScreen extends StatelessWidget {
  const ConnexionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: const ComingSoon(module: 'Module 1 - Utilisateurs\nÉcran de connexion'),
    );
  }
}
