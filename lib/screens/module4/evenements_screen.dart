import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/models/sondage.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/photos_m4.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/arch_date_block.dart';
import 'calendrier_screen.dart';
import 'election_screen.dart';
import 'evenement_detail_screen.dart';
import 'evenement_form_screen.dart';
import 'module4_widgets.dart';
import 'nouveautes_m4.dart';
import 'sondage_form_screen.dart';
import 'sondage_screen.dart';
import 'statistiques_screen.dart';

/// Les filtres rapides de la liste des événements.
enum FiltreEvenements { tous, semaine, jOrganise, jeParticipe }

/// M4 - Onglet Événements : deux sous-onglets, "Événements" et "Sondages".
///
/// StatefulWidget : l'écran garde les listes chargées, l'onglet actif,
/// la recherche et les filtres choisis.
class EvenementsScreen extends StatefulWidget {
  const EvenementsScreen({super.key});

  @override
  State<EvenementsScreen> createState() {
    return _EvenementsScreenState();
  }
}

class _EvenementsScreenState extends State<EvenementsScreen> {
  final EvenementRepository _depot = EvenementRepository();
  final TextEditingController _recherche = TextEditingController();

  bool _ongletEvenements = true; // false = onglet "Sondages"

  // Événements
  List<Evenement> _evenements = [];
  Set<String> _mesParticipations = {}; // ids des événements où je participe
  bool _chargementEvenements = true;
  String? _erreurEvenements;

  // Sondages
  List<Sondage> _sondages = [];
  bool _chargementSondages = true;
  String? _erreurSondages;

  // Filtres
  FiltreEvenements _filtre = FiltreEvenements.tous;
  CategorieEvenement? _categorie; // null = toutes les catégories

  @override
  void initState() {
    super.initState();
    NouveautesM4.marquerVu(); // le point « nouveau » disparaît
    _chargerEvenements();
    _chargerSondages();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  // =====================================================================
  // Chargements
  // =====================================================================

  Future<void> _chargerEvenements() async {
    setState(() {
      _chargementEvenements = true;
      _erreurEvenements = null;
    });
    final Resultat<List<Evenement>> resultat = await _depot.chargerEvenements();
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      setState(() {
        _chargementEvenements = false;
        _erreurEvenements = resultat.erreur;
      });
      return;
    }

    // Où est-ce que je participe ? (seulement les événements à venir)
    final List<Evenement> liste = resultat.donnee!;
    final Set<String> participations = {};
    for (final Evenement evenement in liste) {
      if (evenement.estPasse) {
        continue;
      }
      final Resultat<bool> inscrit = await _depot.estInscrit(evenement.id);
      if (inscrit.donnee == true) {
        participations.add(evenement.id);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _chargementEvenements = false;
      _evenements = liste;
      _mesParticipations = participations;
    });
  }

  Future<void> _chargerSondages() async {
    setState(() {
      _chargementSondages = true;
      _erreurSondages = null;
    });
    final Resultat<List<Sondage>> resultat = await _depot.chargerSondages();
    if (!mounted) {
      return;
    }
    setState(() {
      _chargementSondages = false;
      if (resultat.estSucces) {
        _sondages = resultat.donnee!;
      } else {
        _erreurSondages = resultat.erreur;
      }
    });
  }

  // =====================================================================
  // Filtres
  // =====================================================================

  /// true si l'événement passe la recherche et les filtres choisis.
  bool _estAffiche(Evenement evenement) {
    final String texte = _recherche.text.trim().toLowerCase();
    if (texte.isNotEmpty &&
        !evenement.titre.toLowerCase().contains(texte) &&
        !evenement.lieu.toLowerCase().contains(texte) &&
        !evenement.description.toLowerCase().contains(texte)) {
      return false;
    }
    if (_categorie != null && evenement.categorie != _categorie) {
      return false;
    }
    switch (_filtre) {
      case FiltreEvenements.tous:
        return true;
      case FiltreEvenements.semaine:
        final DateTime dans7Jours = DateTime.now().add(const Duration(days: 7));
        return !evenement.estPasse && evenement.date.isBefore(dans7Jours);
      case FiltreEvenements.jOrganise:
        return evenement.organisateurId == _moi.id;
      case FiltreEvenements.jeParticipe:
        return _mesParticipations.contains(evenement.id);
    }
  }

