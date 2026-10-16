import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/quartier.dart';

/// M1 - Les morceaux de carte communs à "Mon quartier" et "Tracer les
/// limites" : le fond OpenStreetMap et les contours des quartiers.

/// Rouge des limites (comme sur Google Maps)
const Color rougeLimites = Color(0xFFD93025);

/// Le fond de carte OpenStreetMap (images téléchargées sur Internet).
TileLayer fondOpenStreetMap() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    // Demandé par OpenStreetMap pour identifier l'application
    userAgentPackageName: 'tn.esprit.houmani',
  );
}

/// La mention obligatoire "© OpenStreetMap".
Widget attributionOpenStreetMap() {
  return const RichAttributionWidget(
    attributions: [TextSourceAttribution('OpenStreetMap')],
  );
}

/// Nos points -> les points de flutter_map.
List<LatLng> versLatLng(List<PointGps> points) {
  final List<LatLng> resultat = [];
  for (final PointGps point in points) {
    resultat.add(LatLng(point.latitude, point.longitude));
  }
  return resultat;
}

/// Les limites de MON quartier : pointillé rouge, intérieur rosé.
Polygon contourRouge(List<LatLng> points) {
  return Polygon(
    points: points,
    color: rougeLimites.withValues(alpha: 0.08),
    borderColor: rougeLimites,
    borderStrokeWidth: 3,
    pattern: const StrokePattern.dotted(),
  );
}

/// Les limites d'un quartier voisin : tirets gris, avec son nom.
Polygon contourVoisin(Quartier voisin) {
  return Polygon(
    points: versLatLng(voisin.contour),
    color: Colors.grey.withValues(alpha: 0.12),
    borderColor: Colors.grey.shade600,
    borderStrokeWidth: 2,
    pattern: StrokePattern.dashed(segments: const [8, 6]),
    label: voisin.nom,
    labelStyle: TextStyle(color: Colors.grey.shade800, fontSize: 11),
  );
}

/// Les quartiers (autres que [monQuartierId]) qui ont un contour.
List<Polygon> contoursVoisins(List<Quartier> quartiers, String monQuartierId) {
  final List<Polygon> polygones = [];
  for (final Quartier quartier in quartiers) {
    if (quartier.id != monQuartierId && quartier.contour.length >= 3) {
      polygones.add(contourVoisin(quartier));
    }
  }
  return polygones;
}
