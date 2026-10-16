import '../services/firestore_commun.dart';
import 'statut_demande.dart';

/// M2 - Une demande faite par un voisin pour un service.
///
/// Firestore : quartiers/{q}/demandes/{id} (voir docs/schema_firestore.md).
class DemandeService {
  final String id;
  final String serviceId; // id du Service demandé
  final String serviceTitre; // titre recopié pour la liste
  final String demandeurId; // uid du voisin qui demande
  final String demandeurNom; // nom court du demandeur
  final String auteurServiceId; // uid du voisin qui a publié le service
  final String auteurServiceNom; // nom court de l'auteur du service
  final StatutDemande statut;
  final DateTime dateDemande;
  final bool evaluee; // true une fois que le demandeur a évalué le service

  const DemandeService({
    required this.id,
    required this.serviceId,
    required this.demandeurId,
    required this.demandeurNom,
    required this.auteurServiceId,
    required this.auteurServiceNom,
    required this.statut,
    required this.dateDemande,
    this.serviceTitre = '',
    this.evaluee = false,
  });

  /// Anciens noms des champs (noms affichés).
  String get demandeur => demandeurNom;
  String get auteurService => auteurServiceNom;

  /// Copie de la demande avec le statut ou "évaluée" changés.
  DemandeService copyWith({StatutDemande? statut, bool? evaluee}) {
    return DemandeService(
      id: id,
      serviceId: serviceId,
      serviceTitre: serviceTitre,
      demandeurId: demandeurId,
      demandeurNom: demandeurNom,
      auteurServiceId: auteurServiceId,
      auteurServiceNom: auteurServiceNom,
      statut: statut ?? this.statut,
      dateDemande: dateDemande,
      evaluee: evaluee ?? this.evaluee,
    );
  }

  /// Les champs enregistrés dans Firestore (l'id est le nom du document).
  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'serviceTitre': serviceTitre,
      'demandeurId': demandeurId,
      'demandeurNom': demandeurNom,
      'auteurServiceId': auteurServiceId,
      'auteurServiceNom': auteurServiceNom,
      'statut': statut.name, // enum → texte, ex : "enAttente"
      'dateDemande': dateDemande, // DateTime → Timestamp
      'evaluee': evaluee,
    };
  }

  /// Construit une demande à partir d'un document Firestore.
  factory DemandeService.fromMap(String id, Map<String, dynamic> map) {
    return DemandeService(
      id: id,
      serviceId: map['serviceId'] ?? '',
      serviceTitre: map['serviceTitre'] ?? '',
      demandeurId: map['demandeurId'] ?? '',
      demandeurNom: map['demandeurNom'] ?? '',
      auteurServiceId: map['auteurServiceId'] ?? '',
      auteurServiceNom: map['auteurServiceNom'] ?? '',
      statut: FirestoreCommun.lireEnum(
        StatutDemande.values,
        map['statut'],
        StatutDemande.enAttente,
      ),
      dateDemande:
          FirestoreCommun.lireDate(map['dateDemande']) ?? DateTime.now(),
      evaluee: map['evaluee'] ?? false,
    );
  }
}
