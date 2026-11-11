import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
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
    if (!await _verifierReseau() || !mounted) {
      return;
    }
    setState(() {
      _actionEnCours = true;
    });
    final Resultat<void> resultat =
        await SignalementRepository().changerStatut(signalement.id, nouveau);
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Détail du signalement', 'Tafasil it-tabligh')),
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
      enfants.add(ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Image.network(
          photo,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, erreur, trace) => const SizedBox.shrink(),
        ),
      ));
    }
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
    return AppCard(
      child: Column(
        children: [
          _ligneInfo(Icons.place_outlined, signalement.lieu),
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
