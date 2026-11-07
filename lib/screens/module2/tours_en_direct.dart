import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/creneau_commun.dart';
import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';

/// M2 - Ce que les écrans ont besoin de savoir sur les rotations.
class DonneesRotation {
  /// idCréneau -> la personne dont c'est le tour (tous les services en rotation).
  final Map<String, TourRotation> tours;

  /// idService -> tous les créneaux de ce service (services en rotation).
  final Map<String, List<CreneauCommun>> creneauxParService;

  const DonneesRotation({required this.tours, required this.creneauxParService});
}

/// M2 - Écoute les créneaux de chaque service en rotation et CALCULE le tour
/// de chacun (ServiceRepository.calculerTours) : rien n'est écrit sur les
/// créneaux. Se met à jour tout seul quand un créneau ou la liste des
/// participants change. Une erreur de lecture est ignorée (pas de tour affiché).
class ToursEnDirect extends StatefulWidget {
  final List<Service> services;
  final Widget Function(BuildContext context, DonneesRotation donnees) construire;

  const ToursEnDirect({
    super.key,
    required this.services,
    required this.construire,
  });

  @override
  State<ToursEnDirect> createState() {
    return _ToursEnDirectState();
  }
}

class _ToursEnDirectState extends State<ToursEnDirect> {
  final ServiceRepository _repository = ServiceRepository();
  final Map<String, StreamSubscription<List<CreneauCommun>>> _abonnements = {};
  final Map<String, List<CreneauCommun>> _listes = {};

  @override
  void initState() {
    super.initState();
    _synchroniser();
  }

  @override
  void didUpdateWidget(ToursEnDirect ancien) {
    super.didUpdateWidget(ancien);
    _synchroniser();
  }

  @override
  void dispose() {
    for (final StreamSubscription<List<CreneauCommun>> abonnement
        in _abonnements.values) {
      abonnement.cancel();
    }
    _abonnements.clear();
    super.dispose();
  }

  /// Un abonnement par service en rotation (créé une seule fois).
  void _synchroniser() {
    final Set<String> voulus = {};
    for (final Service service in widget.services) {
      if (service.estCommun && service.modeRotation) {
        voulus.add(service.id);
      }
    }
    for (final String id in _abonnements.keys.toList()) {
      if (!voulus.contains(id)) {
        _abonnements.remove(id)?.cancel();
        _listes.remove(id);
      }
    }
    for (final String id in voulus) {
      if (_abonnements.containsKey(id)) {
        continue;
      }
      _abonnements[id] = _repository.ecouterCreneauxParService(id).listen(
        (liste) {
          if (mounted) {
            setState(() {
              _listes[id] = liste;
            });
          }
        },
        onError: (Object erreur) {
          // Pas de tour affiché pour ce service, le reste de l'écran marche
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, TourRotation> tours = {};
    for (final Service service in widget.services) {
      final List<CreneauCommun>? liste = _listes[service.id];
      if (service.estCommun && service.modeRotation && liste != null) {
        tours.addAll(ServiceRepository.calculerTours(service, liste));
      }
    }
    return widget.construire(
      context,
      DonneesRotation(tours: tours, creneauxParService: Map.of(_listes)),
    );
  }
}
