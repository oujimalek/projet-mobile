import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 2, vérification du numéro par SMS.
///
/// L'utilisateur tape le code à 6 chiffres reçu par SMS.
/// Un compte à rebours empêche de redemander un code trop vite.
/// (Démo : le code est toujours UtilisateurRepository.codeOtpDemo.)
class VerificationOtpScreen extends StatefulWidget {
  const VerificationOtpScreen({super.key});

  @override
  State<VerificationOtpScreen> createState() {
    return _VerificationOtpScreenState();
  }
}

class _VerificationOtpScreenState extends State<VerificationOtpScreen> {
  static const int dureeAttente = 60; // secondes avant de pouvoir renvoyer

  String _code = '';
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

  void _renvoyerCode() {
    setState(() {
      _erreur = '';
      _demarrerCompteARebours();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Un nouveau code t\'a été envoyé')),
    );
  }

  void _verifier() {
    if (UtilisateurRepository().verifierCode(_code)) {
      // Numéro vérifié : étape suivante, choisir son quartier
      context.push('/code-quartier');
    } else {
      setState(() {
        _erreur = 'Code incorrect, vérifie le SMS reçu';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String telephone = UtilisateurRepository().telephoneMasque();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: ''),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TitreEcran(
                  titre: 'Vérifie ton numéro',
                  sousTitre: 'Nous avons envoyé un code à 6 chiffres au\n$telephone',
                ),
                const SizedBox(height: 24),

                // ----- Les 6 cases + compte à rebours -----
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: Column(
                    children: [
                      SaisieCode(
                        chiffresSeulement: true,
                        onChanged: (code) {
                          setState(() {
                            _code = code;
                            _erreur = '';
                          });
                        },
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

                // Le bouton reste désactivé tant que les 6 chiffres ne sont pas tapés
                PrimaryButton(
                  texte: 'Vérifier',
                  onPressed: _code.length == 6 ? _verifier : null,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Retour à l'inscription pour corriger le numéro
                      context.pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Modifier le numéro',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Démo : le code est ${UtilisateurRepository.codeOtpDemo}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Renvoyer le code dans 00:42", puis un lien "Renvoyer le code".
  Widget _ligneRenvoi() {
    if (_secondesRestantes > 0) {
      return Text.rich(
        TextSpan(
          text: 'Renvoyer le code dans ',
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
      onPressed: _renvoyerCode,
      child: const Text(
        'Renvoyer le code',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
