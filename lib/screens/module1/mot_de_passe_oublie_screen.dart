import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : réinitialisation du mot de passe.
///
/// Ouvert depuis "Mot de passe oublié ?" sur l'écran de connexion.
/// On saisit son téléphone ou son e-mail, puis "Envoyer le lien".
/// Le message de confirmation est toujours le même, que le compte existe
/// ou non (on ne révèle pas quels comptes existent).
class MotDePasseOublieScreen extends StatefulWidget {
  const MotDePasseOublieScreen({super.key});

  @override
  State<MotDePasseOublieScreen> createState() {
    return _MotDePasseOublieScreenState();
  }
}

class _MotDePasseOublieScreenState extends State<MotDePasseOublieScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifiantController = TextEditingController();

  // true une fois le lien "envoyé" : on affiche la confirmation
  bool _lienEnvoye = false;

  @override
  void dispose() {
    _identifiantController.dispose();
    super.dispose();
  }

  /// Même règle que sur l'écran de connexion :
  /// un e-mail (avec @ et .) ou un téléphone d'au moins 8 chiffres.
  String? _validerIdentifiant(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton téléphone ou ton e-mail';
    }
    final String texte = valeur.trim();
    if (texte.contains('@')) {
      if (!texte.contains('.')) {
        return 'Adresse e-mail invalide';
      }
      return null;
    }
    int chiffres = 0;
    for (int i = 0; i < texte.length; i++) {
      if ('0123456789'.contains(texte[i])) {
        chiffres++;
      }
    }
    if (chiffres < 8) {
      return 'Numéro de téléphone invalide (8 chiffres)';
    }
    return null;
  }

  Future<void> _envoyerLien() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await UtilisateurRepository().envoyerLienReinitialisation(
      _identifiantController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lienEnvoye = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Mot de passe oublié'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: _lienEnvoye ? _confirmation() : _formulaire(),
            ),
          ),
        ],
      ),
    );
  }

  /// Avant l'envoi : le champ et le bouton.
  List<Widget> _formulaire() {
    return [
      const TitreEcran(
        titre: 'Réinitialiser le mot de passe',
        sousTitre: 'Saisis le téléphone ou l\'e-mail de ton compte : '
            'on t\'envoie un lien pour choisir un nouveau mot de passe.',
      ),
      const SizedBox(height: 24),
      Form(
        key: _formKey,
        child: AppTextField(
          label: 'Téléphone ou e-mail',
          hint: '+216 22 345 678',
          controller: _identifiantController,
          clavier: TextInputType.emailAddress,
          validator: _validerIdentifiant,
        ),
      ),
      const SizedBox(height: 24),
      PrimaryButton(texte: 'Envoyer le lien', onPressed: _envoyerLien),
    ];
  }

  /// Après l'envoi : le message de confirmation et le retour à la connexion.
  List<Widget> _confirmation() {
    return [
      const SizedBox(height: 16),
      Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: AppColors.primary,
            size: 44,
          ),
        ),
      ),
      const SizedBox(height: 20),
      const AppCard(
        child: Text(
          'Si ce compte existe, un lien a été envoyé.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Pense à vérifier tes SMS et tes courriers indésirables.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 32),
      PrimaryButton(
        texte: 'Retour à la connexion',
        onPressed: () {
          context.pop();
        },
      ),
    ];
  }
}
