import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/models/sondage.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_badge.dart';
import 'graphique_sondage.dart';

/// M4 - Événements : sondage entre voisins.
///
/// StatefulWidget : au chargement, on lit le sondage en cours et son vote
/// éventuel ; quand l'utilisateur confirme, le vote est enregistré et les
/// barres de pourcentage se mettent à jour.
class SondageScreen extends StatefulWidget {
  /// Le sondage à afficher ; null = le sondage en cours (accueil, démo).
  final String? sondageId;

  const SondageScreen({super.key, this.sondageId});

  @override
  State<SondageScreen> createState() {
    return _SondageScreenState();
  }
}

class _SondageScreenState extends State<SondageScreen> {
  final EvenementRepository _depot = EvenementRepository();

  Sondage? _sondage; // null : pas de sondage ouvert
  String? _erreur; // message si le chargement a échoué
  bool _enChargement = true; // chargement du sondage
  bool _envoiEnCours = false; // envoi du vote

  // Nombre de votes de chaque option (copié depuis le sondage au départ)
  final List<int> _votes = [];

  int? _choix; // index de l'option choisie, null = aucune
  bool _aVote = false; // true une fois le vote confirmé

  // Votes en direct : les barres bougent quand un voisin vote
  StreamSubscription<List<int>>? _ecoute;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _ecoute?.cancel();
    super.dispose();
  }

  /// Écoute les votes du sondage (remplace l'écoute précédente).
  void _ecouterVotes(Sondage sondage) {
    _ecoute?.cancel();
    _ecoute = _depot
        .ecouterVotes(sondage.id, sondage.options.length)
        .listen((compteurs) {
      if (!mounted) {
        return;
      }
      setState(() {
        _votes
          ..clear()
          ..addAll(compteurs);
      });
    });
  }

  /// Lit le sondage en cours, puis le vote de l'utilisateur.
  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    final Resultat<List<Sondage>> resultat = await _depot.chargerSondages();
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

    // Le sondage demandé, sinon le sondage en cours
    Sondage? sondage;
    if (widget.sondageId == null) {
      sondage = _depot.getSondageActif();
    } else {
      for (final Sondage candidat in resultat.donnee!) {
        if (candidat.id == widget.sondageId) {
          sondage = candidat;
        }
      }
    }
    int? monVote;
    if (sondage != null) {
      final Resultat<int?> vote = await _depot.getMonVote(sondage.id);
      if (!mounted) {
        return;
      }
      monVote = vote.donnee;
    }

    setState(() {
      _enChargement = false;
      _sondage = sondage;
      _votes.clear();
      if (sondage != null) {
        // On copie les votes du repository pour pouvoir les modifier ici
        for (final option in sondage.options) {
          _votes.add(option.votes);
        }
      }
      _choix = monVote;
      _aVote = monVote != null;
    });
    if (sondage != null) {
      _ecouterVotes(sondage);
    }
  }

  /// Nombre total de votes (toutes options confondues).
  int _totalVotes() {
    int total = 0;
    for (final nombre in _votes) {
      total += nombre;
    }
    return total;
  }

  /// Sous-titre : "Proposé par l'admin · se termine dans 2 jours".
  String _sousTitre(Sondage sondage) {
    // Nombre de jours entre aujourd'hui et la date de fin (sans les heures)
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime fin = sondage.dateFin;
    final DateTime jourFin = DateTime(fin.year, fin.month, fin.day);
    final int jours = jourFin.difference(aujourdhui).inDays;

    String finTexte;
    if (jours < 0) {
      finTexte = 'terminé';
    } else if (jours == 0) {
      finTexte = 'se termine aujourd\'hui';
    } else if (jours == 1) {
      finTexte = 'se termine demain';
    } else {
      finTexte = 'se termine dans $jours jours';
    }

    if (sondage.proposePar.isEmpty) {
      return 'Sondage du quartier · $finTexte';
    }
    return 'Proposé par ${sondage.proposePar} · $finTexte';
  }

  /// "1 vote", "3 votes" (0 et 1 : singulier).
  String _texteVotes(int nombre) {
    return nombre > 1 ? '$nombre votes' : '$nombre vote';
  }

  /// Texte sous les options : "22 votes sur 46 membres".
  String _texteTotal(Sondage sondage) {
    if (sondage.nombreMembres > 0) {
      return '${_texteVotes(_totalVotes())} sur ${sondage.nombreMembres} membres';
    }
    return '${_texteVotes(_totalVotes())} au total';
  }

  /// Les résultats par choix sont cachés tant que je n'ai pas voté
  /// (pour ne pas influencer le vote), et montrés à la fin du sondage.
  bool _resultatsVisibles(Sondage sondage) {
    return _aVote || !sondage.estOuvert;
  }

  /// "Plus que 1 j 5 h · 12 voisins n'ont pas encore voté"
  String _texteParticipation(Sondage sondage) {
    final Duration reste = sondage.dateFin.difference(DateTime.now());
    String temps;
    if (reste.inDays >= 1) {
      temps = 'Plus que ${reste.inDays} j ${reste.inHours % 24} h';
    } else if (reste.inHours >= 1) {
      temps = 'Plus que ${reste.inHours} h ${reste.inMinutes % 60} min';
    } else {
      temps = 'Plus que ${reste.inMinutes} min';
    }
    final int restants = sondage.nombreMembres - _totalVotes();
    if (sondage.nombreMembres <= 0 || restants <= 0) {
      return temps;
    }
    return '$temps · $restants voisin${restants > 1 ? 's n\'ont' : ' n\'a'} pas encore voté';
  }

  /// Appelé quand on touche "Confirmer mon vote" : enregistre le vote.
  Future<void> _confirmerVote() async {
    final int? choix = _choix;
    final Sondage? sondage = _sondage;
    if (choix == null || sondage == null) {
      return;
    }
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat = await _depot.voter(sondage, choix);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }
    // Les nombres de votes arrivent par l'écoute en direct (_ecouterVotes)
    setState(() {
      _aVote = true;
    });
  }

  /// L'auteur ou l'admin supprime le sondage (après confirmation).
  Future<void> _supprimer() async {
    final Sondage? sondage = _sondage;
    if (sondage == null) {
      return;
    }
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer le sondage ?'),
          content: const Text('Les votes seront perdus. Cette action est définitive.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Supprimer', style: TextStyle(color: AppColors.error)),
            ),
          ],
        );
      },
    );
    if (confirme != true || !mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat = await _depot.supprimerSondage(sondage.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }
    // Ouvert depuis la liste : on y retourne. Depuis l'onglet : on recharge.
    if (widget.sondageId != null && Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Sondage? sondage = _sondage;

    // Chargement, erreur ou aucun sondage : un message au centre
    Widget? message;
    if (_enChargement) {
      message = const CircularProgressIndicator();
    } else if (_erreur != null) {
      message = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_erreur!, textAlign: TextAlign.center),
          TextButton(onPressed: _charger, child: const Text('Réessayer')),
        ],
      );
    } else if (sondage == null) {
      message = Text(
        'Aucun sondage en cours dans ta houma',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    if (message != null || sondage == null) {
      return Scaffold(
        body: Column(
          children: [
            const AppHeader(titre: 'Sondage'),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: message,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Le bouton est désactivé (null) tant qu'on n'a rien choisi, pendant
    // l'envoi ou après le vote
    Function()? actionBouton;
    if (_choix != null && !_aVote && !_envoiEnCours && sondage.estOuvert) {
      actionBouton = _confirmerVote;
    }

    // Une carte par option, construites avec une boucle
    final List<Widget> cartesOptions = [];
    for (int i = 0; i < sondage.options.length; i++) {
      cartesOptions.add(_carteOption(sondage, i));
    }

    // Badge "En cours" tant que le sondage n'est pas terminé
    final StatutSignalement statut = sondage.estOuvert
        ? StatutSignalement.enCours
        : StatutSignalement.resolu;

    return Scaffold(
      body: Column(
        children: [
          // En-tête blanc arrondi, comme sur la maquette ; l'auteur et
          // l'admin peuvent supprimer le sondage
          AppHeader(
            titre: 'Sondage',
            action: EvenementRepository.peutSupprimer(
                    UtilisateurRepository().getUtilisateurConnecte(),
                    sondage.proposeParId)
                ? IconButton(
                    tooltip: 'Supprimer le sondage',
                    icon: Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: _envoiEnCours ? null : _supprimer,
                  )
                : null,
          ),

          // ----- Question + options (partie qui défile) -----
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  sondage.question,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Wrap : le badge passe à la ligne si le sous-titre est long
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(statut: statut),
                    Text(
                      _sousTitre(sondage),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                // Compte à rebours + voisins qui n'ont pas encore voté
                if (sondage.estOuvert) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 18, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _texteParticipation(sondage),
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Column(children: cartesOptions),
                if (!_resultatsVisibles(sondage))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Vote pour voir les résultats',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  _texteTotal(sondage),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                // Camembert des résultats (quand ils sont visibles)
                if (_resultatsVisibles(sondage)) ...[
                  const SizedBox(height: 16),
                  GraphiqueSondage(
                    choix: [for (final option in sondage.options) option.texte],
                    votes: List.of(_votes),
                  ),
                ],
              ],
            ),
          ),

          // ----- Boutons fixes en bas -----
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              children: [
                Text(
                  _aVote ? 'Yaatik saha, ton vote est enregistré !' : '',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  texte: !sondage.estOuvert && !_aVote
                      ? 'Sondage terminé'
                      : (_aVote ? 'Vote enregistré' : 'Confirmer mon vote'),
                  onPressed: actionBouton,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La carte d'une option : rond de sélection, texte, votes et barre.
  Widget _carteOption(Sondage sondage, int index) {
    final OptionSondage option = sondage.options[index];
    final bool choisie = _choix == index;

    // Pourcentage de cette option (entre 0 et 1) pour la barre
    final int total = _totalVotes();
    double pourcentage = 0;
    if (total > 0) {
      pourcentage = _votes[index] / total;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        onTap: () {
          // Après le vote, on ne peut plus changer d'option
          if (!_aVote) {
            setState(() {
              _choix = index;
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: choisie ? AppColors.secondaryLight : AppColors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: choisie ? AppColors.secondary : AppColors.border,
              width: choisie ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Rond de sélection (anneau doré épais quand choisi)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: choisie ? AppColors.secondary : AppColors.border,
                        width: choisie ? 6 : 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.texte,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Résultats cachés avant mon vote
                  if (_resultatsVisibles(sondage))
                    Text(
                      _texteVotes(_votes[index]),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
              if (_resultatsVisibles(sondage)) ...[
                const SizedBox(height: 12),

                // Barre de pourcentage (animée quand les votes changent)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: pourcentage),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, valeur, enfant) {
                    return LinearProgressIndicator(
                      value: valeur,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: AppColors.border,
                      color: choisie
                          ? AppColors.secondary
                          : AppColors.textSecondary,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
