import 'package:flutter/material.dart';

import '../../data/models/election.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/election_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'module4_widgets.dart';

/// M4 - Élection des leaders du quartier.
///
/// L'écran change selon la phase (calculée à partir des dates) :
/// - pas d'élection en cours : les leaders actuels, la date de la prochaine
///   élection, "Demander une nouvelle élection" (membres), "Ouvrir
///   l'élection" (admin) ;
/// - candidatures : la liste des candidats, "Me porter candidat" ;
/// - vote : choisir un candidat (vote secret, une seule fois) ;
/// - dépouillement : le classement ; l'admin publie les résultats.
class ElectionScreen extends StatefulWidget {
  const ElectionScreen({super.key});

  @override
  State<ElectionScreen> createState() {
    return _ElectionScreenState();
  }
}

class _ElectionScreenState extends State<ElectionScreen> {
  final ElectionRepository _depot = ElectionRepository();

  Election? _election; // la dernière élection (en cours ou terminée)
  List<Candidat> _candidats = [];
  String? _monVote; // candidat choisi (null : pas encore voté)
  bool _aDemande = false;
  int _nbDemandes = 0;
  bool _enChargement = true;
  bool _envoiEnCours = false;
  String? _erreur;

  // Choix de l'utilisateur
  String? _choixVote;
  int _nbPlaces = 3; // admin : nombre de leaders à élire
  final Set<String> _elusChoisis = {}; // admin : élus cochés au dépouillement

  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    final Resultat<Election?> resultat = await _depot.getDerniereElection();
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      setState(() {
        _enChargement = false;
        _erreur = resultat.erreur;
      });
      return;
    }
    final Election? election = resultat.donnee;
    List<Candidat> candidats = [];
    String? monVote;
    if (election != null) {
      candidats = (await _depot.getCandidats(election.id)).donnee ?? [];
      monVote = (await _depot.getMonVote(election.id)).donnee;
    }
    final bool aDemande = (await _depot.aDemandeElection()).donnee ?? false;
    int nbDemandes = 0;
    if (_moi.estAdmin) {
      nbDemandes = (await _depot.compterDemandes()).donnee ?? 0;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _election = election;
      _candidats = ElectionRepository.classement(candidats);
      _monVote = monVote;
      _aDemande = aDemande;
      _nbDemandes = nbDemandes;
      _choixVote = monVote;
      // Dépouillement : les N premiers sont cochés d'office
      _elusChoisis.clear();
      if (election != null) {
        for (final Candidat elu
            in ElectionRepository.elusProposes(candidats, election.nbPlaces)) {
          _elusChoisis.add(elu.id);
        }
      }
    });
  }

  /// Lance une action, affiche le message (succès ou erreur) et recharge.
  Future<void> _action(
    Future<Resultat<void>> Function() action,
    String messageSucces,
  ) async {
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultat.estSucces ? messageSucces : resultat.erreur!)),
    );
    if (resultat.estSucces) {
      _charger();
    }
  }

  /// "samedi 14 novembre à 18:00"
  String _quand(DateTime date) {
    return '${texteDate(date)} à ${texteHeure(date)}';
  }

  @override
  Widget build(BuildContext context) {
    Widget corps;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_erreur != null) {
      corps = MessageM4(
        texte: _erreur!,
        icone: Icons.error_outline,
        reessayer: _charger,
      );
    } else {
      corps = RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: _contenu(),
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Élection des leaders'),
          Expanded(child: corps),
        ],
      ),
    );
  }

  List<Widget> _contenu() {
    final Election? election = _election;
    if (election == null) {
      return _sansElectionEnCours(null);
    }
    switch (election.phase()) {
      case PhaseElection.candidatures:
        return _phaseCandidatures(election);
      case PhaseElection.vote:
        return _phaseVote(election);
      case PhaseElection.depouillement:
        return _phaseDepouillement(election);
      case PhaseElection.terminee:
        return _sansElectionEnCours(election);
    }
  }

  // ----- Pas d'élection en cours -----

  List<Widget> _sansElectionEnCours(Election? derniere) {
    final List<Widget> enfants = [];

    // Les leaders actuels
    final List<String> leaders = derniere?.elusNoms ?? [];
    enfants.add(_titre('Les leaders de ta houma'));
    enfants.add(
      AppCard(
        child: leaders.isEmpty
            ? Text(
                'Pas encore de leaders élus.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : Column(
                children: [
                  for (final String nom in leaders) _ligneLeader(nom),
                ],
              ),
      ),
    );
    enfants.add(const SizedBox(height: 16));

    // La prochaine élection
    final DateTime? prochaine = ElectionRepository.prochaineElection(derniere);
    String texteProchaine;
    if (prochaine == null) {
      texteProchaine = 'La première élection n\'a pas encore eu lieu.';
    } else if (prochaine.isBefore(DateTime.now())) {
      texteProchaine = 'L\'élection semestrielle est due depuis le ${texteDate(prochaine)}.';
    } else {
      texteProchaine = 'Prochaine élection : ${texteDate(prochaine)} (tous les 6 mois).';
    }
    enfants.add(_ligneInfo(Icons.event_repeat, texteProchaine));
    enfants.add(const SizedBox(height: 20));

    if (_moi.estAdmin) {
      enfants.addAll(_ouvertureAdmin(derniere));
    } else {
      enfants.addAll(_demandeMembre());
    }
    return enfants;
  }

  /// Membre : demander (ou retirer sa demande d') une élection anticipée.
  List<Widget> _demandeMembre() {
    return [
      Text(
        'Pas satisfait des leaders ? Demande une nouvelle élection : '
        'l\'admin voit le nombre de demandes et peut ouvrir une élection de 24 h.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      _aDemande
          ? SecondaryButton(
              texte: 'Retirer ma demande',
              onPressed: _envoiEnCours
                  ? null
                  : () => _action(() => _depot.demanderElection(false),
                      'Ta demande est retirée'),
            )
          : PrimaryButton(
              texte: 'Demander une nouvelle élection',
              icone: Icons.how_to_vote_outlined,
              onPressed: _envoiEnCours
                  ? null
                  : () => _action(() => _depot.demanderElection(true),
                      'Ta demande est envoyée à l\'admin'),
            ),
    ];
  }

  /// Admin : nombre de places, demandes reçues, ouvrir l'élection.
  List<Widget> _ouvertureAdmin(Election? derniere) {
    return [
      _titre('Ouvrir une élection'),
      _ligneInfo(Icons.campaign_outlined,
          '$_nbDemandes membre${_nbDemandes > 1 ? 's demandent' : ' demande'} une nouvelle élection.'),
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(
            child: Text('Nombre de leaders à élire',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            onPressed: _nbPlaces > 1 ? () => setState(() => _nbPlaces--) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$_nbPlaces',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: _nbPlaces < ElectionRepository.placesMax
                ? () => setState(() => _nbPlaces++)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: 8),
      PrimaryButton(
        texte: 'Ouvrir l\'élection (3 j + 2 j)',
        onPressed: _envoiEnCours
            ? null
            : () => _action(
                  () => _depot.ouvrirElection(nbPlaces: _nbPlaces, anticipee: false),
                  'L\'élection est ouverte : 3 jours de candidatures',
                ),
      ),
      const SizedBox(height: 10),
      SecondaryButton(
        texte: 'Élection anticipée (24 h)',
        onPressed: _envoiEnCours
            ? null
            : () => _action(
                  () => _depot.ouvrirElection(nbPlaces: _nbPlaces, anticipee: true),
                  'Élection anticipée ouverte : 12 h de candidatures',
                ),
      ),
    ];
  }

  // ----- Candidatures -----

  List<Widget> _phaseCandidatures(Election election) {
    bool suisCandidat = false;
    for (final Candidat candidat in _candidats) {
      if (candidat.id == _moi.id) {
        suisCandidat = true;
      }
    }
    final String? refus = ElectionRepository.refusCandidature(
      _moi,
      election,
      dejaCandidat: suisCandidat,
    );

    final List<Widget> enfants = [
      _bandeauPhase(
        Icons.person_add_alt_1_outlined,
        'Candidatures ouvertes',
        'Jusqu\'au ${_quand(election.finCandidatures)} · '
            '${election.nbPlaces} place${election.nbPlaces > 1 ? 's' : ''}'
            '${election.anticipee ? ' · élection anticipée' : ''}',
      ),
      const SizedBox(height: 16),
      _titre('Candidats (${_candidats.length})'),
    ];
    if (_candidats.isEmpty) {
      enfants.add(Text('Personne ne s\'est encore présenté.',
          style: TextStyle(color: AppColors.textSecondary)));
    }
    for (final Candidat candidat in _candidats) {
      enfants.add(_carteCandidat(candidat));
    }
    enfants.add(const SizedBox(height: 16));

    if (suisCandidat) {
      enfants.add(SecondaryButton(
        texte: 'Retirer ma candidature',
        onPressed: _envoiEnCours
            ? null
            : () => _action(() => _depot.retirerCandidature(election),
                'Ta candidature est retirée'),
      ));
    } else if (refus == null) {
      enfants.add(PrimaryButton(
        texte: 'Me porter candidat',
        icone: Icons.front_hand_outlined,
        onPressed: _envoiEnCours ? null : () => _seporterCandidat(election),
      ));
    } else {
      enfants.add(_ligneInfo(Icons.info_outline, refus));
    }
    return enfants;
  }

  Future<void> _seporterCandidat(Election election) async {
    final String? presentation = await showDialog<String>(
      context: context,
      builder: (context) => const _DialoguePresentation(),
    );
    if (presentation == null || !mounted) {
      return;
    }
    _action(
      () => _depot.sePorterCandidat(election, presentation),
      'Ta candidature est enregistrée. Bonne chance !',
    );
  }

  // ----- Vote -----

  List<Widget> _phaseVote(Election election) {
    final bool aVote = _monVote != null;
    final List<Widget> enfants = [
      _bandeauPhase(
        Icons.how_to_vote_outlined,
        'Vote ouvert',
        'Jusqu\'au ${_quand(election.finVote)} · ${election.nbPlaces} '
            'place${election.nbPlaces > 1 ? 's' : ''} · vote secret',
      ),
      const SizedBox(height: 16),
      _titre(aVote ? 'Ton vote' : 'Choisis ton candidat'),
    ];
    if (_candidats.isEmpty) {
      enfants.add(Text('Aucun candidat pour cette élection.',
          style: TextStyle(color: AppColors.textSecondary)));
    }
    for (final Candidat candidat in _candidats) {
      final bool choisi = _choixVote == candidat.id;
      enfants.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            onTap: aVote
                ? null
                : () => setState(() => _choixVote = candidat.id),
            child: Row(
              children: [
                Icon(
                  choisi ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: choisi ? AppColors.secondary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(child: _nomEtPresentation(candidat)),
              ],
            ),
          ),
        ),
      );
    }
    enfants.add(const SizedBox(height: 8));
    if (aVote) {
      enfants.add(Text(
        'Yaatik saha, ton vote est enregistré. Il reste secret : '
        'les résultats seront publiés après le ${_quand(election.finVote)}.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
      ));
    } else {
      final String? choix = _choixVote;
      enfants.add(PrimaryButton(
        texte: 'Confirmer mon vote',
        onPressed: choix == null || _envoiEnCours
            ? null
            : () => _action(() => _depot.voter(election, choix),
                'Ton vote est enregistré'),
      ));
    }
    return enfants;
  }

  // ----- Dépouillement -----

  List<Widget> _phaseDepouillement(Election election) {
    final List<Widget> enfants = [
      _bandeauPhase(
        Icons.fact_check_outlined,
        'Vote terminé',
        _moi.estAdmin
            ? 'Coche les ${election.nbPlaces} élus puis publie les résultats.'
            : 'En attente de la publication des résultats par l\'admin.',
      ),
      const SizedBox(height: 16),
      _titre('Résultats'),
    ];
    if (_moi.estAdmin &&
        ElectionRepository.egalite(_candidats, election.nbPlaces)) {
      enfants.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _ligneInfo(Icons.balance,
            'Égalité pour la dernière place : à toi de choisir qui est élu.'),
      ));
    }
    for (final Candidat candidat in _candidats) {
      final bool coche = _elusChoisis.contains(candidat.id);
      enfants.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            onTap: _moi.estAdmin
                ? () => setState(() {
                      if (coche) {
                        _elusChoisis.remove(candidat.id);
                      } else if (_elusChoisis.length < election.nbPlaces) {
                        _elusChoisis.add(candidat.id);
                      }
                    })
                : null,
            child: Row(
              children: [
                if (_moi.estAdmin) ...[
                  Icon(
                    coche ? Icons.check_box : Icons.check_box_outline_blank,
                    color: coche ? AppColors.secondary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: _nomEtPresentation(candidat)),
                Text(
                  '${candidat.nbVoix} voix',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_moi.estAdmin) {
      final List<Candidat> elus = [];
      for (final Candidat candidat in _candidats) {
        if (_elusChoisis.contains(candidat.id)) {
          elus.add(candidat);
        }
      }
      enfants.add(const SizedBox(height: 8));
      enfants.add(PrimaryButton(
        texte: 'Publier les résultats',
        onPressed: elus.isEmpty || _envoiEnCours
            ? null
            : () => _action(() => _depot.publierResultats(election, elus),
                'Résultats publiés : les élus sont maintenant leaders'),
      ));
    }
    return enfants;
  }

  // ----- Petits widgets -----

  Widget _titre(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(texte,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _ligneInfo(IconData icone, String texte) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(texte)),
      ],
    );
  }

  Widget _bandeauPhase(IconData icone, String titre, String detail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(icone, color: AppColors.primary, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneLeader(String nom) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.star_rounded, color: AppColors.secondary),
          const SizedBox(width: 8),
          Text(nom, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _carteCandidat(Candidat candidat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(child: _nomEtPresentation(candidat)),
    );
  }

  Widget _nomEtPresentation(Candidat candidat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(candidat.nom,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (candidat.presentation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(candidat.presentation,
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

/// La fenêtre "Me porter candidat" avec une courte présentation.
/// Un widget à part : il garde son TextEditingController.
class _DialoguePresentation extends StatefulWidget {
  const _DialoguePresentation();

  @override
  State<_DialoguePresentation> createState() {
    return _DialoguePresentationState();
  }
}

class _DialoguePresentationState extends State<_DialoguePresentation> {
  final TextEditingController _texte = TextEditingController();

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Me porter candidat'),
      content: TextField(
        controller: _texte,
        maxLines: 3,
        maxLength: ElectionRepository.presentationMax,
        decoration: const InputDecoration(
          hintText: 'Pourquoi voter pour toi ? (optionnel)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _texte.text),
          child: const Text('Me présenter'),
        ),
      ],
    );
  }
}
