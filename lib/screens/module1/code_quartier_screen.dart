import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/quartier.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/localisation.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 4, rejoindre sa houma.
///
/// Deux façons de choisir son quartier :
/// - taper le code d'invitation à 6 caractères donné par l'admin ;
/// - OU chercher le quartier par son nom et le sélectionner.
/// La demande part ensuite à l'administrateur (écran d'attente).
///
/// Ouvert depuis "Mon quartier" par un résident actif : c'est un
/// changement de quartier (flèche retour, confirmation avant d'envoyer).
class CodeQuartierScreen extends StatefulWidget {
  const CodeQuartierScreen({super.key});

  @override
  State<CodeQuartierScreen> createState() {
    return _CodeQuartierScreenState();
  }
}

class _CodeQuartierScreenState extends State<CodeQuartierScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  final TextEditingController _rechercheController = TextEditingController();

  String _code = '';
  Quartier? _quartierDuCode; // trouvé grâce au code complet (6 caractères)
  bool _codeInconnu = false; // code complet mais qui ne correspond à rien
  Quartier? _quartierSelectionne; // choisi dans la liste de recherche
  List<Quartier> _quartiersTrouves = []; // résultat de la recherche
  String _erreurRecherche = ''; // ex : pas de réseau
  bool _enChargement = false; // true pendant l'envoi de la demande
  bool _localisation = false; // true pendant la recherche GPS

  @override
  void initState() {
    super.initState();
    _rechercher(); // au départ : tous les quartiers
    // On met la liste à jour à chaque lettre tapée dans la recherche
    _rechercheController.addListener(_rechercher);
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  /// Demande au repository les quartiers qui correspondent à la recherche.
  Future<void> _rechercher() async {
    final Resultat<List<Quartier>> resultat =
        await _repository.rechercherQuartiers(_rechercheController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      // En cas d'échec (pas de réseau...), la liste reste vide
      // et on affiche pourquoi
      _quartiersTrouves = resultat.donnee ?? [];
      _erreurRecherche = resultat.estSucces ? '' : resultat.erreur!;
    });
  }

  /// Appelé à chaque caractère du code : dès qu'il est complet,
  /// on cherche le quartier correspondant.
  Future<void> _codeModifie(String code) async {
    setState(() {
      _code = code;
      _quartierDuCode = null;
      _codeInconnu = false;
    });
    if (code.length < 6) {
      return;
    }
    final Resultat<Quartier?> resultat = await _repository.trouverParCode(code);
    final Quartier? quartier = resultat.donnee;
    // Le code a pu changer pendant l'attente : on ignore l'ancienne réponse
    if (!mounted || code != _code) {
      return;
    }
    setState(() {
      _quartierDuCode = quartier;
      _codeInconnu = quartier == null;
    });
  }

  /// "Me localiser" : sélectionne le quartier dont les limites
  /// (tracées par son admin) contiennent ma position GPS.
  Future<void> _meLocaliser() async {
    setState(() {
      _localisation = true;
    });
    final Resultat<PointGps> position = await Localisation.positionActuelle();
    Quartier? trouve;
    String message = '';
    if (!position.estSucces) {
      message = position.erreur!;
    } else {
      final Resultat<List<Quartier>> quartiers =
          await _repository.rechercherQuartiers('');
      if (!quartiers.estSucces) {
        message = quartiers.erreur!;
      } else {
        for (final Quartier quartier in quartiers.donnee!) {
          if (quartier.contient(position.donnee!)) {
            trouve = quartier;
            break;
          }
        }
        if (trouve == null) {
          message = tr(
            'Aucun quartier trouvé à ta position. '
                'Demande le code à ton administrateur.',
            'Ma l9ina 7atta houma fi blastek. '
                'Otlob el code mel admin mte3ek.',
          );
        } else if (_changement() &&
            trouve.id == _repository.getUtilisateurConnecte().quartierId) {
          message = tr(
            'Tu es dans ton quartier actuel',
            'Enti fi houmtek tawa',
          );
          trouve = null;
        } else {
          message = tr('Tu es dans ${trouve.nom}', 'Enti fi ${trouve.nom}');
        }
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _localisation = false;
      if (trouve != null) {
        _quartierSelectionne = trouve;
      }
    });
    if (trouve != null) {
      // La liste ne montre plus que ce quartier (sélectionné)
      _rechercheController.text = trouve.nom;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Le quartier qui sera rejoint : celui du code s'il est complet,
  /// sinon celui sélectionné dans la liste.
  Quartier? _quartierChoisi() {
    if (_code.length == 6) {
      return _quartierDuCode;
    }
    return _quartierSelectionne;
  }

  Future<void> _rejoindre() async {
    final Quartier? quartier = _quartierChoisi();
    if (quartier == null) {
      return;
    }
    if (_changement() && !await _confirmerChangement(quartier)) {
      return;
    }
    setState(() {
      _enChargement = true;
    });
    final Resultat<void> resultat = await _repository.rejoindreQuartier(quartier);
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }
    // go : après l'envoi de la demande, pas de retour en arrière
    context.go('/attente');
  }

  /// true : un résident actif change de quartier (venu de "Mon quartier").
  bool _changement() {
    return _repository.getUtilisateurConnecte().statut ==
        StatutUtilisateur.actif;
  }

  /// Prévient le résident qu'il quitte son quartier actuel.
  /// Renvoie true s'il confirme.
  Future<bool> _confirmerChangement(Quartier nouveau) async {
    final String actuel = _repository.getUtilisateurConnecte().quartier;
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr('Changer de quartier ?', 'Tbadel houmtek ?')),
          content: Text(
            tr(
              'Tu vas quitter $actuel pour rejoindre ${nouveau.nom}. '
                  'Tu n\'auras plus accès à ton quartier actuel, et '
                  'l\'administrateur de ${nouveau.nom} devra valider ta demande.',
              'Bech to5rej men $actuel w tod5ol l ${nouveau.nom}. '
                  'Ma 3adech todkhol l houmtek tawa, w el admin mta3 '
                  '${nouveau.nom} lazem y9abel demande mte3ek.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(tr('Annuler', 'Batel')),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(tr('Changer', 'Badel')),
            ),
          ],
        );
      },
    );
    return confirme == true;
  }

  @override
  Widget build(BuildContext context) {
    // Bouton actif seulement si un quartier est choisi, qu'il a un admin
    // pour valider la demande, et que rien n'est en cours
    final Quartier? choisi = _quartierChoisi();
    final bool peutRejoindre =
        choisi != null && choisi.aUnAdmin && !_enChargement;
    final bool changement = _changement();

    return Scaffold(
      body: Column(
        children: [
          // Changement : flèche retour vers "Mon quartier" (pas de déconnexion)
          changement
              ? const AppHeader(titre: '')
              : const AppHeader(titre: '', action: BoutonDeconnexion()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                changement
                    ? TitreEcran(
                        titre: tr('Changer de quartier', 'Badel houmtek'),
                        sousTitre: tr(
                          'Entre le code d\'invitation de ton nouveau '
                              'quartier, ou cherche-le.',
                          'Ekteb code el invitation mta3 houmtek ejdida, '
                              'wala lawej 3liha.',
                        ),
                      )
                    : TitreEcran(
                        titre: tr('Rejoins ta houma', 'Od5ol l houmtek'),
                        sousTitre: tr(
                          'Entre le code d\'invitation reçu de ton '
                              'administrateur, ou cherche ton quartier.',
                          'Ekteb code el invitation elli 3tahoulek el admin, '
                              'wala lawej 3la houmtek.',
                        ),
                      ),
                const SizedBox(height: 20),
                // Demande précédente refusée (ex : au redémarrage de l'app,
                // l'utilisateur arrive ici directement) : on explique pourquoi
                if (_repository.getUtilisateurConnecte().statut ==
                    StatutUtilisateur.refuse)
                  _bandeauRefus(),

                // ----- Code d'invitation -----
                Text(
                  tr('Code d\'invitation', 'Code el invitation'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SaisieCode(
                  chiffresSeulement: false,
                  libelle: tr('Code d\'invitation', 'Code el invitation'),
                  onChanged: _codeModifie,
                ),
                if (_codeInconnu)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      tr(
                        'Ce code ne correspond à aucun quartier',
                        'El code hedha mouch mta3 7atta houma',
                      ),
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                // Code valide mais personne pour valider la demande
                if (_code.length == 6 &&
                    _quartierDuCode != null &&
                    !_quartierDuCode!.aUnAdmin)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      tr(
                        '${_quartierDuCode!.nom} n\'a pas encore '
                            'd\'administrateur : impossible de le rejoindre '
                            'pour l\'instant.',
                        '${_quartierDuCode!.nom} mazel ma 3andhech admin : '
                            'ma tnajjamch tod5olha tawa.',
                      ),
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                _separateurOu(),

                // ----- Recherche d'un quartier -----
                AppTextField(
                  label: tr('Rechercher un quartier', 'Lawej 3la houma'),
                  hint: tr(
                    'Ex : Résidence El Yasmine, Ennasr...',
                    'Mathalan : Résidence El Yasmine, Ennasr...',
                  ),
                  icone: Icons.search,
                  controller: _rechercheController,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      _localisation
                          ? tr('Localisation...', 'Nlawej 3la blastek...')
                          : tr('Me localiser', 'Win ana ?'),
                    ),
                    onPressed: _localisation ? null : _meLocaliser,
                  ),
                ),
                const SizedBox(height: 4),
                ..._listeQuartiers(),
                const SizedBox(height: 24),

                PrimaryButton(
                  texte: tr('Rejoindre la houma', 'Od5ol lel houma'),
                  onPressed: peutRejoindre ? _rejoindre : null,
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'Ta demande sera validée par l\'administrateur du quartier.',
                    'El admin mta3 el houma bech y9abel demande mte3ek.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bandeau rouge clair : la dernière demande a été refusée.
  Widget _bandeauRefus() {
    final String motif = _repository.getUtilisateurConnecte().motif;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.error),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              motif.isEmpty
                  ? tr(
                      'Ta dernière demande a été refusée par l\'administrateur. '
                          'Vérifie le code ou choisis un autre quartier.',
                      'El admin rfodh e5er demande mte3ek. '
                          'Thabbet fel code wala a5tar houma o5ra.',
                    )
                  : tr(
                      'Ta dernière demande a été refusée par l\'administrateur '
                          '(motif : $motif). Vérifie le code ou choisis un '
                          'autre quartier.',
                      'El admin rfodh e5er demande mte3ek '
                          '(sbab : $motif). Thabbet fel code wala a5tar '
                          'houma o5ra.',
                    ),
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Ligne "——— ou ———" entre les deux façons de choisir.
  Widget _separateurOu() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              tr('ou', 'wala'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }

  /// Les cartes des quartiers trouvés (avec un bouton radio).
  List<Widget> _listeQuartiers() {
    final List<Widget> cartes = [];
    final Utilisateur moi = _repository.getUtilisateurConnecte();
    for (final Quartier quartier in _quartiersTrouves) {
      // Changement de quartier : on ne propose pas le quartier actuel
      if (_changement() && quartier.id == moi.quartierId) {
        continue;
      }
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _carteQuartier(quartier),
        ),
      );
    }
    if (_erreurRecherche.isNotEmpty) {
      cartes.add(
        Text(
          _erreurRecherche,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.error),
        ),
      );
    } else if (cartes.isEmpty) {
      cartes.add(
        Text(
          tr('Aucun quartier trouvé', 'Ma l9ina 7atta houma'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return cartes;
  }

  Widget _carteQuartier(Quartier quartier) {
    final bool selectionne = _quartierSelectionne?.id == quartier.id;

    return Material(
      color: selectionne ? AppColors.primaryLight : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(
          color: selectionne ? AppColors.primary : AppColors.border,
          width: selectionne ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _quartierSelectionne = quartier;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const HoumaniLogo(taille: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quartier.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    // (Pas de nombre de membres : les règles Firestore
                    // ne permettent pas de compter les membres d'un
                    // quartier qu'on n'a pas encore rejoint.)
                    Text(
                      quartier.localisation,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    // Personne pour valider : on prévient avant la demande
                    if (!quartier.aUnAdmin)
                      Text(
                        tr(
                          'Pas encore d\'administrateur',
                          'Mazel ma 3andhech admin',
                        ),
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selectionne ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selectionne ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
