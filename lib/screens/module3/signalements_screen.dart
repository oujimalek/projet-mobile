import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/resultat.dart';
import '../../data/services/signalement_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/status_badge.dart';
import 'create_signalement_screen.dart';
import 'signalement_detail_screen.dart';
import 'widgets_module3.dart';

/// Les deux façons de trier la liste.
enum TriSignalements { recents, urgents }

/// M3 - Signalements : la liste du quartier (onglet "Signalements").
///
/// StatefulWidget : les choix de l'utilisateur changent l'affichage
///   - "Tous" ou "Mes signalements" ;
///   - le filtre de statut et le filtre de catégorie ;
///   - le tri : plus récents ou plus urgents.
/// Toucher une carte ouvre le détail ; le bouton "Signaler" ouvre la création.
class SignalementsScreen extends StatefulWidget {
  const SignalementsScreen({super.key});

  @override
  State<SignalementsScreen> createState() {
    return _SignalementsScreenState();
  }
}

class _SignalementsScreenState extends State<SignalementsScreen> {
  // Données et état du chargement
  List<Signalement> _signalements = [];
  bool _enChargement = true; // true : le premier chargement démarre tout de suite
  String? _erreur; // message affiché si le chargement a échoué
  int _numeroChargement = 0; // pour ignorer une réponse arrivée trop tard

  // Choix de l'utilisateur
  bool _mesSignalements = false; // false = tout le quartier
  StatutSignalement? _statutChoisi; // null = tous les statuts
  String? _categorieChoisie; // null = toutes les catégories
  TriSignalements _tri = TriSignalements.recents;

  @override
  void initState() {
    super.initState();
    // Pas de setState pendant initState : _enChargement vaut déjà true
    _chargerDonnees();
  }

