import 'package:flutter/material.dart';

import '../../data/models/evenement.dart'; // M4 (D3)
import '../../data/models/historique_signalement.dart';
import '../../data/models/quartier.dart' show PointGps;
import '../../data/models/signalement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart'; // M4 (D3)
import '../../data/services/liens_m3.dart';
import '../../data/services/photos_m3.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/sync_signalements_m3.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/status_badge.dart';
// M4 (D3) : formulaire et détail d'un événement (import seulement)
import '../module4/evenement_detail_screen.dart';
import '../module4/evenement_form_screen.dart';
import 'carte_signalements_screen.dart';
import 'create_signalement_screen.dart';
import 'widgets_module3.dart';

/// M3 - Signalements : le détail d'un signalement.
///
/// Selon qui regarde :
///   - un voisin : bouton "Sa7, ena zeda" (une seule fois) ;
///   - l'auteur, tant que c'est en attente : Modifier / Supprimer ;
///   - l'admin : changer le statut (et supprimer).
///
/// Se ferme avec `Navigator.pop(context, true)` après une suppression.
class SignalementDetailScreen extends StatefulWidget {
  final String signalementId;

  const SignalementDetailScreen({super.key, required this.signalementId});

  @override
  State<SignalementDetailScreen> createState() {
    return _SignalementDetailScreenState();
  }
}

class _SignalementDetailScreenState extends State<SignalementDetailScreen> {
  Signalement? _signalement;
  bool _aConfirme = false; // l'utilisateur connecté a déjà confirmé
  bool _enChargement = true; // chargement du signalement
  bool _actionEnCours = false; // confirmer, changer le statut, supprimer
  String? _erreur;
  bool _depuisCache = false; // lu dans SQLite (hors ligne) : pas d'action
  List<EntreeHistorique>? _historique; // null : pas encore chargé
  // (D3) Événements organisés à la suite de ce signalement (module 4).
  // null : pas chargés (hors ligne, erreur) → la section est cachée
  List<Evenement>? _evenementsLies;
  String? _erreurHistorique;

