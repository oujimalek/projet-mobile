import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/nail_divider.dart';
import '../../widgets/primary_button.dart';

/// M1 - Utilisateurs : écran 3, connexion.
///
/// Un Form avec deux champs (téléphone ou e-mail, mot de passe).
/// Le bouton "Se connecter" vérifie les champs, puis interroge
/// UtilisateurRepository (compte de démo : voir mock_utilisateur_repository.dart).
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
  final TextEditingController _identifiantController = TextEditingController();
  final TextEditingController _motDePasseController = TextEditingController();

  // Message d'erreur affiché sous le bouton après une tentative ratée
  String _message = '';

  @override
  void dispose() {
    // On libère les contrôleurs quand l'écran est fermé
    _identifiantController.dispose();
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

  /// Validation du champ "Téléphone ou e-mail".
  String? _validerIdentifiant(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton téléphone ou ton e-mail';
    }
    final String texte = valeur.trim();

    // Si le texte contient un @, on le traite comme un e-mail
    if (texte.contains('@')) {
      if (!texte.contains('.')) {
        return 'Adresse e-mail invalide';
      }
      return null;
    }

    // Sinon c'est un téléphone : au moins 8 chiffres (numéro tunisien)
    if (_compterChiffres(texte) < 8) {
      return 'Numéro de téléphone invalide (8 chiffres)';
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

    // 2. On demande au repository si le compte existe
    //    (await : la réponse peut prendre du temps avec un vrai serveur)
    final Utilisateur? utilisateur = await UtilisateurRepository().connexion(
      _identifiantController.text,
      _motDePasseController.text,
    );
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }

    if (utilisateur == null) {
      setState(() {
        _message = 'Identifiant ou mot de passe incorrect';
      });
      return;
    }

    // 3. On ouvre l'écran qui correspond au statut du compte
    //    (go : on remplace la connexion, pas de retour possible vers elle)
    switch (utilisateur.statut) {
      case StatutUtilisateur.actif:
        context.go('/accueil');
      case StatutUtilisateur.enAttente:
        // Pas encore de quartier : il doit d'abord en choisir un
        if (utilisateur.quartier.isEmpty) {
          context.go('/code-quartier');
        } else {
          context.go('/attente');
        }
      case StatutUtilisateur.bloque:
        setState(() {
          _message = 'Ton compte a été bloqué par l\'administrateur';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? aideDemo = UtilisateurRepository().aideDemoConnexion;

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
                  label: 'Téléphone ou e-mail',
                  hint: '+216 22 345 678',
                  controller: _identifiantController,
                  clavier: TextInputType.emailAddress,
                  validator: _validerIdentifiant,
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

          // ----- Mot de passe oublié (visuel seulement pour l'instant) -----
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                // Écran "mot de passe oublié" : à venir
              },
              child: const Text(
                'Mot de passe oublié ?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ----- Bouton principal -----
          PrimaryButton(texte: 'Se connecter', onPressed: _seConnecter),
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
          // Aide de démo (rien avec une vraie source de données)
          if (aideDemo != null)
            Text(
              'Démo : $aideDemo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
