import 'package:flutter/material.dart';

import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'mes_demandes_screen.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';
import 'service_detail_screen.dart';
import 'service_form_screen.dart';
import 'services_communs_screen.dart';

/// M2 - Services : liste des services entre voisins.
///
/// StatefulWidget car deux choix de l'utilisateur changent l'affichage :
///   - l'onglet actif (Offres ou Demandes)
///   - la catégorie choisie dans les filtres
class ServicesListScreen extends StatefulWidget {
  const ServicesListScreen({super.key});

  @override
  State<ServicesListScreen> createState() {
    return _ServicesListScreenState();
  }
}

class _ServicesListScreenState extends State<ServicesListScreen> {
  final ServiceRepository _repository = ServiceRepository();

  // Les services en direct (créé UNE fois : voir FluxM2)
  late final Stream<List<Service>> _flux = _repository.ecouterServices();

  // État de l'écran
  bool _afficherOffres = true; // true = onglet "Offres", false = "Demandes"
  String _categorieChoisie = 'Tous';

  // Couleurs des avatars (fond, texte), utilisées à tour de rôle
  // (des `get` : les couleurs suivent le thème clair/sombre)
  List<Color> get _fondsAvatar => [
    AppColors.secondaryLight,
    AppColors.primaryLight,
    AppColors.backgroundSecondary,
  ];
  List<Color> get _textesAvatar => [
    AppColors.secondary,
    AppColors.primary,
    AppColors.textSecondary,
  ];

  /// Les services à afficher selon l'onglet et la catégorie choisis.
  List<Service> _servicesAffiches(List<Service> tous) {
    final List<Service> resultat = [];
    for (final service in tous) {
      if (service.estOffre != _afficherOffres) {
        continue;
      }
      if (_categorieChoisie != 'Tous' && service.categorie != _categorieChoisie) {
        continue;
      }
      resultat.add(service);
    }
    return resultat;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _enTete(),
          const SizedBox(height: 16),
          _ongletsOffresDemandes(),
          const SizedBox(height: 12),
          _filtresCategories(),
          const SizedBox(height: 12),

          // ----- La liste des services (en direct) -----
          Expanded(
            child: FluxM2<List<Service>>(
              flux: _flux,
              construire: (context, tous) {
                final List<Service> services = _servicesAffiches(tous);
                if (services.isEmpty) {
                  return MessageEtat(
                    texte: tous.isEmpty
                        ? 'Aucun service pour l\'instant. Publie le premier !'
                        : 'Aucun service dans cette catégorie',
                    icone: Icons.handshake_outlined,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: services.length,
                  itemBuilder: (context, index) {
                    return _carteService(services[index], index);
                  },
                );
              },
            ),
          ),
        ],
      ),

      // Bouton bleu "+" pour publier un service
      floatingActionButton: FloatingActionButton(
        onPressed: _ouvrirPublication,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 30),
      ),
      // Pas de barre du bas ici : elle est affichée par le routeur
      // (AppShell dans lib/router/app_router.dart) pour tous les onglets
    );
  }

  /// En-tête bleu cobalt avec le titre de l'écran.
  Widget _enTete() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Services entre voisins',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Entraide dans ta houma',
                  style: TextStyle(color: AppColors.primaryLight),
                ),
              ],
            ),
          ),
          // Accès à "Mes demandes" et au planning des services communs
          IconButton(
            tooltip: 'Mes demandes',
            onPressed: () {
              ouvrirEcran(context, const MesDemandesScreen());
            },
            icon: Icon(Icons.inbox_outlined, color: AppColors.card),
          ),
          IconButton(
            tooltip: 'Planning des services communs',
            onPressed: () {
              ouvrirEcran(context, const ServicesCommunsScreen());
            },
            icon: Icon(Icons.calendar_month_outlined, color: AppColors.card),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'écran "Nouvelle publication". Au retour, on affiche l'onglet
  /// du service publié (la liste se met à jour toute seule).
  Future<void> _ouvrirPublication() async {
    final Service? publie = await ouvrirEcran<Service>(
      context,
      const ServiceFormScreen(),
    );
    if (!mounted || publie == null) {
      return;
    }
    setState(() {
      _afficherOffres = publie.estOffre;
      _categorieChoisie = 'Tous';
    });
  }

  /// Ouvre le détail d'un service.
  void _ouvrirDetail(Service service) {
    ouvrirEcran(context, ServiceDetailScreen(serviceId: service.id));
  }

  /// Les deux onglets "Offres" / "Demandes".
  Widget _ongletsOffresDemandes() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(child: _onglet('Offres', true)),
          Expanded(child: _onglet('Demandes', false)),
        ],
      ),
    );
  }

  /// Un onglet. estOffres indique s'il s'agit de l'onglet "Offres".
  Widget _onglet(String texte, bool estOffres) {
    final bool actif = _afficherOffres == estOffres;
    return InkWell(
      onTap: () {
        setState(() {
          _afficherOffres = estOffres;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: actif ? AppColors.card : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: actif ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Les filtres par catégorie (passent à la ligne s'il n'y a pas la place).
  Widget _filtresCategories() {
    final List<Widget> filtres = [];
    for (final categorie in _repository.getCategories()) {
      filtres.add(_filtre(categorie));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filtres,
        ),
      ),
    );
  }

  /// Un filtre de catégorie (doré quand il est sélectionné).
  Widget _filtre(String categorie) {
    final bool actif = _categorieChoisie == categorie;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _categorieChoisie = categorie;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? AppColors.secondary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? AppColors.secondary : AppColors.border,
          ),
        ),
        child: Text(
          categorie,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: actif ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// La carte d'un service dans la liste.
  Widget _carteService(Service service, int index) {
    // Couleur de l'avatar : on alterne entre 3 couleurs
    final int couleur = index % 3;

    // Sous-titre : catégorie · auteur · bloc (+ jour si service commun)
    String sousTitre = '${service.categorie} · ${service.auteurNom}';
    if (service.bloc.isNotEmpty) {
      sousTitre = '$sousTitre · ${service.bloc}';
    }
    if (service.estCommun) {
      sousTitre = '$sousTitre · Chaque ${service.jour}';
    }

    // Heure de publication affichée à droite ("1 h", "hier"...)
    String publication = '';
    final DateTime? date = service.datePublication;
    if (date != null) {
      publication = depuisQuand(date);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        // Toucher la carte ouvre le détail du service
        onTap: () {
          _ouvrirDetail(service);
        },
        child: Row(
          children: [
            // Avatar rond avec les initiales
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _fondsAvatar[couleur],
                shape: BoxShape.circle,
              ),
              child: Text(
                initiales(service.auteurNom),
                style: TextStyle(
                  color: _textesAvatar[couleur],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Titre + sous-titre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.titre,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sousTitre,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Heure de publication à droite
            Text(
              publication,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
