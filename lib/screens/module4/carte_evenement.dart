import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/quartier.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../module1/carte_quartier.dart';

/// M4 - Le lieu exact d'un événement sur la carte (flutter_map +
/// OpenStreetMap, les mêmes outils que la carte du module 1).

/// Centre par défaut si le quartier n'a pas de position : Tunis.
const LatLng _tunis = LatLng(36.8065, 10.1815);

LatLng _versLatLng(PointGps point) => LatLng(point.latitude, point.longitude);

/// L'épingle de l'événement.
Marker _epingle(LatLng point) {
  return Marker(
    point: point,
    width: 44,
    height: 44,
    alignment: Alignment.topCenter,
    child: const Icon(Icons.location_on, color: rougeLimites, size: 44),
  );
}

/// Petite carte non interactive du détail d'un événement.
class MiniCarteEvenement extends StatelessWidget {
  final PointGps position;

  const MiniCarteEvenement({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    final LatLng point = _versLatLng(position);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: SizedBox(
        height: 170,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16,
            // Carte fixe : on ne la déplace pas dans la page qui défile
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            fondOpenStreetMap(),
            MarkerLayer(markers: [_epingle(point)]),
            attributionOpenStreetMap(),
          ],
        ),
      ),
    );
  }
}

/// Écran plein : l'organisateur touche la carte pour placer l'épingle,
/// puis « Valider ce lieu ». Renvoie le PointGps choisi (Navigator.pop).
class ChoisirLieuScreen extends StatefulWidget {
  final PointGps? initial;

  const ChoisirLieuScreen({super.key, this.initial});

  @override
  State<ChoisirLieuScreen> createState() {
    return _ChoisirLieuScreenState();
  }
}

class _ChoisirLieuScreenState extends State<ChoisirLieuScreen> {
  LatLng? _choisi;
  Quartier? _quartier; // pour centrer la carte et dessiner ses limites
  bool _enChargement = true;

  @override
  void initState() {
    super.initState();
    final PointGps? initial = widget.initial;
    if (initial != null) {
      _choisi = _versLatLng(initial);
    }
    _chargerQuartier();
  }

  Future<void> _chargerQuartier() async {
    final Resultat<Quartier?> resultat =
        await UtilisateurRepository().getQuartierConnecte();
    if (!mounted) {
      return;
    }
    setState(() {
      _quartier = resultat.donnee;
      _enChargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Quartier? quartier = _quartier;
    final PointGps? centreQuartier = quartier?.centre;
    final LatLng centre = _choisi ??
        (centreQuartier == null ? _tunis : _versLatLng(centreQuartier));
    final LatLng? choisi = _choisi;

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Lieu de l\'événement'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Touche la carte pour placer l\'épingle à l\'endroit exact.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: _enChargement
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: centre,
                      initialZoom: centreQuartier == null && choisi == null ? 13 : 17,
                      onTap: (TapPosition position, LatLng point) {
                        setState(() {
                          _choisi = point;
                        });
                      },
                    ),
                    children: [
                      fondOpenStreetMap(),
                      // Les limites de mon quartier (module 1)
                      if (quartier != null && quartier.contour.length >= 3)
                        PolygonLayer(polygons: [
                          contourRouge(versLatLng(quartier.contour)),
                        ]),
                      if (choisi != null) MarkerLayer(markers: [_epingle(choisi)]),
                      attributionOpenStreetMap(),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PrimaryButton(
                texte: 'Valider ce lieu',
                icone: Icons.check,
                onPressed: choisi == null
                    ? null
                    : () => Navigator.pop(
                        context, PointGps(choisi.latitude, choisi.longitude)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
