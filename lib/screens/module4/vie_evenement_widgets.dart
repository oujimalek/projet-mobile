import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/models/sondage.dart';
import '../../data/models/utilisateur.dart';
import '../../data/models/vie_evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/base_locale_m4.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import 'module4_widgets.dart';
import 'sondage_form_screen.dart';
import 'sondage_screen.dart';

/// M4 - Les sections du bas du détail d'un événement :
/// « Qui apporte quoi ? », « Questions » et « Avis ».
/// Chaque section charge ses propres données (StatefulWidget + setState).

Utilisateur _moi() => UtilisateurRepository().getUtilisateurConnecte();

/// Titre d'une section avec une icône.
Widget _titreSection(IconData icone, String texte) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icone, color: AppColors.secondary),
        const SizedBox(width: 8),
        Text(texte,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// Affiche le message d'un Resultat en échec.
void _erreur(BuildContext context, Resultat resultat) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(resultat.erreur!)));
}

// =========================================================================
// Qui apporte quoi ?
// =========================================================================

class SectionObjets extends StatefulWidget {
  final Evenement evenement;

  const SectionObjets({super.key, required this.evenement});

  @override
  State<SectionObjets> createState() {
    return _SectionObjetsState();
  }
}

class _SectionObjetsState extends State<SectionObjets> {
  final EvenementRepository _depot = EvenementRepository();
  final TextEditingController _nouvel = TextEditingController();
  List<ObjetAApporter> _objets = [];
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _nouvel.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final Resultat<List<ObjetAApporter>> resultat =
        await _depot.getObjets(widget.evenement.id);
    if (!mounted || !resultat.estSucces) {
      return;
    }
    setState(() {
      _objets = resultat.donnee!;
    });
  }

  Future<void> _faire(Future<Resultat<void>> Function() action) async {
    setState(() {
      _envoi = true;
    });
    final Resultat<void> resultat = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _envoi = false;
    });
    if (!resultat.estSucces) {
      _erreur(context, resultat);
      return;
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final bool organise = EvenementRepository.peutModifier(_moi(), widget.evenement);
    // Rien à montrer : pas d'objet et ce n'est pas l'organisateur
    if (_objets.isEmpty && !organise) {
      return const SizedBox.shrink();
    }
    final List<Widget> lignes = [];
    for (final ObjetAApporter objet in _objets) {
      final bool moi = objet.prisParId == _moi().id;
      lignes.add(
        Row(
          children: [
            Icon(
              objet.estPris ? Icons.check_circle : Icons.radio_button_unchecked,
              color: objet.estPris ? AppColors.success : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(objet.objet,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (objet.estPris)
                    Text('${moi ? 'Toi' : objet.prisParNom} s\'en charge',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (!objet.estPris || moi)
              TextButton(
                onPressed: _envoi || widget.evenement.estPasse
                    ? null
                    : () => _faire(() => _depot.prendreObjet(
                        widget.evenement.id, objet, !moi)),
                child: Text(moi ? tr('Je ne l\'apporte plus', 'Ma3adech njibou') : tr('Je l\'apporte', 'Ena njibou')),
              ),
            if (organise)
              IconButton(
                tooltip: 'Retirer de la liste',
                icon: Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                onPressed: _envoi
                    ? null
                    : () => _faire(
                        () => _depot.supprimerObjet(widget.evenement, objet.id)),
              ),
          ],
        ),
      );
    }
    if (organise) {
      lignes.add(
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nouvel,
                decoration: const InputDecoration(
                  hintText: 'Ajouter : chaises, boissons...',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ajouter',
              icon: Icon(Icons.add_circle, color: AppColors.primary),
              onPressed: _envoi
                  ? null
                  : () async {
                      final String texte = _nouvel.text;
                      await _faire(
                          () => _depot.ajouterObjet(widget.evenement, texte));
                      _nouvel.clear();
                    },
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection(Icons.shopping_basket_outlined, tr('Qui apporte quoi ?', 'Chkoun yjib chnowa ?')),
            ...lignes,
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Questions / commentaires
// =========================================================================

class SectionQuestions extends StatefulWidget {
  final Evenement evenement;

  const SectionQuestions({super.key, required this.evenement});

  @override
  State<SectionQuestions> createState() {
    return _SectionQuestionsState();
  }
}

class _SectionQuestionsState extends State<SectionQuestions> {
  final EvenementRepository _depot = EvenementRepository();
  final TextEditingController _texte = TextEditingController();
  List<Commentaire> _commentaires = [];
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final Resultat<List<Commentaire>> resultat =
        await _depot.getCommentaires(widget.evenement.id);
    if (!mounted || !resultat.estSucces) {
      return;
    }
    setState(() {
      _commentaires = resultat.donnee!;
    });
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoi = true;
    });
    final Resultat<void> resultat =
        await _depot.ajouterCommentaire(widget.evenement.id, _texte.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoi = false;
    });
    if (!resultat.estSucces) {
      _erreur(context, resultat);
      return;
    }
    _texte.clear();
    _charger();
  }

  Future<void> _supprimer(Commentaire commentaire) async {
    final Resultat<void> resultat =
        await _depot.supprimerCommentaire(widget.evenement.id, commentaire.id);
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      _erreur(context, resultat);
      return;
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> lignes = [];
    if (_commentaires.isEmpty) {
      lignes.add(Text(tr('Pas encore de question. Pose la première !', 'Mazel 7atta sou2el. Is2el enti el lowel !'),
          style: TextStyle(color: AppColors.textSecondary)));
    }
    for (final Commentaire commentaire in _commentaires) {
      final bool deLorganisateur =
          commentaire.auteurId == widget.evenement.organisateurId;
      lignes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(commentaire.auteurNom,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (deLorganisateur) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(tr('Organisateur', "L'organisateur"),
                                style: TextStyle(
                                    color: AppColors.primary, fontSize: 11)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(commentaire.texte),
                  ],
                ),
              ),
              if (EvenementRepository.peutSupprimerCommentaire(
                  _moi(), commentaire, widget.evenement))
                IconButton(
                  tooltip: 'Supprimer',
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () => _supprimer(commentaire),
                ),
            ],
          ),
        ),
      );
    }
    lignes.add(
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _texte,
              maxLength: EvenementRepository.commentaireMax,
              decoration: InputDecoration(
                hintText: tr('Pose une question...', 'Is2el sou2el...'),
                isDense: true,
                counterText: '',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Envoyer',
            icon: Icon(Icons.send, color: AppColors.primary),
            onPressed: _envoi ? null : _envoyer,
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection(Icons.forum_outlined,
                'Questions (${_commentaires.length})'),
            ...lignes,
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Avis après l'événement
// =========================================================================

class SectionAvis extends StatefulWidget {
  final Evenement evenement;
  final bool participe; // seuls les participants donnent leur avis

  const SectionAvis({super.key, required this.evenement, required this.participe});

  @override
  State<SectionAvis> createState() {
    return _SectionAvisState();
  }
}

class _SectionAvisState extends State<SectionAvis> {
  final EvenementRepository _depot = EvenementRepository();
  final TextEditingController _commentaire = TextEditingController();
  List<AvisEvenement> _avis = [];
  int _note = 0;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final Resultat<List<AvisEvenement>> resultat =
        await _depot.getAvis(widget.evenement.id);
    if (!mounted || !resultat.estSucces) {
      return;
    }
    setState(() {
      _avis = resultat.donnee!;
    });
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoi = true;
    });
    final Resultat<void> resultat = await _depot.donnerAvis(
        widget.evenement, _note, _commentaire.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoi = false;
    });
    if (!resultat.estSucces) {
      _erreur(context, resultat);
      return;
    }
    BaseLocaleM4.noterAvis(widget.evenement, _note); // (SQLite) mon historique
    _charger();
  }

  Widget _etoiles(int note, {double taille = 18, Function(int)? choisir}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          GestureDetector(
            onTap: choisir == null ? null : () => choisir(i),
            child: Icon(
              i <= note ? Icons.star_rounded : Icons.star_outline_rounded,
              color: AppColors.secondary,
              size: taille,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Les avis n'existent qu'après l'événement
    if (!widget.evenement.estPasse) {
      return const SizedBox.shrink();
    }
    final double? moyenne = EvenementRepository.moyenne(_avis);
    final bool dejaDonne = _avis.any((a) => a.id == _moi().id);
    final List<Widget> lignes = [];

    if (moyenne != null) {
      lignes.add(Row(
        children: [
          Text(moyenne.toStringAsFixed(1),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          _etoiles(moyenne.round()),
          const SizedBox(width: 8),
          Text('(${_avis.length} avis)',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ));
      lignes.add(const SizedBox(height: 8));
    }
    for (final AvisEvenement avis in _avis) {
      lignes.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(avis.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              _etoiles(avis.note, taille: 14),
            ]),
            if (avis.commentaire.isNotEmpty) Text(avis.commentaire),
          ],
        ),
      ));
    }

    if (widget.participe && !dejaDonne) {
      lignes.add(const Text('Ton avis sur l\'événement :'));
      lignes.add(const SizedBox(height: 6));
      lignes.add(_etoiles(_note, taille: 32, choisir: (note) {
        setState(() {
          _note = note;
        });
      }));
      lignes.add(TextField(
        controller: _commentaire,
        decoration: const InputDecoration(
          hintText: 'Un petit mot (optionnel)',
          isDense: true,
        ),
      ));
      lignes.add(Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _note == 0 || _envoi ? null : _envoyer,
          child: Text(tr('Envoyer mon avis', 'Ab3ath ra2yek')),
        ),
      ));
    } else if (_avis.isEmpty) {
      lignes.add(Text('Pas encore d\'avis.',
          style: TextStyle(color: AppColors.textSecondary)));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection(Icons.star_border_rounded, tr('Avis', 'Ara2')),
            ...lignes,
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Sondages rattachés à l'événement
// =========================================================================

class SectionSondagesEvenement extends StatefulWidget {
  final Evenement evenement;

  const SectionSondagesEvenement({super.key, required this.evenement});

  @override
  State<SectionSondagesEvenement> createState() {
    return _SectionSondagesEvenementState();
  }
}

class _SectionSondagesEvenementState extends State<SectionSondagesEvenement> {
  final EvenementRepository _depot = EvenementRepository();
  List<Sondage> _sondages = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final Resultat<List<Sondage>> resultat =
        await _depot.chargerSondagesDe(widget.evenement.id);
    if (!mounted || !resultat.estSucces) {
      return;
    }
    setState(() {
      _sondages = resultat.donnee!;
    });
  }

  Future<void> _ouvrir(Widget ecran) async {
    await ouvrirEcranM4<void>(context, ecran);
    if (mounted) {
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    // L'organisateur (leader ou admin) peut ajouter un sondage
    final bool peutAjouter =
        EvenementRepository.peutModifier(_moi(), widget.evenement) &&
            EvenementRepository.peutOrganiser(_moi()) &&
            !widget.evenement.estPasse;
    if (_sondages.isEmpty && !peutAjouter) {
      return const SizedBox.shrink();
    }
    final List<Widget> lignes = [];
    for (final Sondage sondage in _sondages) {
      lignes.add(
        InkWell(
          onTap: () => _ouvrir(SondageScreen(sondageId: sondage.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.poll_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sondage.question,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${sondage.totalVotes} vote${sondage.totalVotes > 1 ? 's' : ''} · ${texteFin(sondage.dateFin)}',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      );
    }
    if (peutAjouter) {
      lignes.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                _ouvrir(SondageFormScreen(evenement: widget.evenement)),
            icon: const Icon(Icons.add),
            label: Text(tr('Ajouter un sondage', 'Zid sondage')),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection(Icons.poll_outlined,
                tr('Sondages de l\'événement', 'Les sondages mta3 l\'événement')),
            ...lignes,
          ],
        ),
      ),
    );
  }
}