  // =====================================================================
  // Navigation
  // =====================================================================

  /// Le bouton + : choisir entre un événement et un sondage.
  void _ouvrirCreation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.event_outlined, color: AppColors.primary),
                title: Text(tr('Nouvel événement', 'Événement jdid')),
                onTap: () {
                  Navigator.pop(context);
                  _nouvelEvenement();
                },
              ),
              ListTile(
                leading: Icon(Icons.poll_outlined, color: AppColors.primary),
                title: Text(tr('Nouveau sondage', 'Sondage jdid')),
                onTap: () {
                  Navigator.pop(context);
                  _nouveauSondage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _nouvelEvenement() async {
    final bool? cree =
        await ouvrirEcranM4<bool>(context, const EvenementFormScreen());
    if (!mounted || cree != true) {
      return;
    }
    setState(() {
      _ongletEvenements = true;
    });
    _chargerEvenements();
  }

  Future<void> _nouveauSondage() async {
    final bool? cree =
        await ouvrirEcranM4<bool>(context, const SondageFormScreen());
    if (!mounted || cree != true) {
      return;
    }
    setState(() {
      _ongletEvenements = false;
    });
    _chargerSondages();
  }

  /// Ouvre le détail ; au retour, la liste est rechargée (inscription,
  /// modification ou suppression).
  Future<void> _ouvrirEvenement(Evenement evenement) async {
    await ouvrirEcranM4<void>(
      context,
      EvenementDetailScreen(evenementId: evenement.id),
    );
    if (mounted) {
      _chargerEvenements();
    }
  }

  Future<void> _ouvrirSondage(Sondage sondage) async {
    await ouvrirEcranM4<void>(context, SondageScreen(sondageId: sondage.id));
    if (mounted) {
      _chargerSondages();
    }
  }

  // =====================================================================
  // Affichage
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _enTete(),
          const SizedBox(height: 16),
          _onglets(),
          const SizedBox(height: 12),
          Expanded(
            child: _ongletEvenements ? _contenuEvenements() : _contenuSondages(),
          ),
        ],
      ),
      // Bouton + : seulement pour les leaders et l'admin
      floatingActionButton: EvenementRepository.peutOrganiser(_moi)
          ? FloatingActionButton(
              onPressed: _ouvrirCreation,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 30),
            )
          : null,
    );
  }

  /// En-tête bleu cobalt (comme les autres onglets).
  Widget _enTete() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Événements',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('Ce qui se passe dans ta houma', 'Chnowa sayer fi houmtek'),
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          // Statistiques : pour l'admin seulement
          if (_moi.estAdmin)
            IconButton(
              tooltip: 'Statistiques',
              onPressed: () {
                ouvrirEcranM4<void>(context, const StatistiquesScreen());
              },
              icon: Icon(Icons.insights_outlined, color: AppColors.card),
            ),
          // Calendrier du mois
          IconButton(
            tooltip: 'Calendrier',
            onPressed: () async {
              await ouvrirEcranM4<void>(context, const CalendrierScreen());
              if (mounted) {
                _chargerEvenements();
              }
            },
            icon: Icon(Icons.calendar_month_outlined, color: AppColors.card),
          ),
          // Élection des leaders (pour tout le monde)
          IconButton(
            tooltip: 'Élection des leaders',
            onPressed: () {
              ouvrirEcranM4<void>(context, const ElectionScreen());
            },
            icon: Icon(Icons.how_to_vote_outlined, color: AppColors.card),
          ),
        ],
      ),
    );
  }

  /// Les deux onglets "Événements" / "Sondages".
  Widget _onglets() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(child: _onglet('Événements', true)),
          Expanded(child: _onglet('Sondages', false)),
        ],
      ),
    );
  }

  Widget _onglet(String texte, bool evenements) {
    final bool actif = _ongletEvenements == evenements;
    return InkWell(
      onTap: () {
        setState(() {
          _ongletEvenements = evenements;
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

  // ----- Onglet Événements -----

  Widget _contenuEvenements() {
    if (_chargementEvenements) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreurEvenements != null) {
      return MessageM4(
        texte: _erreurEvenements!,
        icone: Icons.error_outline,
        reessayer: _chargerEvenements,
      );
    }

    final List<Evenement> aVenir = [];
    final List<Evenement> passes = [];
    for (final Evenement evenement in _evenements) {
      if (!_estAffiche(evenement)) {
        continue;
      }
      if (evenement.estPasse) {
        passes.add(evenement);
      } else {
        aVenir.add(evenement);
      }
    }
    // À venir : les événements officiels (admin) d'abord, puis par date
    final List<Evenement> officiels = [];
    final List<Evenement> autres = [];
    for (final Evenement evenement in aVenir) {
      if (evenement.officiel) {
        officiels.add(evenement);
      } else {
        autres.add(evenement);
      }
    }
    aVenir
      ..clear()
      ..addAll(officiels)
      ..addAll(autres);
    // Passés : le plus récent d'abord
    final List<Evenement> passesRecents = passes.reversed.toList();

    final List<Widget> contenu = [
      _champRecherche(),
      const SizedBox(height: 10),
      _filtresRapides(),
      const SizedBox(height: 8),
      _filtresCategories(),
      const SizedBox(height: 16),
    ];

    if (aVenir.isEmpty && passesRecents.isEmpty) {
      contenu.add(
        MessageM4(
          texte: _evenements.isEmpty
              ? (EvenementRepository.peutOrganiser(_moi)
                  ? 'Aucun événement pour l\'instant.\nOrganise le premier avec le bouton + !'
                  : 'Aucun événement pour l\'instant.\nLes leaders de ta houma les annonceront ici.')
              : tr('Aucun événement ne correspond à ta recherche', 'Ma l9ina 7atta événement'),
          icone: Icons.event_busy_outlined,
        ),
      );
    }
    if (aVenir.isNotEmpty) {
      contenu.add(_titreSection(tr('À venir', 'Jeyin')));
      for (final Evenement evenement in aVenir) {
        contenu.add(_carteEvenement(evenement));
      }
    }
    if (passesRecents.isNotEmpty) {
      contenu.add(const SizedBox(height: 8));
      contenu.add(_titreSection(tr('Passés', 'Fetou')));
      for (final Evenement evenement in passesRecents) {
        contenu.add(_carteEvenement(evenement));
      }
    }

    return RefreshIndicator(
      onRefresh: _chargerEvenements,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        children: contenu,
      ),
    );
  }

  Widget _champRecherche() {
    return TextField(
      controller: _recherche,
      onChanged: (texte) {
        setState(() {}); // la liste se filtre à chaque lettre
      },
      decoration: InputDecoration(
        hintText: tr('Rechercher un événement, un lieu...', 'Lawej 3la événement, blassa...'),
        prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
        suffixIcon: _recherche.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _recherche.clear();
                  });
                },
              ),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  /// Tous · Cette semaine · J'organise · Je participe
  Widget _filtresRapides() {
    final Map<FiltreEvenements, String> textes = {
      FiltreEvenements.tous: tr('Tous', 'Kol chay'),
      FiltreEvenements.semaine: tr('Cette semaine', 'El jem3a hedhi'),
      FiltreEvenements.jOrganise: tr('J\'organise', 'Ena nnadhem'),
      FiltreEvenements.jeParticipe: tr('Je participe', 'Ena jey'),
    };
    final List<Widget> puces = [];
    for (final FiltreEvenements filtre in FiltreEvenements.values) {
      puces.add(
        _puce(textes[filtre]!, _filtre == filtre, () {
          setState(() {
            _filtre = filtre;
          });
        }),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: puces);
  }

  /// Une puce par catégorie (toucher la puce active la désélectionne).
  Widget _filtresCategories() {
    final List<Widget> puces = [];
    for (final CategorieEvenement categorie in CategorieEvenement.values) {
      puces.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _puce(
            categorie.libelle,
            _categorie == categorie,
            () {
              setState(() {
                _categorie = _categorie == categorie ? null : categorie;
              });
            },
            icone: iconeCategorie(categorie),
          ),
        ),
      );
    }
    // Défile horizontalement : 6 catégories ne tiennent pas sur une ligne
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: puces),
    );
  }

  Widget _puce(String texte, bool actif, Function() onTap, {IconData? icone}) {
    final Color couleurTexte = actif ? Colors.white : AppColors.textPrimary;
    final List<Widget> enfants = [];
    if (icone != null) {
      enfants.add(Icon(icone, size: 16, color: couleurTexte));
      enfants.add(const SizedBox(width: 4));
    }
    enfants.add(
      Text(
        texte,
        style: TextStyle(fontWeight: FontWeight.w600, color: couleurTexte),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? AppColors.secondary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? AppColors.secondary : AppColors.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: enfants),
      ),
    );
  }

  Widget _titreSection(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// La carte d'un événement : date en arc, titre, horaire et lieu,
  /// catégorie et nombre de participants.
  Widget _carteEvenement(Evenement evenement) {
    final List<Widget> badges = [PastilleCategorie(categorie: evenement.categorie)];
    if (evenement.officiel) {
      badges.add(
        BadgeM4(
          texte: tr('Officiel', 'Rasmi'),
          couleur: AppColors.primary,
          fond: AppColors.primaryLight,
        ),
      );
    }
    if (evenement.estComplet && !evenement.annule) {
      badges.add(
        BadgeM4(
          texte: tr('Complet', 'Kemel'),
          couleur: AppColors.error,
          fond: AppColors.badgeRefuseFond,
        ),
      );
    }
    if (evenement.annule) {
      badges.add(
        BadgeM4(
          texte: tr('Annulé', 'Tbattel'),
          couleur: AppColors.error,
          fond: AppColors.badgeRefuseFond,
        ),
      );
    }
    if (_mesParticipations.contains(evenement.id)) {
      badges.add(
        BadgeM4(
          texte: tr('Je participe', 'Ena jey'),
          couleur: AppColors.success,
          fond: AppColors.badgeResoluFond,
        ),
      );
    }
    if (evenement.organisateurId == _moi.id) {
      badges.add(
        BadgeM4(
          texte: tr('J\'organise', 'Ena nnadhem'),
          couleur: AppColors.primary,
          fond: AppColors.primaryLight,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        // les événements passés ou annulés en grisé
        opacity: evenement.estPasse || evenement.annule ? 0.6 : 1,
        child: AppCard(
          onTap: () {
            _ouvrirEvenement(evenement);
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La photo (petite), sinon la date en arc
              if (evenement.photoUrl != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        PhotosM4.miniature(evenement.photoUrl!, largeur: 150, hauteur: 150),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, erreur, pile) =>
                            ArchDateBlock(date: evenement.date),
                      ),
                    ),
                  ],
                )
              else
                ArchDateBlock(date: evenement.date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evenement.titre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${texteHoraire(evenement)} · ${evenement.lieu}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      evenement.placesMax > 0
                          ? '${evenement.participants} / ${evenement.placesMax} places'
                          : '${evenement.participants} participant${evenement.participants > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- Onglet Sondages -----

  Widget _contenuSondages() {
    if (_chargementSondages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreurSondages != null) {
      return MessageM4(
        texte: _erreurSondages!,
        icone: Icons.error_outline,
        reessayer: _chargerSondages,
      );
    }
    if (_sondages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _chargerSondages,
        child: ListView(
          children: [
            const SizedBox(height: 60),
            MessageM4(
              texte: EvenementRepository.peutOrganiser(_moi)
                  ? 'Aucun sondage pour l\'instant.\nPose une question à tes voisins avec le bouton + !'
                  : 'Aucun sondage pour l\'instant.',
              icone: Icons.poll_outlined,
            ),
          ],
        ),
      );
    }

    final List<Widget> contenu = [];
    bool titreTermines = false;
    contenu.add(_titreSection(tr('En cours', 'Mazelou')));
    if (!_sondages.first.estOuvert) {
      contenu.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            tr('Aucun sondage en cours', 'Ma famma 7atta sondage tawa'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    // La liste arrive triée : les ouverts d'abord, puis les terminés
    for (final Sondage sondage in _sondages) {
      if (!sondage.estOuvert && !titreTermines) {
        titreTermines = true;
        contenu.add(const SizedBox(height: 8));
        contenu.add(_titreSection(tr('Terminés', 'Kemlou')));
      }
      contenu.add(_carteSondage(sondage));
    }

    return RefreshIndicator(
      onRefresh: _chargerSondages,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        children: contenu,
      ),
    );
  }

  Widget _carteSondage(Sondage sondage) {
    final int votes = sondage.totalVotes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: sondage.estOuvert ? 1 : 0.6,
        child: AppCard(
          onTap: () {
            _ouvrirSondage(sondage);
          },
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.poll_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sondage.question,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$votes vote${votes > 1 ? 's' : ''} · ${texteFin(sondage.dateFin)}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
