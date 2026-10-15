import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/nail_divider.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 3, connexion.
///
/// Un Form avec deux champs (e-mail, mot de passe).
/// Le bouton "Se connecter" vérifie les champs, puis interroge
/// UtilisateurRepository (Firebase Auth).
/// Selon le statut du compte, on ouvre l'accueil, le choix du quartier
/// ou l'écran d'attente de validation.
class ConnexionScreen extends StatefulWidget {
  const ConnexionScreen({super.key});

  @override
  State<ConnexionScreen> createState() {
    return _ConnexionScreenState();
  }
}

class _ConnexionScreenState extends State<ConnexionScreen> {
  // Clé du formulaire : permet d'appeler validate() sur tous les champs
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Contrôleurs : permettent de lire le texte saisi dans les champs
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _motDePasseController = TextEditingController();

  // Message d'erreur affiché sous le bouton après une tentative ratée
  String _message = '';

  // true pendant qu'on attend la réponse du serveur
  bool _enChargement = false;

  @override
  void dispose() {
    // On libère les contrôleurs quand l'écran est fermé
    _emailController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  /// Validation du champ "E-mail" (on se connecte avec l'e-mail).
  String? _validerEmail(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton e-mail';
    }
    final String texte = valeur.trim();
    if (!texte.contains('@') || !texte.contains('.')) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  /// Validation du champ "Mot de passe".
  String? _validerMotDePasse(String? valeur) {
    if (valeur == null || valeur.isEmpty) {
      return 'Saisis ton mot de passe';
    }
    if (valeur.length < 6) {
      return 'Au moins 6 caractères';
    }
    return null;
  }

  /// Appelé quand on touche "Se connecter".
  Future<void> _seConnecter() async {
    // 1. On vérifie les champs : si une règle n'est pas respectée, on s'arrête
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 2. Chargement : la roue tourne et le bouton est désactivé
    //    (pas de double clic pendant l'attente)
    setState(() {
      _enChargement = true;
      _message = '';
    });

    // 3. On demande au repository si le compte existe
    //    (await : la réponse peut prendre du temps avec un vrai serveur)
    final Resultat<Utilisateur> resultat = await UtilisateurRepository()
        .connexion(_emailController.text, _motDePasseController.text);
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });

    // Échec (mauvais mot de passe, pas de réseau, compte bloqué...) :
    // le repository donne le message à afficher
    if (!resultat.estSucces) {
      setState(() {
        _message = resultat.erreur!;
      });
      return;
    }

    // 4. On ouvre l'écran qui correspond au statut du compte
    //    (go : on remplace la connexion, pas de retour possible vers elle)
    final String? chemin = cheminSelonStatut(resultat.donnee!);
    if (chemin == null) {
      setState(() {
        _message = 'Ton compte a été bloqué par l\'administrateur';
      });
      return;
    }
    context.go(chemin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barre du haut discrète (couleur du fond) : seulement la flèche retour
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          // ----- En-tête : logo + bienvenue -----
          const SizedBox(height: 8),
          const Center(child: HoumaniLogo(taille: 72)),
          const SizedBox(height: 20),
          const Text(
            'Ahla bik !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Connecte-toi à ta houma',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const NailDivider(),
          const SizedBox(height: 12),

          // ----- Formulaire -----
          Form(
            key: _formKey,
            child: Column(
              children: [
                AppTextField(
                  label: 'E-mail',
                  hint: 'exemple@mail.com',
                  controller: _emailController,
                  clavier: TextInputType.emailAddress,
                  validator: _validerEmail,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Mot de passe',
                  hint: '••••••••',
                  controller: _motDePasseController,
                  motDePasse: true,
                  validator: _validerMotDePasse,
                ),
              ],
            ),
          ),

          // ----- Mot de passe oublié -----
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                // push : la flèche retour ramène à la connexion
                context.push('/mot-de-passe-oublie');
              },
              child: const Text(
                'Mot de passe oublié ?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ----- Bouton principal -----
          // null pendant le chargement : bouton désactivé
          PrimaryButton(
            texte: 'Se connecter',
            onPressed: _enChargement ? null : _seConnecter,
          ),
          if (_enChargement) const IndicateurChargement(),
          const SizedBox(height: 12),

          // ----- Erreur de connexion -----
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          // ----- Inscription -----
          // Wrap : passe à la ligne si l'écran est trop étroit
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Pas encore de compte ?',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () {
                  context.push('/inscription');
                },
                child: const Text(
                  'S\'inscrire',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
