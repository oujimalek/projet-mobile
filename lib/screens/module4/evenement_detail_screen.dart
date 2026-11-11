import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/evenement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../module1/widgets_module1.dart';
import 'evenement_form_screen.dart';
import 'module4_widgets.dart';

/// M4 - Détail d'un événement : infos, participants, et le bouton
/// "Je participe" / "Me retirer".
///
/// Droits (voir docs/module4_evenements.md) :
/// - tout membre actif participe ou se retire (pas après l'événement) ;
/// - l'organisateur et l'admin modifient, suppriment et voient les noms
///   des participants ; les autres voisins voient seulement le nombre.
class EvenementDetailScreen extends StatefulWidget {
  final String evenementId;

  const EvenementDetailScreen({super.key, required this.evenementId});

  @override
  State<EvenementDetailScreen> createState() {
    return _EvenementDetailScreenState();
  }
}

class _EvenementDetailScreenState extends State<EvenementDetailScreen> {
  final EvenementRepository _depot = EvenementRepository();

  Evenement? _evenement;
  bool _inscrit = false;
  List<Participant> _participants = []; // organisateur et admin seulement
  bool _enChargement = true;
  bool _envoiEnCours = false; // participer / se retirer / supprimer
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    final Resultat<Evenement> resultat =
        await _depot.getEvenement(widget.evenementId);
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
    final Evenement evenement = resultat.donnee!;

