import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/quartier.dart';
import '../../data/models/signalement.dart';
import '../../data/resultat.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/sync_signalements_m3.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/status_badge.dart';
// M1 : fond OpenStreetMap et contour rouge du quartier (import seulement)
import '../module1/carte_quartier.dart';
import 'signalement_detail_screen.dart';
import 'widgets_module3.dart';

/// M3 - La carte des signalements du quartier.
///
/// - Un repère par signalement qui a un point GPS, de la couleur de sa
///   catégorie ; les urgents sont plus grands, entourés de rouge, au-dessus.
/// - Les mêmes filtres que la liste (statut, catégorie).
/// - Toucher un repère : une petite fiche, puis "Voir le détail".
/// - Centrée sur le quartier (son contour) et les repères ; ou sur UN
///   signalement ([centreSur], depuis "Voir sur la carte" du détail).
/// - Hors ligne : les signalements viennent du cache SQLite ; le fond de
///   carte (images OpenStreetMap) a besoin d'Internet.
///
/// Le fond, le contour et l'attribution viennent du module 1
/// (carte_quartier.dart), sans modifier ses fichiers.
class CarteSignalementsScreen extends StatefulWidget {
  final StatutSignalement? statut; // filtre de départ (celui de la liste)
  final String? categorieId;
  final String? centreSur; // id du signalement à montrer (détail)

  const CarteSignalementsScreen({
    super.key,
    this.statut,
    this.categorieId,
    this.centreSur,
  });

  /// Le fond de carte (remplaçable dans les tests : pas de téléchargement
  /// d'images).
  static Widget Function() fondDeCarte = fondOpenStreetMap;

  @override
  State<CarteSignalementsScreen> createState() {
    return _CarteSignalementsScreenState();
  }
}

class _CarteSignalementsScreenState extends State<CarteSignalementsScreen> {
  final SyncSignalementsM3 _sync = SyncSignalementsM3.instance;

  // Données
  List<Signalement> _signalements = [];
  List<LatLng> _contour = []; // limites de mon quartier (module 1)
  LatLng? _centreQuartier;
  bool _enChargement = true;
  bool _premierChargement = true; // la caméra se place une seule fois
  String? _erreur;
  bool _depuisCache = false;
  bool _horsLigne = false;

  // Choix
  StatutSignalement? _statutChoisi;
  String? _categorieChoisie;
  Signalement? _choisi; // repère touché (petite fiche en bas)

  @override
  void initState() {
    super.initState();
    _statutChoisi = widget.statut;
    _categorieChoisie = widget.categorieId;
    _chargerDonnees();
  }

  /// Le quartier (contour, centre) puis les signalements.
  Future<void> _chargerDonnees() async {
    if (_premierChargement) {
      await _chargerQuartier();
    }
    final Resultat<ListeSignalementsM3> resultat =
        await _sync.chargerSignalements(
      statut: _statutChoisi,
      categorieId: _categorieChoisie,
    );
    if (!mounted) {
      return;
    }
    final bool premier = _premierChargement;
    setState(() {
      _enChargement = false;
      // La caméra de FlutterMap n'est placée qu'à son premier affichage :
      // les rechargements suivants (filtres) ne la déplacent pas.
      _premierChargement = false;
      if (!resultat.estSucces) {
        _erreur = resultat.erreur;
        return;
      }
      _erreur = null;
      final ListeSignalementsM3 liste = resultat.donnee!;
      _signalements = liste.signalements;
      _depuisCache = liste.depuisCache;
      _horsLigne = liste.horsLigne;
      // Le repère choisi a pu disparaître avec le filtre
      final Signalement? choisi = _choisi;
      if (choisi != null) {
        _choisi = _parId(choisi.id);
      }
      // Arrivée depuis le détail : la fiche de ce signalement est ouverte
      if (premier && widget.centreSur != null) {
        _choisi = _parId(widget.centreSur!);
      }
    });
  }

