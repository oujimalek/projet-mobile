import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 2, vérification de l'adresse e-mail.
///
/// Firebase envoie un e-mail avec un lien. L'utilisateur clique dessus
/// dans sa boîte mail, revient dans l'app et touche "J'ai vérifié mon
/// e-mail". Un compte à rebours empêche de renvoyer l'e-mail trop vite.
///
/// (Ancien écran du code SMS : le nom de la classe et la route
/// '/verification' sont gardés pour ne pas toucher au routeur commun.)
class VerificationOtpScreen extends StatefulWidget {
  const VerificationOtpScreen({super.key});

  @override
  State<VerificationOtpScreen> createState() {
    return _VerificationOtpScreenState();
  }
}

class _VerificationOtpScreenState extends State<VerificationOtpScreen> {
  static const int dureeAttente = 60; // secondes avant de pouvoir renvoyer

  String _erreur = '';
  int _secondesRestantes = dureeAttente;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _demarrerCompteARebours();
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  /// Lance (ou relance) le compte à rebours : -1 seconde chaque seconde.
  void _demarrerCompteARebours() {
    _minuteur?.cancel();
    _secondesRestantes = dureeAttente;
    _minuteur = Timer.periodic(const Duration(seconds: 1), (minuteur) {
      setState(() {
        _secondesRestantes--;
      });
      if (_secondesRestantes <= 0) {
        minuteur.cancel();
      }
    });
  }

  /// 42 secondes donne "00:42".
  String _formaterTemps(int secondes) {
    final String minutes = (secondes ~/ 60).toString().padLeft(2, '0');
    final String reste = (secondes % 60).toString().padLeft(2, '0');
    return '$minutes:$reste';
  }

  Future<void> _renvoyerEmail() async {
    setState(() {
      _erreur = '';
      _demarrerCompteARebours();
    });
    final Resultat<void> resultat =
        await UtilisateurRepository().envoyerEmailVerification();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resultat.estSucces ? 'Un nouvel e-mail t\'a été envoyé' : resultat.erreur!,
        ),
      ),
    );
  }

  Future<void> _verifier() async {
    final Resultat<bool> resultat =
        await UtilisateurRepository().emailEstVerifie();
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    if (!resultat.estSucces) {
      setState(() {
        _erreur = resultat.erreur!;
      });
    } else if (resultat.donnee!) {
      // E-mail vérifié : étape suivante, choisir son quartier
      context.push('/code-quartier');
    } else {
      setState(() {
        _erreur = 'E-mail pas encore vérifié : clique sur le lien reçu';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String email = UtilisateurRepository().emailConnecte();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: ''),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TitreEcran(
                  titre: 'Vérifie ton e-mail',
                  sousTitre: 'Nous avons envoyé un lien de vérification à\n$email',
                ),
                const SizedBox(height: 24),

                // ----- Explication + compte à rebours -----
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ouvre ta boîte mail, clique sur le lien, '
                        'puis reviens ici.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      _ligneRenvoi(),
                    ],
                  ),
                ),
                if (_erreur.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _erreur,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                PrimaryButton(
                  texte: 'J\'ai vérifié mon e-mail',
                  onPressed: _verifier,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Retour à l'inscription
                      context.pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Retour',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                // ----- Raccourci de démo (pas de vraie boîte mail) -----
                if (UtilisateurRepository().estDemo) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await UtilisateurRepository().simulerVerificationEmail();
                        _verifier();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Démo : simuler le clic sur le lien'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Renvoyer l'e-mail dans 00:42", puis un lien "Renvoyer l'e-mail".
  Widget _ligneRenvoi() {
    if (_secondesRestantes > 0) {
      return Text.rich(
        TextSpan(
          text: 'Renvoyer l\'e-mail dans ',
          style: const TextStyle(color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: _formaterTemps(_secondesRestantes),
              style: const TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return TextButton(
      onPressed: _renvoyerEmail,
      child: const Text(
        'Renvoyer l\'e-mail',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
