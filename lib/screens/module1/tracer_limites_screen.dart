import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/quartier.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import 'carte_quartier.dart';
import 'mon_quartier_screen.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : "Tracer les limites" (admin du quartier).
///
/// L'admin touche la carte pour placer les coins de son quartier, dans
/// l'ordre. Le contour s'affiche en pointillé rouge ; les quartiers
/// voisins restent visibles en gris pour bien coller aux frontières.
/// Exemple : "Charguia 1" et "Charguia 2" sont deux quartiers, chacun
/// avec son admin et ses limites.
class TracerLimitesScreen extends StatefulWidget {
  const TracerLimitesScreen({super.key});

  @override
  State<TracerLimitesScreen> createState() {
    return _TracerLimitesScreenState();
  }
}

class _TracerLimitesScreenState extends State<TracerLimitesScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  // Centre de Tunis : si le quartier n'a encore aucune coordonnée
  static const LatLng _tunis = LatLng(36.8065, 10.1815);

  bool _enChargement = true;
  bool _enregistrement = false;
  String _erreur = '';
  Quartier? _quartier;
  List<Quartier> _voisins = [];
  // Les coins placés par l'admin, dans l'ordre
  final List<PointGps> _points = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final Resultat<Quartier?> quartier = await _repository.getQuartierConnecte();
    final Resultat<List<Quartier>> quartiers =
        await _repository.rechercherQuartiers('');
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _quartier = quartier.donnee;
      _erreur = quartier.estSucces ? '' : quartier.erreur!;
      _voisins = quartiers.donnee ?? [];
      // On repart du contour actuel, pour le corriger
      if (quartier.donnee != null) {
        _points.addAll(quartier.donnee!.contour);
      }
    });
  }

  void _ajouterPoint(LatLng point) {
    setState(() {
      _points.add(PointGps(point.latitude, point.longitude));
    });
  }

  void _annulerDernier() {
    setState(() {
      _points.removeLast();
    });
  }

  void _toutEffacer() {
    setState(() {
      _points.clear();
    });
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
    });
    final Resultat<void> resultat = await _repository.enregistrerContour(_points);
    if (!mounted) {
      return;
    }
    setState(() {
      _enregistrement = false;
    });
    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Limites enregistrées', 'El 7doud tsajlou')),
      ),
    );
    Navigator.of(context).pop(true); // Mon quartier se recharge
  }

  @override
  Widget build(BuildContext context) {
    Widget corps;
    if (_enChargement) {
      corps = const IndicateurChargement();
    } else if (_quartier == null) {
      corps = Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _erreur.isNotEmpty
              ? _erreur
              : tr('Aucun quartier trouvé', 'Ma l9ina 7atta houma'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.error),
        ),
      );
    } else {
      corps = Column(
        children: [
          Expanded(child: _carte(_quartier!)),
          _commandes(),
        ],
      );
    }

    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Limites du quartier', '7doud el houma')),
          Expanded(child: corps),
        ],
      ),
    );
  }

  /// La carte : on touche pour ajouter un coin.
  Widget _carte(Quartier quartier) {
    // Dans les tests : pas de carte (images téléchargées sur Internet)
    if (!MonQuartierScreen.afficherCarte) {
      return const SizedBox(key: Key('carteTrace'));
    }

    final List<LatLng> points = versLatLng(_points);
    final PointGps? centre = quartier.centre;

    final List<Polygon> polygones =
        contoursVoisins(_voisins, quartier.id);
    if (points.length >= 3) {
      polygones.add(contourRouge(points));
    }

    // Les coins : des petits ronds rouges
    final List<CircleMarker> coins = [];
    for (final LatLng point in points) {
      coins.add(
        CircleMarker(
          point: point,
          radius: 6,
          color: Colors.white,
          borderColor: rougeLimites,
          borderStrokeWidth: 3,
        ),
      );
    }

    return FlutterMap(
      key: const Key('carteTrace'),
      options: MapOptions(
        initialCenter:
            centre == null ? _tunis : LatLng(centre.latitude, centre.longitude),
        initialZoom: centre == null ? 13 : 16,
        onTap: (TapPosition position, LatLng point) {
          _ajouterPoint(point);
        },
      ),
      children: [
        fondOpenStreetMap(),
        if (polygones.isNotEmpty) PolygonLayer(polygons: polygones),
        // 2 coins seulement : un simple trait en attendant le 3e
        if (points.length == 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: rougeLimites,
                strokeWidth: 3,
                pattern: const StrokePattern.dotted(),
              ),
            ],
          ),
        CircleLayer(circles: coins),
        attributionOpenStreetMap(),
      ],
    );
  }

  /// En bas : le nombre de coins et les boutons.
  Widget _commandes() {
    String aide;
    if (_points.length < 3) {
      aide = tr(
        'Touche la carte pour placer les coins du quartier '
            '(${_points.length}/3 minimum).',
        'Enzel 3al kharita bech t7ot zwaya el houma '
            '(${_points.length}/3 3al a9al).',
      );
    } else {
      aide = tr(
        '${_points.length} coins placés.',
        '${_points.length} zwaya mawjoudin.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(aide, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.undo),
                  label: Text(tr('Annuler le dernier', 'Na77i e5er wa7ed')),
                  onPressed: _points.isEmpty ? null : _annulerDernier,
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Tout effacer', 'Fasa5 kol chay')),
                  onPressed: _points.isEmpty ? null : _toutEffacer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            texte: _enregistrement
                ? tr('Enregistrement...', 'Nsajjel...')
                : tr('Enregistrer', 'Sajjel'),
            icone: Icons.check,
            onPressed: _points.length < 3 || _enregistrement ? null : _enregistrer,
          ),
        ],
      ),
    );
  }
}
