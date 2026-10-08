import 'package:flutter/material.dart';

import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
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

  // Couleurs des avatars, choisies à tour de rôle
  static const List<Color> _couleursAvatar = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.textSecondary,
  ];
  static const List<Color> _fondsAvatar = [
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
    final List<Utilisateur> enAttente =
        await _repository.getMembres(StatutUtilisateur.enAttente);
    final List<Utilisateur> actifs =
        await _repository.getMembres(StatutUtilisateur.actif);
    final List<Utilisateur> bloques =
        await _repository.getMembres(StatutUtilisateur.bloque);
    if (!mounted) {
      return;
    }
    setState(() {
      _enAttente = enAttente;
      _actifs = actifs;
      _bloques = bloques;
    });
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
      return 'il y a ${ecart.inMinutes} min';
    }
    if (ecart.inHours < 24) {
      return 'il y a ${ecart.inHours} h';
    }
    if (ecart.inDays == 1) {
      return 'hier';
    }
    return 'il y a ${ecart.inDays} jours';
  }

  /// Applique une action sur un membre, recharge les listes
  /// et affiche un message.
  Future<void> _action(String message, Future<void> Function() action) async {
    await action();
    await _charger();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    if (cartes.isEmpty) {
      cartes.add(
        const Padding(
          padding: EdgeInsets.only(top: 32),
          child: Text(
            'Aucun membre ici',
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
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un membre...',
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
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
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Membres',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${admin.quartier} · $total membres',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Pastille(texte: 'Admin'),
        ],
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
          _boutonOnglet('En attente', StatutUtilisateur.enAttente),
          _boutonOnglet('Actifs', StatutUtilisateur.actif),
          _boutonOnglet('Bloqués', StatutUtilisateur.bloque),
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
    String detail = membre.logement;
    final String depuis = _depuis(membre.dateDemande);
    if (_onglet == StatutUtilisateur.enAttente && depuis.isNotEmpty) {
      detail = '$detail · $depuis';
    }

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
                    Text(
                      membre.nomComplet,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
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

  /// Les boutons d'action, selon l'onglet affiché.
  Widget _boutons(Utilisateur membre) {
    switch (_onglet) {
      case StatutUtilisateur.enAttente:
        return Row(
          children: [
            Expanded(
              child: PrimaryButton(
                texte: 'Valider',
                onPressed: () {
                  _action('${membre.prenom} a rejoint la houma', () {
                    return _repository.validerMembre(membre.id);
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _boutonRouge('Refuser', () {
                _action('Demande de ${membre.prenom} refusée', () {
                  return _repository.refuserMembre(membre.id);
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
        return _boutonRouge('Bloquer', () {
          _action('${membre.prenom} est bloqué(e)', () {
            return _repository.bloquerMembre(membre.id);
          });
        });
      case StatutUtilisateur.bloque:
        return SecondaryButton(
          texte: 'Débloquer',
          onPressed: () {
            _action('${membre.prenom} est débloqué(e)', () {
              return _repository.debloquerMembre(membre.id);
            });
          },
        );
    }
  }

  /// Bouton blanc à bordure rouge (action négative : refuser, bloquer).
  Widget _boutonRouge(String texte, Function() onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        backgroundColor: AppColors.card,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.error, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(texte),
    );
  }
}
