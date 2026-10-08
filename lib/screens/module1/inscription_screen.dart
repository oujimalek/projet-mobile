import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/primary_button.dart';

/// M1 - Utilisateurs : écran 1, création de compte.
///
/// Nom, téléphone, e-mail (optionnel), mot de passe + conditions d'utilisation.
/// Si tout est correct, on crée le compte puis on passe à la vérification
/// du numéro (écran OTP).
class InscriptionScreen extends StatefulWidget {
  const InscriptionScreen({super.key});

  @override
  State<InscriptionScreen> createState() {
    return _InscriptionScreenState();
  }
}

class _InscriptionScreenState extends State<InscriptionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _telephoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _motDePasseController = TextEditingController();

  bool _conditionsAcceptees = false;
  bool _erreurConditions = false; // true = afficher le message sous la case

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  /// Compte le nombre de chiffres dans un texte (pour le téléphone).
  int _compterChiffres(String texte) {
    int nombre = 0;
    for (int i = 0; i < texte.length; i++) {
      if ('0123456789'.contains(texte[i])) {
        nombre++;
      }
    }
    return nombre;
  }

  String? _validerNom(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton nom complet';
    }
    if (!valeur.trim().contains(' ')) {
      return 'Saisis ton prénom et ton nom';
    }
    return null;
  }

  String? _validerTelephone(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton numéro de téléphone';
    }
    if (_compterChiffres(valeur) < 8) {
      return 'Numéro de téléphone invalide (8 chiffres)';
    }
    return null;
  }

  String? _validerEmail(String? valeur) {
    // Optionnel : un champ vide est accepté
    if (valeur == null || valeur.trim().isEmpty) {
      return null;
    }
    if (!valeur.contains('@') || !valeur.contains('.')) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  String? _validerMotDePasse(String? valeur) {
    if (valeur == null || valeur.isEmpty) {
      return 'Choisis un mot de passe';
    }
    if (valeur.length < 8) {
      return '8 caractères minimum';
    }
    return null;
  }

  /// Appelé quand on touche "S'inscrire".
  void _sInscrire() {
    final bool champsValides = _formKey.currentState!.validate();
    setState(() {
      _erreurConditions = !_conditionsAcceptees;
    });
    if (!champsValides || !_conditionsAcceptees) {
      return;
    }

    UtilisateurRepository().inscription(
      nomComplet: _nomController.text,
      telephone: _telephoneController.text,
      email: _emailController.text,
      motDePasse: _motDePasseController.text,
    );
    // Étape suivante : vérifier le numéro de téléphone
    context.push('/verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----- En-tête : logo + titre -----
            const AppCard(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HoumaniLogo(taille: 44),
                  SizedBox(height: 16),
                  Text(
                    'Créer un compte',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Rejoins ta houma et entraide-toi avec tes voisins.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ----- Formulaire -----
            AppCard(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    AppTextField(
                      label: 'Nom complet',
                      hint: 'Ex : Mohamed Zahi',
                      controller: _nomController,
                      validator: _validerNom,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Numéro de téléphone',
                      hint: '+216 XX XXX XXX',
                      controller: _telephoneController,
                      clavier: TextInputType.phone,
                      validator: _validerTelephone,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Adresse e-mail (optionnel)',
                      hint: 'exemple@mail.com',
                      controller: _emailController,
                      clavier: TextInputType.emailAddress,
                      validator: _validerEmail,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Mot de passe',
                      hint: '8 caractères minimum',
                      controller: _motDePasseController,
                      motDePasse: true,
                      validator: _validerMotDePasse,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ----- Conditions d'utilisation -----
            _caseConditions(),
            const SizedBox(height: 16),

            PrimaryButton(texte: 'S\'inscrire', onPressed: _sInscrire),
            const SizedBox(height: 8),

            // ----- Déjà membre -----
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Déjà membre ?',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: () {
                    context.go('/connexion');
                  },
                  child: const Text(
                    'Se connecter',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bloc bleu clair avec la case "J'accepte les conditions d'utilisation".
  Widget _caseConditions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          onTap: () {
            setState(() {
              _conditionsAcceptees = !_conditionsAcceptees;
              _erreurConditions = false;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _conditionsAcceptees,
                  activeColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary, width: 1.5),
                  onChanged: (valeur) {
                    setState(() {
                      _conditionsAcceptees = valeur ?? false;
                      _erreurConditions = false;
                    });
                  },
                ),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'J\'accepte les ',
                      style: TextStyle(color: AppColors.textSecondary),
                      children: [
                        TextSpan(
                          text: 'conditions d\'utilisation',
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_erreurConditions)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 6),
            child: Text(
              'Tu dois accepter les conditions d\'utilisation',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
