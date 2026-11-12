import 'package:flutter/material.dart';

import '../../data/resultat.dart';
import '../../data/services/assistant_ia_m4.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import 'evenement_form_screen.dart';
import 'module4_widgets.dart';
import 'sondage_form_screen.dart';

/// M4 - (IA) La carte « Assistant du leader », en haut de l'onglet
/// Événements (leaders et admin seulement). Elle montre les idées de l'IA
/// pour la houma : événements, sondages et conseil, chacun avec sa raison,
/// et un bouton « Créer » qui ouvre le formulaire déjà rempli.
class AssistantIACarte extends StatefulWidget {
  final String quartierId;

  /// Appelé quand un événement ou un sondage a été créé (pour recharger).
  final VoidCallback? apresCreation;

  const AssistantIACarte({super.key, required this.quartierId, this.apresCreation});

  @override
  State<AssistantIACarte> createState() => _AssistantIACarteState();
}

class _AssistantIACarteState extends State<AssistantIACarte> {
  IdeesIA? _idees;
  bool _enChargement = true;
  bool _actualisation = false;
  bool _ouverte = true; // la carte peut être repliée
  String? _message;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    IdeesIA? idees;
    try {
      final Resultat<IdeesIA?> resultat = await AssistantIAM4.lire(widget.quartierId);
      idees = resultat.donnee;
    } catch (e) {
      idees = null; // pas de Firebase (tests) : carte vide
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _idees = idees;
    });
  }

  Future<void> _actualiser() async {
    setState(() {
      _actualisation = true;
      _message = null;
    });
    final Resultat<IdeesIA> resultat = await AssistantIAM4.actualiser(widget.quartierId);
    if (!mounted) {
      return;
    }
    setState(() {
      _actualisation = false;
      if (resultat.estSucces) {
        _idees = resultat.donnee;
      } else {
        _message = resultat.erreur;
      }
    });
  }

  Future<void> _creer(SuggestionIA idee) async {
    final Widget ecran = idee.estSondage
        ? SondageFormScreen(questionInitiale: idee.titre, choixInitiaux: idee.choix)
        : EvenementFormScreen(
            titreInitial: idee.titre,
            dateInitiale: idee.date,
            categorieInitiale: idee.categorie,
          );
    final Object? cree = await ouvrirEcranM4<Object>(context, ecran);
    if (cree == true) {
      widget.apresCreation?.call();
    }
  }

  /// "il y a 3 jours", "aujourd'hui"...
  String _quand(DateTime date) {
    final int jours = DateTime.now().difference(date).inDays;
    if (jours <= 0) {
      return tr('aujourd\'hui', 'lyoum');
    }
    if (jours == 1) {
      return tr('hier', 'lbere7');
    }
    return tr('il y a $jours jours', 'hedhi $jours ayyem');
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> enfants = [
      Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Assistant du leader', 'Moussa3ed el leader'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Nouvelles idées',
            onPressed: _actualisation ? null : _actualiser,
            icon: _actualisation
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh, color: AppColors.primary),
          ),
          IconButton(
            tooltip: _ouverte ? 'Replier' : 'Déplier',
            onPressed: () => setState(() => _ouverte = !_ouverte),
            icon: Icon(_ouverte ? Icons.expand_less : Icons.expand_more,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    ];

    if (_ouverte) {
      final IdeesIA? idees = _idees;
      if (_enChargement) {
        enfants.add(const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()),
        ));
      } else if (idees == null || idees.suggestions.isEmpty) {
        enfants.add(Text(
          _actualisation
              ? tr('L\'IA analyse ta houma...', 'El IA t7allel fi houmtek...')
              : tr('Appuie sur ↻ : l\'IA analyse ta houma (événements passés, '
                  'participation, saison, fêtes) et te propose des idées.',
                  'Inzel 3la ↻ : el IA t7allel houmtek w taatik afkar.'),
          style: TextStyle(color: AppColors.textSecondary),
        ));
      } else {
        if (idees.date != null) {
          enfants.add(Text(
            '${tr('Analyse', 'Ta7lil')} ${_quand(idees.date!)} · ${tr('nouvelles idées chaque lundi', 'afkar jdod kol thnin')}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ));
        }
        for (final SuggestionIA idee in idees.suggestions) {
          enfants.add(_idee(idee));
        }
      }
      if (_message != null) {
        enfants.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_message!, style: TextStyle(color: AppColors.error)),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants),
      ),
    );
  }

  Widget _idee(SuggestionIA idee) {
    final IconData icone = idee.estEvenement
        ? iconeCategorie(idee.categorie)
        : idee.estSondage
            ? Icons.poll_outlined
            : Icons.lightbulb_outline;
    String sousTitre = idee.raison;
    if (idee.estEvenement && idee.date != null) {
      sousTitre = '${texteDate(idee.date!)} · ${texteHeure(idee.date!)}\n${idee.raison}';
    } else if (idee.estSondage) {
      sousTitre = '${idee.choix.join(' · ')}\n${idee.raison}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(idee.titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sousTitre,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (!idee.estSondage && !idee.estEvenement)
            const SizedBox.shrink()
          else
            TextButton(
              onPressed: () => _creer(idee),
              child: Text(tr('Créer', 'A3mel')),
            ),
        ],
      ),
    );
  }
}
