import 'package:flutter/material.dart';

import '../../data/services/base_locale_m4.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import 'evenement_form_screen.dart';
import 'module4_widgets.dart';

/// M4 - (SQLite) « Mes brouillons » : les événements commencés mais pas
/// encore publiés, gardés sur le téléphone. On les reprend ou on les supprime.
/// Renvoie `true` (Navigator.pop) si un événement a été publié.
class BrouillonsScreen extends StatefulWidget {
  const BrouillonsScreen({super.key});

  @override
  State<BrouillonsScreen> createState() => _BrouillonsScreenState();
}

class _BrouillonsScreenState extends State<BrouillonsScreen> {
  List<BrouillonEvenement> _brouillons = [];
  bool _enChargement = true;
  bool _publie = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final List<BrouillonEvenement> liste = await BaseLocaleM4.brouillons();
    if (!mounted) {
      return;
    }
    setState(() {
      _brouillons = liste;
      _enChargement = false;
    });
  }

  Future<void> _reprendre(BrouillonEvenement brouillon) async {
    final bool? publie = await ouvrirEcranM4<bool>(
        context, EvenementFormScreen(brouillon: brouillon));
    if (publie == true) {
      _publie = true;
    }
    _charger();
  }

  Future<void> _supprimer(BrouillonEvenement brouillon) async {
    final bool? oui = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Supprimer le brouillon ?', 'Tfasa5 el brouillon ?')),
        content: Text(brouillon.titre.isEmpty ? '(sans titre)' : brouillon.titre),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Annuler', 'Batel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Supprimer', 'Fasakh'),
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    final int? id = brouillon.id;
    if (oui != true || id == null) {
      return;
    }
    await BaseLocaleM4.supprimerBrouillon(id);
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    Widget corps;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_brouillons.isEmpty) {
      corps = MessageM4(
        texte: tr('Aucun brouillon.\nUn événement commencé et pas publié est gardé ici.',
            'Ma famma 7atta brouillon.'),
        icone: Icons.drafts_outlined,
      );
    } else {
      final List<Widget> cartes = [];
      for (final BrouillonEvenement brouillon in _brouillons) {
        final DateTime? debut = brouillon.debut;
        cartes.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            onTap: () => _reprendre(brouillon),
            child: Row(
              children: [
                Icon(iconeCategorie(brouillon.categorie), color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brouillon.titre.isEmpty ? '(sans titre)' : brouillon.titre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${debut == null ? tr('Date à choisir', 'Date mazelet') : texteDate(debut)}'
                        ' · ${tr('modifié le', 'tbaddel')} ${texteDate(brouillon.majLe)}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _supprimer(brouillon),
                ),
              ],
            ),
          ),
        ));
      }
      corps = ListView(padding: const EdgeInsets.all(20), children: cartes);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, resultat) {
        if (!aQuitte) {
          Navigator.of(context).pop(_publie);
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            AppHeader(titre: tr('Mes brouillons', 'Brouillonet mte3i')),
            Expanded(child: corps),
          ],
        ),
      ),
    );
  }
}
