import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/nail_divider.dart';
import '../../widgets/primary_button.dart';
import 'conditions_utilisation.dart';
import 'dialogue_sms.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 3, connexion.
///
/// Un Form avec deux champs (e-mail ou téléphone, mot de passe).
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

  /// Validation du champ "E-mail ou téléphone" : avec un @, c'est un
  /// e-mail ; sinon, un numéro tunisien à 8 chiffres.
  String? _validerIdentifiant(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return tr(
        'Saisis ton e-mail ou ton numéro',
        'Ekteb el e-mail wala el nouméro mte3ek',
      );
    }
    final String texte = valeur.trim();
    if (UtilisateurRepository.estUnNumero(texte)) {
      if (UtilisateurRepository.normaliserTelephone(texte) == null) {
        return tr(
          'Numéro de téléphone invalide (8 chiffres)',
          'Nouméro mouch s7i7 (8 ar9am)',
        );
      }
      return null;
    }
    if (!texte.contains('.')) {
      return tr('Adresse e-mail invalide', 'E-mail mouch s7i7');
    }
    return null;
  }

  /// Validation du champ "Mot de passe".
  String? _validerMotDePasse(String? valeur) {
    if (valeur == null || valeur.isEmpty) {
      return tr('Saisis ton mot de passe', 'Ekteb el mot de passe mte3ek');
    }
    if (valeur.length < 6) {
      return tr('Au moins 6 caractères', 'Mouch a9al men 6 7rouf');
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
        _message = _messageBloque();
      });
      return;
    }
    context.go(chemin);
  }

  /// "Se connecter par SMS" : la fenêtre du code, puis le même aiguillage
  /// que la connexion par mot de passe.
  Future<void> _seConnecterParSms() async {
    setState(() {
      _message = '';
    });
    final bool connecte = await afficherDialogueSms(
      context,
      titre: tr('Connexion par SMS', 'Od5ol b SMS'),
      valider: UtilisateurRepository().connexionParSms,
    );
    if (!connecte || !mounted) {
      return;
    }
    final String? chemin =
        cheminSelonStatut(UtilisateurRepository().getUtilisateurConnecte());
    if (chemin == null) {
      setState(() {
        _message = _messageBloque();
      });
      return;
    }
    context.go(chemin);
  }

  String _messageBloque() {
    return tr(
      'Ton compte a été bloqué par l\'administrateur',
      'El admin bloka el compte mte3ek',
    );
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
          Text(
            tr('Connecte-toi à ta houma', 'Od5ol l houmtek'),
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
                  label: tr('E-mail ou téléphone', 'E-mail wala téléphone'),
                  hint: tr(
                    'exemple@mail.com ou 22 345 678',
                    'exemple@mail.com wala 22 345 678',
                  ),
                  controller: _emailController,
                  clavier: TextInputType.emailAddress,
                  validator: _validerIdentifiant,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: tr('Mot de passe', 'Kelmet esser'),
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
              child: Text(
                tr('Mot de passe oublié ?', 'Nsit el mot de passe ?'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ----- Bouton principal -----
          // null pendant le chargement : bouton désactivé
          PrimaryButton(
            texte: tr('Se connecter', 'Od5ol'),
            onPressed: _enChargement ? null : _seConnecter,
          ),
          if (_enChargement) const IndicateurChargement(),
          Center(
            child: TextButton.icon(
              onPressed: _enChargement ? null : _seConnecterParSms,
              icon: const Icon(Icons.sms_outlined, size: 18),
              label: Text(
                tr('Se connecter par SMS', 'Od5ol b SMS'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // ----- Erreur de connexion -----
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(
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
              Text(
                tr('Pas encore de compte ?', 'Ma 3andekch compte ?'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () {
                  context.push('/inscription');
                },
                child: Text(
                  tr('S\'inscrire', 'A3mel compte'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ----- Pied de page : conditions + © -----
          Center(
            child: TextButton(
              onPressed: () {
                afficherConditions(context, avecAcceptation: false);
              },
              child: Text(
                tr('Conditions d\'utilisation', 'Chourout el isti3mel'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          Text(
            copyrightHoumani,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
