import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter/material.dart';

import '../services/firestore_commun.dart';
import 'quartier.dart' show PointGps; // M1 : point GPS (import seulement)

/// Les 4 statuts possibles d'un signalement (affichés avec StatusBadge).
enum StatutSignalement { enAttente, enCours, resolu, refuse }

/// Le niveau d'urgence d'un signalement. Il est CALCULÉ dans l'application
/// (voir SignalementRepository.niveauUrgence), jamais rangé dans Firestore.
enum NiveauUrgence { faible, normal, urgent }

/// M3 - Une catégorie de signalement (électricité, eau, ordures...).
/// Chaque catégorie a son icône et ses deux couleurs (normale + très claire).
class CategorieSignalement {
  final String id;
  final String nom;
  final IconData icone;
  final Color couleur;
  final Color couleurClaire;

  const CategorieSignalement({
    required this.id,
    required this.nom,
    required this.icone,
    required this.couleur,
    required this.couleurClaire,
  });
}

/// M3 - Un signalement d'un événement du quotidien (coupure, travaux...).
///
/// Firestore : quartiers/{quartierId}/signalements/{id}
/// (voir docs/schema_firestore.md, section 5).
class Signalement {
  final String id; // id du document Firestore (pas écrit dans le document)
  final String titre;
  final String description;
  final String categorieId; // id d'une CategorieSignalement
  final StatutSignalement statut;
  final DateTime date;
  final String lieu;
  final String auteurId; // uid de l'auteur (vérifié par firestore.rules)
  final String auteurNom; // nom recopié pour l'affichage, ex : "Amira B."
  final int nbConfirmations; // nombre de voisins qui ont dit "Sa7, ena zeda"
  final bool danger; // "Danger pour les personnes" (compte dans l'urgence)
  final String? photoUrl; // pour plus tard (pas encore enregistrée)
  // Point GPS ("Utiliser ma position"), optionnel. `lieu` reste le texte
  // lisible (adresse trouvée ou écrite par l'utilisateur).
  final PointGps? position;

  const Signalement({
    required this.id,
    required this.titre,
    required this.description,
    required this.categorieId,
    required this.statut,
    required this.date,
    required this.lieu,
    required this.auteurId,
    required this.auteurNom,
    this.nbConfirmations = 0,
    this.danger = false,
    this.photoUrl,
    this.position,
  });

  /// L'auteur peut encore modifier ou supprimer son signalement.
  bool get estEnAttente => statut == StatutSignalement.enAttente;

  /// Résolu ou refusé : on ne peut plus le confirmer.
  bool get estCloture =>
      statut == StatutSignalement.resolu || statut == StatutSignalement.refuse;

  /// Une copie avec certains champs changés.
  Signalement copyWith({
    String? id,
    String? titre,
    String? description,
    String? categorieId,
    StatutSignalement? statut,
    DateTime? date,
    String? lieu,
    String? auteurId,
    String? auteurNom,
    int? nbConfirmations,
    bool? danger,
    String? photoUrl,
    PointGps? position,
  }) {
    return Signalement(
      id: id ?? this.id,
      titre: titre ?? this.titre,
      description: description ?? this.description,
      categorieId: categorieId ?? this.categorieId,
      statut: statut ?? this.statut,
      date: date ?? this.date,
      lieu: lieu ?? this.lieu,
      auteurId: auteurId ?? this.auteurId,
      auteurNom: auteurNom ?? this.auteurNom,
      nbConfirmations: nbConfirmations ?? this.nbConfirmations,
      danger: danger ?? this.danger,
      photoUrl: photoUrl ?? this.photoUrl,
      position: position ?? this.position,
    );
  }

  /// Le document Firestore. L'id n'est pas écrit : c'est le nom du document.
  /// photoUrl n'est pas encore écrit (l'envoi de photo n'existe pas encore).
  /// position n'est écrite que si elle existe (champ optionnel).
  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'titre': titre,
      'description': description,
      'categorieId': categorieId,
      'statut': statut.name, // enum → texte, ex "enAttente"
      'date': date, // DateTime → Timestamp (fait par Firestore)
      'lieu': lieu,
      'auteurId': auteurId,
      'auteurNom': auteurNom,
      'nbConfirmations': nbConfirmations,
      'danger': danger,
    };
    final PointGps? point = position;
    if (point != null) {
      // GeoPoint : le type "point GPS" de Firestore (latlng dans les règles)
      map['position'] = GeoPoint(point.latitude, point.longitude);
    }
    return map;
  }

  /// Lit un document Firestore. Champ absent : valeur par défaut.
  factory Signalement.fromMap(String id, Map<String, dynamic> map) {
    final Object? nombre = map['nbConfirmations'];
    final Object? photo = map['photoUrl'];
    final Object? point = map['position'];
    return Signalement(
      id: id,
      titre: map['titre'] is String ? map['titre'] : '',
      description: map['description'] is String ? map['description'] : '',
      categorieId: map['categorieId'] is String ? map['categorieId'] : 'incident',
      statut: FirestoreCommun.lireEnum(
        StatutSignalement.values,
        map['statut'],
        StatutSignalement.enAttente,
      ),
      date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
      lieu: map['lieu'] is String ? map['lieu'] : '',
      auteurId: map['auteurId'] is String ? map['auteurId'] : '',
      auteurNom: map['auteurNom'] is String ? map['auteurNom'] : '',
      nbConfirmations: nombre is num ? nombre.toInt() : 0,
      danger: map['danger'] == true, // absent (anciens documents) : false
      photoUrl: photo is String && photo.isNotEmpty ? photo : null,
      position: point is GeoPoint
          ? PointGps(point.latitude, point.longitude)
          : null,
    );
  }
}
