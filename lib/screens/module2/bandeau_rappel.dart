import 'package:flutter/material.dart';

import '../../data/models/creneau_commun.dart';
import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import 'inscription_creneau_screen.dart';
import 'module2_outils.dart';
import 'tours_en_direct.dart';

/// M2 - Bandeau « Rappel : demain, tu es de service pour ... » (dans
/// l'application, sans notification système).
///
/// Affiché en haut de l'écran Services et du planning quand l'utilisateur
/// connecté a un créneau aujourd'hui ou demain (créneau où il est inscrit, ou
/// tour calculé à son nom). Le bouton « Voir » ouvre le créneau. S'il n'y a
/// rien à rappeler, ou si la lecture échoue, il ne prend aucune place.
class BandeauRappel extends StatefulWidget {
  const BandeauRappel({super.key});

  @override
  State<BandeauRappel> createState() {
    return _BandeauRappelState();
  }
}

class _BandeauRappelState extends State<BandeauRappel> {
  final ServiceRepository _repository = ServiceRepository();

  // Flux créés UNE fois
  late final Stream<List<Service>> _fluxServices = _repository.ecouterServices();
  late final Stream<List<CreneauCommun>> _fluxCreneaux =
      _repository.ecouterCreneauxDeLaSemaine(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Service>>(
      stream: _fluxServices,
      builder: (context, servicesInstantane) {
        final List<Service> services = servicesInstantane.data ?? const [];
        return ToursEnDirect(
          services: services,
          construire: (context, donnees) {
            return StreamBuilder<List<CreneauCommun>>(
              stream: _fluxCreneaux,
              builder: (context, creneauxInstantane) {
                final List<RappelCreneau> rappels = ServiceRepository.rappelsPour(
                  services: services,
                  tours: donnees.tours,
                  creneaux: creneauxInstantane.data ?? const [],
                  moiId: _repository.getMonId(),
                  maintenant: DateTime.now(),
                );
                if (rappels.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      for (final RappelCreneau rappel in rappels)
                        _ligne(context, rappel),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _ligne(BuildContext context, RappelCreneau rappel) {
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
              rappel.texte,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              ouvrirEcran(
                context,
                InscriptionCreneauScreen(creneauId: rappel.creneau.id),
              );
            },
            child: const Text('Voir'),
          ),
        ],
      ),
    );
  }
}
