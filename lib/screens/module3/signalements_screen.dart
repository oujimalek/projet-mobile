import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/resultat.dart';
import '../../data/services/base_locale_m3.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/sync_signalements_m3.dart';
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

  // Hors ligne (SQLite)
  final SyncSignalementsM3 _sync = SyncSignalementsM3.instance;
  List<EnvoiEnAttente> _envois = []; // mes signalements pas encore envoyés
  final Set<int> _envoisOccupes = {}; // "Réessayer" en cours
  bool _depuisCache = false; // la liste vient du cache SQLite
  bool _horsLigne = false;
  DateTime? _miseAJour; // dernier chargement complet (cache)

  // Choix de l'utilisateur
  bool _mesSignalements = false; // false = tout le quartier
  StatutSignalement? _statutChoisi; // null = tous les statuts
  String? _categorieChoisie; // null = toutes les catégories
  TriSignalements _tri = TriSignalements.recents;

  @override
  void initState() {
    super.initState();
    // Écoute la file d'envoi (ex : envoyée au retour du réseau)
    _sync.changements.addListener(_fileChangee);
    // Envoie la file maintenant et à chaque retour du réseau
    _sync.demarrer();
    // Pas de setState pendant initState : _enChargement vaut déjà true
    _chargerDonnees();
  }

  @override
  void dispose() {
    _sync.changements.removeListener(_fileChangee);
    super.dispose();
  }

  /// La file d'envoi a changé : on recharge (un envoi a pu partir).
  void _fileChangee() {
    if (mounted) {
      _charger();
    }
  }

  /// Recharge la liste (filtre changé, tirer pour actualiser, retour d'un écran).
  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    await _chargerDonnees();
  }

  /// Demande la liste selon les filtres choisis : SyncSignalementsM3 lit
  /// Firestore si le réseau est là, sinon le cache SQLite.
  Future<void> _chargerDonnees() async {
    _numeroChargement++;
    final int numero = _numeroChargement;
    final Resultat<ListeSignalementsM3> resultat =
        await _sync.chargerSignalements(
      statut: _statutChoisi,
      categorieId: _categorieChoisie,
      mesSignalements: _mesSignalements,
    );
    final List<EnvoiEnAttente> envois = await _sync.getEnvois();
    // L'écran est fermé, ou un autre chargement a commencé entre-temps
    if (!mounted || numero != _numeroChargement) {
      return;
    }

    setState(() {
      _enChargement = false;
      _envois = envois;
      if (!resultat.estSucces) {
        _erreur = resultat.erreur;
        _depuisCache = false;
        return;
      }
      final ListeSignalementsM3 liste = resultat.donnee!;
      _signalements = liste.signalements;
      _depuisCache = liste.depuisCache;
      _horsLigne = liste.horsLigne;
      _miseAJour = liste.miseAJour;
    });
  }

  /// "Réessayer" sur un envoi en attente.
  Future<void> _reessayerEnvoi(EnvoiEnAttente envoi) async {
    setState(() {
      _envoisOccupes.add(envoi.id!);
    });
    final Resultat<void> resultat = await _sync.reessayer(envoi.id!);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoisOccupes.remove(envoi.id!);
    });
    afficherMessageM3(
      context,
      resultat.estSucces
          ? tr('Signalement envoyé', 'Tabligh tbaath')
          : resultat.erreur!,
    );
  }

  /// "Annuler" un envoi en attente (après confirmation).
  Future<void> _annulerEnvoi(EnvoiEnAttente envoi) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Annuler cet envoi ?', 'Tbattel el ib3ath ?')),
          content: Text(tr('Le signalement ne sera pas envoyé.',
              'It-tabligh mouch bech yetb3ath.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Garder', 'Khallih')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(tr('Annuler l\'envoi', 'Battel')),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _sync.annuler(envoi.id!);
    }
  }

  /// La liste triée selon le choix de l'utilisateur.
  List<Signalement> get _listeTriee {
    if (_tri == TriSignalements.urgents) {
      return SignalementRepository.trierParUrgence(_signalements);
    }
    return SignalementRepository.trierParDate(_signalements);
  }

  /// Ouvre la création. Au retour : message (envoyé, ou gardé pour plus
  /// tard si pas de réseau) + rechargement.
  Future<void> _ouvrirCreation() async {
    final EtatPublicationM3? etat = await ouvrirEcranM3<EtatPublicationM3>(
      context,
      const CreateSignalementScreen(),
    );
    if (!mounted || etat == null) {
      return;
    }
    if (etat == EtatPublicationM3.envoye) {
      afficherMessageM3(
        context,
        tr('Yaatik saha ! Signalement publié.', 'Yaatik saha ! Tablighek tbaath.'),
      );
    } else {
      afficherMessageM3(
        context,
        tr('Pas de connexion : ton signalement sera envoyé automatiquement.',
            'Ma famech connexion : tablighek yetb3ath wa7dou ba3d.'),
      );
    }
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
          if (_depuisCache) _bandeauCache(),
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
    if (liste.isEmpty && _envois.isEmpty) {
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
    // D'abord mes envois en attente, puis les signalements
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemCount: _envois.length + liste.length,
      itemBuilder: (context, index) {
        if (index < _envois.length) {
          return _carteEnvoi(_envois[index]);
        }
        return _carteSignalement(liste[index - _envois.length]);
      },
    );
  }

  /// Bandeau "Hors ligne — dernière mise à jour à HH:mm".
  Widget _bandeauCache() {
    final DateTime? miseAJour = _miseAJour;
    final String quand = miseAJour == null
        ? tr('aucune donnée enregistrée sur ce téléphone',
            'ma famma 7atta chay msajjel')
        : '${tr('dernière mise à jour à', 'akher mise à jour m3a')} ${heureM3(miseAJour)}';
    final String debut = _horsLigne
        ? tr('Hors ligne', 'Mafamech connexion')
        : tr('Actualisation impossible', 'Ma najjamnech n7adthou');
    return BandeauM3(icone: Icons.cloud_off, texte: '$debut — $quand');
  }

  /// La carte d'un signalement pas encore envoyé (file SQLite).
  Widget _carteEnvoi(EnvoiEnAttente envoi) {
    final CategorieSignalement categorie =
        SignalementRepository.getCategorieParId(envoi.categorieId);
    final bool occupe = _envoisOccupes.contains(envoi.id);
    final Color couleur = envoi.estEnEchec ? AppColors.error : AppColors.warning;
    String etat = envoi.estEnEchec
        ? tr('Échec de l\'envoi', 'Ma tba3thech')
        : tr('En attente d\'envoi', 'Yestanna bech yetb3ath');
    if (envoi.nbTentatives > 0) {
      etat = '$etat · ${envoi.nbTentatives} ${tr('essai(s)', 'mo7awla')}';
    }
    final List<Widget> lignes = [
      Text(
        envoi.titre,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Text(
              '${envoi.lieu} · ${depuisQuandM3(envoi.dateCreation)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          if (envoi.photoLocale != null || envoi.photoUrl != null)
            Icon(
              Icons.photo_camera_outlined,
              key: const ValueKey('icone_photo_envoi'),
              size: 16,
              color: AppColors.textSecondary,
            ),
        ],
      ),
      const SizedBox(height: 8),
      // Badge d'état
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 14, color: couleur),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                etat,
                style: TextStyle(
                  color: couleur,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
    final String? erreur = envoi.derniereErreur;
    if (envoi.estEnEchec && erreur != null) {
      lignes.add(const SizedBox(height: 6));
      lignes.add(Text(
        erreur,
        style: TextStyle(fontSize: 12, color: AppColors.error),
      ));
    }
    // Wrap : les boutons passent à la ligne sur un petit écran
    lignes.add(Wrap(
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: occupe ? null : () => _annulerEnvoi(envoi),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text(tr('Annuler', 'Battel')),
        ),
        TextButton(
          onPressed: occupe ? null : () => _reessayerEnvoi(envoi),
          child: Text(tr('Réessayer', '3awed')),
        ),
      ],
    ));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(opacity: 0.6, child: PastilleCategorie(categorie: categorie)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lignes,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Le message quand il n'y a rien à afficher.
  String _texteListeVide() {
    if (_depuisCache && _miseAJour == null) {
      return tr('Hors ligne : connecte-toi une première fois pour voir les signalements',
          'Connecti mara bech tchouf it-tablighat');
    }
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
                      if (signalement.photoUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            key: const ValueKey('icone_photo'),
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
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
