import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/firestore_commun.dart';
import 'quartier.dart';

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
  final int placesMax; // 0 = pas de limite
  final int interesses; // "Peut-être" (Firestore : nbInteresses, compteur protégé)
  final DateTime? dateCreation; // pour le badge « nouveau » (null : ancien événement)
  final PointGps? position; // le lieu exact sur la carte (optionnel)
  final String? photoUrl; // la photo de l'événement (Cloudinary), optionnelle

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
    this.placesMax = 0,
    this.interesses = 0,
    this.dateCreation,
    this.position,
    this.photoUrl,
  });

  /// true si l'événement est terminé (sa fin, ou son début s'il n'a pas de fin).
  bool get estPasse => (dateFin ?? date).isBefore(DateTime.now());

  /// true si toutes les places sont prises.
  bool get estComplet => placesMax > 0 && participants >= placesMax;

  /// Places encore libres (null : pas de limite).
  int? get placesRestantes => placesMax > 0 ? placesMax - participants : null;

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
      'placesMax': placesMax,
      'nbInteresses': interesses,
      'dateCreation': dateCreation ?? DateTime.now(),
      // GeoPoint dans Firestore, comme la position d'un quartier (M1)
      'position': position == null
          ? null
          : GeoPoint(position!.latitude, position!.longitude),
      'photoUrl': photoUrl,
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
      placesMax: map['placesMax'] ?? 0,
      interesses: map['nbInteresses'] ?? 0,
      dateCreation: FirestoreCommun.lireDate(map['dateCreation']),
      position: Quartier.lirePoint(map['position']),
      photoUrl: map['photoUrl'],
    );
  }

  /// Une copie avec quelques champs changés (ex : après une modification).
  /// [sansFin] : true pour retirer l'heure de fin.
  /// [sansPosition] : true pour retirer le point sur la carte.
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
    int? placesMax,
    int? interesses,
    PointGps? position,
    bool sansPosition = false,
    String? photoUrl,
    bool sansPhoto = false,
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
      placesMax: placesMax ?? this.placesMax,
      interesses: interesses ?? this.interesses,
      dateCreation: dateCreation,
      position: sansPosition ? null : (position ?? this.position),
      photoUrl: sansPhoto ? null : (photoUrl ?? this.photoUrl),
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
