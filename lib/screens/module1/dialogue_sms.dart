import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : fenêtre du code SMS (showDialog), en deux temps.
///
/// 1. Le numéro : tapé par l'utilisateur (connexion), ou celui du profil
///    (Paramètres, [numeroFixe]). "Recevoir le code" envoie le SMS.
/// 2. Le code à 6 chiffres. "Valider" appelle [valider] :
///    connexionParSms (connexion) ou verifierTelephone (Paramètres).
///
/// Une fenêtre plutôt qu'un écran : pas de nouvelle route dans le routeur
/// commun. Renvoie true si le code a été accepté.
Future<bool> afficherDialogueSms(
  BuildContext context, {
  required String titre,
  required Future<Resultat<Object?>> Function(String code) valider,
  String? numeroFixe,
}) async {
  final bool? accepte = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // on ne ferme pas par erreur en plein envoi
    builder: (context) {
      return DialogueSms(
        titre: titre,
        valider: valider,
        numeroFixe: numeroFixe,
      );
    },
  );
  return accepte ?? false;
}

class DialogueSms extends StatefulWidget {
  final String titre;
  final Future<Resultat<Object?>> Function(String code) valider;
  final String? numeroFixe; // null : l'utilisateur tape son numéro

  const DialogueSms({
    super.key,
    required this.titre,
    required this.valider,
    this.numeroFixe,
  });

  @override
  State<DialogueSms> createState() {
    return _DialogueSmsState();
  }
}

class _DialogueSmsState extends State<DialogueSms> {
  static const int dureeAttente = 30; // secondes avant de pouvoir renvoyer

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _numeroController = TextEditingController();

  bool _codeEnvoye = false; // false : étape 1 (numéro), true : étape 2 (code)
  bool _enChargement = false;
  String _code = '';
  String _erreur = '';
  int _secondesRestantes = 0;
  Timer? _minuteur;

  @override
  void dispose() {
    _numeroController.dispose();
    _minuteur?.cancel();
    super.dispose();
  }

  String get _numero {
    return widget.numeroFixe ?? _numeroController.text;
  }

  static String? _validerNumero(String? valeur) {
    final String texte = (valeur ?? '').trim();
    if (texte.isEmpty) {
      return 'Saisis ton numéro';
    }
    if (UtilisateurRepository.normaliserTelephone(texte) == null) {
      return 'Numéro de téléphone invalide (8 chiffres)';
    }
    return null;
  }

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

  /// Étape 1 (et "Renvoyer le code") : demande le SMS à Firebase.
  Future<void> _envoyerCode() async {
    if (widget.numeroFixe == null && !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _enChargement = true;
      _erreur = '';
    });
    final Resultat<void> resultat =
        await UtilisateurRepository().envoyerCodeSms(_numero);
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      if (resultat.estSucces) {
        _codeEnvoye = true;
        _demarrerCompteARebours();
      } else {
        _erreur = resultat.erreur!;
      }
    });
  }

  /// Étape 2 : envoie les 6 chiffres. Succès : la fenêtre se ferme (true).
  Future<void> _validerCode() async {
    setState(() {
      _enChargement = true;
      _erreur = '';
    });
    final Resultat<Object?> resultat = await widget.valider(_code);
    if (!mounted) {
      return;
    }
    if (resultat.estSucces) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _enChargement = false;
      _erreur = resultat.erreur!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> contenu = [];
    if (!_codeEnvoye) {
      if (widget.numeroFixe == null) {
        contenu.add(_texte('Un code à 6 chiffres te sera envoyé par SMS.'));
        contenu.add(const SizedBox(height: 16));
        contenu.add(
          AppTextField(
            label: 'Numéro de téléphone',
            hint: '22 345 678',
            icone: Icons.phone_outlined,
            controller: _numeroController,
            clavier: TextInputType.phone,
            validator: _validerNumero,
          ),
        );
      } else {
        contenu.add(
          _texte('Un code à 6 chiffres sera envoyé par SMS au '
              '${widget.numeroFixe}.'),
        );
      }
    } else {
      contenu.add(_texte('Saisis le code reçu au ${_numero.trim()}.'));
      contenu.add(const SizedBox(height: 16));
      contenu.add(
        SaisieCode(
          libelle: 'Code SMS',
          onChanged: (String code) {
            setState(() {
              _code = code;
            });
          },
        ),
      );
      contenu.add(const SizedBox(height: 8));
      contenu.add(_ligneRenvoi());
    }
    if (_erreur.isNotEmpty) {
      contenu.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _erreur,
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (_enChargement) {
      contenu.add(const IndicateurChargement());
    }

    // Le bouton principal : "Recevoir le code", puis "Valider" (actif
    // quand les 6 chiffres sont tapés)
    Function()? actionPrincipale;
    if (!_enChargement) {
      if (!_codeEnvoye) {
        actionPrincipale = _envoyerCode;
      } else if (_code.length == 6) {
        actionPrincipale = _validerCode;
      }
    }

    return AlertDialog(
      title: Text(widget.titre),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: contenu,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enChargement ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: actionPrincipale,
          child: Text(
            _codeEnvoye ? 'Valider' : 'Recevoir le code',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _texte(String texte) {
    return Text(
      texte,
      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
    );
  }

  /// "Renvoyer le code dans 25 s", puis un lien "Renvoyer le code".
  Widget _ligneRenvoi() {
    if (_secondesRestantes > 0) {
      return Text(
        'Renvoyer le code dans $_secondesRestantes s',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }
    return TextButton(
      onPressed: _enChargement ? null : _envoyerCode,
      child: const Text('Renvoyer le code'),
    );
  }
}
