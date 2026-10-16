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
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/secondary_button.dart';
import 'carte_quartier.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : "Mon quartier".
///
/// Nom, localisation et nombre de membres du quartier, sa carte
/// (OpenStreetMap, si l'admin a saisi la position ou le contour),
/// le code d'invitation et "Tracer les limites" (admin seulement) et le
/// bouton "Changer de quartier" (résident actif seulement).
/// Sur la carte : mon quartier en pointillé rouge, les voisins en gris.
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
  List<Quartier> _tousLesQuartiers = []; // pour dessiner les voisins

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
    // Les voisins sont un plus : en cas d'échec, on ne les dessine pas
    final Resultat<List<Quartier>> quartiers =
        await _repository.rechercherQuartiers('');
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _quartier = quartier.donnee;
      _erreur = quartier.estSucces ? '' : quartier.erreur!;
      _nbMembres = membres.donnee;
      _code = code?.donnee;
      _tousLesQuartiers = quartiers.donnee ?? [];
    });
  }

  /// Admin : ouvre l'écran de tracé, puis recharge si c'est enregistré.
  Future<void> _tracerLimites() async {
    final bool? enregistre = await context.push<bool>('/profil/quartier/limites');
    if (enregistre == true && mounted) {
      await _charger();
    }
  }

  Future<void> _copierCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Code copié', 'El code tnasakh'))),
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
            _erreur.isNotEmpty
                ? _erreur
                : tr('Aucun quartier trouvé', 'Ma l9ina 7atta houma'),
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
      if (moi.estAdmin) {
        contenu.add(const SizedBox(height: 16));
        contenu.add(
          SecondaryButton(
            texte: quartier.contour.length >= 3
                ? tr('Modifier les limites', 'Badel el 7doud')
                : tr('Tracer les limites', 'Orsem el 7doud'),
            icone: Icons.draw_outlined,
            onPressed: _tracerLimites,
          ),
        );
      }
      // Un admin ne peut pas quitter son quartier (il en est responsable)
      if (!moi.estAdmin && moi.statut == StatutUtilisateur.actif) {
        contenu.add(const SizedBox(height: 24));
        contenu.add(
          SecondaryButton(
            texte: tr('Changer de quartier', 'Badel el houma'),
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
          AppHeader(titre: tr('Mon quartier', 'Houmti')),
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
      membres = _nbMembres == 1
          ? tr('1 membre', '1 sekn')
          : tr('$_nbMembres membres', '$_nbMembres sokkan');
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
                  tr('Code d\'invitation', 'Code el invitation'),
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
            tooltip: tr('Copier le code', 'Ansa5 el code'),
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
        tr(
          'La carte du quartier n\'est pas encore disponible.',
          'Kharitat el houma mazelet mouch mawjouda.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      );
    }
    if (!MonQuartierScreen.afficherCarte) {
      return const SizedBox(key: Key('carteQuartier'), height: 260);
    }

    final List<LatLng> contour = versLatLng(quartier.contour);
    // Centre : la position saisie, sinon le milieu du contour
    final PointGps milieu = quartier.centre!;
    final LatLng centre = LatLng(milieu.latitude, milieu.longitude);

    // Les voisins d'abord (en gris), puis mon quartier par-dessus (en rouge)
    final List<Polygon> polygones =
        contoursVoisins(_tousLesQuartiers, quartier.id);
    if (contour.length >= 3) {
      polygones.add(contourRouge(contour));
    }

    return ClipRRect(
      key: const Key('carteQuartier'),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(initialCenter: centre, initialZoom: 15),
          children: [
            fondOpenStreetMap(),
            if (polygones.isNotEmpty) PolygonLayer(polygons: polygones),
            MarkerLayer(
              markers: [
                Marker(
                  point: centre,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_on, color: rougeLimites, size: 36),
                ),
              ],
            ),
            attributionOpenStreetMap(),
          ],
        ),
      ),
    );
  }
}