  /// Recharge la liste (filtre changé, tirer pour actualiser, retour d'un écran).
  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    await _chargerDonnees();
  }

  /// Demande la liste au repository selon les filtres choisis.
  Future<void> _chargerDonnees() async {
    _numeroChargement++;
    final int numero = _numeroChargement;
    final SignalementRepository repository = SignalementRepository();
    Resultat<List<Signalement>> resultat;
    if (_mesSignalements) {
      resultat = await repository.getMesSignalements();
    } else {
      resultat = await repository.getSignalements(
        statut: _statutChoisi,
        categorieId: _categorieChoisie,
      );
    }
    // L'écran est fermé, ou un autre chargement a commencé entre-temps
    if (!mounted || numero != _numeroChargement) {
      return;
    }

    setState(() {
      _enChargement = false;
      if (!resultat.estSucces) {
        _erreur = resultat.erreur;
        return;
      }
      List<Signalement> liste = resultat.donnee!;
      if (_mesSignalements) {
        // "Mes signalements" : les filtres sont appliqués ici
        if (_statutChoisi != null) {
          liste = liste.where((s) => s.statut == _statutChoisi).toList();
        }
        liste = SignalementRepository.filtrerParCategorie(
          liste,
          _categorieChoisie,
        );
      }
      _signalements = liste;
    });
  }

  /// La liste triée selon le choix de l'utilisateur.
  List<Signalement> get _listeTriee {
    if (_tri == TriSignalements.urgents) {
      return SignalementRepository.trierParUrgence(_signalements);
    }
    return SignalementRepository.trierParDate(_signalements);
  }

  /// Ouvre la création. Au retour (publié), message + rechargement.
  Future<void> _ouvrirCreation() async {
    final bool? publie = await ouvrirEcranM3<bool>(
      context,
      const CreateSignalementScreen(),
    );
    if (!mounted || publie != true) {
      return;
    }
    afficherMessageM3(
      context,
      tr('Yaatik saha ! Signalement publié.', 'Yaatik saha ! Tablighek tbaath.'),
    );
    _charger();
  }

  /// Ouvre le détail. Au retour, on recharge (confirmation, statut,
  /// modification ou suppression ont pu changer la liste).
  Future<void> _ouvrirDetail(Signalement signalement) async {
    final bool? supprime = await ouvrirEcranM3<bool>(
      context,
      SignalementDetailScreen(signalementId: signalement.id),
    );
    if (!mounted) {
      return;
    }
    if (supprime == true) {
      afficherMessageM3(context, tr('Signalement supprimé', 'Tabligh tfasakh'));
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Signalements', 'Tablighat')),
          const SizedBox(height: 12),
          _ongletsTousMes(),
          const SizedBox(height: 12),
          _filtresStatut(),
          const SizedBox(height: 8),
          _filtresCategorie(),
          const SizedBox(height: 8),
          _ligneTri(),
          // Fine barre de chargement quand une liste est déjà affichée
          SizedBox(
            height: 2,
            child: _enChargement && _signalements.isNotEmpty
                ? const LinearProgressIndicator()
                : null,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _charger,
              child: _contenu(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirCreation,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(
          tr('Signaler', 'Ballegh'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // Pas de barre du bas ici : elle est affichée par le routeur
    );
  }

  /// Le contenu sous les filtres : chargement, erreur, vide ou liste.
  /// Toujours une ListView défilante, pour que "tirer pour actualiser"
  /// marche aussi sur un message.
  Widget _contenu() {
    if (_enChargement && _signalements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? erreur = _erreur;
    if (erreur != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          MessageEtatM3(
            icone: Icons.cloud_off,
            texte: erreur,
            texteBouton: tr('Réessayer', '3awed'),
            onBouton: _charger,
          ),
        ],
      );
    }
    final List<Signalement> liste = _listeTriee;
    if (liste.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          MessageEtatM3(
            icone: Icons.campaign_outlined,
            texte: _texteListeVide(),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemCount: liste.length,
      itemBuilder: (context, index) {
        return _carteSignalement(liste[index]);
      },
    );
  }

  /// Le message quand il n'y a rien à afficher.
  String _texteListeVide() {
    if (_statutChoisi != null || _categorieChoisie != null) {
      return tr('Aucun signalement avec ces filtres',
          'Hatta tabligh b les filtres hedhom');
    }
    if (_mesSignalements) {
      return tr('Tu n\'as encore rien signalé',
          'Mazelt ma ballaght 3la chay');
    }
    return tr('Aucun signalement pour l\'instant. Tout va bien dans la houma !',
        'Hatta tabligh lel wa9t. El houma labes !');
  }

  /// Les deux onglets "Tous" / "Mes signalements".
  Widget _ongletsTousMes() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Expanded(child: _onglet(tr('Tous', 'El kol'), false)),
          Expanded(
            child: _onglet(tr('Mes signalements', 'Tablighati'), true),
          ),
        ],
      ),
    );
  }

  /// Un onglet. [mes] : true pour "Mes signalements".
  Widget _onglet(String texte, bool mes) {
    final bool actif = _mesSignalements == mes;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (actif) {
          return;
        }
        setState(() {
          _mesSignalements = mes;
          _signalements = [];
        });
        _charger();
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

  /// Les filtres de statut, sur une ligne qui défile.
  Widget _filtresStatut() {
    final List<Widget> filtres = [
      _filtre(
        texte: tr('Tous les statuts', 'Kol el 7alet'),
        actif: _statutChoisi == null,
        onTap: () => _choisirStatut(null),
      ),
    ];
    for (final StatutSignalement statut in StatutSignalement.values) {
      filtres.add(_filtre(
        texte: texteStatut(statut),
        actif: _statutChoisi == statut,
        onTap: () => _choisirStatut(statut),
      ));
    }
    return _ligneQuiDefile(filtres);
  }

  /// Les filtres de catégorie, sur une ligne qui défile.
  Widget _filtresCategorie() {
    final List<Widget> filtres = [
      _filtre(
        texte: tr('Toutes', 'El kol'),
        actif: _categorieChoisie == null,
        onTap: () => _choisirCategorie(null),
      ),
    ];
    for (final CategorieSignalement categorie
        in SignalementRepository.categories) {
      filtres.add(_filtre(
        texte: categorie.nom,
        icone: categorie.icone,
        couleurIcone: categorie.couleur,
        actif: _categorieChoisie == categorie.id,
        onTap: () => _choisirCategorie(categorie.id),
      ));
    }
    return _ligneQuiDefile(filtres);
  }

  void _choisirStatut(StatutSignalement? statut) {
    setState(() {
      _statutChoisi = statut;
    });
    _charger();
  }

  void _choisirCategorie(String? categorieId) {
    setState(() {
      _categorieChoisie = categorieId;
    });
    _charger();
  }

  /// Une ligne de filtres qui défile horizontalement.
  Widget _ligneQuiDefile(List<Widget> filtres) {
    final List<Widget> espaces = [];
    for (final Widget filtre in filtres) {
      espaces.add(Padding(
        padding: const EdgeInsets.only(right: 8),
        child: filtre,
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: espaces),
    );
  }

  /// Un filtre (doré quand il est sélectionné), comme dans le module 2.
  Widget _filtre({
    required String texte,
    required bool actif,
    required Function() onTap,
    IconData? icone,
    Color? couleurIcone,
  }) {
    final List<Widget> contenu = [];
    if (icone != null) {
      contenu.add(Icon(
        icone,
        size: 16,
        color: actif ? Colors.white : couleurIcone,
      ));
      contenu.add(const SizedBox(width: 4));
    }
    contenu.add(Text(
      texte,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: actif ? Colors.white : AppColors.textPrimary,
      ),
    ));
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
        child: Row(mainAxisSize: MainAxisSize.min, children: contenu),
      ),
    );
  }

  /// Le texte d'un tri.
  String _texteTri(TriSignalements tri) {
    if (tri == TriSignalements.urgents) {
      return tr('Plus urgents', 'El mosta3jlin');
    }
    return tr('Plus récents', 'El jdod');
  }

  /// Le nombre de signalements et le choix du tri (petit menu).
  Widget _ligneTri() {
    final int nombre = _signalements.length;
    final List<PopupMenuEntry<TriSignalements>> choix = [];
    for (final TriSignalements tri in TriSignalements.values) {
      choix.add(PopupMenuItem<TriSignalements>(
        value: tri,
        child: Text(_texteTri(tri)),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              nombre <= 1
                  ? tr('$nombre signalement', '$nombre tabligh')
                  : tr('$nombre signalements', '$nombre tablighat'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          PopupMenuButton<TriSignalements>(
            tooltip: tr('Trier', 'Rattab'),
            initialValue: _tri,
            onSelected: (tri) {
              setState(() {
                _tri = tri;
              });
            },
            itemBuilder: (context) => choix,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    _texteTri(_tri),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La carte d'un signalement dans la liste.
  Widget _carteSignalement(Signalement signalement) {
    final CategorieSignalement categorie =
        SignalementRepository.getCategorieParId(signalement.categorieId);

    // Titre, avec l'étiquette "Danger" si besoin
    final List<Widget> ligneTitre = [
      Expanded(
        child: Text(
          signalement.titre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ];
    if (signalement.danger) {
      ligneTitre.add(const SizedBox(width: 6));
      ligneTitre.add(const EtiquetteDanger());
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () {
          _ouvrirDetail(signalement);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PastilleCategorie(categorie: categorie),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: ligneTitre),
                  const SizedBox(height: 4),
                  // Lieu · depuis quand
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '${signalement.lieu} · ${depuisQuandM3(signalement.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Statut, urgence et nombre de confirmations
                  Row(
                    children: [
                      // Wrap : les badges passent à la ligne sur un petit écran
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            StatusBadge(statut: signalement.statut),
                            BadgeUrgence(
                              niveau: SignalementRepository.niveauUrgence(
                                signalement,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.people_alt_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${signalement.nbConfirmations}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
