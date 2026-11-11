import '../services/firestore_commun.dart';

/// M4 - Le type d'un événement. Firestore : `categorie.name` (ex "fete").
/// L'icône et la couleur restent dans le code (module4_widgets.dart).
enum CategorieEvenement {
  fete,
  reunion,
  nettoyage,
  sport,
  culture,
  autre;

  /// Le nom affiché : "Fête", "Réunion"...
  String get libelle {
    switch (this) {
      case CategorieEvenement.fete:
        return 'Fête';
      case CategorieEvenement.reunion:
        return 'Réunion';
      case CategorieEvenement.nettoyage:
        return 'Nettoyage';
      case CategorieEvenement.sport:
        return 'Sport';
      case CategorieEvenement.culture:
        return 'Culture';
      case CategorieEvenement.autre:
        return 'Autre';
    }
  }
}

/// M4 - Un événement du quartier (fête, réunion, nettoyage...).
///
/// Firestore : quartiers/{quartierId}/evenements/{id}
/// (voir docs/schema_firestore.md). Les participants sont rangés dans la
/// sous-collection participants/{uid} ; [participants] est le compteur
/// `nbParticipants`, protégé par les règles (+1 / -1 avec sa fiche).
class Evenement {
  final String id;
  final String titre;
  final String description;
  final DateTime date; // début
  final DateTime? dateFin; // fin (optionnelle), le même jour ou après
  final String lieu;
  final CategorieEvenement categorie;
  final String organisateurId; // uid de l'organisateur (règles de sécurité)
  final String organisateur; // son nom, recopié pour l'affichage (Firestore : organisateurNom)
  final int participants; // Firestore : nbParticipants
  final bool annule; // annulé : reste visible avec un badge, plus d'inscription
  final bool officiel; // créé par l'admin : badge "Officiel", en tête de liste

  const Evenement({
    required this.id,
    required this.titre,
    required this.description,
    required this.date,
    this.dateFin,
    required this.lieu,
    this.categorie = CategorieEvenement.autre,
    this.organisateurId = '',
    required this.organisateur,
    this.participants = 0,
    this.annule = false,
    this.officiel = false,
  });

  /// true si l'événement est terminé (sa fin, ou son début s'il n'a pas de fin).
  bool get estPasse => (dateFin ?? date).isBefore(DateTime.now());

  /// Le document Firestore (l'id n'est pas recopié : c'est le nom du document).
  Map<String, dynamic> toMap() {
    return {
      'titre': titre,
      'description': description,
      'date': date,
      'dateFin': dateFin, // null si pas d'heure de fin
      'lieu': lieu,
      'categorie': categorie.name,
      'organisateurId': organisateurId,
      'organisateurNom': organisateur,
      'nbParticipants': participants,
      'annule': annule,
      'officiel': officiel,
    };
  }

  factory Evenement.fromMap(String id, Map<String, dynamic> map) {
    return Evenement(
      id: id,
      titre: map['titre'] ?? '',
      description: map['description'] ?? '',
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
      dateFin: FirestoreCommun.lireDate(map['dateFin']),
      lieu: map['lieu'] ?? '',
      categorie: FirestoreCommun.lireEnum(
        CategorieEvenement.values,
        map['categorie'],
        CategorieEvenement.autre,
      ),
      organisateurId: map['organisateurId'] ?? '',
      organisateur: map['organisateurNom'] ?? '',
      participants: map['nbParticipants'] ?? 0,
      annule: map['annule'] ?? false,
      officiel: map['officiel'] ?? false,
    );
  }

  /// Une copie avec quelques champs changés (ex : après une modification).
  /// [sansFin] : true pour retirer l'heure de fin.
  Evenement copyWith({
    String? titre,
    String? description,
    DateTime? date,
    DateTime? dateFin,
    bool sansFin = false,
    String? lieu,
    CategorieEvenement? categorie,
    int? participants,
    bool? annule,
  }) {
    return Evenement(
      id: id,
      titre: titre ?? this.titre,
      description: description ?? this.description,
      date: date ?? this.date,
      dateFin: sansFin ? null : (dateFin ?? this.dateFin),
      lieu: lieu ?? this.lieu,
      categorie: categorie ?? this.categorie,
      organisateurId: organisateurId,
      organisateur: organisateur,
      participants: participants ?? this.participants,
      annule: annule ?? this.annule,
      officiel: officiel,
    );
  }
}

/// M4 - Un participant à un événement (fiche participants/{uid}).
/// [avatar] : l'avatar de la galerie du module 1 (vide : initiales).
class Participant {
  final String id; // uid
  final String nom;
  final String avatar;

  const Participant({required this.id, required this.nom, this.avatar = ''});
}
