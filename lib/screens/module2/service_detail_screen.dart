import 'package:flutter/material.dart';

import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';
import 'services_communs_screen.dart';

/// M2 - Détail d'un service (écran 02).
///
/// Affiche le service, son auteur (note moyenne, services rendus) et le
/// bouton pour le demander. S'ouvre en plein écran depuis la liste.
class ServiceDetailScreen extends StatefulWidget {
  final String serviceId; // id du service à afficher

  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailScreen> createState() {
    return _ServiceDetailScreenState();
  }
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final ServiceRepository _repository = ServiceRepository();

  /// Appelé quand on touche "Demander ce service".
  void _demander(Service service) {
    final bool envoyee = _repository.envoyerDemande(service.id);
    // On redessine l'écran : le bouton devient "Demande envoyée"
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          envoyee
              ? 'Demande envoyée à ${service.auteur}'
              : 'Impossible d\'envoyer la demande',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Service? service = _repository.getServiceParId(widget.serviceId);

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Détail du service'),
          Expanded(
            child: service == null
                ? const Center(
                    child: Text(
                      'Ce service n\'existe plus',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : _contenu(service),
          ),
        ],
      ),
    );
  }

  /// Le contenu qui défile + l'action fixe en bas.
  Widget _contenu(Service service) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _badges(service),
              const SizedBox(height: 14),
              Text(
                service.titre,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                service.description,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ..._infos(service),
              _carteAuteur(service),
            ],
          ),
        ),
        _actions(service),
      ],
    );
  }

  /// Les badges : catégorie, Offre / Demande, service commun.
  Widget _badges(Service service) {
    final List<Widget> badges = [
      PastilleTexte(
        texte: service.categorie,
        couleur: AppColors.textSecondary,
        fond: AppColors.backgroundSecondary,
      ),
      service.estOffre
          ? const PastilleTexte(
              texte: 'Offre',
              couleur: AppColors.badgeResolu,
              fond: AppColors.badgeResoluFond,
            )
          : const PastilleTexte(
              texte: 'Demande',
              couleur: AppColors.badgeEnCours,
              fond: AppColors.badgeEnCoursFond,
            ),
    ];
    if (service.estCommun) {
      badges.add(const PastilleTexte(
        texte: 'Service commun',
        couleur: AppColors.primary,
        fond: AppColors.primaryLight,
      ));
    }
    if (service.prix != null) {
      badges.add(PastilleTexte(
        texte: service.prix!,
        couleur: AppColors.secondary,
        fond: AppColors.secondaryLight,
      ));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: badges);
  }

  /// Les lignes Disponibilité / Durée / Récupération (seulement si renseignées).
  List<Widget> _infos(Service service) {
    final List<Widget> lignes = [];
    if (service.disponibilite != null) {
      lignes.add(_ligneInfo(Icons.event_available_outlined, 'Disponibilité', service.disponibilite!));
    }
    if (service.duree != null) {
      lignes.add(_ligneInfo(Icons.timer_outlined, 'Durée', service.duree!));
    }
    if (service.recuperation != null) {
      lignes.add(_ligneInfo(Icons.place_outlined, 'Récupération', service.recuperation!));
    }
    if (lignes.isEmpty) {
      return [];
    }
    // Une seule carte qui regroupe les lignes
    return [
      AppCard(child: Column(children: lignes)),
      const SizedBox(height: 16),
    ];
  }

  Widget _ligneInfo(IconData icone, String titre, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(titre, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// La carte de l'auteur : avatar, nom, note moyenne, services rendus.
  Widget _carteAuteur(Service service) {
    final double note = _repository.getNoteMoyenne(service.auteur);
    final int avis = _repository.getNombreEvaluations(service.auteur);
    final int rendus = _repository.getNombreServicesRendus(service.auteur);

    final String texteNote = avis == 0
        ? 'Pas encore noté'
        : '${note.toStringAsFixed(1)} ($avis avis)';
    final String texteRendus = rendus <= 1
        ? '$rendus service rendu'
        : '$rendus services rendus';

    return AppCard(
      child: Row(
        children: [
          AvatarInitiales(nom: service.auteur),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.auteur,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (service.bloc.isNotEmpty)
                  Text(
                    service.bloc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$texteNote · $texteRendus',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La zone fixe en bas : bouton de demande, planning ou "Votre publication".
  Widget _actions(Service service) {
    final bool estMonService = service.auteur == _repository.getMonNom();
    final List<Widget> contenu = [];

    if (estMonService) {
      contenu.add(const Text(
        'Votre publication',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ));
    }

    if (service.estCommun) {
      if (contenu.isNotEmpty) {
        contenu.add(const SizedBox(height: 12));
      }
      contenu.add(PrimaryButton(
        texte: 'Voir le planning',
        icone: Icons.calendar_month_outlined,
        onPressed: () async {
          await ouvrirEcran(context, const ServicesCommunsScreen());
          if (mounted) {
            setState(() {});
          }
        },
      ));
    } else if (!estMonService) {
      final bool dejaDemande = _repository.aDejaDemande(service.id);
      contenu.add(PrimaryButton(
        texte: dejaDemande ? 'Demande envoyée' : 'Demander ce service',
        icone: dejaDemande ? Icons.check : null,
        // null = bouton désactivé
        onPressed: dejaDemande
            ? null
            : () {
                _demander(service);
              },
      ));
      contenu.add(const SizedBox(height: 10));
      contenu.add(Text(
        '${service.auteur} recevra la demande et pourra l\'accepter',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ));
    }

    if (contenu.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: contenu),
      ),
    );
  }
}
