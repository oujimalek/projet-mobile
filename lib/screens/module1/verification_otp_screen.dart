import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
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
  bool _enChargement = false; // true pendant qu'on interroge Firebase
  int _secondesRestantes = dureeAttente;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _demarrerCompteARebours();
    _dejaVerifie();
  }

  /// Au redémarrage de l'app, un compte déjà vérifié (mais sans quartier)
  /// arrive ici : on passe directement au choix du quartier.
  /// Sans réseau ou pas encore vérifié : on reste sur cet écran.
  Future<void> _dejaVerifie() async {
    final Resultat<bool> resultat =
        await UtilisateurRepository().emailEstVerifie();
    if (!mounted) {
      return;
    }
    if (resultat.estSucces && resultat.donnee!) {
      context.go('/code-quartier');
    }
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
          resultat.estSucces
              ? tr(
                  'Un nouvel e-mail t\'a été envoyé',
                  'Ba3thnalek e-mail jdid',
                )
              : resultat.erreur!,
        ),
      ),
    );
  }

  Future<void> _verifier() async {
    setState(() {
      _enChargement = true;
      _erreur = '';
    });
    final Resultat<bool> resultat =
        await UtilisateurRepository().emailEstVerifie();
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      setState(() {
        _erreur = resultat.erreur!;
      });
    } else if (resultat.donnee!) {
      // E-mail vérifié : étape suivante, choisir son quartier
      // (go : revenir à la vérification n'aurait plus de sens)
      context.go('/code-quartier');
    } else {
      setState(() {
        _erreur = tr(
          'E-mail pas encore vérifié : clique sur le lien reçu',
          'El e-mail mazel ma tthabbtech : enzel 3al lien elli jek',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String email = UtilisateurRepository().emailConnecte();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: '', action: BoutonDeconnexion()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TitreEcran(
                  titre: tr('Vérifie ton e-mail', 'Thabbet fel e-mail mte3ek'),
                  sousTitre: tr(
                    'Nous avons envoyé un lien de vérification à\n$email',
                    'Ba3thna lien mta3 vérification l\n$email',
                  ),
                ),
                const SizedBox(height: 24),

                // ----- Explication + compte à rebours -----
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: Column(
                    children: [
                      Icon(
                        Icons.mark_email_unread_outlined,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          'Ouvre ta boîte mail, clique sur le lien, '
                              'puis reviens ici.',
                          '7el el boîte mail, enzel 3al lien, '
                              'w ba3d arja3 lahne.',
                        ),
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
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                PrimaryButton(
                  texte: tr(
                    'J\'ai vérifié mon e-mail',
                    'Thabbet fel e-mail mte3i',
                  ),
                  onPressed: _enChargement ? null : _verifier,
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Retour à l'inscription. Si l'écran a été ouvert
                      // avec go (connexion, démarrage), il n'y a pas
                      // d'écran précédent : on va à la connexion.
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/connexion');
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: Text(
                      tr('Retour', 'Arja3'),
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

  /// "Renvoyer l'e-mail dans 00:42", puis un lien "Renvoyer l'e-mail".
  Widget _ligneRenvoi() {
    if (_secondesRestantes > 0) {
      return Text.rich(
        TextSpan(
          text: tr('Renvoyer l\'e-mail dans ', 'Ta3awed tab3ath el e-mail ba3d '),
          style: TextStyle(color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: _formaterTemps(_secondesRestantes),
              style: TextStyle(
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
      child: Text(
        tr('Renvoyer l\'e-mail', 'Ab3ath el e-mail marra o5ra'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