  final SyncSignalementsM3 _sync = SyncSignalementsM3.instance;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  /// L'utilisateur connecté (module 1).
  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  /// Recharge le signalement (bouton "Réessayer", retour de la modification).
  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    await _chargerDonnees();
  }

  /// Lit le signalement (Firestore, ou le cache SQLite hors ligne), puis
  /// si je l'ai déjà confirmé.
  Future<void> _chargerDonnees() async {
    final Resultat<SignalementLuM3> resultat =
        await _sync.lireSignalement(widget.signalementId);
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      setState(() {
        _enChargement = false;
        _erreur = resultat.erreur;
      });
      return;
    }
    final Signalement signalement = resultat.donnee!.signalement;
    final bool depuisCache = resultat.donnee!.depuisCache;

    // Pas besoin de demander pour son propre signalement, ni hors ligne
    bool deja = false;
    final SignalementRepository repository = SignalementRepository();
    if (signalement.auteurId != _moi.id && !depuisCache) {
      final Resultat<bool> confirme = await repository.aConfirme(signalement.id);
      if (!mounted) {
        return;
      }
      deja = confirme.donnee ?? false;
    }
    setState(() {
      _signalement = signalement;
      _aConfirme = deja;
      _depuisCache = depuisCache;
      _enChargement = false;
    });
    if (!depuisCache) {
      await _chargerHistorique(signalement.id);
      await _chargerEvenementsLies(signalement.id);
    }
  }

  /// (D3) Les événements organisés à la suite de ce signalement.
  /// Échec ou délai dépassé : la section reste cachée.
  Future<void> _chargerEvenementsLies(String id) async {
    final Resultat<List<Evenement>> resultat = await EvenementRepository()
        .getEvenementsDuSignalement(id)
        .timeout(
          SyncSignalementsM3.delaiReseau,
          onTimeout: () =>
              const Resultat.echec(SyncSignalementsM3.messageDelai),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _evenementsLies = resultat.donnee;
    });
  }

  /// (D3) « Organiser un événement » : le formulaire du module 4,
  /// pré-rempli (type, titre, lieu, point GPS, lien vers ce signalement).
  Future<void> _organiserEvenement() async {
    final Signalement signalement = _signalement!;
    final bool? cree = await ouvrirEcranM3<bool>(
      context,
      EvenementFormScreen(
        titreInitial: SignalementRepository.titreEvenementPour(signalement),
        categorieInitiale:
            SignalementRepository.categorieEvenementPour(signalement.categorieId),
        lieuInitial: signalement.lieu,
        positionInitiale: signalement.position,
        signalementId: signalement.id,
        signalementTitre: signalement.titre,
      ),
    );
    if (!mounted || cree != true) {
      return;
    }
    _message(tr('Événement organisé : les voisins sont prévenus.',
        'L\'événement mnadhem : el jiran 3raf.'));
    await _chargerEvenementsLies(signalement.id); // la section se met à jour
  }

  /// (D3) Ouvre un événement lié ; au retour, la section est rechargée.
  Future<void> _ouvrirEvenement(Evenement evenement) async {
    await ouvrirEcranM3<void>(
      context,
      EvenementDetailScreen(evenementId: evenement.id),
    );
    if (mounted) {
      await _chargerEvenementsLies(widget.signalementId);
    }
  }

  /// (D3) La section « Événement organisé » (cachée hors ligne ou sans
  /// événement), avec le conseil à l'admin quand l'événement est passé.
  List<Widget> _sectionEvenements(Signalement signalement, Utilisateur moi) {
    final List<Evenement>? evenements = _evenementsLies;
    if (_depuisCache || evenements == null || evenements.isEmpty) {
      return [];
    }
    final List<Widget> lignes = [
      Text(
        evenements.length == 1
            ? tr('Événement organisé', 'Événement mnadhem')
            : tr('Événements organisés', 'Événements mnadhmin'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
    ];
    for (final Evenement evenement in evenements) {
      lignes.add(InkWell(
        key: ValueKey('evenement_lie_${evenement.id}'),
        onTap: () => _ouvrirEvenement(evenement),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.event_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evenement.titre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${dateCompleteM3(evenement.date)} · '
                      '${evenement.participants} '
                      '${evenement.participants <= 1 ? tr('participant', 'mcharek') : tr('participants', 'mcharkin')}'
                      '${evenement.annule ? ' · ${tr('Annulé', 'Mbattel')}' : ''}',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ));
    }
    // Conseil à l'admin : l'événement a eu lieu, le signalement est ouvert
    final bool aEuLieu = evenements.any((e) => e.estPasse && !e.annule);
    if (moi.estAdmin && !signalement.estCloture && aEuLieu) {
      lignes.add(Container(
        key: const ValueKey('conseil_resolu'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('L\'événement a eu lieu — marquer comme résolu ?',
                  'L\'événement t3ada — n7otouh tsalle7 ?'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _actionEnCours
                    ? null
                    : () => _changerStatut(StatutSignalement.resolu),
                child: Text(tr('Marquer comme résolu', 'Tsalle7')),
              ),
            ),
          ],
        ),
      ));
    }
    return [
      AppCard(
        key: const ValueKey('evenements_lies'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lignes,
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// L'historique des statuts (en ligne seulement).
  Future<void> _chargerHistorique(String id) async {
    final Resultat<List<EntreeHistorique>> resultat = await SignalementRepository()
        .getHistorique(id)
        .timeout(
          SyncSignalementsM3.delaiReseau,
          onTimeout: () =>
              const Resultat.echec(SyncSignalementsM3.messageDelai),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _historique = resultat.donnee;
      _erreurHistorique = resultat.erreur;
    });
  }

  /// Avant une action : sans réseau, Firestore attendrait sans fin.
  /// Renvoie false (avec un message) s'il n'y a pas de réseau.
  Future<bool> _verifierReseau() async {
    final bool enLigne = await _sync.estEnLigne();
    if (!enLigne && mounted) {
      _message(tr('Pas de connexion Internet : réessaie quand le réseau revient',
          'Ma famech connexion : 3awed ki yerja3 el réseau'));
    }
    return enLigne;
  }

  /// Affiche un message en bas de l'écran.
  void _message(String texte) {
    afficherMessageM3(context, texte);
  }

  /// "Sa7, ena zeda" : je confirme le problème.
  Future<void> _confirmer() async {
    final Signalement signalement = _signalement!;
    if (!await _verifierReseau() || !mounted) {
      return;
    }
    setState(() {
      _actionEnCours = true;
    });
    final Resultat<void> resultat =
        await SignalementRepository().confirmer(signalement.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _actionEnCours = false;
    });
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
      return;
    }
    setState(() {
      _aConfirme = true;
      _signalement = signalement.copyWith(
        nbConfirmations: signalement.nbConfirmations + 1,
      );
    });
    _message(tr('Merci ! Ta confirmation aide à traiter le problème plus vite.',
        'Ya3tik saha ! Ta2kidek y3awen bech yetsalla7 asra3.'));
  }

  /// L'auteur ouvre le formulaire en mode modification.
  Future<void> _modifier() async {
    final bool? modifie = await ouvrirEcranM3<bool>(
      context,
      CreateSignalementScreen(signalement: _signalement),
    );
    if (!mounted || modifie != true) {
      return;
    }
    _message(tr('Signalement modifié', 'Tabligh tbaddel'));
    _charger();
  }

  /// Supprime après confirmation, puis revient à la liste.
  Future<void> _supprimer() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Supprimer ce signalement ?', 'Tfasakh it-tabligh ?')),
          content: Text(tr('Cette action est définitive.',
              'Ma tnajjemch traja3 fiha.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Annuler', 'Batel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(tr('Supprimer', 'Fasakh')),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      return;
    }
    if (!await _verifierReseau() || !mounted) {
      return;
    }
    setState(() {
      _actionEnCours = true;
    });
    final Resultat<void> resultat =
        await SignalementRepository().supprimerSignalement(widget.signalementId);
    if (!mounted) {
      return;
    }
    setState(() {
      _actionEnCours = false;
    });
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
      return;
    }
    await _sync.oublier(widget.signalementId); // retiré du cache SQLite aussi
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  /// L'admin change le statut.
  Future<void> _changerStatut(StatutSignalement nouveau) async {
    final Signalement signalement = _signalement!;
    if (nouveau == signalement.statut) {
      return;
    }
    // La note de l'admin (obligatoire pour "refusé") ; null : annulé
    final String? note = await _demanderNote(nouveau);
    if (note == null || !mounted) {
      return;
    }
    if (!await _verifierReseau() || !mounted) {
      return;
    }
    setState(() {
      _actionEnCours = true;
    });
    final Resultat<void> resultat = await SignalementRepository()
        .changerStatut(signalement.id, nouveau, note: note);
    if (!mounted) {
      return;
    }
    setState(() {
      _actionEnCours = false;
    });
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
      return;
    }
    setState(() {
      _signalement = signalement.copyWith(statut: nouveau);
    });
    _message('${tr('Statut mis à jour', 'El 7ala tbadlet')} : ${texteStatut(nouveau)}');
    await _chargerHistorique(signalement.id); // la nouvelle étape apparaît
  }

  /// La fenêtre de l'admin : passer à [nouveau], avec une note. Renvoie la
  /// note ('' : sans note), ou null si l'admin annule.
  Future<String?> _demanderNote(StatutSignalement nouveau) {
    final bool obligatoire = nouveau == StatutSignalement.refuse;
    String texte = '';
    String? erreur;
    return showDialog<String>(
      context: context,
      builder: (context) {
        // StatefulBuilder : la fenêtre se redessine pour afficher l'erreur
        return StatefulBuilder(
          builder: (context, setStateFenetre) {
            return AlertDialog(
              title: Text(
                '${tr('Passer à', 'Badel l')} « ${texteStatut(nouveau)} »',
              ),
              content: TextField(
                key: const ValueKey('note_statut'),
                autofocus: true,
                maxLines: 3,
                maxLength: SignalementRepository.noteMax,
                onChanged: (valeur) => texte = valeur,
                decoration: InputDecoration(
                  labelText: obligatoire
                      ? tr('Raison du refus (obligatoire)', '3lech martoud (lezem)')
                      : tr('Note pour les voisins (optionnelle)',
                          'Kelma lel jiran (ken t7eb)'),
                  hintText: obligatoire
                      ? tr('Ex : déjà signalé à la municipalité',
                          'Ex : deja mballagh lel baladiya')
                      : tr('Ex : intervention prévue jeudi',
                          'Ex : yjiw nhar el khmis'),
                  errorText: erreur,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Annuler', 'Batel')),
                ),
                TextButton(
                  onPressed: () {
                    final String? refus =
                        SignalementRepository.refusNote(nouveau, texte);
                    if (refus != null) {
                      setStateFenetre(() {
                        erreur = refus;
                      });
                      return;
                    }
                    Navigator.of(context).pop(texte.trim());
                  },
                  child: Text(tr('Valider', 'Sajjel')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// La frise de l'historique : une étape par changement de statut.
  Widget _carteHistorique(Signalement signalement) {
    final List<Widget> contenu = [
      Text(
        tr('Historique', 'Tarikh'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
    ];
    final List<EntreeHistorique>? historique = _historique;
    final String? erreur = _erreurHistorique;
    if (_depuisCache) {
      contenu.add(Text(
        tr('L\'historique s\'affiche avec la connexion.',
            'Et-tarikh yban ki tarja3 el connexion.'),
        style: TextStyle(color: AppColors.textSecondary),
      ));
    } else if (erreur != null) {
      contenu.add(Text(erreur, style: TextStyle(color: AppColors.error)));
    } else if (historique == null) {
      contenu.add(const LinearProgressIndicator(minHeight: 2));
    } else {
      // Signalement créé avant l'historique : sa 1re étape (la création)
      // n'existe pas ; on la refait à partir du signalement lui-même
      final List<EntreeHistorique> etapes = List.of(historique);
      final bool creationConnue = etapes.isNotEmpty &&
          etapes.first.statut == StatutSignalement.enAttente &&
          etapes.first.parId == signalement.auteurId;
      if (!creationConnue) {
        etapes.insert(
          0,
          EntreeHistorique(
            statut: StatutSignalement.enAttente,
            date: signalement.date,
            parId: signalement.auteurId,
            parNom: signalement.auteurNom,
          ),
        );
      }
      for (int i = 0; i < etapes.length; i++) {
        contenu.add(_etape(etapes[i], premiere: i == 0, derniere: i == etapes.length - 1));
      }
    }
    return AppCard(
      key: const ValueKey('historique'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: contenu,
      ),
    );
  }

  /// Une étape : un point (et un trait vers la suivante), le statut, la
  /// date, qui, et la note.
  Widget _etape(
    EntreeHistorique etape, {
    required bool premiere,
    required bool derniere,
  }) {
    final List<Widget> details = [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(statut: etape.statut),
          Text(
            dateCompleteM3(etape.date),
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        premiere
            ? '${tr('Signalé par', 'Ballegh 3lih')} ${etape.parNom}'
            : '${tr('Par', 'Men')} ${etape.parNom}',
        style: const TextStyle(fontSize: 13),
      ),
    ];
    if (etape.note.isNotEmpty) {
      details.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '« ${etape.note} »',
          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
        ),
      ));
    }
    // IntrinsicHeight : le trait vertical prend la hauteur de l'étape
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: derniere ? AppColors.primary : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!derniere)
                  Expanded(
                    child: Container(width: 2, color: AppColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: derniere ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: tr('Détail du signalement', 'Tafasil it-tabligh'),
            // Partager : seulement quand le signalement est chargé (marche
            // aussi hors ligne : c'est le téléphone qui partage)
            action: _signalement == null
                ? null
                : IconButton(
                    tooltip: tr('Partager', 'Charek'),
                    onPressed: _partager,
                    icon: Icon(Icons.share_outlined, color: AppColors.primary),
                  ),
          ),
          Expanded(child: _contenu()),
        ],
      ),
    );
  }

  Widget _contenu() {
    if (_enChargement) {
      return const Center(child: CircularProgressIndicator());
    }
    final Signalement? signalement = _signalement;
    if (_erreur != null || signalement == null) {
      return Center(
        child: MessageEtatM3(
          icone: Icons.cloud_off,
          texte: _erreur ?? tr('Signalement introuvable', 'Tabligh mouch mawjoud'),
          texteBouton: tr('Réessayer', '3awed'),
          onBouton: _charger,
        ),
      );
    }

    final Utilisateur moi = _moi;
    final List<Widget> enfants = [];
    if (_depuisCache) {
      enfants.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: BandeauM3(
          icone: Icons.cloud_off,
          texte: tr('Hors ligne : version enregistrée sur le téléphone',
              'Mafamech connexion : nos5a msajla fel téléphone'),
        ),
      ));
    }
    enfants.addAll([
      _carteEnTete(signalement),
      const SizedBox(height: 12),
      _carteInfos(signalement),
      const SizedBox(height: 12),
      _carteDescription(signalement),
    ]);
    final String? photo = signalement.photoUrl;
    if (photo != null) {
      enfants.add(const SizedBox(height: 12));
      enfants.add(_photo(photo));
    }
    // Numéro utile de la catégorie (aussi hors ligne : un appel n'a pas
    // besoin d'Internet)
    final NumeroUtile? numero =
        SignalementRepository.numeroUtile(signalement.categorieId);
    if (numero != null) {
      enfants.add(const SizedBox(height: 12));
      enfants.add(_carteNumeroUtile(numero));
    }
    enfants.add(const SizedBox(height: 12));
    enfants.addAll(_sectionEvenements(signalement, _moi)); // (D3)
    enfants.add(_carteHistorique(signalement));
    enfants.add(const SizedBox(height: 24));
    if (_depuisCache) {
      // Hors ligne : les actions passent par Firestore, on les cache
      enfants.add(Text(
        tr('Les actions reviendront avec la connexion.',
            'El actions yarj3ou ki tarja3 el connexion.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ));
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: enfants,
      );
    }
    enfants.add(_zoneConfirmation(signalement, moi));
    // (D3) Leader ou admin, signalement ouvert, ordures ou travaux
    if (SignalementRepository.peutOrganiserEvenement(moi, signalement)) {
      enfants.add(const SizedBox(height: 12));
      enfants.add(SecondaryButton(
        key: const ValueKey('organiser_evenement'),
        texte: tr('Organiser un événement', 'Nadhem événement'),
        icone: Icons.event_available_outlined,
        onPressed: _actionEnCours ? null : _organiserEvenement,
      ));
    }
    enfants.addAll(_actionsAuteur(signalement, moi));
    if (moi.estAdmin) {
      enfants.add(const SizedBox(height: 24));
      enfants.add(_zoneAdmin(signalement));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: enfants,
    );
  }

  /// Catégorie, titre, statut, urgence et danger.
  Widget _carteEnTete(Signalement signalement) {
    final CategorieSignalement categorie =
        SignalementRepository.getCategorieParId(signalement.categorieId);
    final List<Widget> badges = [
      StatusBadge(statut: signalement.statut),
      BadgeUrgence(niveau: SignalementRepository.niveauUrgence(signalement)),
    ];
    if (signalement.danger) {
      badges.add(const EtiquetteDanger());
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PastilleCategorie(categorie: categorie, taille: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categorie.nom,
                      style: TextStyle(
                        color: categorie.couleur,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      signalement.titre,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: badges),
        ],
      ),
    );
  }

  /// Lieu, date, auteur, confirmations et score d'urgence.
  Widget _carteInfos(Signalement signalement) {
    final int nb = signalement.nbConfirmations;
    final String confirmations = nb == 0
        ? tr('Personne n\'a encore confirmé', 'Hatta 7ad ma akked')
        : nb == 1
            ? tr('1 voisin a confirmé', 'Jar wa7ed akked')
            : tr('$nb voisins ont confirmé', '$nb jiran akkdou');
    final List<Widget> lignesPosition = [];
    final PointGps? position = signalement.position;
    if (position != null) {
      lignesPosition.add(_lignePosition(position, signalement.titre));
    }
    return AppCard(
      child: Column(
        children: [
          _ligneInfo(Icons.place_outlined, signalement.lieu),
          ...lignesPosition,
          _ligneInfo(Icons.schedule, dateCompleteM3(signalement.date)),
          _ligneInfo(
            Icons.person_outline,
            '${tr('Signalé par', 'Ballegh 3lih')} ${signalement.auteurNom}',
          ),
          _ligneInfo(Icons.people_alt_outlined, confirmations),
          _ligneInfo(
            Icons.speed,
            '${tr('Score d\'urgence', 'Score el isti3jal')} : '
            '${SignalementRepository.scoreUrgence(signalement)}',
          ),
        ],
      ),
    );
  }

  /// "Partager" : la fenêtre de partage du téléphone (WhatsApp, SMS...).
  Future<void> _partager() async {
    final Signalement? signalement = _signalement;
    if (signalement == null) {
      return;
    }
    final Resultat<void> resultat = await LiensM3.partager(
      texteDePartageM3(signalement),
      signalement.titre,
    );
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
    }
  }

  /// "Appeler" : ouvre le clavier du téléphone avec le numéro.
  Future<void> _appeler(NumeroUtile numero) async {
    final Resultat<void> resultat = await LiensM3.appeler(numero.numero);
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
    }
  }

  /// Le numéro utile de la catégorie, avec le bouton "Appeler".
  Widget _carteNumeroUtile(NumeroUtile numero) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.phone_in_talk_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Numéro utile', 'Noumrou mouhem'),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  numero.nom,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  numero.numeroLisible,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _appeler(numero),
            icon: const Icon(Icons.call, size: 18),
            label: Text(tr('Appeler', 'Ekleb')),
          ),
        ],
      ),
    );
  }

  /// La photo : miniature Cloudinary (légère) ; toucher l'ouvre en grand.
  Widget _photo(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: () => ouvrirEcranM3<void>(context, PhotoPleinEcranM3(url: url)),
        child: Image.network(
          PhotosM3.miniature(url, largeur: 800, hauteur: 450),
          key: const ValueKey('photo_signalement'),
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, image, progression) {
            if (progression == null) {
              return image;
            }
            return Container(
              height: 200,
              color: AppColors.backgroundSecondary,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            );
          },
          // Hors ligne ou photo supprimée : un cadre neutre, pas d'erreur
          errorBuilder: (context, erreur, trace) => Container(
            height: 200,
            color: AppColors.backgroundSecondary,
            alignment: Alignment.center,
            child: Text(
              tr('Photo indisponible', 'Taswira mouch mawjouda'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  /// "Voir sur la carte" : la carte des signalements de l'app, centrée sur
  /// celui-ci (sa fiche est ouverte). Au retour, le détail est rechargé.
  Future<void> _ouvrirMaCarte() async {
    await ouvrirEcranM3<void>(
      context,
      CarteSignalementsScreen(centreSur: widget.signalementId),
    );
    if (mounted) {
      _charger();
    }
  }

  /// "Application de cartes" (action secondaire) : l'application de cartes
  /// du téléphone (lien geo:), sinon OpenStreetMap dans le navigateur.
  Future<void> _voirSurLaCarte(PointGps position, String libelle) async {
    final Resultat<void> resultat = await LiensM3.ouvrirCarte(position, libelle);
    if (!mounted) {
      return;
    }
    if (!resultat.estSucces) {
      _message(resultat.erreur!);
    }
  }

  /// Le point GPS + "Voir sur la carte".
  Widget _lignePosition(PointGps position, String libelle) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.my_location, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texteCoordonnees(position),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                // Wrap : les deux boutons passent à la ligne à 360 px
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _ouvrirMaCarte,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(tr('Voir sur la carte', 'Chouf fel carte')),
                    ),
                    TextButton.icon(
                      onPressed: () => _voirSurLaCarte(position, libelle),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: AppColors.textSecondary,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(
                        tr('Application de cartes', 'Application cartes'),
                        style: const TextStyle(fontSize: 13),
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

  Widget _ligneInfo(IconData icone, String texte) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(texte)),
        ],
      ),
    );
  }

  Widget _carteDescription(Signalement signalement) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Description', 'Chnoua sar'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            signalement.description,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Le bouton "Sa7, ena zeda" (caché sur son propre signalement).
  Widget _zoneConfirmation(Signalement signalement, Utilisateur moi) {
    if (signalement.auteurId == moi.id) {
      return Text(
        tr('C\'est ton signalement : tes voisins peuvent le confirmer.',
            'Hedha tablighek : jiranek ynajmou y2akkdouh.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    if (_aConfirme) {
      return PrimaryButton(
        texte: tr('Tu as confirmé', 'Akkedt'),
        icone: Icons.check,
        onPressed: null, // désactivé : une seule confirmation
      );
    }
    if (signalement.estCloture) {
      return Text(
        tr('Ce signalement est clôturé : il ne peut plus être confirmé.',
            'Hedha it-tabligh tsakker : ma3adech yetakked.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Column(
      children: [
        PrimaryButton(
          texte: 'Sa7, ena zeda',
          icone: Icons.front_hand_outlined,
          onPressed: _actionEnCours ? null : _confirmer,
        ),
        const SizedBox(height: 6),
        Text(
          tr('Tu as le même problème ? Confirme-le pour qu\'il soit traité plus vite.',
              'Andek nafs el machkel ? Akkdou bech yetsalla7 asra3.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// Modifier (l'auteur, en attente) et Supprimer (l'auteur en attente, ou l'admin).
  List<Widget> _actionsAuteur(Signalement signalement, Utilisateur moi) {
    final bool peutModifier =
        SignalementRepository.refusModification(signalement, moi.id) == null;
    final bool peutSupprimer =
        SignalementRepository.refusSuppression(signalement, moi) == null;
    final List<Widget> actions = [];
    if (peutModifier) {
      actions.add(const SizedBox(height: 16));
      actions.add(SecondaryButton(
        texte: tr('Modifier', 'Badel'),
        icone: Icons.edit_outlined,
        onPressed: _actionEnCours ? null : _modifier,
      ));
    }
    if (peutSupprimer) {
      actions.add(const SizedBox(height: 8));
      actions.add(Center(
        child: TextButton.icon(
          onPressed: _actionEnCours ? null : _supprimer,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Supprimer', 'Fasakh')),
        ),
      ));
    }
    return actions;
  }

  /// L'admin choisit le nouveau statut.
  Widget _zoneAdmin(Signalement signalement) {
    final List<Widget> choix = [];
    for (final StatutSignalement statut in StatutSignalement.values) {
      choix.add(ChoiceChip(
        label: Text(texteStatut(statut)),
        selected: signalement.statut == statut,
        selectedColor: AppColors.secondaryLight,
        onSelected: _actionEnCours
            ? null
            : (choisi) {
                _changerStatut(statut);
              },
      ));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Changer le statut (admin)', 'Badel el 7ala (admin)'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: choix),
        ],
      ),
    );
  }
}
