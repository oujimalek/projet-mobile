import 'package:flutter/material.dart';

import '../../data/models/creneau_commun.dart';
import '../../data/models/service.dart';
import '../../data/resultat.dart';
import '../../data/services/jours_feries_m2.dart';
import '../../data/services/service_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'bandeau_rappel.dart';
import 'inscription_creneau_screen.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';
import 'tours_en_direct.dart';

/// M2 - Planning des services communs (écran 06).
///
/// Une semaine (du lundi au dimanche) en haut, et en dessous les créneaux
/// du jour choisi. On peut s'inscrire à un créneau libre.
class ServicesCommunsScreen extends StatefulWidget {
  /// Le jour affiché au départ (sa semaine est montrée). Par défaut : aujourd'hui.
  final DateTime? jourInitial;

  const ServicesCommunsScreen({super.key, this.jourInitial});

  @override
  State<ServicesCommunsScreen> createState() {
    return _ServicesCommunsScreenState();
  }
}

class _ServicesCommunsScreenState extends State<ServicesCommunsScreen> {
  final ServiceRepository _repository = ServiceRepository();

  // Les créneaux de la semaine, en direct (créé UNE fois : voir FluxM2)
  late final Stream<List<CreneauCommun>> _flux = _repository
      .ecouterCreneauxDeLaSemaine(_lundi);

  // Les services (rotation, créneaux faits), en direct
  late final Stream<List<Service>> _fluxServices = _repository.ecouterServices();

  bool _enCours = false; // true pendant « Marquer fait »

  late final DateTime _aujourdhui; // aujourd'hui, sans l'heure
  late final DateTime _lundi; // premier jour de la semaine affichée
  late DateTime _jourChoisi; // jour dont on affiche les créneaux

