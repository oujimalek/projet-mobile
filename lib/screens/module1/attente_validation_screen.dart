import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/signalement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/nail_divider.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/status_badge.dart';

/// M1 - Utilisateurs : écran 5, attente de la validation par l'admin.
///
/// Une frise en 3 étapes montre où en est la demande :
/// envoyée → validation par l'admin → accès à la houma.
class AttenteValidationScreen extends StatelessWidget {
  const AttenteValidationScreen({super.key});

  /// L'heure de la demande, ex : "Aujourd'hui, 15:42".
  String _heureDemande(DateTime? date) {
    if (date == null) {
      return 'Aujourd\'hui';
    }
    final String heures = date.hour.toString().padLeft(2, '0');
    final String minutes = date.minute.toString().padLeft(2, '0');
    return 'Aujourd\'hui, $heures:$minutes';
  }

  void _contacterAdmin(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Contacter l\'administrateur'),
          content: const Text(
            'Un message a été envoyé à l\'administrateur de ton quartier. '
            'Il te répondra par notification.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = UtilisateurRepository().getUtilisateurConnecte();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Validation en cours'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ----- Logo dans un cercle bleu clair -----
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const HoumaniLogo(taille: 56),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Demande envoyée !',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'L\'administrateur de ${utilisateur.quartier} doit valider '
                  'ton inscription. Tu recevras une notification dès que '
                  'c\'est fait.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const NailDivider(),

                // ----- Frise de suivi -----
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Suivi de la validation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _etape(
                        icone: Icons.check_circle,
                        couleur: AppColors.secondary,
                        titre: 'Demande envoyée',
                        detail: _heureDemande(utilisateur.dateDemande),
                      ),
                      const Divider(color: AppColors.border),
                      _etape(
                        icone: Icons.radio_button_checked,
                        couleur: AppColors.warning,
                        titre: 'Validation par l\'admin',
                        detail: 'En général sous 24 h',
                        // Le badge "En attente" commun à toute l'app
                        badge: const StatusBadge(
                          statut: StatutSignalement.enAttente,
                        ),
                      ),
                      const Divider(color: AppColors.border),
                      _etape(
                        icone: Icons.radio_button_unchecked,
                        couleur: AppColors.border,
                        titre: 'Accès à ta houma',
                        detail: 'Services, signalements, événements',
                        aVenir: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                SecondaryButton(
                  texte: 'Modifier mon quartier',
                  onPressed: () {
                    context.go('/code-quartier');
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      _contacterAdmin(context);
                    },
                    child: const Text(
                      'Contacter l\'administrateur',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                // ----- Raccourci de démo (pas d'admin réel) -----
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      UtilisateurRepository().simulerValidation();
                      context.go('/accueil');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Démo : simuler la validation'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Une étape de la frise : pastille colorée, titre, détail, badge éventuel.
  Widget _etape({
    required IconData icone,
    required Color couleur,
    required String titre,
    required String detail,
    Widget? badge,
    bool aVenir = false, // true = étape pas encore atteinte (texte grisé)
  }) {
    final List<Widget> ligne = [
      Icon(icone, color: couleur, size: 18),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: aVenir ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ];
    if (badge != null) {
      ligne.add(badge);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: ligne),
    );
  }
}
