import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/quartier.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/secondary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : "Mon quartier".
///
/// Nom, localisation et nombre de membres du quartier, sa carte
/// (OpenStreetMap, si l'admin a saisi la position ou le contour),
/// le code d'invitation (admin seulement) et le bouton
/// "Changer de quartier" (résident actif seulement).
class MonQuartierScreen extends StatefulWidget {
  const MonQuartierScreen({super.key});

  /// false dans les tests : la carte télécharge des images sur Internet.
  static bool afficherCarte = true;

  @override
  State<MonQuartierScreen> createState() {
    return _MonQuartierScreenState();
  }
}

class _MonQuartierScreenState extends State<MonQuartierScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  bool _enChargement = true;
  String _erreur = '';
  Quartier? _quartier;
  int? _nbMembres; // null : pas encore chargé (ou échec)
  String? _code; // admin seulement

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final Utilisateur moi = _repository.getUtilisateurConnecte();
    final Resultat<Quartier?> quartier = await _repository.getQuartierConnecte();
    final Resultat<int> membres =
        await _repository.compterMembres(StatutUtilisateur.actif);
    Resultat<String?>? code;
    if (moi.estAdmin) {
      code = await _repository.getCodeInvitation();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _quartier = quartier.donnee;
      _erreur = quartier.estSucces ? '' : quartier.erreur!;
      _nbMembres = membres.donnee;
      _code = code?.donnee;
    });
  }

  Future<void> _copierCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur moi = _repository.getUtilisateurConnecte();
    final List<Widget> contenu = [];

    if (_enChargement) {
      contenu.add(const IndicateurChargement());
    } else if (_erreur.isNotEmpty || _quartier == null) {
      contenu.add(
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            _erreur.isNotEmpty ? _erreur : 'Aucun quartier trouvé',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.error),
          ),
        ),
      );
    } else {
      final Quartier quartier = _quartier!;
      contenu.add(_carteInfos(quartier));
      contenu.add(const SizedBox(height: 16));
      if (moi.estAdmin && _code != null) {
        contenu.add(_carteCode(_code!));
        contenu.add(const SizedBox(height: 16));
      }
      contenu.add(_carte(quartier));
      // Un admin ne peut pas quitter son quartier (il en est responsable)
      if (!moi.estAdmin && moi.statut == StatutUtilisateur.actif) {
        contenu.add(const SizedBox(height: 24));
        contenu.add(
          SecondaryButton(
            texte: 'Changer de quartier',
            icone: Icons.swap_horiz,
            onPressed: () {
              context.push('/code-quartier');
            },
          ),
        );
      }
    }

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Mon quartier'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: contenu,
            ),
          ),
        ],
      ),
    );
  }

  /// Nom, localisation et nombre de membres actifs.
  Widget _carteInfos(Quartier quartier) {
    String membres = '';
    if (_nbMembres != null) {
      membres = _nbMembres == 1 ? '1 membre' : '$_nbMembres membres';
    }
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quartier.nom,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  quartier.localisation,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (membres.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(membres, style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Le code d'invitation, avec un bouton pour le copier (admin).
  Widget _carteCode(String code) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code d\'invitation',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copier le code',
            icon: Icon(Icons.copy, color: AppColors.primary),
            onPressed: () {
              _copierCode(code);
            },
          ),
        ],
      ),
    );
  }

  /// La carte OpenStreetMap : contour du quartier et/ou son centre.
  Widget _carte(Quartier quartier) {
    if (!quartier.aUnePosition) {
      return Text(
        'La carte du quartier n\'est pas encore disponible.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }
    if (!MonQuartierScreen.afficherCarte) {
      return const SizedBox(key: Key('carteQuartier'), height: 260);
    }

    final List<LatLng> contour = [];
    for (final PointGps point in quartier.contour) {
      contour.add(LatLng(point.latitude, point.longitude));
    }
    // Centre : la position saisie, sinon le milieu du contour
    LatLng centre;
    if (quartier.position != null) {
      centre = LatLng(quartier.position!.latitude, quartier.position!.longitude);
    } else {
      double lat = 0;
      double lng = 0;
      for (final LatLng point in contour) {
        lat = lat + point.latitude;
        lng = lng + point.longitude;
      }
      centre = LatLng(lat / contour.length, lng / contour.length);
    }

    return ClipRRect(
      key: const Key('carteQuartier'),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(initialCenter: centre, initialZoom: 15),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              // Demandé par OpenStreetMap pour identifier l'application
              userAgentPackageName: 'tn.esprit.houmani',
            ),
            if (contour.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: contour,
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: centre,
                  width: 40,
                  height: 40,
                  child: Icon(Icons.location_on, color: AppColors.primary, size: 36),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap')],
            ),
          ],
        ),
      ),
    );
  }
}
