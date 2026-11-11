import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import 'evenement_detail_screen.dart';
import 'module4_widgets.dart';
import 'nouveautes_m4.dart';

/// M4 - Bandeau « Rappel : demain à 18:00, Fête des voisins (Jardin) »
/// (dans l'application, sans notification système), comme le bandeau du
/// module 2.
///
/// Affiché sur l'accueil pour les événements où l'utilisateur participe,
/// aujourd'hui ou demain. Le bouton « Voir » ouvre l'événement. S'il n'y a
/// rien à rappeler, ou si la lecture échoue, il ne prend aucune place.
class BandeauRappelM4 extends StatefulWidget {
  const BandeauRappelM4({super.key});

  @override
  State<BandeauRappelM4> createState() {
    return _BandeauRappelM4State();
  }
}

class _BandeauRappelM4State extends State<BandeauRappelM4> {
  final EvenementRepository _depot = EvenementRepository();
  List<Evenement> _rappels = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    // Le point « nouveau » de l'onglet Événements
    NouveautesM4.calculer();
    final Resultat<List<Evenement>> resultat = await _depot.chargerEvenements();
    if (!resultat.estSucces) {
      return; // pas de bandeau si la lecture échoue
    }
    final DateTime maintenant = DateTime.now();
    // On ne vérifie la participation que pour les événements des 2 jours
    final List<Evenement> proches = EvenementRepository.rappels(
      resultat.donnee!,
      {for (final Evenement e in resultat.donnee!) e.id},
      maintenant,
    );
    final Set<String> mesParticipations = {};
    for (final Evenement evenement in proches) {
      final Resultat<bool> inscrit = await _depot.estInscrit(evenement.id);
      if (inscrit.donnee == true) {
        mesParticipations.add(evenement.id);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _rappels =
          EvenementRepository.rappels(proches, mesParticipations, maintenant);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rappels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (final Evenement evenement in _rappels) _ligne(evenement),
        ],
      ),
    );
  }

  Widget _ligne(Evenement evenement) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              EvenementRepository.texteRappel(evenement, DateTime.now()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              ouvrirEcranM4(
                context,
                EvenementDetailScreen(evenementId: evenement.id),
              );
            },
            child: const Text('Voir'),
          ),
        ],
      ),
    );
  }
}