  /// Le contour de mon quartier (module 1). Sans réseau ni contour : rien.
  Future<void> _chargerQuartier() async {
    try {
      final Resultat<Quartier?> resultat = await UtilisateurRepository()
          .getQuartierConnecte()
          .timeout(const Duration(seconds: 5));
      final Quartier? quartier = resultat.donnee;
      if (quartier == null) {
        return;
      }
      if (quartier.contour.length >= 3) {
        _contour = versLatLng(quartier.contour);
      }
      final PointGps? position = quartier.position;
      if (position != null) {
        _centreQuartier = LatLng(position.latitude, position.longitude);
      }
    } catch (erreur) {
      // pas de quartier : la carte se centre sur les repères
    }
  }

  Signalement? _parId(String id) {
    for (final Signalement s in _signalements) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  Future<void> _recharger() async {
    setState(() {
      _enChargement = true;
    });
    await _chargerDonnees();
  }

  void _choisirStatut(StatutSignalement? statut) {
    setState(() {
      _statutChoisi = statut;
    });
    _recharger();
  }

  void _choisirCategorie(String? categorieId) {
    setState(() {
      _categorieChoisie = categorieId;
    });
    _recharger();
  }

  /// Les signalements qui ont un point GPS, les plus urgents en dernier
  /// (dessinés au-dessus des autres).
  List<Signalement> get _avecPosition {
    final List<Signalement> liste =
        _signalements.where((s) => s.position != null).toList();
    liste.sort((a, b) => SignalementRepository.scoreUrgence(a)
        .compareTo(SignalementRepository.scoreUrgence(b)));
    return liste;
  }

  /// Ouvre le détail ; au retour, la carte est rechargée.
  Future<void> _ouvrirDetail(Signalement signalement) async {
    await ouvrirEcranM3<bool>(
      context,
      SignalementDetailScreen(signalementId: signalement.id),
    );
    if (mounted) {
      _recharger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Carte des signalements', 'Carte it-tablighat')),
          const SizedBox(height: 12),
          FiltresSignalementsM3(
            statut: _statutChoisi,
            categorieId: _categorieChoisie,
            onStatut: _choisirStatut,
            onCategorie: _choisirCategorie,
          ),
          const SizedBox(height: 8),
          if (_depuisCache) _bandeauHorsLigne(),
          _ligneCompteur(),
          Expanded(child: _contenu()),
        ],
      ),
    );
  }

  Widget _bandeauHorsLigne() {
    return BandeauM3(
      icone: Icons.cloud_off,
      texte: _horsLigne
          ? tr('Hors ligne : le fond de carte a besoin d\'Internet. Les '
                  'signalements viennent du téléphone.',
              'Mafamech connexion : el carte t7eb Internet. It-tablighat '
                  'mel téléphone.')
          : tr('Actualisation impossible : signalements enregistrés sur le '
                  'téléphone.',
              'Ma najjamnech n7adthou : it-tablighat mel téléphone.'),
    );
  }

  /// "3 sur la carte · 1 sans point GPS".
  Widget _ligneCompteur() {
    final int surCarte = _avecPosition.length;
    final int sans = _signalements.length - surCarte;
    String texte = '$surCarte ${tr('sur la carte', 'fel carte')}';
    if (sans > 0) {
      texte = '$texte · $sans ${tr('sans point GPS', 'bla GPS')}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          texte,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _contenu() {
    if (_premierChargement) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? erreur = _erreur;
    if (erreur != null && _signalements.isEmpty) {
      return Center(
        child: MessageEtatM3(
          icone: Icons.cloud_off,
          texte: erreur,
          texteBouton: tr('Réessayer', '3awed'),
          onBouton: _recharger,
        ),
      );
    }
    final List<Widget> calques = [_carte()];
    if (_avecPosition.isEmpty) {
      calques.add(Positioned(
        left: 16,
        right: 16,
        top: 16,
        child: AppCard(
          child: Text(
            tr('Aucun signalement avec un point GPS ici',
                'Hatta tabligh b GPS lehna'),
            textAlign: TextAlign.center,
          ),
        ),
      ));
    }
    final Signalement? choisi = _choisi;
    if (choisi != null) {
      calques.add(Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: _fiche(choisi),
      ));
    }
    if (_enChargement) {
      calques.add(const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: LinearProgressIndicator(minHeight: 2),
      ));
    }
    return Stack(children: calques);
  }

  /// La carte : fond, contour du quartier, repères. La caméra est placée
  /// au premier affichage seulement.
  Widget _carte() {
    final List<Signalement> avecPosition = _avecPosition;
    final List<LatLng> points = [
      for (final Signalement s in avecPosition)
        LatLng(s.position!.latitude, s.position!.longitude),
    ];
    MapOptions options;
    final Signalement? cible =
        widget.centreSur == null ? null : _parId(widget.centreSur!);
    final PointGps? pointCible = cible?.position;
    final List<LatLng> aMontrer = [..._contour, ...points];
    if (pointCible != null) {
      // Depuis "Voir sur la carte" : centré sur CE signalement
      options = MapOptions(
        initialCenter: LatLng(pointCible.latitude, pointCible.longitude),
        initialZoom: 17,
        onTap: (position, point) => _fermerFiche(),
      );
    } else if (aMontrer.isNotEmpty) {
      // Le quartier et tous les repères visibles d'un coup
      options = MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: aMontrer,
          padding: const EdgeInsets.all(48),
          maxZoom: 17,
        ),
        onTap: (position, point) => _fermerFiche(),
      );
    } else {
      // Ni contour ni repère : le centre du quartier, sinon Tunis
      options = MapOptions(
        initialCenter: _centreQuartier ?? const LatLng(36.8065, 10.1815),
        initialZoom: _centreQuartier == null ? 12 : 15,
        onTap: (position, point) => _fermerFiche(),
      );
    }

    return FlutterMap(
      key: const ValueKey('carte_signalements'),
      options: options,
      children: [
        CarteSignalementsScreen.fondDeCarte(),
        if (_contour.isNotEmpty) PolygonLayer(polygons: [contourRouge(_contour)]),
        MarkerLayer(
          markers: [
            for (final Signalement s in avecPosition) _repere(s),
          ],
        ),
        attributionOpenStreetMap(),
      ],
    );
  }

  void _fermerFiche() {
    if (_choisi != null) {
      setState(() {
        _choisi = null;
      });
    }
  }

  /// Un repère : rond de la couleur de la catégorie, avec son icône.
  /// Urgent : plus grand, bord rouge épais, ombre.
  Marker _repere(Signalement signalement) {
    final CategorieSignalement categorie =
        SignalementRepository.getCategorieParId(signalement.categorieId);
    final bool urgent =
        SignalementRepository.niveauUrgence(signalement) == NiveauUrgence.urgent;
    final bool choisi = _choisi?.id == signalement.id;
    final double taille = urgent ? 46 : 36;
    return Marker(
      point: LatLng(
        signalement.position!.latitude,
        signalement.position!.longitude,
      ),
      width: taille,
      height: taille,
      child: Semantics(
        label: signalement.titre,
        button: true,
        child: GestureDetector(
          key: ValueKey('repere_${signalement.id}'),
          onTap: () {
            setState(() {
              _choisi = signalement;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: categorie.couleur,
              shape: BoxShape.circle,
              border: Border.all(
                color: choisi
                    ? AppColors.secondary
                    : urgent
                        ? AppColors.error
                        : Colors.white,
                width: urgent || choisi ? 3 : 2,
              ),
              boxShadow: urgent
                  ? [
                      BoxShadow(
                        color: AppColors.error.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              categorie.icone,
              color: Colors.white,
              size: urgent ? 24 : 18,
            ),
          ),
        ),
      ),
    );
  }

  /// La petite fiche du repère touché.
  Widget _fiche(Signalement signalement) {
    final CategorieSignalement categorie =
        SignalementRepository.getCategorieParId(signalement.categorieId);
    return AppCard(
      key: const ValueKey('fiche_repere'),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PastilleCategorie(categorie: categorie, taille: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signalement.titre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${signalement.lieu} · ${depuisQuandM3(signalement.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusBadge(statut: signalement.statut),
                        BadgeUrgence(
                          niveau: SignalementRepository.niveauUrgence(signalement),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Fermer', 'Sakker'),
                onPressed: _fermerFiche,
                icon: Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _ouvrirDetail(signalement),
              child: Text(tr('Voir le détail', 'Chouf it-tafasil')),
            ),
          ),
        ],
      ),
    );
  }
}
