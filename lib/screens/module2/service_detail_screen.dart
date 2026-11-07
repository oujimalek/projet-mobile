import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/models/service.dart';
import '../../data/resultat.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';
import 'participants_rotation_screen.dart';
import 'service_form_screen.dart';
import 'services_communs_screen.dart';

/// M2 - Détail d'un service (écran 02).
///
/// Affiche le service, son auteur (note moyenne, services rendus) et le
/// bouton pour le demander. L'auteur peut le modifier ou le supprimer.
/// S'ouvre en plein écran depuis la liste.
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

  // Flux créés UNE fois (voir FluxM2)
  late final Stream<Service?> _fluxService = _repository.ecouterService(
    widget.serviceId,
  );
  late final Stream<List<DemandeService>> _fluxEnvoyees = _repository
      .ecouterDemandesEnvoyees();

  bool _enCours = false; // true pendant une écriture : boutons désactivés

  /// Appelé quand on touche "Demander ce service".
  Future<void> _demander(Service service) async {
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.envoyerDemande(
      service.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    afficherMessage(
      context,
      resultat.estSucces
          ? 'Demande envoyée à ${service.auteurNom}'
          : resultat.erreur!,
    );
  }

  /// "Modifier" : le formulaire s'ouvre pré-rempli.
  Future<void> _modifier(Service service) async {
    await ouvrirEcran(context, ServiceFormScreen(service: service));
  }

  /// "Supprimer" : après confirmation. Les demandes en attente sont refusées.
  Future<void> _supprimer(Service service) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) {
        return AlertDialog(
          title: const Text('Supprimer ce service ?'),
          content: const Text(
            'Les demandes en attente seront refusées. '
            'Cette action est définitive.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexte).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(contexte).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (confirme != true || !mounted) {
      return;
    }
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.supprimerService(
      service.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    if (resultat.estSucces) {
      afficherMessage(context, 'Service supprimé');
      Navigator.of(context).pop();
    } else {
      afficherMessage(context, resultat.erreur!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Détail du service'),
          Expanded(
            child: FluxM2<Service?>(
              flux: _fluxService,
              construire: (context, service) {
                if (service == null) {
                  return const MessageEtat(texte: 'Ce service n\'existe plus');
                }
                return _contenu(service);
              },
            ),
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
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ..._infos(service),
              if (service.estCommun) ..._carteParticipants(service),
              _CarteAuteur(
                key: ValueKey(service.auteurId),
                service: service,
                repository: _repository,
              ),
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
          ? PastilleTexte(
              texte: 'Offre',
              couleur: AppColors.badgeResolu,
              fond: AppColors.badgeResoluFond,
            )
          : PastilleTexte(
              texte: 'Demande',
              couleur: AppColors.badgeEnCours,
              fond: AppColors.badgeEnCoursFond,
            ),
    ];
    if (service.estCommun) {
      badges.add(PastilleTexte(
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
    if (service.estCommun && service.jour != null) {
      final String horaire = service.heureDebut != null && service.heureFin != null
          ? ' · ${service.heureDebut} – ${service.heureFin}'
          : '';
      lignes.add(_ligneInfo(Icons.repeat, 'Chaque semaine', '${service.jour}$horaire'));
    }
    // Une ligne vide (absente, "" ou seulement des espaces) n'est pas affichée
    if (service.disponibilite?.trim().isNotEmpty ?? false) {
      lignes.add(_ligneInfo(
        Icons.event_available_outlined,
        'Disponibilité',
        service.disponibilite!.trim(),
      ));
    }
    if (service.duree?.trim().isNotEmpty ?? false) {
      lignes.add(_ligneInfo(Icons.timer_outlined, 'Durée', service.duree!.trim()));
    }
    if (service.recuperation?.trim().isNotEmpty ?? false) {
      lignes.add(_ligneInfo(
        Icons.place_outlined,
        'Récupération',
        service.recuperation!.trim(),
      ));
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

  /// Service commun : le mode (libre ou rotation) et, en rotation, les
  /// participants dans l'ordre de passage. L'auteur peut les modifier.
  List<Widget> _carteParticipants(Service service) {
    final bool estMonService =
        service.auteurId.isNotEmpty && service.auteurId == _repository.getMonId();
    if (!service.modeRotation) {
      return [
        AppCard(
          child: _ligneInfo(Icons.event_note_outlined, 'Mode', 'Inscription libre'),
        ),
        const SizedBox(height: 16),
      ];
    }
    final List<TourRotation> participants = service.participants;
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ligneInfo(Icons.autorenew, 'Mode', 'Rotation automatique'),
            const SizedBox(height: 6),
            const Text(
              'Ordre de passage',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (participants.isEmpty)
              Text(
                'Aucun participant',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            for (int i = 0; i < participants.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${i + 1}. ${participants[i].nom}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            if (estMonService) ...[
              const SizedBox(height: 10),
              SecondaryButton(
                texte: 'Modifier les participants',
                icone: Icons.groups_outlined,
                onPressed: _enCours ? null : () => _modifierParticipants(service),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  /// L'auteur ajoute, retire ou réordonne les participants.
  Future<void> _modifierParticipants(Service service) async {
    final List<ParticipantRotation>? choisis = await ouvrirEcran<List<ParticipantRotation>>(
      context,
      ParticipantsRotationScreen(
        minimum: 0,
        initiaux: [
          for (final TourRotation p in service.participants)
            ParticipantRotation(id: p.id, nom: p.nom),
        ],
      ),
    );
    if (choisis == null || !mounted) {
      return;
    }
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.modifierParticipants(
      service.id,
      [for (final p in choisis) p.id],
      [for (final p in choisis) p.nom],
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    afficherMessage(
      context,
      resultat.estSucces ? 'Participants enregistrés' : resultat.erreur!,
    );
  }

  /// L'auteur prolonge le planning de 4 semaines.
  Future<void> _prolonger(Service service) async {
    setState(() {
      _enCours = true;
    });
    final Resultat<int> resultat = await _repository.prolongerPlanning(service.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    String message;
    if (!resultat.estSucces) {
      message = resultat.erreur!;
    } else if (resultat.donnee == 0) {
      message = 'Le planning est déjà à jour';
    } else {
      message = '${resultat.donnee} créneaux ajoutés';
    }
    afficherMessage(context, message);
  }

  Widget _ligneInfo(IconData icone, String titre, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(titre, style: TextStyle(color: AppColors.textSecondary)),
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

  /// La zone fixe en bas : bouton de demande, planning ou "Votre publication".
  Widget _actions(Service service) {
    final bool estMonService =
        service.auteurId.isNotEmpty && service.auteurId == _repository.getMonId();
    final List<Widget> contenu = [];

    if (estMonService) {
      contenu.add(Text(
        'Votre publication',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ));
      contenu.add(const SizedBox(height: 12));
      contenu.add(Row(
        children: [
          Expanded(
            child: SecondaryButton(
              texte: 'Supprimer',
              onPressed: _enCours ? null : () => _supprimer(service),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              texte: 'Modifier',
              onPressed: _enCours ? null : () => _modifier(service),
            ),
          ),
        ],
      ));
    }

    if (service.estCommun) {
      if (contenu.isNotEmpty) {
        contenu.add(const SizedBox(height: 12));
      }
      if (estMonService) {
        contenu.add(SecondaryButton(
          texte: 'Prolonger le planning (+4 semaines)',
          icone: Icons.add_circle_outline,
          onPressed: _enCours ? null : () => _prolonger(service),
        ));
        contenu.add(const SizedBox(height: 12));
      }
      contenu.add(PrimaryButton(
        texte: 'Voir le planning',
        icone: Icons.calendar_month_outlined,
        onPressed: () {
          ouvrirEcran(context, const ServicesCommunsScreen());
        },
      ));
    } else if (!estMonService) {
      contenu.add(_boutonDemande(service));
      contenu.add(const SizedBox(height: 10));
      contenu.add(Text(
        '${service.auteurNom} recevra la demande et pourra l\'accepter',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ));
    }

    if (contenu.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: contenu),
      ),
    );
  }

  /// "Demander ce service", ou "Demande envoyée" si j'ai déjà demandé.
  Widget _boutonDemande(Service service) {
    return StreamBuilder<List<DemandeService>>(
      stream: _fluxEnvoyees,
      builder: (context, instantane) {
        bool dejaDemande = false;
        for (final demande in instantane.data ?? const <DemandeService>[]) {
          if (demande.serviceId == service.id) {
            dejaDemande = true;
          }
        }
        return PrimaryButton(
          texte: dejaDemande ? 'Demande envoyée' : 'Demander ce service',
          icone: dejaDemande ? Icons.check : null,
          // null = bouton désactivé
          onPressed: (dejaDemande || _enCours) ? null : () => _demander(service),
        );
      },
    );
  }
}

/// La carte de l'auteur d'un service. La note est calculée une seule fois
/// à l'ouverture (average() et count() sur les évaluations).
class _CarteAuteur extends StatefulWidget {
  final Service service;
  final ServiceRepository repository;

  const _CarteAuteur({
    super.key,
    required this.service,
    required this.repository,
  });

  @override
  State<_CarteAuteur> createState() {
    return _CarteAuteurState();
  }
}

class _CarteAuteurState extends State<_CarteAuteur> {
  late final Future<Resultat<ResumeAuteur>> _resume = widget.repository
      .getResumeAuteur(widget.service.auteurId);

  @override
  Widget build(BuildContext context) {
    final Service service = widget.service;
    return AppCard(
      child: Row(
        children: [
          AvatarInitiales(nom: service.auteurNom),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.auteurNom,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (service.bloc.isNotEmpty)
                  Text(
                    service.bloc,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Flexible(child: _texteNote()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _texteNote() {
    return FutureBuilder<Resultat<ResumeAuteur>>(
      future: _resume,
      builder: (context, instantane) {
        String texte = 'Note en cours de chargement…';
        final Resultat<ResumeAuteur>? resultat = instantane.data;
        if (resultat != null && resultat.estSucces) {
          final ResumeAuteur resume = resultat.donnee!;
          if (resume.nombreAvis == 0) {
            texte = 'Pas encore d\'avis';
          } else {
            final String texteNote =
                '${resume.noteMoyenne.toStringAsFixed(1)} (${resume.nombreAvis} avis)';
            final String texteRendus = resume.servicesRendus <= 1
                ? '${resume.servicesRendus} service rendu'
                : '${resume.servicesRendus} services rendus';
            texte = '$texteNote · $texteRendus';
          }
        } else if (resultat != null || instantane.hasError) {
          texte = 'Note indisponible';
        }
        return Text(
          texte,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        );
      },
    );
  }
}
