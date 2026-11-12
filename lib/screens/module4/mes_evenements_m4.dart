import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'evenement_detail_screen.dart';
import 'module4_widgets.dart';

/// M4 - Section « Mes événements » de l'écran Profil (module 1) : les
/// prochains événements que j'organise ou auxquels je participe.
/// Si rien n'est prévu, une phrase courte ; si la lecture échoue, rien.
class MesEvenementsM4 extends StatefulWidget {
  const MesEvenementsM4({super.key});

  @override
  State<MesEvenementsM4> createState() {
    return _MesEvenementsM4State();
  }
}

class _MesEvenementsM4State extends State<MesEvenementsM4> {
  final EvenementRepository _depot = EvenementRepository();
  List<Evenement> _miens = [];
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final Resultat<List<Evenement>> resultat = await _depot.chargerEvenements();
    if (!resultat.estSucces) {
      return;
    }
    final Utilisateur moi = UtilisateurRepository().getUtilisateurConnecte();
    final List<Evenement> miens = [];
    for (final Evenement evenement in resultat.donnee!) {
      if (evenement.estPasse || evenement.annule) {
        continue;
      }
      if (evenement.organisateurId == moi.id) {
        miens.add(evenement);
        continue;
      }
      final Resultat<bool> inscrit = await _depot.estInscrit(evenement.id);
      if (inscrit.donnee == true) {
        miens.add(evenement);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _miens = miens;
      _charge = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) {
      return const SizedBox.shrink();
    }
    final Utilisateur moi = UtilisateurRepository().getUtilisateurConnecte();
    final List<Widget> lignes = [];
    if (_miens.isEmpty) {
      lignes.add(Text(
        'Aucun événement prévu pour toi.',
        style: TextStyle(color: AppColors.textSecondary),
      ));
    }
    for (final Evenement evenement in _miens.take(5)) {
      lignes.add(
        InkWell(
          onTap: () async {
            await ouvrirEcranM4<void>(
              context,
              EvenementDetailScreen(evenementId: evenement.id),
            );
            if (mounted) {
              _charger();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(iconeCategorie(evenement.categorie),
                    color: couleurCategorie(evenement.categorie)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(evenement.titre,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${texteDate(evenement.date)} · ${texteHoraire(evenement)}',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (evenement.organisateurId == moi.id)
                  BadgeM4(
                    texte: 'J\'organise',
                    couleur: AppColors.primary,
                    fond: AppColors.primaryLight,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mes événements',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lignes,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
