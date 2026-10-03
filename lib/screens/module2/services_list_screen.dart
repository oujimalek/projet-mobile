import 'package:flutter/material.dart';

import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';

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

  // État de l'écran
  bool _afficherOffres = true; // true = onglet "Offres", false = "Demandes"
  String _categorieChoisie = 'Tous';

  // Couleurs des avatars (fond, texte), utilisées à tour de rôle
  final List<Color> _fondsAvatar = [
    AppColors.primaryLight,
    AppColors.secondaryLight,
    AppColors.border,
  ];
  final List<Color> _textesAvatar = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.textSecondary,
  ];

  /// Les services à afficher selon l'onglet et la catégorie choisis.
  List<Service> _servicesAffiches() {
    final List<Service> resultat = [];
    for (final service in _repository.getServicesParCategorie(_categorieChoisie)) {
      if (service.estOffre == _afficherOffres) {
        resultat.add(service);
      }
    }
    return resultat;
  }

  /// Initiales d'un nom, par exemple "Karim M." donne "KM".
  String _initiales(String nom) {
    String initiales = '';
    for (final mot in nom.split(' ')) {
      if (mot.isNotEmpty && initiales.length < 2) {
        initiales = initiales + mot[0].toUpperCase();
      }
    }
    return initiales;
  }

  /// Temps écoulé depuis une date, en texte court : "12 min", "3 h",
  /// "hier", ou la date (ex : "28/9") si c'est plus ancien.
  String _depuisQuand(DateTime date) {
    final Duration ecart = DateTime.now().difference(date);
    if (ecart.inMinutes < 60) {
      return '${ecart.inMinutes} min';
    }
    if (ecart.inHours < 24) {
      return '${ecart.inHours} h';
    }
    if (ecart.inHours < 48) {
      return 'hier';
    }
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final List<Service> services = _servicesAffiches();

    return Scaffold(
      body: Column(
        children: [
          _enTete(),
          const SizedBox(height: 16),
          _ongletsOffresDemandes(),
          const SizedBox(height: 12),
          _filtresCategories(),
          const SizedBox(height: 12),

          // ----- La liste des services -----
          Expanded(
            child: services.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun service pour l\'instant',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: services.length,
                    itemBuilder: (context, index) {
                      return _carteService(services[index], index);
                    },
                  ),
          ),
        ],
      ),

      // Bouton bleu "+" pour publier un service (visuel pour l'instant)
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Écran "Publier un service" : à venir
        },
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
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: const Column(
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
    );
  }

  /// Les deux onglets "Offres" / "Demandes".
  Widget _ongletsOffresDemandes() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border,
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
          color: actif ? AppColors.card : AppColors.border,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: actif ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// La rangée horizontale des filtres par catégorie.
  Widget _filtresCategories() {
    final List<String> categories = _repository.getCategories();
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, // défilement de gauche à droite
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          return _filtre(categories[index]);
        },
      ),
    );
  }

  /// Un filtre de catégorie (bleu cobalt quand il est sélectionné).
  Widget _filtre(String categorie) {
    final bool actif = _categorieChoisie == categorie;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            _categorieChoisie = categorie;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: actif ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: actif ? AppColors.primary : AppColors.border,
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
      ),
    );
  }

  /// La carte d'un service dans la liste.
  Widget _carteService(Service service, int index) {
    // Couleur de l'avatar : on alterne entre 3 couleurs
    final int couleur = index % 3;

    // Sous-titre : catégorie · auteur · bloc (+ jour si service commun)
    String sousTitre = '${service.categorie} · ${service.auteur}';
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
      publication = _depuisQuand(date);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
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
                _initiales(service.auteur),
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
                    style: const TextStyle(
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
              style: const TextStyle(
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
