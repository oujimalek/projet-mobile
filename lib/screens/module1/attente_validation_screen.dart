import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/signalement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/nail_divider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/status_badge.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 5, attente de la validation par l'admin.
///
/// Une frise en 3 étapes montre où en est la demande :
/// envoyée → validation par l'admin → accès à la houma.
/// "Vérifier ma demande" relit le profil sur Firestore pour savoir
/// si l'admin a accepté (ou refusé) la demande.
class AttenteValidationScreen extends StatefulWidget {
  const AttenteValidationScreen({super.key});

  @override
  State<AttenteValidationScreen> createState() {
    return _AttenteValidationScreenState();
  }
}

class _AttenteValidationScreenState extends State<AttenteValidationScreen> {
  bool _enChargement = false; // true pendant la lecture du profil

  /// L'heure de la demande, ex : "Aujourd'hui, 15:42".
  String _heureDemande(DateTime? date) {
    if (date == null) {
      return tr('Aujourd\'hui', 'Lyoum');
    }
    final String heures = date.hour.toString().padLeft(2, '0');
    final String minutes = date.minute.toString().padLeft(2, '0');
    return tr('Aujourd\'hui, $heures:$minutes', 'Lyoum, $heures:$minutes');
  }

  void _afficherMessage(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte)),
    );
  }

  /// Relit le profil sur le serveur et ouvre l'écran qui correspond
  /// au nouveau statut.
  Future<void> _verifierDemande() async {
    setState(() {
      _enChargement = true;
    });
    final Resultat<Utilisateur> resultat =
        await UtilisateurRepository().rafraichirProfil();
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      _afficherMessage(resultat.erreur!);
      // Compte bloqué ou supprimé : le repository a déconnecté
      if (UtilisateurRepository().getUtilisateurConnecte().id.isEmpty) {
        context.go('/connexion');
      }
      return;
    }
    final Utilisateur utilisateur = resultat.donnee!;
    // Le message reste visible sur l'écran suivant (ScaffoldMessenger commun)
    _afficherMessage(_messageSelonStatut(utilisateur));
    // Même choix d'écran qu'à la connexion et au démarrage
    final String? chemin = cheminSelonStatut(utilisateur);
    if (chemin != null && chemin != '/attente') {
      context.go(chemin);
    }
  }

  String _messageSelonStatut(Utilisateur utilisateur) {
    switch (utilisateur.statut) {
      case StatutUtilisateur.actif:
        return tr('Ta demande a été acceptée !', 'Demande mte3ek t9eblet !');
      case StatutUtilisateur.refuse:
        // Le motif donné par l'admin, s'il y en a un
        if (utilisateur.motif.isNotEmpty) {
          return tr(
            'Ta demande a été refusée : ${utilisateur.motif}',
            'Demande mte3ek tarfdhet : ${utilisateur.motif}',
          );
        }
        return tr(
          'Ta demande a été refusée : choisis un autre quartier',
          'Demande mte3ek tarfdhet : a5tar houma o5ra',
        );
      case StatutUtilisateur.bloque:
        return UtilisateurRepository.messageBloque(utilisateur.motif);
      case StatutUtilisateur.enAttente:
        return tr(
          'Toujours en attente de validation',
          'Mazelet testanna fel validation',
        );
    }
  }

  void _contacterAdmin(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Contacter l\'administrateur', 'Kallem el admin')),
          content: Text(
            tr(
              'Un message a été envoyé à l\'administrateur de ton quartier. '
                  'Il te répondra par notification.',
              'Tba3thet risala lel admin mta3 houmtek. '
                  'Bech yjewbek b notification.',
            ),
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
          AppHeader(
            titre: tr('Validation en cours', 'Testanna el validation'),
            action: const BoutonDeconnexion(),
          ),
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
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const HoumaniLogo(taille: 56),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('Demande envoyée !', 'Demande tba3thet !'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'L\'administrateur de ${utilisateur.quartier} doit valider '
                        'ton inscription. Reviens vérifier ta demande un peu '
                        'plus tard.',
                    'El admin mta3 ${utilisateur.quartier} lazem y9abel '
                        'inscription mte3ek. Arja3 thabbet ba3d chwaya.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                      Text(
                        tr('Suivi de la validation', 'Win wsolt el validation'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _etape(
                        icone: Icons.check_circle,
                        couleur: AppColors.secondary,
                        titre: tr('Demande envoyée', 'Demande tba3thet'),
                        detail: _heureDemande(utilisateur.dateDemande),
                      ),
                      Divider(color: AppColors.border),
                      _etape(
                        icone: Icons.radio_button_checked,
                        couleur: AppColors.warning,
                        titre: tr('Validation par l\'admin', 'El admin y9abel'),
                        detail: tr('En général sous 24 h', 'Ghaleban fi 24 se3a'),
                        // Le badge "En attente" commun à toute l'app
                        badge: const StatusBadge(
                          statut: StatutSignalement.enAttente,
                        ),
                      ),
                      Divider(color: AppColors.border),
                      _etape(
                        icone: Icons.radio_button_unchecked,
                        couleur: AppColors.border,
                        titre: tr('Accès à ta houma', 'Todkhol l houmtek'),
                        detail: tr(
                          'Services, signalements, événements',
                          'Services, signalements w événements',
                        ),
                        aVenir: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // null pendant le chargement : bouton désactivé
                PrimaryButton(
                  texte: tr('Vérifier ma demande', 'Thabbet fel demande'),
                  onPressed: _enChargement ? null : _verifierDemande,
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 12),
                SecondaryButton(
                  texte: tr('Modifier mon quartier', 'Badel houmti'),
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
                    child: Text(
                      tr('Contacter l\'administrateur', 'Kallem el admin'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
              style: TextStyle(
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
