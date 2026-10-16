import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import 'conditions_utilisation.dart';
import 'dialogue_sms.dart';
import 'widgets_module1.dart';

/// Version affichée dans "À propos" (la même que dans pubspec.yaml).
const String versionHoumani = '1.0.0';

/// M1 - Utilisateurs : écran Paramètres.
///
/// Ouvert depuis le profil ou le menu latéral.
/// - Sécurité : vérifier son numéro par SMS (pour se connecter par SMS),
///   changer le mot de passe, changer l'e-mail, supprimer le
///   compte. Chaque action ouvre une fenêtre (showDialog) avec un Form ;
///   le mot de passe actuel est toujours redemandé (exigé par Firebase).
/// - Apparence : thème comme le téléphone, clair ou sombre.
/// - À propos : conditions d'utilisation, version, copyright.
class ParametresScreen extends StatefulWidget {
  const ParametresScreen({super.key});

  @override
  State<ParametresScreen> createState() {
    return _ParametresScreenState();
  }
}

class _ParametresScreenState extends State<ParametresScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  // true pendant qu'on attend Firebase (la roue tourne, les lignes sont inactives)
  bool _enChargement = false;

  // ----- Règles des champs (les mêmes qu'à l'inscription) -----

  static String? _validerMotDePasseActuel(String valeur, List<String> saisies) {
    if (valeur.isEmpty) {
      return 'Saisis ton mot de passe actuel';
    }
    return null;
  }

  static String? _validerNouveauMotDePasse(
    String valeur,
    List<String> saisies,
  ) {
    if (valeur.length < 8) {
      return 'Au moins 8 caractères';
    }
    if (valeur == saisies[0]) {
      return 'Choisis un mot de passe différent de l\'actuel';
    }
    return null;
  }

  static String? _validerConfirmation(String valeur, List<String> saisies) {
    if (valeur != saisies[1]) {
      return 'Les deux mots de passe ne sont pas identiques';
    }
    return null;
  }

  static String? _validerNouvelEmail(String valeur, List<String> saisies) {
    final String texte = valeur.trim();
    if (texte.isEmpty) {
      return 'Saisis la nouvelle adresse';
    }
    if (!texte.contains('@') || !texte.contains('.')) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  // ----- Les trois actions -----

  /// Envoie l'opération au repository, avec la roue pendant l'attente,
  /// puis affiche le message (succès ou erreur) dans une SnackBar.
  /// Renvoie true si l'opération a réussi.
  Future<bool> _executer(
    Future<Resultat<void>> operation,
    String messageSucces,
  ) async {
    setState(() {
      _enChargement = true;
    });
    final Resultat<void> resultat = await operation;
    if (!mounted) {
      return false;
    }
    setState(() {
      _enChargement = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(resultat.estSucces ? messageSucces : resultat.erreur!),
      ),
    );
    return resultat.estSucces;
  }

  Future<void> _changerMotDePasse() async {
    final List<String>? saisies = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return const DialogueSecurite(
          titre: 'Changer le mot de passe',
          texteBouton: 'Enregistrer',
          champs: [
            ChampSecurite('Mot de passe actuel', _validerMotDePasseActuel),
            ChampSecurite('Nouveau mot de passe', _validerNouveauMotDePasse),
            ChampSecurite('Confirmer le nouveau', _validerConfirmation),
          ],
        );
      },
    );
    if (saisies == null) {
      return; // fenêtre annulée
    }
    await _executer(
      _repository.changerMotDePasse(saisies[0], saisies[1]),
      'Mot de passe modifié',
    );
  }

  Future<void> _changerEmail() async {
    final List<String>? saisies = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return const DialogueSecurite(
          titre: 'Changer l\'e-mail',
          explication: 'Un lien de confirmation sera envoyé à la nouvelle '
              'adresse. L\'e-mail changera quand tu cliqueras dessus ; '
              'tu devras alors te reconnecter.',
          texteBouton: 'Envoyer le lien',
          champs: [
            ChampSecurite(
              'Nouvel e-mail',
              _validerNouvelEmail,
              motDePasse: false,
            ),
            ChampSecurite('Mot de passe actuel', _validerMotDePasseActuel),
          ],
        );
      },
    );
    if (saisies == null) {
      return;
    }
    await _executer(
      _repository.changerEmail(saisies[0], saisies[1]),
      'Lien envoyé à ${saisies[0].trim()}',
    );
  }

  Future<void> _supprimerCompte() async {
    final List<String>? saisies = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return const DialogueSecurite(
          titre: 'Supprimer mon compte',
          explication: 'Ton profil et ton compte seront effacés '
              'définitivement. Cette action est irréversible.',
          texteBouton: 'Supprimer',
          danger: true,
          champs: [
            ChampSecurite('Mot de passe actuel', _validerMotDePasseActuel),
          ],
        );
      },
    );
    if (saisies == null || !mounted) {
      return;
    }
    // On garde le routeur avant l'attente (l'écran peut changer entre-temps)
    final GoRouter routeur = GoRouter.of(context);
    final bool supprime = await _executer(
      _repository.supprimerCompte(saisies[0]),
      'Ton compte a été supprimé',
    );
    if (supprime) {
      routeur.go('/connexion'); // go : plus de retour possible
    }
  }

  /// Vérifie le numéro du profil par SMS : il pourra ensuite servir à se
  /// connecter avec "Se connecter par SMS".
  Future<void> _verifierNumero() async {
    final bool verifie = await afficherDialogueSms(
      context,
      titre: 'Vérifier mon numéro',
      numeroFixe: _repository.getUtilisateurConnecte().telephone,
      valider: _repository.verifierTelephone,
    );
    if (!verifie || !mounted) {
      return;
    }
    setState(() {}); // la ligne affiche maintenant "Vérifié"
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Numéro vérifié : tu peux te connecter par SMS'),
      ),
    );
  }

  // ----- Affichage -----

  @override
  Widget build(BuildContext context) {
    final String email = _repository.emailConnecte();
    final String telephone = _repository.getUtilisateurConnecte().telephone;
    final bool telephoneVerifie = _repository.telephoneEstVerifie();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Paramètres'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _titreSection('SÉCURITÉ'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Vérifié : ligne d'information avec une coche verte
                      _ligne(
                        icone: Icons.sms_outlined,
                        titre: telephoneVerifie
                            ? 'Numéro vérifié'
                            : 'Vérifier mon numéro',
                        detail: telephone,
                        onTap: telephoneVerifie || telephone.isEmpty
                            ? null
                            : _verifierNumero,
                        fin: telephoneVerifie
                            ? Icon(Icons.verified, color: AppColors.success)
                            : null,
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.lock_outline,
                        titre: 'Changer le mot de passe',
                        onTap: _changerMotDePasse,
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.alternate_email,
                        titre: 'Changer l\'e-mail',
                        detail: email,
                        onTap: _changerEmail,
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.delete_outline,
                        titre: 'Supprimer mon compte',
                        couleur: AppColors.error,
                        onTap: _supprimerCompte,
                      ),
                    ],
                  ),
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 24),

                _titreSection('APPARENCE'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _choixTheme(
                        ModeTheme.systeme,
                        Icons.brightness_auto_outlined,
                        'Comme le téléphone',
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _choixTheme(
                        ModeTheme.clair,
                        Icons.light_mode_outlined,
                        'Clair',
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _choixTheme(
                        ModeTheme.sombre,
                        Icons.dark_mode_outlined,
                        'Sombre',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _titreSection('À PROPOS'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _ligne(
                        icone: Icons.description_outlined,
                        titre: 'Conditions d\'utilisation',
                        onTap: () {
                          afficherConditions(context, avecAcceptation: false);
                        },
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.info_outline,
                        titre: 'Version',
                        detail: versionHoumani,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  copyrightHoumani,
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

  Widget _titreSection(String titre) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        titre,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Une ligne du choix de thème : coche dorée sur le choix actuel.
  /// Le changement est immédiat (PreferenceTheme prévient HoumaniApp).
  Widget _choixTheme(ModeTheme mode, IconData icone, String titre) {
    final bool choisi = PreferenceTheme.mode.value == mode;
    return _ligne(
      icone: icone,
      titre: titre,
      onTap: () {
        PreferenceTheme.choisir(mode);
      },
      fin: choisi
          ? Icon(Icons.check, color: AppColors.secondary)
          : const SizedBox(width: 24),
    );
  }

  /// Une ligne de réglage. onTap null : ligne d'information (pas de flèche).
  /// fin : ce qui remplace la flèche à droite (ex : une coche).
  Widget _ligne({
    required IconData icone,
    required String titre,
    String? detail,
    Color? couleur, // par défaut : couleur du texte
    Function()? onTap,
    Widget? fin,
  }) {
    final Color couleurLigne = couleur ?? AppColors.textPrimary;
    return InkWell(
      // Pendant le chargement, les lignes ne réagissent plus
      onTap: _enChargement ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icone, color: couleurLigne, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: couleurLigne,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (fin != null)
              fin
            else if (onTap != null)
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Un champ d'une fenêtre de sécurité.
/// validator reçoit la valeur du champ ET toutes les saisies de la fenêtre
/// (pour comparer "Confirmer" au nouveau mot de passe).
class ChampSecurite {
  final String label;
  final String? Function(String valeur, List<String> saisies) validator;
  final bool motDePasse; // true = texte masqué (bouton œil)

  const ChampSecurite(this.label, this.validator, {this.motDePasse = true});
}

/// Fenêtre (AlertDialog) avec un Form. "Annuler" renvoie null ;
/// le bouton principal renvoie les saisies si tous les champs sont valides.
/// C'est un StatefulWidget pour posséder (et libérer) ses contrôleurs.
class DialogueSecurite extends StatefulWidget {
  final String titre;
  final String? explication;
  final List<ChampSecurite> champs;
  final String texteBouton;
  final bool danger; // true = bouton rouge (action irréversible)

  const DialogueSecurite({
    super.key,
    required this.titre,
    this.explication,
    required this.champs,
    required this.texteBouton,
    this.danger = false,
  });

  @override
  State<DialogueSecurite> createState() {
    return _DialogueSecuriteState();
  }
}

class _DialogueSecuriteState extends State<DialogueSecurite> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.champs.length; i++) {
      _controllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _saisies() {
    final List<String> saisies = [];
    for (final TextEditingController controller in _controllers) {
      saisies.add(controller.text);
    }
    return saisies;
  }

  void _valider() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(_saisies());
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> contenu = [];
    if (widget.explication != null) {
      contenu.add(
        Text(
          widget.explication!,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
      contenu.add(const SizedBox(height: 16));
    }
    for (int i = 0; i < widget.champs.length; i++) {
      final ChampSecurite champ = widget.champs[i];
      if (i > 0) {
        contenu.add(const SizedBox(height: 12));
      }
      contenu.add(
        AppTextField(
          label: champ.label,
          controller: _controllers[i],
          motDePasse: champ.motDePasse,
          clavier: champ.motDePasse
              ? TextInputType.visiblePassword
              : TextInputType.emailAddress,
          validator: (String? valeur) {
            return champ.validator(valeur ?? '', _saisies());
          },
        ),
      );
    }

    return AlertDialog(
      title: Text(widget.titre),
      // SingleChildScrollView : le clavier peut cacher le bas de la fenêtre
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: contenu),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _valider,
          child: Text(
            widget.texteBouton,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: widget.danger ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
