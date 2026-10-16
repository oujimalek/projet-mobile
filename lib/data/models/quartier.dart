import 'package:cloud_firestore/cloud_firestore.dart';

/// M1 - Un point sur la carte (latitude, longitude en degrés).
class PointGps {
  final double latitude;
  final double longitude;

  const PointGps(this.latitude, this.longitude);
}

/// M1 - Un quartier (une "houma") que l'on peut rejoindre.
///
/// Dans Firestore : document `quartiers/{id}` avec `nom`, `localisation`
/// et, si l'admin les a saisis, `position` et `contour` (voir
/// docs/schema_firestore.md).
class Quartier {
  final String id;
  final String nom; // ex : "Résidence El Yasmine"
  final String localisation; // ex : "Ennasr 2, Ariana"
  // Code à 6 caractères donné par l'admin. Pas stocké dans le quartier :
  // il est dans codesQuartier/{code} (sinon tout le monde pourrait le lire).
  final String codeInvitation;
  // Pas stocké non plus : calculé (count) par un membre actif
  final int nbMembres;
  // Le centre du quartier sur la carte (null : pas encore saisi)
  final PointGps? position;
  // Les coins du quartier, dans l'ordre (vide : pas de contour)
  final List<PointGps> contour;
  // true : un administrateur gère ce quartier et peut valider les
  // demandes. Écrit seulement par un script (admin SDK), pas par l'app.
  final bool aUnAdmin;

  const Quartier({
    required this.id,
    required this.nom,
    required this.localisation,
    this.codeInvitation = '',
    this.nbMembres = 0,
    this.position,
    this.contour = const [],
    this.aUnAdmin = false,
  });

  /// Le quartier peut-il être affiché sur la carte ?
  bool get aUnePosition {
    return position != null || contour.isNotEmpty;
  }

  /// Le centre sur la carte : la position saisie, sinon le milieu du
  /// contour (null : ni l'un ni l'autre).
  PointGps? get centre {
    if (position != null) {
      return position;
    }
    return milieu(contour);
  }

  /// La moyenne des points (null si la liste est vide).
  static PointGps? milieu(List<PointGps> points) {
    if (points.isEmpty) {
      return null;
    }
    double lat = 0;
    double lng = 0;
    for (final PointGps point in points) {
      lat = lat + point.latitude;
      lng = lng + point.longitude;
    }
    return PointGps(lat / points.length, lng / points.length);
  }

  /// Le point est-il à l'intérieur du contour ? (false sans contour)
  ///
  /// Méthode du "rayon" : on trace une ligne horizontale depuis le point
  /// et on compte combien de côtés du contour elle traverse. Impair :
  /// le point est dedans ; pair : dehors.
  bool contient(PointGps point) {
    if (contour.length < 3) {
      return false;
    }
    bool dedans = false;
    int j = contour.length - 1;
    for (int i = 0; i < contour.length; i++) {
      final PointGps a = contour[i];
      final PointGps b = contour[j];
      final bool traverse = (a.latitude > point.latitude) !=
          (b.latitude > point.latitude);
      if (traverse) {
        // Longitude où le côté [a, b] coupe la ligne du point
        final double lngCroisement = a.longitude +
            (point.latitude - a.latitude) /
                (b.latitude - a.latitude) *
                (b.longitude - a.longitude);
        if (point.longitude < lngCroisement) {
          dedans = !dedans;
        }
      }
      j = i;
    }
    return dedans;
  }

  /// Les champs enregistrés dans Firestore.
  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'nom': nom,
      'localisation': localisation,
    };
    if (position != null) {
      map['position'] = GeoPoint(position!.latitude, position!.longitude);
    }
    if (contour.isNotEmpty) {
      final List<GeoPoint> points = [];
      for (final PointGps point in contour) {
        points.add(GeoPoint(point.latitude, point.longitude));
      }
      map['contour'] = points;
    }
    return map;
  }

  /// Construit un quartier à partir d'un document Firestore.
  factory Quartier.fromMap(String id, Map<String, dynamic> map) {
    final List<PointGps> contour = [];
    final dynamic brut = map['contour'];
    if (brut is List) {
      for (final dynamic element in brut) {
        final PointGps? point = lirePoint(element);
        if (point != null) {
          contour.add(point);
        }
      }
    }
    return Quartier(
      id: id,
      nom: map['nom'] ?? '',
      localisation: map['localisation'] ?? '',
      position: lirePoint(map['position']),
      contour: contour,
      aUnAdmin: map['aUnAdmin'] == true,
    );
  }

  /// Un point lu dans Firestore (GeoPoint) ou dans le cache local
  /// (`{'lat': ..., 'lng': ...}`). null si la valeur n'est pas un point.
  static PointGps? lirePoint(dynamic valeur) {
    if (valeur is GeoPoint) {
      return PointGps(valeur.latitude, valeur.longitude);
    }
    if (valeur is Map && valeur['lat'] is num && valeur['lng'] is num) {
      return PointGps(
        (valeur['lat'] as num).toDouble(),
        (valeur['lng'] as num).toDouble(),
      );
    }
    return null;
  }
}
