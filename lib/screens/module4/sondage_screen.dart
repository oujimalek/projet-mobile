import 'package:flutter/material.dart';

import '../../data/models/sondage.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

/// M4 - Événements : sondage entre voisins.
///
/// StatefulWidget : quand l'utilisateur choisit une option puis confirme,
/// le nombre de votes et les barres de pourcentage se mettent à jour.
class SondageScreen extends StatefulWidget {
  const SondageScreen({super.key});

  @override
  State<SondageScreen> createState() {
    return _SondageScreenState();
  }
}

class _SondageScreenState extends State<SondageScreen> {
  final Sondage _sondage = EvenementRepository().getSondageActif();

  // Nombre de votes de chaque option (copié depuis le sondage au départ)
  final List<int> _votes = [];

  int? _choix; // index de l'option choisie, null = aucune
  bool _aVote = false; // true une fois le vote confirmé

  @override
  void initState() {
    super.initState();
    // On copie les votes du repository pour pouvoir les modifier ici
    for (final option in _sondage.options) {
      _votes.add(option.votes);
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
  String _sousTitre() {
    // Nombre de jours entre aujourd'hui et la date de fin (sans les heures)
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime fin = _sondage.dateFin;
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

    if (_sondage.proposePar.isEmpty) {
      return 'Sondage du quartier · $finTexte';
    }
    return 'Proposé par ${_sondage.proposePar} · $finTexte';
  }

  /// Texte sous les options : "22 votes sur 46 membres".
  String _texteTotal() {
    if (_sondage.nombreMembres > 0) {
      return '${_totalVotes()} votes sur ${_sondage.nombreMembres} membres';
    }
    return '${_totalVotes()} votes au total';
  }

  /// Appelé quand on touche "Confirmer mon vote".
  void _confirmerVote() {
    final int? choix = _choix;
    if (choix == null) {
      return;
    }
    setState(() {
      _votes[choix]++; // on ajoute notre vote à l'option choisie
      _aVote = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le bouton est désactivé (null) tant qu'on n'a rien choisi ou après le vote
    Function()? actionBouton;
    if (_choix != null && !_aVote) {
      actionBouton = _confirmerVote;
    }

    // Une carte par option, construites avec une boucle
    final List<Widget> cartesOptions = [];
    for (int i = 0; i < _sondage.options.length; i++) {
      cartesOptions.add(_carteOption(i));
    }

    return Scaffold(
      // Barre du haut claire, comme sur la maquette
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        centerTitle: false,
        title: const Text('Sondage'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        children: [
          // ----- Question + options (partie qui défile) -----
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _sondage.question,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _sousTitre(),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Column(children: cartesOptions),
                const SizedBox(height: 8),
                Text(
                  _texteTotal(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
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
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  texte: _aVote ? 'Vote enregistré' : 'Confirmer mon vote',
                  onPressed: actionBouton,
                ),
                TextButton(
                  onPressed: () {
                    // Proposer une autre date : à venir
                  },
                  child: const Text(
                    'Proposer une autre date',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La carte d'une option : rond de sélection, texte, votes et barre.
  Widget _carteOption(int index) {
    final OptionSondage option = _sondage.options[index];
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
            color: choisie ? AppColors.primaryLight : AppColors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: choisie ? AppColors.primary : AppColors.border,
              width: choisie ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Rond de sélection (anneau teal épais quand choisi)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: choisie ? AppColors.primary : AppColors.border,
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
                  Text(
                    '${_votes[index]} votes',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Barre de pourcentage
              LinearProgressIndicator(
                value: pourcentage,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: AppColors.border,
                color: choisie ? AppColors.primary : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