    final Resultat<bool> inscrit = await _depot.estInscrit(evenement.id);
    List<Participant> noms = [];
    if (EvenementRepository.peutVoirParticipants(_moi, evenement)) {
      final Resultat<List<Participant>> participants =
          await _depot.getParticipants(evenement.id);
      noms = participants.donnee ?? [];
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _evenement = evenement;
      _inscrit = inscrit.donnee ?? false;
      _participants = noms;
    });
  }

  /// Affiche le message d'erreur d'un Resultat en échec.
  void _afficherErreur(Resultat resultat) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultat.erreur!)),
    );
  }

  Future<void> _participerOuSeRetirer() async {
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat = _inscrit
        ? await _depot.seRetirer(widget.evenementId)
        : await _depot.participer(widget.evenementId);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    if (!resultat.estSucces) {
      _afficherErreur(resultat);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_inscrit
            ? 'Tu ne participes plus à cet événement'
            : 'Yaatik saha, tu participes !'),
      ),
    );
    _charger(); // nouveau nombre de participants
  }

  Future<void> _modifier() async {
    final bool? modifie = await ouvrirEcranM4<bool>(
      context,
      EvenementFormScreen(evenement: _evenement),
    );
    if (mounted && modifie == true) {
      _charger();
    }
  }

  Future<void> _supprimer() async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer l\'événement ?'),
          content: const Text(
              'Les voisins inscrits ne le verront plus. Cette action est définitive.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Supprimer', style: TextStyle(color: AppColors.error)),
            ),
          ],
        );
      },
    );
    if (confirme != true || !mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat =
        await _depot.supprimerEvenement(widget.evenementId);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    if (!resultat.estSucces) {
      _afficherErreur(resultat);
      return;
    }
    Navigator.pop(context); // retour à la liste
  }

  @override
  Widget build(BuildContext context) {
    final Evenement? evenement = _evenement;

    // Menu "Modifier / Supprimer" pour l'organisateur et l'admin
    Widget? menu;
    if (evenement != null) {
      final bool peutModifier = EvenementRepository.peutModifier(_moi, evenement);
      final bool peutSupprimer =
          EvenementRepository.peutSupprimer(_moi, evenement.organisateurId);
      if (peutModifier || peutSupprimer) {
        menu = PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: AppColors.primary),
          onSelected: (choix) {
            if (choix == 'modifier') {
              _modifier();
            } else if (choix == 'annuler') {
              _annuler(evenement, !evenement.annule);
            } else {
              _supprimer();
            }
          },
          itemBuilder: (context) {
            final List<PopupMenuEntry<String>> choix = [];
            if (peutModifier) {
              choix.add(const PopupMenuItem(
                  value: 'modifier', child: Text('Modifier')));
              choix.add(PopupMenuItem(
                  value: 'annuler',
                  child: Text(evenement.annule
                      ? 'Rétablir l\'événement'
                      : 'Annuler l\'événement')));
            }
            if (peutSupprimer) {
              choix.add(const PopupMenuItem(
                  value: 'supprimer', child: Text('Supprimer')));
            }
            return choix;
          },
        );
      }
    }

    Widget corps;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_erreur != null || evenement == null) {
      corps = MessageM4(
        texte: _erreur ?? 'Événement introuvable',
        icone: Icons.event_busy_outlined,
        reessayer: _charger,
      );
    } else {
      corps = _contenu(evenement);
    }

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: 'Événement',
            action: evenement == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Partager l'invitation (WhatsApp, SMS...)
                      IconButton(
                        tooltip: 'Partager',
                        icon: Icon(Icons.share_outlined, color: AppColors.primary),
                        onPressed: () {
                          SharePlus.instance.share(ShareParams(
                            text: EvenementRepository.texteInvitation(evenement),
                          ));
                        },
                      ),
                      ?menu, // menu Modifier / Annuler / Supprimer (s'il existe)
                    ],
                  ),
          ),
          Expanded(child: corps),
          if (evenement != null && !_enChargement) _boutonBas(evenement),
        ],
      ),
    );
  }

  Widget _contenu(Evenement evenement) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        IllustrationCategorie(categorie: evenement.categorie),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            PastilleCategorie(categorie: evenement.categorie),
            if (evenement.officiel)
              BadgeM4(
                texte: 'Officiel',
                couleur: AppColors.primary,
                fond: AppColors.primaryLight,
              ),
            if (evenement.annule)
              BadgeM4(
                texte: 'Annulé',
                couleur: AppColors.error,
                fond: AppColors.badgeRefuseFond,
              ),
            if (evenement.estPasse)
              BadgeM4(
                texte: 'Terminé',
                couleur: AppColors.textSecondary,
                fond: AppColors.backgroundSecondary,
              ),
            if (_inscrit)
              BadgeM4(
                texte: 'Je participe',
                couleur: AppColors.success,
                fond: AppColors.badgeResoluFond,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          evenement.titre,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _ligneInfo(Icons.calendar_today_outlined,
            '${texteDate(evenement.date)} · ${texteHoraire(evenement)}'),
        _ligneInfo(Icons.place_outlined, evenement.lieu),
        _ligneInfo(Icons.person_outline, 'Organisé par ${evenement.organisateur}'),
        if (evenement.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            evenement.description,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        _blocParticipants(evenement),
      ],
    );
  }

  Widget _ligneInfo(IconData icone, String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  /// Le nombre de participants, et leurs noms pour l'organisateur et l'admin.
  Widget _blocParticipants(Evenement evenement) {
    final int nombre = evenement.participants;
    final List<Widget> enfants = [
      Row(
        children: [
          Icon(Icons.groups_outlined, color: AppColors.secondary),
          const SizedBox(width: 8),
          Text(
            '$nombre participant${nombre > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ];

    if (EvenementRepository.peutVoirParticipants(_moi, evenement)) {
      if (_participants.isEmpty) {
        enfants.add(const SizedBox(height: 8));
        enfants.add(Text(
          'Personne n\'est encore inscrit',
          style: TextStyle(color: AppColors.textSecondary),
        ));
      }
      for (final Participant participant in _participants) {
        enfants.add(const SizedBox(height: 10));
        enfants.add(
          Row(
            children: [
              // L'avatar choisi dans le profil (module 1), sinon les initiales
              AvatarUtilisateur(
                avatar: participant.avatar,
                initiales: _initiales(participant.nom),
                taille: 34,
                couleur: AppColors.primary,
                fond: AppColors.primaryLight,
              ),
              const SizedBox(width: 10),
              Text(participant.nom),
            ],
          ),
        );
      }
    } else {
      enfants.add(const SizedBox(height: 6));
      enfants.add(Text(
        'Seuls l\'organisateur et l\'admin voient la liste des participants.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: enfants,
      ),
    );
  }

  /// "Salma G." → "SG"
  String _initiales(String nom) {
    String resultat = '';
    for (final String mot in nom.split(' ')) {
      if (mot.isNotEmpty && resultat.length < 2) {
        resultat = resultat + mot[0].toUpperCase();
      }
    }
    return resultat;
  }

  /// L'organisateur (ou l'admin) annule l'événement ou le rétablit.
  Future<void> _annuler(Evenement evenement, bool annule) async {
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat =
        await _depot.annulerEvenement(evenement, annule);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiEnCours = false;
    });
    if (!resultat.estSucces) {
      _afficherErreur(resultat);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(annule
            ? 'Événement annulé : les participants le verront'
            : 'Événement rétabli'),
      ),
    );
    _charger();
  }

  /// "Je participe" (bleu) ou "Me retirer" (doré), fixé en bas.
  Widget _boutonBas(Evenement evenement) {
    Widget bouton;
    final String? refus = EvenementRepository.refusParticipation(evenement);
    if (refus != null && !_inscrit) {
      bouton = Text(
        refus,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    } else if (evenement.estPasse) {
      bouton = Text(
        'Cet événement est terminé',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    } else if (_inscrit) {
      bouton = SecondaryButton(
        texte: 'Me retirer',
        onPressed: _envoiEnCours ? null : _participerOuSeRetirer,
      );
    } else {
      bouton = PrimaryButton(
        texte: 'Je participe',
        icone: Icons.check,
        onPressed: _envoiEnCours ? null : _participerOuSeRetirer,
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(width: double.infinity, child: bouton),
      ),
    );
  }
}
