import 'package:flutter/material.dart';

import '../../data/models/quartier.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../data/services/verification_adresse_m1.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 8, liste des membres (administrateur).
///
/// Trois onglets : demandes en attente, membres actifs, membres bloqués.
/// L'admin valide ou refuse les demandes, bloque ou débloque un membre.
class AdminMembresScreen extends StatefulWidget {
  const AdminMembresScreen({super.key});

  @override
  State<AdminMembresScreen> createState() {
    return _AdminMembresScreenState();
  }
}

class _AdminMembresScreenState extends State<AdminMembresScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();
  final TextEditingController _rechercheController = TextEditingController();

  // Onglet affiché (par défaut : les demandes en attente)
  StatutUtilisateur _onglet = StatutUtilisateur.enAttente;

  // Les membres de chaque onglet, chargés depuis le repository
  List<Utilisateur> _enAttente = [];
  List<Utilisateur> _actifs = [];
  List<Utilisateur> _bloques = [];
  int _nbRefuses = 0; // pas d'onglet : seulement compté (statistiques)

  bool _enChargement = true; // true jusqu'au premier chargement
  String _erreur = ''; // ex : pas de réseau

  // Vérification des adresses des demandes (Nominatim), par id de membre.
  // Absent : pas encore vérifiée ; échec : pas de réseau.
  final Map<String, Resultat<VerdictAdresse>> _verdicts = {};

  // Couleurs des avatars, choisies à tour de rôle
  // (des `get` : les couleurs suivent le thème clair/sombre)
  static List<Color> get _couleursAvatar => [
    AppColors.primary,
    AppColors.secondary,
    AppColors.textSecondary,
  ];
  static List<Color> get _fondsAvatar => [
    AppColors.primaryLight,
    AppColors.secondaryLight,
    AppColors.backgroundSecondary,
  ];

  @override
  void initState() {
    super.initState();
    _charger();
    _rechercheController.addListener(() {
      setState(() {});
    });
  }

  /// (Re)charge les membres des 3 onglets.
  Future<void> _charger() async {
    final Resultat<List<Utilisateur>> enAttente =
        await _repository.getMembres(StatutUtilisateur.enAttente);
    final Resultat<List<Utilisateur>> actifs =
        await _repository.getMembres(StatutUtilisateur.actif);
    final Resultat<List<Utilisateur>> bloques =
        await _repository.getMembres(StatutUtilisateur.bloque);
    final Resultat<int> refuses =
        await _repository.compterMembres(StatutUtilisateur.refuse);
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _nbRefuses = refuses.donnee ?? 0;
      // En cas d'échec, l'onglet reste vide et on affiche pourquoi
      _enAttente = enAttente.donnee ?? [];
      _actifs = actifs.donnee ?? [];
      _bloques = bloques.donnee ?? [];
      _erreur = '';
      for (final Resultat<List<Utilisateur>> r in [enAttente, actifs, bloques]) {
        if (!r.estSucces) {
          _erreur = r.erreur!;
        }
      }
    });
    _verifierAdresses();
  }

  /// Vérifie, une par une, les adresses des demandes en attente :
  /// sont-elles dans le contour du quartier ? (en arrière-plan)
  Future<void> _verifierAdresses() async {
    final List<Utilisateur> aVerifier = [];
    for (final Utilisateur membre in _enAttente) {
      if (membre.adresse.isNotEmpty && !_verdicts.containsKey(membre.id)) {
        aVerifier.add(membre);
      }
    }
    if (aVerifier.isEmpty) {
      return;
    }
    final Resultat<Quartier?> quartier = await _repository.getQuartierConnecte();
    if (quartier.donnee == null) {
      return;
    }
    for (final Utilisateur membre in aVerifier) {
      final Resultat<VerdictAdresse> verdict =
          await VerificationAdresseM1.verifier(membre.adresse, quartier.donnee!);
      if (!mounted) {
        return;
      }
      setState(() {
        _verdicts[membre.id] = verdict;
      });
    }
  }

  /// Les membres chargés pour un statut.
  List<Utilisateur> _membresDe(StatutUtilisateur statut) {
    switch (statut) {
      case StatutUtilisateur.enAttente:
        return _enAttente;
      case StatutUtilisateur.actif:
        return _actifs;
      case StatutUtilisateur.bloque:
        return _bloques;
      case StatutUtilisateur.refuse:
        return []; // pas d'onglet pour les demandes refusées
    }
  }

  /// Les membres de l'onglet affiché dont le nom contient la recherche.
  List<Utilisateur> _membresAffiches() {
    final String texte = _rechercheController.text.trim().toLowerCase();
    final List<Utilisateur> resultats = [];
    for (final Utilisateur membre in _membresDe(_onglet)) {
      if (membre.nomComplet.toLowerCase().contains(texte)) {
        resultats.add(membre);
      }
    }
    return resultats;
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  /// "il y a 2 h", "hier", "il y a 3 jours"...
  String _depuis(DateTime? date) {
    if (date == null) {
      return '';
    }
    final Duration ecart = DateTime.now().difference(date);
    if (ecart.inMinutes < 60) {
      return tr(
        'il y a ${ecart.inMinutes} min',
        'hedhi ${ecart.inMinutes} d9i9a',
      );
    }
    if (ecart.inHours < 24) {
      return tr('il y a ${ecart.inHours} h', 'hedhi ${ecart.inHours} se3a');
    }
    if (ecart.inDays == 1) {
      return tr('hier', 'il bera7');
    }
    return tr('il y a ${ecart.inDays} jours', 'hedhi ${ecart.inDays} ayem');
  }

  /// Applique une action sur un membre, recharge les listes
  /// et affiche un message.
  Future<void> _action(
    String message,
    Future<Resultat<void>> Function() action,
  ) async {
    final Resultat<void> resultat = await action();
    await _charger();
    if (!mounted) {
      return;
    }
    // Succès : le message prévu ; échec : le message d'erreur
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultat.estSucces ? message : resultat.erreur!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Utilisateur> membres = _membresAffiches();

    final List<Widget> cartes = [];
    for (int i = 0; i < membres.length; i++) {
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _carteMembre(membres[i], i),
        ),
      );
    }
    if (_enChargement) {
      cartes.add(const IndicateurChargement());
    } else if (_erreur.isNotEmpty) {
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            _erreur,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.error),
          ),
        ),
      );
    } else if (cartes.isEmpty) {
      cartes.add(
        Padding(
          padding: EdgeInsets.only(top: 32),
          child: Text(
            tr('Aucun membre ici', 'Ma famma 7ad lahne'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _enTete(context),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Même style que les autres champs (thème de l'app)
                TextField(
                  controller: _rechercheController,
                  decoration: InputDecoration(
                    hintText: tr('Rechercher un membre...', 'Lawej 3la sekn...'),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 14),
                _statistiques(),
                const SizedBox(height: 14),
                _onglets(),
                const SizedBox(height: 14),
                ...cartes,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// En-tête blanc : "Membres", pastille Admin, quartier et nombre de membres.
  Widget _enTete(BuildContext context) {
    final Utilisateur admin = _repository.getUtilisateurConnecte();
    final int total = _enAttente.length + _actifs.length + _bloques.length;

    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 12,
        20,
        20,
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
                Text(
                  tr('Membres', 'Sokkan'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  tr(
                    '${admin.quartier} · $total membres',
                    '${admin.quartier} · $total sokkan',
                  ),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Pastille(texte: 'Admin'),
        ],
      ),
    );
  }

  /// Les statistiques du quartier : actifs, en attente, bloqués, refusés.
  Widget _statistiques() {
    return Row(
      children: [
        _carteStat(
          '${_actifs.length}',
          tr('Actifs', 'Mawjoudin'),
          AppColors.success,
        ),
        const SizedBox(width: 8),
        _carteStat(
          '${_enAttente.length}',
          tr('En attente', 'Yestannew'),
          AppColors.warning,
        ),
        const SizedBox(width: 8),
        _carteStat(
          '${_bloques.length}',
          tr('Bloqués', 'Mbloukiyin'),
          AppColors.error,
        ),
        const SizedBox(width: 8),
        _carteStat(
          '$_nbRefuses',
          tr('Refusés', 'Marfoudhin'),
          AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _carteStat(String valeur, String libelle, Color couleur) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(
              valeur,
              style: TextStyle(
                color: couleur,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              libelle,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// Les 3 onglets avec leur compteur, sur un fond beige.
  Widget _onglets() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          _boutonOnglet(
            tr('En attente', 'Yestannew'),
            StatutUtilisateur.enAttente,
          ),
          _boutonOnglet(tr('Actifs', 'Mawjoudin'), StatutUtilisateur.actif),
          _boutonOnglet(tr('Bloqués', 'Mbloukiyin'), StatutUtilisateur.bloque),
        ],
      ),
    );
  }

  Widget _boutonOnglet(String nom, StatutUtilisateur statut) {
    final bool actif = _onglet == statut;
    final int nombre = _membresDe(statut).length;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _onglet = statut;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: actif ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$nom ($nombre)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: actif ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// La carte d'un membre : avatar, nom, logement, puis les boutons d'action.
  Widget _carteMembre(Utilisateur membre, int index) {
    // Logement et ancienneté de la demande, sans "·" si l'un des deux manque
    final List<String> morceaux = [];
    if (membre.logement.isNotEmpty) {
      morceaux.add(membre.logement);
    }
    final String depuis = _depuis(membre.dateDemande);
    if (_onglet == StatutUtilisateur.enAttente && depuis.isNotEmpty) {
      morceaux.add(depuis);
    }
    // Onglet Bloqués : on rappelle la raison donnée
    if (_onglet == StatutUtilisateur.bloque && membre.motif.isNotEmpty) {
      morceaux.add(tr('Motif : ${membre.motif}', 'Sbab : ${membre.motif}'));
    }
    final String detail = morceaux.join(' · ');

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              AvatarInitiales(
                initiales: membre.initiales,
                couleur: _couleursAvatar[index % 3],
                fond: _fondsAvatar[index % 3],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            membre.nomComplet,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // M4 : badge doré des leaders du quartier
                        if (membre.estLeader) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Leader',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    // Demande avec une adresse : vérifiée sur la carte
                    if (_onglet == StatutUtilisateur.enAttente &&
                        membre.adresse.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        membre.adresse,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      _badgeAdresse(_verdicts[membre.id]),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _boutons(membre),
        ],
      ),
    );
  }

  /// Le résultat de la vérification de l'adresse, en couleur.
  Widget _badgeAdresse(Resultat<VerdictAdresse>? verdict) {
    String texte;
    Color couleur;
    IconData icone;
    if (verdict == null) {
      texte = tr('Vérification de l\'adresse...', 'Nthabtou fel adresse...');
      couleur = AppColors.textSecondary;
      icone = Icons.hourglass_empty;
    } else if (!verdict.estSucces) {
      texte = tr(
        'Adresse non vérifiée (pas de réseau ?)',
        'Ma najjamnech nthabtou fel adresse (ma famech réseau ?)',
      );
      couleur = AppColors.textSecondary;
      icone = Icons.cloud_off;
    } else {
      final VerdictAdresse v = verdict.donnee!;
      final String km = v.distanceMetres == null
          ? ''
          : ' · ${(v.distanceMetres! / 1000).toStringAsFixed(1)} km';
      switch (v.etat) {
        case EtatAdresse.dansLeQuartier:
          texte = tr('Adresse dans la houma', 'L\'adresse fel houma');
          couleur = AppColors.success;
          icone = Icons.verified_outlined;
        case EtatAdresse.horsDuQuartier:
          texte = tr(
            'Adresse hors de la houma$km',
            'L\'adresse barra el houma$km',
          );
          couleur = AppColors.warning;
          icone = Icons.warning_amber_rounded;
        case EtatAdresse.introuvable:
          texte = tr(
            'Adresse introuvable sur la carte',
            'Ma l9inech l\'adresse 3al carte',
          );
          couleur = AppColors.textSecondary;
          icone = Icons.help_outline;
        case EtatAdresse.sansContour:
          texte = tr(
            'Trace les limites du quartier pour vérifier$km',
            'Arsem 7doud el houma bech tthabbet$km',
          );
          couleur = AppColors.textSecondary;
          icone = Icons.map_outlined;
      }
    }
    return Row(
      children: [
        Icon(icone, size: 14, color: couleur),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            texte,
            style: TextStyle(
              color: couleur,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Les boutons d'action, selon l'onglet affiché.
  Widget _boutons(Utilisateur membre) {
    switch (_onglet) {
      case StatutUtilisateur.enAttente:
        return Row(
          children: [
            Expanded(
              child: PrimaryButton(
                texte: tr('Valider', 'A9bel'),
                onPressed: () {
                  _action(
                    tr(
                      '${membre.prenom} a rejoint la houma',
                      '${membre.prenom} dkhal lel houma',
                    ),
                    () {
                      return _repository.validerMembre(membre.id);
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _boutonRouge(tr('Refuser', 'Orfodh'), () async {
                final String? motif = await _demanderMotif(
                  tr('Refuser la demande ?', 'Torfodh el demande ?'),
                  tr(
                    '${membre.nomComplet} ne pourra pas rejoindre le quartier. '
                        'Il pourra faire une nouvelle demande.',
                    '${membre.nomComplet} ma ynajjamch yodkhol lel houma. '
                        'Ynajjem yab3ath demande jdida.',
                  ),
                  tr('Refuser', 'Orfodh'),
                );
                if (motif == null) {
                  return;
                }
                _action(
                    tr(
                      'Demande de ${membre.prenom} refusée',
                      'Demande mta3 ${membre.prenom} tarfdhet',
                    ), () {
                  return _repository.refuserMembre(membre.id, motif);
                });
              }),
            ),
          ],
        );
      case StatutUtilisateur.actif:
        // L'admin ne peut pas se bloquer lui-même
        if (membre.id == _repository.getUtilisateurConnecte().id) {
          return const SizedBox();
        }
        return Row(
          children: [
            // M4 : nommer leader / retirer le rôle de leader
            Expanded(child: _boutonLeader(membre)),
            const SizedBox(width: 10),
            Expanded(child: _boutonBloquer(membre)),
          ],
        );
      case StatutUtilisateur.bloque:
        return SecondaryButton(
          texte: tr('Débloquer', 'Debloki'),
          onPressed: () {
            _action(
                tr(
                  '${membre.prenom} est débloqué(e)',
                  '${membre.prenom} tdebloka',
                ), () {
              return _repository.debloquerMembre(membre.id);
            });
          },
        );
      case StatutUtilisateur.refuse:
        return const SizedBox(); // pas d'onglet "refusés"
    }
  }

  /// M4 - Le bouton qui nomme un membre leader, ou lui retire ce rôle.
  Widget _boutonLeader(Utilisateur membre) {
    if (membre.estLeader) {
      return SecondaryButton(
        texte: tr('Retirer leader', 'Na77i leader'),
        onPressed: () {
          _action(
            tr(
              '${membre.prenom} n\'est plus leader',
              '${membre.prenom} ma3adech leader',
            ),
            () => _repository.changerRole(membre.id, RoleUtilisateur.resident),
          );
        },
      );
    }
    return PrimaryButton(
      texte: tr('Nommer leader', 'A3mlou leader'),
      onPressed: () {
        _action(
          tr(
            '${membre.prenom} est maintenant leader',
            '${membre.prenom} wallé leader',
          ),
          () => _repository.changerRole(membre.id, RoleUtilisateur.leader),
        );
      },
    );
  }

  /// Le bouton "Bloquer" d'un membre actif (l'admin donne le motif).
  Widget _boutonBloquer(Utilisateur membre) {
    return _boutonRouge(tr('Bloquer', 'Bloki'), () async {
      final String? motif = await _demanderMotif(
        tr('Bloquer ce membre ?', 'Tbloki el sekn hedha ?'),
        tr(
          '${membre.nomComplet} sera déconnecté et ne pourra plus utiliser '
              'l\'application. Tu pourras le débloquer plus tard.',
          '${membre.nomComplet} bech yokhrej w ma ynajjamch yesta3mel '
              'l\'appli. Tnajjem tdebloukih ba3d.',
        ),
        tr('Bloquer', 'Bloki'),
      );
      if (motif == null) {
        return;
      }
      _action(
          tr(
            '${membre.prenom} est bloqué(e)',
            '${membre.prenom} tbloka',
          ), () {
        return _repository.bloquerMembre(membre.id, motif);
      });
    });
  }

  /// Avant une action négative (refuser, bloquer) : l'admin confirme et
  /// donne la raison, montrée au membre. null si l'admin a annulé.
  Future<String?> _demanderMotif(String titre, String message, String action) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return _DialogueMotif(titre: titre, message: message, action: action);
      },
    );
  }

  /// Bouton blanc à bordure rouge (action négative : refuser, bloquer).
  Widget _boutonRouge(String texte, Function() onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        backgroundColor: AppColors.card,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: AppColors.error, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(texte),
    );
  }
}

/// La fenêtre "Refuser / Bloquer" avec le champ du motif.
/// Un widget à part : il garde son propre TextEditingController,
/// libéré (dispose) quand la fenêtre se ferme.
class _DialogueMotif extends StatefulWidget {
  final String titre;
  final String message;
  final String action; // texte du bouton rouge, ex : "Bloquer"

  const _DialogueMotif({
    required this.titre,
    required this.message,
    required this.action,
  });

  @override
  State<_DialogueMotif> createState() {
    return _DialogueMotifState();
  }
}

class _DialogueMotifState extends State<_DialogueMotif> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _motifController = TextEditingController();

  @override
  void dispose() {
    _motifController.dispose();
    super.dispose();
  }

  void _valider() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_motifController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motifController,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr(
                  'Motif (vu par le membre)',
                  'Sbab (yarah el sekn)',
                ),
                hintText: tr(
                  'Ex : logement introuvable dans la résidence',
                  'Mathalan : el dar mouch mawjouda fel résidence',
                ),
              ),
              validator: (String? valeur) {
                return UtilisateurRepository.refusMotif(valeur ?? '');
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // null = annulé
          },
          child: Text(tr('Annuler', 'Batel')),
        ),
        TextButton(
          onPressed: _valider,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
