import 'package:flutter/material.dart';

import '../../data/models/election.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/election_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import 'election_screen.dart';
import 'module4_widgets.dart';

/// M4 - L'élection du leader, présentée comme un événement spécial.
///
/// - Dans la liste des Événements (alerteSeulement = false) : toujours
///   affichée, elle montre l'état de l'élection (candidatures, vote,
///   résultats, ou date de la prochaine) et ouvre l'écran de l'élection.
/// - Sur l'Accueil (alerteSeulement = true) : seulement pour l'admin global,
///   et seulement s'il a quelque chose à faire dans la cité visitée :
///   le tiers des membres demande une élection anticipée, l'élection
///   semestrielle est due, ou des résultats sont à publier.
///
/// Si le chargement échoue, la carte ne s'affiche pas (ce n'est qu'un raccourci).
class CarteElectionM4 extends StatefulWidget {
  final bool alerteSeulement;

  const CarteElectionM4({super.key, this.alerteSeulement = false});

  @override
  State<CarteElectionM4> createState() {
    return _CarteElectionM4State();
  }
}

class _CarteElectionM4State extends State<CarteElectionM4> {
  bool _charge = false; // false : rien à afficher (chargement ou échec)
  Election? _election;
  int _nbDemandes = 0;
  int _nbActifs = 0;

  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final ElectionRepository depot = ElectionRepository();
    final Resultat<Election?> resultat = await depot.getDerniereElection();
    if (!resultat.estSucces) {
      return;
    }
    int nbDemandes = 0;
    int nbActifs = 0;
    if (_moi.estAdmin) {
      nbDemandes = (await depot.compterDemandes()).donnee ?? 0;
      nbActifs = (await depot.compterVotants()).donnee ?? 0;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _charge = true;
      _election = resultat.donnee;
      _nbDemandes = nbDemandes;
      _nbActifs = nbActifs;
    });
  }

  Future<void> _ouvrir() async {
    await ouvrirEcranM4<void>(context, const ElectionScreen());
    if (mounted) {
      _charger();
    }
  }

  /// Ce que l'admin doit faire (null : rien de spécial).
  String? _alerteAdmin() {
    if (!_moi.estAdmin) {
      return null;
    }
    final Election? election = _election;
    final PhaseElection phase =
        election == null ? PhaseElection.terminee : election.phase();
    if (phase == PhaseElection.depouillement) {
      return tr('Vote terminé : publie le résultat',
          'El vote kmel : onshor el natija');
    }
    if (phase != PhaseElection.terminee) {
      return null;
    }
    if (_nbDemandes > 0 &&
        ElectionRepository.seuilAtteint(_nbDemandes, _nbActifs)) {
      final String compte =
          '$_nbDemandes / ${ElectionRepository.seuilAnticipee(_nbActifs)}';
      return tr('$compte demandes : élection anticipée possible',
          '$compte talbet : tnajjem t7ell intikhabet mosta3jla');
    }
    final DateTime? prochaine = ElectionRepository.prochaineElection(election);
    if (prochaine != null && !prochaine.isAfter(DateTime.now())) {
      return tr('L\'élection semestrielle est due',
          'Wa9t intikhabet el 6 chhar');
    }
    return null;
  }

  /// La ligne d'état, pour tout le monde.
  String _etat() {
    final Election? election = _election;
    if (election == null) {
      return tr('La première élection n\'a pas encore eu lieu',
          'L\'intikhabet el oula mazelet');
    }
    switch (election.phase()) {
      case PhaseElection.candidatures:
        final String fin = texteDate(election.finCandidatures);
        return tr('Candidatures ouvertes jusqu\'au $fin',
            'El tarachou7at ma7loula 7atta $fin');
      case PhaseElection.vote:
        final String fin = texteDate(election.finVote);
        return tr('Vote ouvert jusqu\'au $fin', 'El vote ma7loul 7atta $fin');
      case PhaseElection.depouillement:
        return tr('Vote terminé : résultat bientôt publié',
            'El vote kmel : el natija 9rib');
      case PhaseElection.terminee:
        final DateTime? prochaine =
            ElectionRepository.prochaineElection(election);
        if (prochaine == null) {
          return tr('Résultat en attente', 'El natija mazelet');
        }
        final String leader =
            election.elusNoms.isEmpty ? '' : '${election.elusNoms.first} · ';
        final String date = ElectionRepository.dateCourte(prochaine);
        return tr('${leader}Prochaine élection : $date',
            '${leader}El intikhabet el jeya : $date');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) {
      return const SizedBox.shrink();
    }
    final String? alerte = _alerteAdmin();
    if (widget.alerteSeulement && alerte == null) {
      return const SizedBox.shrink();
    }
    final Election? election = _election;
    final bool enCours =
        election != null && election.phase() != PhaseElection.terminee;
    final bool enAvant = enCours || alerte != null;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.alerteSeulement ? 20 : 16),
      child: Material(
        color: enAvant ? AppColors.secondaryLight : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          key: const Key('carteElection'),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: _ouvrir,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  alerte != null
                      ? Icons.notification_important_outlined
                      : Icons.how_to_vote_outlined,
                  size: 32,
                  color: enAvant ? AppColors.secondary : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Élection du leader', 'Intikhabet el leader'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(alerte ?? _etat()),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
