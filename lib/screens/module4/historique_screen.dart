import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/services/base_locale_m4.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import 'module4_widgets.dart';

/// M4 - (SQLite) « Mon historique » : mes participations, présences (QR) et
/// notes, gardées sur MON téléphone, avec un bilan calculé en SQL
/// (COUNT, AVG, GROUP BY) et un filtre par catégorie.
class HistoriqueScreen extends StatefulWidget {
  const HistoriqueScreen({super.key});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  BilanHistorique? _bilan;
  List<LigneHistorique> _lignes = [];
  CategorieEvenement? _filtre; // null = toutes les catégories
  bool _enChargement = true;

  static const List<String> _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final BilanHistorique bilan = await BaseLocaleM4.bilan();
    final List<LigneHistorique> lignes =
        await BaseLocaleM4.historique(categorie: _filtre);
    if (!mounted) {
      return;
    }
    setState(() {
      _bilan = bilan;
      _lignes = lignes;
      _enChargement = false;
    });
  }

  /// "2026-11" -> "novembre 2026"
  String _nomMois(String cle) {
    final List<String> morceaux = cle.split('-');
    final int? m = morceaux.length == 2 ? int.tryParse(morceaux[1]) : null;
    if (m == null || m < 1 || m > 12) {
      return cle;
    }
    return '${_mois[m - 1]} ${morceaux[0]}';
  }

  Widget _chiffre(String valeur, String libelle, Color couleur) {
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valeur,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: couleur)),
            const SizedBox(height: 4),
            Text(libelle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BilanHistorique? bilan = _bilan;
    Widget corps;
    if (_enChargement || bilan == null) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (bilan.nbParticipations == 0) {
      corps = MessageM4(
        texte: tr('Ton historique est vide.\nInscris-toi à un événement : il sera gardé ici, sur ton téléphone.',
            'Historique mte3ek fergh.'),
        icone: Icons.history,
      );
    } else {
      final List<Widget> enfants = [
        Row(children: [
          _chiffre('${bilan.nbParticipations}', bilan.nbParticipations > 1 ? 'événements' : 'événement', AppColors.primary),
          const SizedBox(width: 10),
          _chiffre('${bilan.tauxPresence} %', tr('présence (QR)', '7odhour (QR)'), AppColors.success),
          const SizedBox(width: 10),
          _chiffre(
              bilan.moyenneNotes == null ? '-' : '${bilan.moyenneNotes!.toStringAsFixed(1)} ★',
              tr('mes notes', 'notet mte3i'),
              AppColors.secondary),
        ]),
      ];
      final CategorieEvenement? preferee = bilan.categoriePreferee;
      if (preferee != null) {
        enfants.add(const SizedBox(height: 12));
        enfants.add(Row(children: [
          Icon(iconeCategorie(preferee), color: AppColors.primary),
          const SizedBox(width: 8),
          Text('${tr('Ta catégorie préférée', 'El catégorie elli t7ebha')} : ${preferee.libelle}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]));
      }
      // Par mois
      enfants.add(const SizedBox(height: 16));
      enfants.add(Text(tr('Par mois', 'Kol chhar'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)));
      bilan.parMois.forEach((cle, n) {
        enfants.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${_nomMois(cle)} : $n événement${n > 1 ? 's' : ''}'),
        ));
      });
      // Filtre par catégorie
      enfants.add(const SizedBox(height: 16));
      final List<Widget> puces = [
        ChoiceChip(
          label: Text(tr('Toutes', 'Lkol')),
          selected: _filtre == null,
          onSelected: (_) {
            _filtre = null;
            _charger();
          },
        ),
      ];
      for (final CategorieEvenement c in CategorieEvenement.values) {
        puces.add(ChoiceChip(
          label: Text(c.libelle),
          selected: _filtre == c,
          onSelected: (_) {
            _filtre = c;
            _charger();
          },
        ));
      }
      enfants.add(Wrap(spacing: 8, runSpacing: 4, children: puces));
      enfants.add(const SizedBox(height: 8));
      if (_lignes.isEmpty) {
        enfants.add(Text(tr('Rien dans cette catégorie.', 'Ma famma chay.'),
            style: TextStyle(color: AppColors.textSecondary)));
      }
      for (final LigneHistorique ligne in _lignes) {
        enfants.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppCard(
            child: Row(
              children: [
                Icon(iconeCategorie(ligne.categorie), color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ligne.titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(texteDate(ligne.date),
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                if (ligne.present)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.how_to_reg, color: AppColors.success, size: 20),
                  ),
                if (ligne.note != null)
                  Text('${ligne.note} ★',
                      style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ));
      }
      enfants.add(const SizedBox(height: 12));
      enfants.add(Text(
        tr('Gardé seulement sur ce téléphone (base SQLite).', 'Mkhabi ken 3al telifoun hedha.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ));
      corps = ListView(padding: const EdgeInsets.all(20), children: enfants);
    }
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Mon historique', 'Historique mte3i')),
          Expanded(child: corps),
        ],
      ),
    );
  }
}
