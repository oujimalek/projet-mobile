import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/evenement.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/photos_m4.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../module1/widgets_module1.dart';
import 'carte_evenement.dart';
import 'evenement_form_screen.dart';
import 'module4_widgets.dart';
import 'notifications_m4.dart';
import 'vie_evenement_widgets.dart';

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
  bool _interesse = false; // "Peut-être"
  List<Participant> _attente = []; // liste d'attente, dans l'ordre
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
    final Resultat<bool> interesse = await _depot.estInteresse(evenement.id);
    final Resultat<List<Participant>> attente =
        await _depot.getAttente(evenement.id);
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
      _interesse = interesse.donnee ?? false;
      _attente = attente.donnee ?? [];
      _participants = noms;
    });
  }

  /// Affiche le message d'erreur d'un Resultat en échec.
  void _afficherErreur(Resultat resultat) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultat.erreur!)),
    );
  }

  Future<void> _rejoindreAttente() async {
    final Evenement? evenement = _evenement;
    if (evenement == null) {
      return;
    }
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat = await _depot.rejoindreAttente(evenement);
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tu es sur la liste d\'attente : si une place se libère, elle sera pour toi')));
    _charger();
  }

  Future<void> _quitterAttente() async {
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat =
        await _depot.quitterAttente(widget.evenementId);
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
    _charger();
  }

  /// "Peut-être" : je deviens (ou ne suis plus) intéressé.
  Future<void> _changerInteret() async {
    setState(() {
      _envoiEnCours = true;
    });
    final Resultat<void> resultat =
        await _depot.changerInteret(widget.evenementId, !_interesse);
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
    _charger();
  }

  Future<void> _participerOuSeRetirer() async {
    setState(() {
      _envoiEnCours = true;
    });
    // Je participe : je ne suis plus seulement "peut-être"
    if (!_inscrit && _interesse) {
      await _depot.changerInteret(widget.evenementId, false);
    }
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
    // Rappels sur le téléphone : la veille et 1 h avant (ou on les annule)
    final Evenement? evenement = _evenement;
    if (evenement != null) {
      if (_inscrit) {
        NotificationsM4.annuler(evenement.id);
      } else {
        NotificationsM4.programmer(evenement);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_inscrit
            ? 'Tu ne participes plus à cet événement'
            : 'Yaatik saha, tu participes ! On te le rappellera la veille.'),
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
              child: Text(tr('Annuler', 'Batel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Supprimer', 'Fasakh'), style: TextStyle(color: AppColors.error)),
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
            } else if (choix == 'exporter') {
              // Partager la liste des participants (WhatsApp, e-mail...)
              SharePlus.instance.share(ShareParams(
                text: EvenementRepository.texteListeParticipants(
                    evenement, _participants),
              ));
            } else {
              _supprimer();
            }
          },
          itemBuilder: (context) {
            final List<PopupMenuEntry<String>> choix = [];
            if (peutModifier) {
              choix.add(PopupMenuItem(
                  value: 'modifier', child: Text(tr('Modifier', 'Badel'))));
              choix.add(PopupMenuItem(
                  value: 'annuler',
                  child: Text(evenement.annule
                      ? tr('Rétablir l\'événement', 'Rajja3 l\'événement')
                      : tr('Annuler l\'événement', 'Batel l\'événement'))));
              choix.add(PopupMenuItem(
                  value: 'exporter',
                  child: Text(tr('Exporter la liste des participants', 'Ab3ath liste mta3 el jeyin'))));
            }
            if (peutSupprimer) {
              choix.add(PopupMenuItem(
                  value: 'supprimer', child: Text(tr('Supprimer', 'Fasakh'))));
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
            titre: tr('Événement', 'Événement'),
            action: evenement == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ajouter à l'agenda du téléphone
                      IconButton(
                        tooltip: 'Ajouter à mon agenda',
                        icon: Icon(Icons.event_available_outlined,
                            color: AppColors.primary),
                        onPressed: () => _ajouterAuCalendrier(evenement),
                      ),
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
        // La photo de l'événement (Cloudinary), sinon l'illustration de sa catégorie
        if (evenement.photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Image.network(
              PhotosM4.miniature(evenement.photoUrl!),
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, erreur, pile) =>
                  IllustrationCategorie(categorie: evenement.categorie),
            ),
          )
        else
          IllustrationCategorie(categorie: evenement.categorie),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            PastilleCategorie(categorie: evenement.categorie),
            if (evenement.officiel)
              BadgeM4(
                texte: tr('Officiel', 'Rasmi'),
                couleur: AppColors.primary,
                fond: AppColors.primaryLight,
              ),
            if (evenement.estComplet && !evenement.annule)
              BadgeM4(
                texte: tr('Complet', 'Kemel'),
                couleur: AppColors.error,
                fond: AppColors.badgeRefuseFond,
              ),
            if (evenement.annule)
              BadgeM4(
                texte: tr('Annulé', 'Tbattel'),
                couleur: AppColors.error,
                fond: AppColors.badgeRefuseFond,
              ),
            if (evenement.estPasse)
              BadgeM4(
                texte: tr('Terminé', 'Kmel'),
                couleur: AppColors.textSecondary,
                fond: AppColors.backgroundSecondary,
              ),
            if (_inscrit)
              BadgeM4(
                texte: tr('Je participe', 'Ena jey'),
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
        // Le lieu exact sur la carte, si l'organisateur l'a placé
        if (evenement.position != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MiniCarteEvenement(position: evenement.position!),
          ),
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
        // Qui apporte quoi ? · Questions · Avis (après l'événement)
        SectionSondagesEvenement(evenement: evenement),
        SectionObjets(evenement: evenement),
        SectionAvis(evenement: evenement, participe: _inscrit),
        SectionQuestions(evenement: evenement),
        const SizedBox(height: 8),
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
    // "12 participants / 30 places" + "4 peut-être"
    String detail = '';
    final int? restantes = evenement.placesRestantes;
    if (restantes != null) {
      detail = evenement.estComplet
          ? 'Complet (${evenement.placesMax} places)'
          : '$restantes place${restantes > 1 ? 's' : ''} libre${restantes > 1 ? 's' : ''} sur ${evenement.placesMax}';
    }
    final List<Widget> enfants = [
      Row(
        children: [
          Icon(Icons.groups_outlined, color: AppColors.secondary),
          const SizedBox(width: 8),
          Text(
            '$nombre participant${nombre > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (evenement.interesses > 0)
            Text(
              '${evenement.interesses} peut-être',
              style: TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
      if (detail.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          detail,
          style: TextStyle(
            color: evenement.estComplet ? AppColors.error : AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ];

    if (EvenementRepository.peutVoirParticipants(_moi, evenement)) {
      if (_participants.isEmpty) {
        enfants.add(const SizedBox(height: 8));
        enfants.add(Text(
          tr('Personne n\'est encore inscrit', '7atta 7ad ma tsajjel'),
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
      // La liste d'attente, dans l'ordre
      if (_attente.isNotEmpty) {
        enfants.add(const SizedBox(height: 14));
        enfants.add(Text(
          'Liste d\'attente (${_attente.length})',
          style: TextStyle(
              color: AppColors.secondary, fontWeight: FontWeight.w600),
        ));
        for (int i = 0; i < _attente.length; i++) {
          enfants.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${i + 1}. ${_attente[i].nom}'),
          ));
        }
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

  /// Ouvre l'agenda du téléphone avec l'événement pré-rempli (package
  /// add_2_calendar) : l'utilisateur n'a plus qu'à enregistrer.
  Future<void> _ajouterAuCalendrier(Evenement evenement) async {
    final bool ouvert = await Add2Calendar.addEvent2Cal(
      Event(
        title: evenement.titre,
        description: evenement.description,
        location: evenement.lieu,
        startDate: evenement.date,
        // Sans heure de fin : 2 heures par défaut
        endDate: evenement.dateFin ?? evenement.date.add(const Duration(hours: 2)),
      ),
    );
    if (!mounted || ouvert) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aucune application d\'agenda trouvée')),
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
    final String moiId = _moi.id;
    final List<String> attente = [for (final Participant p in _attente) p.id];
    final int monRang = attente.indexOf(moiId); // -1 : pas en attente
    final String? refus = EvenementRepository.refusParticipation(
      evenement,
      attente: attente,
      moiId: moiId,
    );
    if (!_inscrit && monRang >= 0 && refus != null) {
      // Je suis sur la liste d'attente, pas encore de place pour moi
      bouton = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tu es ${monRang + 1}${monRang == 0 ? 'er' : 'e'} sur la liste d\'attente',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.secondary, fontWeight: FontWeight.w600),
          ),
          TextButton(
            onPressed: _envoiEnCours ? null : _quitterAttente,
            child: Text(tr('Quitter la liste d\'attente', 'O5rej mel liste d\'attente')),
          ),
        ],
      );
    } else if (!_inscrit &&
        evenement.estComplet &&
        !evenement.annule &&
        !evenement.estPasse) {
      // Complet : on peut rejoindre la liste d'attente
      bouton = SecondaryButton(
        texte: 'Rejoindre la liste d\'attente (${attente.length})',
        onPressed: _envoiEnCours ? null : _rejoindreAttente,
      );
    } else if (!_inscrit && monRang >= 0 && refus == null) {
      // Une place s'est libérée pour moi
      bouton = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Une place s\'est libérée pour toi !', 'Famma blassa fer8et lik !'),
            style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          PrimaryButton(
            texte: tr('Je participe', 'Ena jey'),
            icone: Icons.check,
            onPressed: _envoiEnCours ? null : _participerOuSeRetirer,
          ),
        ],
      );
    } else if (refus != null && !_inscrit) {
      bouton = Text(
        refus,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    } else if (evenement.estPasse) {
      bouton = Text(
        tr('Cet événement est terminé', 'L\'événement kmel'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      );
    } else if (_inscrit) {
      bouton = SecondaryButton(
        texte: tr('Me retirer', 'Mouch jey'),
        onPressed: _envoiEnCours ? null : _participerOuSeRetirer,
      );
    } else {
      // "Je participe" + "Peut-être" (je suis intéressé, sans m'engager)
      bouton = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            texte: tr('Je participe', 'Ena jey'),
            icone: Icons.check,
            onPressed: _envoiEnCours ? null : _participerOuSeRetirer,
          ),
          TextButton.icon(
            onPressed: _envoiEnCours ? null : _changerInteret,
            icon: Icon(_interesse ? Icons.star : Icons.star_border),
            label: Text(
              _interesse ? tr('Je ne suis plus intéressé', 'Ma3adech yhemni') : tr('Peut-être', 'Yemken'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
