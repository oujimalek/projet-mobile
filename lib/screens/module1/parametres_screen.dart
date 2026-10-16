import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
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
/// - Langue : français ou derja (textes du module 1, voir tr()).
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
      return tr('Saisis ton mot de passe actuel',
          'Ekteb el mot de passe mte3ek tawa');
    }
    return null;
  }

  static String? _validerNouveauMotDePasse(
    String valeur,
    List<String> saisies,
  ) {
    if (valeur.length < 8) {
      return tr('Au moins 8 caractères', 'Mouch a9al men 8 7rouf');
    }
    if (valeur == saisies[0]) {
      return tr('Choisis un mot de passe différent de l\'actuel',
          'Ekhtar mot de passe ghir elli 3andek');
    }
    return null;
  }

  static String? _validerConfirmation(String valeur, List<String> saisies) {
    if (valeur != saisies[1]) {
      return tr('Les deux mots de passe ne sont pas identiques',
          'Ezzouz mots de passe mouch kif kif');
    }
    return null;
  }

  static String? _validerNouvelEmail(String valeur, List<String> saisies) {
    final String texte = valeur.trim();
    if (texte.isEmpty) {
      return tr('Saisis la nouvelle adresse', 'Ekteb el adresse ejdida');
    }
    if (!texte.contains('@') || !texte.contains('.')) {
      return tr('Adresse e-mail invalide', 'El adresse e-mail ghalta');
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
        return DialogueSecurite(
          titre: tr('Changer le mot de passe', 'Badel el mot de passe'),
          texteBouton: tr('Enregistrer', 'Sajjel'),
          champs: [
            ChampSecurite(
              tr('Mot de passe actuel', 'El mot de passe tawa'),
              _validerMotDePasseActuel,
            ),
            ChampSecurite(
              tr('Nouveau mot de passe', 'Mot de passe jdid'),
              _validerNouveauMotDePasse,
            ),
            ChampSecurite(
              tr('Confirmer le nouveau', 'A3awed ekteb ejdid'),
              _validerConfirmation,
            ),
          ],
        );
      },
    );
    if (saisies == null) {
      return; // fenêtre annulée
    }
    await _executer(
      _repository.changerMotDePasse(saisies[0], saisies[1]),
      tr('Mot de passe modifié', 'El mot de passe tbaddel'),
    );
  }

  Future<void> _changerEmail() async {
    final List<String>? saisies = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return DialogueSecurite(
          titre: tr('Changer l\'e-mail', 'Badel el e-mail'),
          explication: tr(
            'Un lien de confirmation sera envoyé à la nouvelle '
                'adresse. L\'e-mail changera quand tu cliqueras dessus ; '
                'tu devras alors te reconnecter.',
            'Bech nab3thoulek lien 3al adresse ejdida. El e-mail '
                'yetbaddel ki tenzel 3lih, w ba3d lazem todkhol men jdid.',
          ),
          texteBouton: tr('Envoyer le lien', 'Ab3ath el lien'),
          champs: [
            ChampSecurite(
              tr('Nouvel e-mail', 'E-mail jdid'),
              _validerNouvelEmail,
              motDePasse: false,
            ),
            ChampSecurite(
              tr('Mot de passe actuel', 'El mot de passe tawa'),
              _validerMotDePasseActuel,
            ),
          ],
        );
      },
    );
    if (saisies == null) {
      return;
    }
    await _executer(
      _repository.changerEmail(saisies[0], saisies[1]),
      tr('Lien envoyé à ${saisies[0].trim()}',
          'Ba3thna el lien l ${saisies[0].trim()}'),
    );
  }

  Future<void> _supprimerCompte() async {
    final List<String>? saisies = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return DialogueSecurite(
          titre: tr('Supprimer mon compte', 'Fassa5 el compte mte3i'),
          explication: tr(
            'Ton profil et ton compte seront effacés '
                'définitivement. Cette action est irréversible.',
            'El profil w el compte mte3ek bech yetfass5ou nhar w lil. '
                'Ma tnajjemch traja3hom.',
          ),
          texteBouton: tr('Supprimer', 'Fassa5'),
          danger: true,
          champs: [
            ChampSecurite(
              tr('Mot de passe actuel', 'El mot de passe tawa'),
              _validerMotDePasseActuel,
            ),
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
      tr('Ton compte a été supprimé', 'El compte mte3ek tfassa5'),
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
      titre: tr('Vérifier mon numéro', 'Thabbet noumrouk'),
      numeroFixe: _repository.getUtilisateurConnecte().telephone,
      valider: _repository.verifierTelephone,
    );
    if (!verifie || !mounted) {
      return;
    }
    setState(() {}); // la ligne affiche maintenant "Vérifié"
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Numéro vérifié : tu peux te connecter par SMS',
            'Noumrouk mthabbet : tnajjem todkhol b SMS')),
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
          AppHeader(titre: tr('Paramètres', 'El paramètres')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _titreSection(tr('SÉCURITÉ', 'EL AMEN')),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Vérifié : ligne d'information avec une coche verte
                      _ligne(
                        icone: Icons.sms_outlined,
                        titre: telephoneVerifie
                            ? tr('Numéro vérifié', 'Noumrouk mthabbet')
                            : tr('Vérifier mon numéro', 'Thabbet noumrouk'),
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
                        titre: tr(
                          'Changer le mot de passe',
                          'Badel el mot de passe',
                        ),
                        onTap: _changerMotDePasse,
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.alternate_email,
                        titre: tr('Changer l\'e-mail', 'Badel el e-mail'),
                        detail: email,
                        onTap: _changerEmail,
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _ligne(
                        icone: Icons.delete_outline,
                        titre: tr(
                          'Supprimer mon compte',
                          'Fassa5 el compte mte3i',
                        ),
                        couleur: AppColors.error,
                        onTap: _supprimerCompte,
                      ),
                    ],
                  ),
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 24),

                _titreSection(tr('APPARENCE', 'ECHAKL')),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _choixTheme(
                        ModeTheme.systeme,
                        Icons.brightness_auto_outlined,
                        tr('Comme le téléphone', 'Kif el téléphone'),
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _choixTheme(
                        ModeTheme.clair,
                        Icons.light_mode_outlined,
                        tr('Clair', 'Mdhawi'),
                      ),
                      Divider(height: 1, color: AppColors.border),
                      _choixTheme(
                        ModeTheme.sombre,
                        Icons.dark_mode_outlined,
                        tr('Sombre', 'Mdhallem'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _titreSection(tr('LANGUE', 'LOUGHA')),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Chaque langue est écrite dans sa propre langue
                      _choixLangue(Langue.francais, 'Français'),
                      Divider(height: 1, color: AppColors.border),
                      _choixLangue(Langue.derja, 'Derja (tounsi)'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _titreSection(tr('À PROPOS', '3LA EL APPLI')),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _ligne(
                        icone: Icons.description_outlined,
                        titre: tr(
                          'Conditions d\'utilisation',
                          'Chourout el isti3mal',
                        ),
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

  /// Une ligne du choix de langue : même présentation que le thème.
  /// Le changement est immédiat (PreferenceLangue prévient HoumaniApp).
  Widget _choixLangue(Langue langue, String titre) {
    final bool choisie = PreferenceLangue.langue.value == langue;
    return _ligne(
      icone: Icons.translate,
      titre: titre,
      onTap: () {
        PreferenceLangue.choisir(langue);
        setState(() {}); // la coche change de ligne tout de suite
      },
      fin: choisie
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
          child: Text(tr('Annuler', 'Batel')),
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
