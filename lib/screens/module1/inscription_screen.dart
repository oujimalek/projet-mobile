import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/primary_button.dart';
import 'conditions_utilisation.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 1, création de compte.
///
/// Nom, téléphone, e-mail, mot de passe + conditions d'utilisation.
/// Si tout est correct, on crée le compte puis on passe à la vérification
/// de l'adresse e-mail.
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
  bool _enChargement = false; // true pendant la création du compte

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  String? _validerNom(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return tr('Saisis ton nom complet', 'Ekteb esmek kemel');
    }
    if (!valeur.trim().contains(' ')) {
      return tr('Saisis ton prénom et ton nom', 'Ekteb esmek w la9bek');
    }
    return null;
  }

  String? _validerTelephone(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return tr('Saisis ton numéro de téléphone', 'Ekteb nouméro téléphonek');
    }
    // 8 chiffres, avec ou sans +216 : le numéro sert aussi à se connecter
    if (UtilisateurRepository.normaliserTelephone(valeur) == null) {
      return tr(
        'Numéro de téléphone invalide (8 chiffres)',
        'Nouméro mouch s7i7 (8 ar9am)',
      );
    }
    return null;
  }

  String? _validerEmail(String? valeur) {
    // Obligatoire : c'est l'identifiant de connexion
    if (valeur == null || valeur.trim().isEmpty) {
      return tr('Saisis ton adresse e-mail', 'Ekteb el e-mail mte3ek');
    }
    if (!valeur.contains('@') || !valeur.contains('.')) {
      return tr('Adresse e-mail invalide', 'E-mail mouch s7i7');
    }
    return null;
  }

  String? _validerMotDePasse(String? valeur) {
    if (valeur == null || valeur.isEmpty) {
      return tr('Choisis un mot de passe', 'A5tar kelmet ser');
    }
    if (valeur.length < 8) {
      return tr('8 caractères minimum', 'Mouch a9al men 8 7rouf');
    }
    return null;
  }

  /// Appelé quand on touche "S'inscrire".
  Future<void> _sInscrire() async {
    final bool champsValides = _formKey.currentState!.validate();
    setState(() {
      _erreurConditions = !_conditionsAcceptees;
    });
    if (!champsValides || !_conditionsAcceptees) {
      return;
    }

    setState(() {
      _enChargement = true;
    });
    final Resultat<Utilisateur> resultat =
        await UtilisateurRepository().inscription(
      nomComplet: _nomController.text,
      telephone: _telephoneController.text,
      email: _emailController.text,
      motDePasse: _motDePasseController.text,
    );
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });
    // Échec (e-mail déjà utilisé, pas de réseau...) : on affiche le message
    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }
    // Étape suivante : vérifier l'adresse e-mail
    // (go : le compte existe déjà, revenir au formulaire n'aurait plus de sens)
    context.go('/verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----- En-tête : logo + titre -----
            AppCard(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HoumaniLogo(taille: 44),
                  SizedBox(height: 16),
                  Text(
                    tr('Créer un compte', 'A3mel compte'),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    tr(
                      'Rejoins ta houma et entraide-toi avec tes voisins.',
                      'Od5ol l houmtek w t3awen m3a jiranek.',
                    ),
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
                      label: tr('Nom complet', 'Esmek kemel'),
                      hint: 'Ex : Mohamed Zahi',
                      controller: _nomController,
                      validator: _validerNom,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: tr('Numéro de téléphone', 'Nouméro el téléphone'),
                      hint: '+216 XX XXX XXX',
                      controller: _telephoneController,
                      clavier: TextInputType.phone,
                      validator: _validerTelephone,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: tr('Adresse e-mail', 'E-mail'),
                      hint: 'exemple@mail.com',
                      controller: _emailController,
                      clavier: TextInputType.emailAddress,
                      validator: _validerEmail,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: tr('Mot de passe', 'Kelmet esser'),
                      hint: tr('8 caractères minimum', '8 7rouf 3al a9al'),
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

            // null pendant le chargement : bouton désactivé
            PrimaryButton(
              texte: tr('S\'inscrire', 'A3mel compte'),
              onPressed: _enChargement ? null : _sInscrire,
            ),
            if (_enChargement) const IndicateurChargement(),
            const SizedBox(height: 8),

            // ----- Déjà membre -----
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  tr('Déjà membre ?', '3andek compte ?'),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                TextButton(
                  onPressed: () {
                    context.go('/connexion');
                  },
                  child: Text(
                    tr('Se connecter', 'Od5ol'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Ouvre les conditions ; "J'accepte" dans la fenêtre coche la case.
  Future<void> _lireConditions() async {
    final bool accepte = await afficherConditions(context);
    if (accepte && mounted) {
      setState(() {
        _conditionsAcceptees = true;
        _erreurConditions = false;
      });
    }
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
                  side: BorderSide(color: AppColors.secondary, width: 1.5),
                  onChanged: (valeur) {
                    setState(() {
                      _conditionsAcceptees = valeur ?? false;
                      _erreurConditions = false;
                    });
                  },
                ),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        tr('J\'accepte les ', 'Na9bel '),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      // Le lien ouvre les conditions à lire
                      GestureDetector(
                        onTap: _lireConditions,
                        child: Text(
                          tr('conditions d\'utilisation', 'chourout el isti3mel'),
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_erreurConditions)
          Padding(
            padding: EdgeInsets.only(left: 12, top: 6),
            child: Text(
              tr(
                'Tu dois accepter les conditions d\'utilisation',
                'Lazem t9bel chourout el isti3mel',
              ),
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
