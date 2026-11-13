import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/quartier.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/localisation.dart';
import '../../data/services/photos_m3.dart';
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
/// La demande part ensuite au leader de la houma (ou à l'admin global).
/// Quartier sans leader : la photo du contrat d'habitation est obligatoire,
/// l'admin global la vérifie et le premier habitant validé devient leader.
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
  // Facultatif : l'admin vérifie sur la carte qu'elle est dans la houma
  final TextEditingController _adresseController = TextEditingController();

  String _code = '';
  Quartier? _quartierDuCode; // trouvé grâce au code complet (6 caractères)
  bool _codeInconnu = false; // code complet mais qui ne correspond à rien
  Quartier? _quartierSelectionne; // choisi dans la liste de recherche
  List<Quartier> _quartiersTrouves = []; // résultat de la recherche
  String _erreurRecherche = ''; // ex : pas de réseau
  bool _enChargement = false; // true pendant l'envoi de la demande
  bool _localisation = false; // true pendant la recherche GPS
  String? _contrat; // photo du contrat d'habitation (chemin sur le téléphone)

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
    _adresseController.dispose();
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
    final String adresse = _adresseController.text.trim();
    final String? refusAdresse = UtilisateurRepository.refusAdresse(adresse);
    if (refusAdresse != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(refusAdresse)),
      );
      return;
    }
    if (_changement() && !await _confirmerChangement(quartier)) {
      return;
    }
    setState(() {
      _enChargement = true;
    });
    // Pas encore de leader : la photo du contrat part d'abord sur Cloudinary
    String contratUrl = '';
    if (!quartier.aUnLeader && _contrat != null) {
      final Resultat<String> envoi = await PhotosM3.envoyerFichier(_contrat!);
      if (!envoi.estSucces) {
        if (!mounted) {
          return;
        }
        setState(() {
          _enChargement = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(envoi.erreur!)),
        );
        return;
      }
      contratUrl = envoi.donnee!;
    }
    final Resultat<void> resultat =
        await _repository.rejoindreQuartier(quartier, contratUrl: contratUrl);
    if (resultat.estSucces && adresse.isNotEmpty) {
      // Pas bloquant : si l'adresse ne passe pas, la demande est déjà partie
      await _repository.enregistrerAdresse(adresse);
    }
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

  /// Photo du contrat d'habitation : appareil photo ou galerie.
  Future<void> _choisirContrat(ImageSource source) async {
    final Resultat<String?> choix = await PhotosM3.choisir(source);
    if (!mounted) {
      return;
    }
    if (!choix.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(choix.erreur!)),
      );
      return;
    }
    if (choix.donnee == null) {
      return; // annulé
    }
    setState(() {
      _contrat = choix.donnee;
    });
  }

  /// Bloc "Contrat d'habitation" (quartier sans leader).
  Widget _blocContrat(Quartier quartier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              '${quartier.nom} n\'a pas encore de leader',
              '${quartier.nom} mazel ma 3andhech leader',
            ),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Ajoute la photo de ton contrat d\'habitation : l\'administrateur '
                  'la vérifie. Le premier habitant validé devient le leader '
                  'de la houma.',
              'Zid taswira mta3 contrat el sokna mte3ek : el admin '
                  'ychoufha. Awel wa7ed yet9bel ywalli leader el houma.',
            ),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (_contrat != null)
            Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('Photo du contrat ajoutée', 'Taswira mta3 el contrat tzedet'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(tr('Photo', 'Taswira')),
                onPressed: _enChargement
                    ? null
                    : () {
                        _choisirContrat(ImageSource.camera);
                      },
              ),
              TextButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(tr('Galerie', 'Galerie')),
                onPressed: _enChargement
                    ? null
                    : () {
                        _choisirContrat(ImageSource.gallery);
                      },
              ),
            ],
          ),
        ],
      ),
    );
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
                  'le leader de ${nouveau.nom} devra valider ta demande.',
              'Bech to5rej men $actuel w tod5ol l ${nouveau.nom}. '
                  'Ma 3adech todkhol l houmtek tawa, w el leader mta3 '
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
    // Bouton actif seulement si un quartier est choisi, que rien n'est en
    // cours, et (quartier sans leader) que la photo du contrat est là
    final Quartier? choisi = _quartierChoisi();
    final bool peutRejoindre = choisi != null &&
        !_enChargement &&
        (choisi.aUnLeader || _contrat != null);
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
                const SizedBox(height: 16),

                // ----- Adresse (facultative) -----
                AppTextField(
                  label: tr(
                    'Ton adresse (facultatif)',
                    'L\'adresse mte3ek (ken t7eb)',
                  ),
                  hint: tr(
                    'Ex : 12 rue des Jasmins',
                    'Mathalan : 12 rue des Jasmins',
                  ),
                  icone: Icons.home_outlined,
                  controller: _adresseController,
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Vue seulement par l\'administrateur, pour vérifier que '
                        'tu habites bien la houma.',
                    'Ken el admin ychoufha, bech yetthabbet elli enti '
                        'saken fel houma.',
                  ),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 24),

                // Quartier sans leader : contrat d'habitation obligatoire
                if (choisi != null && !choisi.aUnLeader) _blocContrat(choisi),

                PrimaryButton(
                  texte: tr('Rejoindre la houma', 'Od5ol lel houma'),
                  onPressed: peutRejoindre ? _rejoindre : null,
                ),
                if (_enChargement) const IndicateurChargement(),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'Ta demande sera validée par le leader du quartier '
                        '(ou par l\'administrateur).',
                    'El leader mta3 el houma (wala el admin) bech y9abel '
                        'demande mte3ek.',
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
                    // Pas de leader : on prévient (contrat demandé)
                    if (!quartier.aUnLeader)
                      Text(
                        tr(
                          'Pas encore de leader : contrat demandé',
                          'Mazel ma 3andhech leader : lazem contrat',
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
