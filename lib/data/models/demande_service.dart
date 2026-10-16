import 'statut_demande.dart';

/// M2 - Une demande faite par un voisin pour un service.
class DemandeService {
  final String id;
  final String serviceId; // id du Service demandé
  final String demandeur; // nom du voisin qui demande
  final String auteurService; // nom du voisin qui a publié le service
  final StatutDemande statut;
  final DateTime dateDemande;
  final bool evaluee; // true une fois que le demandeur a évalué le service

  const DemandeService({
    required this.id,
    required this.serviceId,
    required this.demandeur,
    required this.auteurService,
    required this.statut,
    required this.dateDemande,
    this.evaluee = false,
  });

  /// Copie de la demande avec le statut ou "évaluée" changés.
  DemandeService copyWith({StatutDemande? statut, bool? evaluee}) {
    return DemandeService(
      id: id,
      serviceId: serviceId,
      demandeur: demandeur,
      auteurService: auteurService,
      statut: statut ?? this.statut,
      dateDemande: dateDemande,
      evaluee: evaluee ?? this.evaluee,
    );
  }
}
