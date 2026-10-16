import 'package:flutter/material.dart';

import '../../data/models/creneau_commun.dart';
import '../../data/services/service_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'inscription_creneau_screen.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Planning des services communs (écran 06).
///
/// Une semaine (du lundi au dimanche) en haut, et en dessous les créneaux
/// du jour choisi. On peut s'inscrire à un créneau libre.
class ServicesCommunsScreen extends StatefulWidget {
  const ServicesCommunsScreen({super.key});

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

  late final DateTime _aujourdhui; // aujourd'hui, sans l'heure
  late final DateTime _lundi; // premier jour de la semaine affichée
  late DateTime _jourChoisi; // jour dont on affiche les créneaux

  @override
  void initState() {
    super.initState();
    final DateTime maintenant = DateTime.now();
    _aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    _lundi = DateTime(
      _aujourdhui.year,
      _aujourdhui.month,
      _aujourdhui.day - (_aujourdhui.weekday - 1),
    );
    _jourChoisi = _aujourdhui; // aujourd'hui est choisi par défaut
  }

  /// Ouvre l'inscription à un créneau (le planning se met à jour tout seul).
  void _ouvrirInscription(CreneauCommun creneau) {
    ouvrirEcran(context, InscriptionCreneauScreen(creneauId: creneau.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _enTete(),
          const SizedBox(height: 16),
          Expanded(
            child: FluxM2<List<CreneauCommun>>(
              flux: _flux,
              construire: (context, semaine) {
                final List<CreneauCommun> creneaux = [];
                for (final creneau in semaine) {
                  if (memeJour(creneau.date, _jourChoisi)) {
                    creneaux.add(creneau);
                  }
                }
                return Column(
                  children: [
                    _bandeauSemaine(semaine),
                    const SizedBox(height: 16),
                    Expanded(
                      child: creneaux.isEmpty
                          ? MessageEtat(
                              texte: semaine.isEmpty
                                  ? 'Aucun service commun pour l\'instant. '
                                      'Publie le premier !'
                                  : 'Aucun créneau ce jour-là',
                              icone: Icons.calendar_month_outlined,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: creneaux.length,
                              itemBuilder: (context, index) {
                                return _carteCreneau(creneaux[index]);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
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
                  color: choisi ? AppColors.card : AppColors.textPrimary,
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

  /// La carte d'un créneau : titre, horaire, inscrit ou "Créneau libre".
  Widget _carteCreneau(CreneauCommun creneau) {
    final String moi = _repository.getMonId();
    final bool estMoi = creneau.inscritId == moi;

    // Un créneau d'un jour déjà passé ne se réserve plus
    final bool passe = creneau.date.isBefore(_aujourdhui);

    // Ce qui s'affiche sous l'horaire
    Widget statut;
    if (passe) {
      final String qui = creneau.estLibre ? '' : ' · ${estMoi ? 'Toi' : creneau.inscrit}';
      statut = Text(
        'Créneau passé$qui',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    } else if (creneau.estLibre) {
      statut = PastilleTexte(
        texte: 'Créneau libre',
        couleur: AppColors.badgeResolu,
        fond: AppColors.badgeResoluFond,
      );
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

    // Le bouton à droite : S'inscrire (libre) ou Gérer (mon créneau)
    Widget? bouton;
    if (passe) {
      bouton = null; // pas de bouton pour un créneau passé
    } else if (creneau.estLibre) {
      bouton = PrimaryButton(
        texte: 'S\'inscrire',
        onPressed: () {
          _ouvrirInscription(creneau);
        },
      );
    } else if (estMoi) {
      bouton = SecondaryButton(
        texte: 'Gérer',
        onPressed: () {
          _ouvrirInscription(creneau);
        },
      );
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
            if (bouton != null) ...[
              const SizedBox(width: 12),
              SizedBox(width: 120, child: bouton),
            ],
          ],
        ),
      ),
    );
  }
}