  // Jours fériés de la semaine ('AAAA-MM-JJ' → nom), via Nager.Date
  Map<String, String> _feries = {};

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime depart = widget.jourInitial == null
        ? _aujourdhui
        : DateTime(
            widget.jourInitial!.year,
            widget.jourInitial!.month,
            widget.jourInitial!.day,
          );
    _lundi = DateTime(depart.year, depart.month, depart.day - (depart.weekday - 1));
    _jourChoisi = depart; // aujourd'hui est choisi par défaut
    _chargerJoursFeries();
  }

  /// Les jours fériés de l'année (des deux années si la semaine est à
  /// cheval sur le 1er janvier). Sans réseau ni cache : rien n'est marqué.
  Future<void> _chargerJoursFeries() async {
    final DateTime dimanche =
        DateTime(_lundi.year, _lundi.month, _lundi.day + 6);
    final Set<int> annees = {_lundi.year, dimanche.year};
    final Map<String, String> feries = {};
    for (final int annee in annees) {
      final Resultat<Map<String, String>> resultat =
          await JoursFeriesM2.joursDe(annee);
      feries.addAll(resultat.donnee ?? {});
    }
    if (!mounted || feries.isEmpty) {
      return;
    }
    setState(() {
      _feries = feries;
    });
  }

  /// Le nom du jour férié, ou null si c'est un jour ordinaire.
  String? _ferie(DateTime jour) {
    return _feries[JoursFeriesM2.cle(jour)];
  }

  /// Ouvre l'inscription à un créneau (le planning se met à jour tout seul).
  void _ouvrirInscription(CreneauCommun creneau) {
    ouvrirEcran(context, InscriptionCreneauScreen(creneauId: creneau.id));
  }

  /// « Marquer fait » (l'auteur du service seulement).
  Future<void> _marquerFait(CreneauCommun creneau) async {
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.marquerFait(creneau.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    afficherMessage(
      context,
      resultat.estSucces ? 'Créneau marqué comme fait' : resultat.erreur!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _enTete(),
          const BandeauRappel(),
          const SizedBox(height: 16),
          Expanded(
            child: FluxM2<List<Service>>(
              flux: _fluxServices,
              construire: (context, services) {
                return ToursEnDirect(
                  services: services,
                  construire: (context, donnees) {
                    return FluxM2<List<CreneauCommun>>(
                      flux: _flux,
                      construire: (context, semaine) {
                        return _corps(services, donnees, semaine);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// La semaine, puis les encarts « Prochain tour » et les créneaux du jour.
  Widget _corps(
    List<Service> services,
    DonneesRotation donnees,
    List<CreneauCommun> semaine,
  ) {
    final List<CreneauCommun> creneaux = [];
    for (final creneau in semaine) {
      if (memeJour(creneau.date, _jourChoisi)) {
        creneaux.add(creneau);
      }
    }
    final List<Widget> encarts = [];
    for (final Service service in services) {
      if (service.estCommun && service.modeRotation && service.participantsIds.isNotEmpty) {
        final Widget? encart = _encartProchainsTours(service, donnees);
        if (encart != null) {
          encarts.add(encart);
        }
      }
    }
    final String? ferie = _ferie(_jourChoisi);
    return Column(
      children: [
        _bandeauSemaine(semaine),
        const SizedBox(height: 16),
        if (ferie != null) _bandeauFerie(ferie, creneaux.isNotEmpty),
        Expanded(
          child: (creneaux.isEmpty && encarts.isEmpty)
              ? MessageEtat(
                  texte: semaine.isEmpty
                      ? 'Aucun service commun pour l\'instant. '
                          'Publie le premier !'
                      : 'Aucun créneau ce jour-là',
                  icone: Icons.calendar_month_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ...encarts,
                    if (creneaux.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Aucun créneau ce jour-là',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final CreneauCommun creneau in creneaux)
                      _carteCreneau(creneau, services, donnees),
                  ],
                ),
        ),
      ],
    );
  }

  /// « Prochain tour de chacun » pour un service en rotation.
  Widget? _encartProchainsTours(Service service, DonneesRotation donnees) {
    final List<CreneauCommun>? liste = donnees.creneauxParService[service.id];
    if (liste == null) {
      return null; // pas encore chargé
    }
    final List<ProchainTour> prochains = ServiceRepository.prochainsTours(
      service,
      liste,
      donnees.tours,
      DateTime.now(),
    );
    final String moi = _repository.getMonId();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prochain tour de chacun',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              service.titre,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < prochains.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${i + 1}. ${prochains[i].participant.nom}'
                        '${prochains[i].participant.id == moi ? ' (toi)' : ''}',
                      ),
                    ),
                    Text(
                      prochains[i].creneau == null
                          ? '—'
                          : dateCourte(prochains[i].creneau!.date),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// En-tête blanc arrondi : flèche retour, titre et résidence.
  Widget _enTete() {
    final String residence =
        UtilisateurRepository().getUtilisateurConnecte().residence;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 12,
        24,
        16,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: Icon(Icons.arrow_back, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Services communs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  residence,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Jour férié : Fête de la République" (+ un rappel s'il y a des créneaux).
  Widget _bandeauFerie(String nom, bool aDesCreneaux) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.incidentLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          children: [
            Icon(Icons.celebration_outlined, color: AppColors.incident),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jour férié : $nom',
                    style: TextStyle(
                      color: AppColors.incident,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (aDesCreneaux)
                    Text(
                      'Vérifie que le créneau est bien maintenu.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Les 7 jours de la semaine (le jour choisi est doré).
  Widget _bandeauSemaine(List<CreneauCommun> semaine) {
    final List<Widget> jours = [];
    for (int i = 0; i < 7; i++) {
      final DateTime jour = DateTime(_lundi.year, _lundi.month, _lundi.day + i);
      jours.add(Expanded(child: _caseJour(jour, semaine)));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: jours),
    );
  }

  /// Un jour du bandeau : "Lun" + numéro, et un point s'il y a des créneaux.
  Widget _caseJour(DateTime jour, List<CreneauCommun> semaine) {
    final bool choisi = memeJour(jour, _jourChoisi);
    final bool estAujourdhui = memeJour(jour, _aujourdhui);
    final bool ferie = _ferie(jour) != null; // numéro en rouge
    bool aDesCreneaux = false;
    for (final creneau in semaine) {
      if (memeJour(creneau.date, jour)) {
        aDesCreneaux = true;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        onTap: () {
          setState(() {
            _jourChoisi = jour;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: choisi ? AppColors.secondary : AppColors.card,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: choisi
                  ? AppColors.secondary
                  : (estAujourdhui ? AppColors.primary : AppColors.border),
            ),
          ),
          child: Column(
            children: [
              Text(
                jourCourt(jour),
                style: TextStyle(
                  fontSize: 12,
                  color: choisi ? AppColors.card : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${jour.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: choisi
                      ? AppColors.card
                      : (ferie ? AppColors.incident : AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              // Petit point : il y a au moins un créneau ce jour-là
              if (aDesCreneaux)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: choisi ? AppColors.card : AppColors.secondary,
                  ),
                )
              else
                const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }

  /// La carte d'un créneau : titre, horaire, badge d'état, tour, boutons.
  Widget _carteCreneau(
    CreneauCommun creneau,
    List<Service> services,
    DonneesRotation donnees,
  ) {
    final String moi = _repository.getMonId();
    final bool estMoi = creneau.inscritId != null && creneau.inscritId == moi;

    Service? service;
    for (final Service s in services) {
      if (s.id == creneau.serviceId) {
        service = s;
      }
    }
    final FaitCreneau? fait = service?.creneauxFaits[creneau.id];
    final bool estFait = fait != null;
    final bool estAuteur =
        service != null && service.auteurId.isNotEmpty && service.auteurId == moi;
    final TourRotation? tour =
        (service?.modeRotation ?? false) ? donnees.tours[creneau.id] : null;
    final bool tourEstMoi = tour != null && tour.id == moi;

    // Un créneau d'un jour déjà passé ne se réserve plus
    final bool passe = creneau.date.isBefore(_aujourdhui);
    // Un tour non confirmé est réservé à son titulaire (sauf désistement)
    final bool reserve = creneau.estLibre &&
        !creneau.estDesiste &&
        tour != null &&
        !tourEstMoi;

    // Ce qui s'affiche sous l'horaire (le marqueur de désistement ne
    // s'affiche jamais : creneau.inscrit ne le renvoie pas)
    Widget statut;
    if (fait != null) {
      final String par = fait.parNom.isEmpty ? '' : 'par ${fait.parNom}';
      statut = Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PastilleTexte(
            texte: 'Fait ✓',
            couleur: AppColors.badgeResolu,
            fond: AppColors.badgeResoluFond,
          ),
          if (par.isNotEmpty)
            Text(
              par,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
        ],
      );
    } else if (passe) {
      String qui = '';
      if (!creneau.estLibre) {
        qui = ' · ${estMoi ? 'Toi' : creneau.inscrit}';
      } else if (tour != null && !creneau.estDesiste) {
        qui = ' · Tour de ${tour.nom}';
      }
      statut = Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PastilleTexte(
            texte: 'À faire',
            couleur: AppColors.badgeEnAttente,
            fond: AppColors.badgeEnAttenteFond,
          ),
          Text(
            'Créneau passé$qui',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      );
    } else if (creneau.estLibre) {
      if (tourEstMoi && !creneau.estDesiste) {
        statut = PastilleTexte(
          texte: 'C\'est ton tour',
          couleur: AppColors.primary,
          fond: AppColors.primaryLight,
        );
      } else if (reserve) {
        statut = Text(
          'Tour de ${tour.nom}',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        );
      } else {
        statut = PastilleTexte(
          texte: 'Créneau libre',
          couleur: AppColors.badgeResolu,
          fond: AppColors.badgeResoluFond,
        );
      }
    } else if (estMoi) {
      statut = PastilleTexte(
        texte: 'Toi',
        couleur: AppColors.primary,
        fond: AppColors.primaryLight,
      );
    } else {
      statut = Text(
        'Inscrit : ${creneau.inscrit}',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }

    // Les boutons à droite : Confirmer / S'inscrire (libre), Gérer (mon
    // créneau), Marquer fait (l'auteur du service, le jour même ou après)
    final List<Widget> boutons = [];
    if (!estFait) {
      if (!passe) {
        if (creneau.estLibre) {
          if (tourEstMoi && !creneau.estDesiste) {
            boutons.add(PrimaryButton(
              texte: 'Confirmer',
              onPressed: () {
                _ouvrirInscription(creneau);
              },
            ));
          } else if (!reserve) {
            boutons.add(PrimaryButton(
              texte: 'S\'inscrire',
              onPressed: () {
                _ouvrirInscription(creneau);
              },
            ));
          }
        } else if (estMoi) {
          boutons.add(SecondaryButton(
            texte: 'Gérer',
            onPressed: () {
              _ouvrirInscription(creneau);
            },
          ));
        }
      }
      if (estAuteur && !creneau.date.isAfter(_aujourdhui)) {
        if (boutons.isNotEmpty) {
          boutons.add(const SizedBox(height: 6));
        }
        boutons.add(SecondaryButton(
          texte: 'Marquer fait',
          onPressed: _enCours ? null : () => _marquerFait(creneau),
        ));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creneau.titre,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dateCourte(creneau.date)} · ${creneau.heureDebut} – ${creneau.heureFin}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  statut,
                ],
              ),
            ),
            if (boutons.isNotEmpty) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Column(mainAxisSize: MainAxisSize.min, children: boutons),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
