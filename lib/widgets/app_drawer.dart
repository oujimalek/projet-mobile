import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/utilisateur.dart';
import '../data/resultat.dart';
import '../data/services/utilisateur_repository.dart';
import '../screens/module1/widgets_module1.dart';
import '../screens/module2/mes_demandes_screen.dart';
import '../screens/module2/module2_outils.dart';
import '../screens/module2/service_form_screen.dart';
import '../screens/module2/services_communs_screen.dart';
import '../theme/app_theme.dart';
import 'houmani_logo.dart';

/// Clé de la coquille (AppShell) : elle permet d'ouvrir le menu latéral
/// depuis n'importe quel onglet, même si l'écran a son propre Scaffold.
final GlobalKey<ScaffoldState> cleCoquille = GlobalKey<ScaffoldState>();

/// Ouvre le menu latéral (à brancher sur un bouton "≡" dans un en-tête).
void ouvrirMenu() {
  cleCoquille.currentState?.openDrawer();
}

/// Le menu latéral de l'application (Drawer).
///
/// - En haut : le logo Houmani et le nom du quartier.
/// - Au milieu : les 4 modules et leurs sous-rubriques, puis le compte.
/// - En bas : la carte de l'utilisateur connecté, avec "Se déconnecter".
///
/// La barre du bas reste là : le menu donne simplement accès à TOUTES
/// les rubriques (la barre du bas ne montre que les 5 onglets).
class AppDrawer extends StatefulWidget {
  final String chemin; // chemin actuel, pour surligner la rubrique active

  const AppDrawer({super.key, required this.chemin});

  @override
  State<AppDrawer> createState() {
    return _AppDrawerState();
  }
}

class _AppDrawerState extends State<AppDrawer> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  // Nombre de demandes d'adhésion en attente (affiché à l'admin)
  int _enAttente = 0;

  @override
  void initState() {
    super.initState();
    _chargerDemandesEnAttente();
  }

  Future<void> _chargerDemandesEnAttente() async {
    if (!_repository.getUtilisateurConnecte().estAdmin) {
      return;
    }
    final Resultat<int> resultat =
        await _repository.compterMembres(StatutUtilisateur.enAttente);
    if (!mounted) {
      return;
    }
    setState(() {
      _enAttente = resultat.donnee ?? 0;
    });
  }

  /// Ferme le menu puis affiche un onglet (go : pas de flèche retour).
  void _allerA(String chemin) {
    Navigator.of(context).pop(); // ferme le menu
    context.go(chemin);
  }

  /// Ferme le menu puis ouvre un écran par-dessus (push : flèche retour).
  void _ouvrir(String chemin) {
    Navigator.of(context).pop();
    context.push(chemin);
  }

  /// Ferme le menu puis ouvre un écran du module 2 (plein écran).
  void _ouvrirEcran(Widget ecran) {
    Navigator.of(context).pop();
    ouvrirEcran(context, ecran);
  }

  Future<void> _seDeconnecter() async {
    // On garde le routeur AVANT de fermer le menu : une fois fermé,
    // le menu disparaît et son context n'est plus utilisable
    final GoRouter routeur = GoRouter.of(context);
    Navigator.of(context).pop();
    await _repository.deconnexion();
    // go : on remplace tout, pas de retour possible
    routeur.go('/connexion');
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = _repository.getUtilisateurConnecte();

    // Rubriques du compte (+ "Membres du quartier" pour l'admin).
    // "Modifier mon profil" est sur l'écran Profil (bouton "Modifier").
    final List<Widget> rubriquesCompte = [
      _rubrique(
        icone: Icons.person_outline,
        titre: 'Mon profil',
        actif: widget.chemin == '/profil',
        onTap: () => _allerA('/profil'),
      ),
      _rubrique(
        icone: Icons.location_city_outlined,
        titre: 'Mon quartier',
        actif: widget.chemin.startsWith('/profil/quartier'),
        onTap: () => _ouvrir('/profil/quartier'),
      ),
    ];
    if (utilisateur.estAdmin) {
      rubriquesCompte.add(
        _rubrique(
          icone: Icons.groups_outlined,
          titre: 'Membres du quartier',
          badge: _enAttente,
          actif: widget.chemin.startsWith('/profil/membres'),
          // push : la flèche retour ramène à l'écran d'où on vient
          onTap: () => _ouvrir('/profil/membres'),
        ),
      );
    }
    rubriquesCompte.add(
      _rubrique(
        icone: Icons.settings_outlined,
        titre: 'Paramètres',
        onTap: () => _ouvrir('/parametres'),
      ),
    );

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            _enTete(utilisateur),
            Divider(height: 1, color: AppColors.border),

            // ----- Rubriques (défilent si l'écran est petit) -----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _rubrique(
                    icone: Icons.home_outlined,
                    titre: 'Accueil',
                    actif: widget.chemin == '/accueil',
                    onTap: () => _allerA('/accueil'),
                  ),
                  _titreSection('MODULES'),
                  _module(
                    icone: Icons.handshake_outlined,
                    titre: 'Services',
                    actif: widget.chemin.startsWith('/services'),
                    sousRubriques: [
                      _sousRubrique('Offres et demandes', () => _allerA('/services')),
                      _sousRubrique('Publier un service',
                          () => _ouvrirEcran(const ServiceFormScreen())),
                      _sousRubrique('Mes demandes',
                          () => _ouvrirEcran(const MesDemandesScreen())),
                      _sousRubrique('Services communs',
                          () => _ouvrirEcran(const ServicesCommunsScreen())),
                    ],
                  ),
                  _module(
                    icone: Icons.campaign_outlined,
                    titre: 'Signalements',
                    actif: widget.chemin.startsWith('/signalements'),
                    sousRubriques: [
                      _sousRubrique(
                          'Nouveau signalement', () => _allerA('/signalements')),
                    ],
                  ),
                  _module(
                    icone: Icons.event_outlined,
                    titre: 'Événements',
                    actif: widget.chemin.startsWith('/evenements'),
                    sousRubriques: [
                      _sousRubrique(
                          'Sondage du quartier', () => _allerA('/evenements')),
                    ],
                  ),
                  _titreSection('MON COMPTE'),
                  ...rubriquesCompte,
                ],
              ),
            ),

            Divider(height: 1, color: AppColors.border),
            _carteUtilisateur(utilisateur),
          ],
        ),
      ),
    );
  }

  /// Logo + nom de l'application + quartier.
  Widget _enTete(Utilisateur utilisateur) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          const HoumaniLogo(taille: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Houmani',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  utilisateur.quartier,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Petit titre gris en majuscules ("MODULES", "MON COMPTE").
  Widget _titreSection(String titre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
      child: Text(
        titre,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  /// Une rubrique simple (icône + titre, badge optionnel).
  /// La rubrique active est sur fond bleu clair.
  Widget _rubrique({
    required IconData icone,
    required String titre,
    required Function() onTap,
    bool actif = false,
    int badge = 0,
  }) {
    Widget? fin;
    if (badge > 0) {
      fin = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.badgeEnAttenteFond,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$badge',
          style: TextStyle(
            color: AppColors.badgeEnAttente,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(
          icone,
          color: actif ? AppColors.primary : AppColors.textSecondary,
        ),
        title: Text(
          titre,
          style: TextStyle(
            fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
            color: actif ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        trailing: fin,
        selected: actif,
        selectedTileColor: AppColors.primaryLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        onTap: onTap,
      ),
    );
  }

  /// Un module qui se déplie pour montrer ses sous-rubriques.
  /// Le module de l'onglet affiché est déplié au départ.
  Widget _module({
    required IconData icone,
    required String titre,
    required bool actif,
    required List<Widget> sousRubriques,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ExpansionTile(
        initiallyExpanded: actif,
        leading: Icon(
          icone,
          color: actif ? AppColors.primary : AppColors.textSecondary,
        ),
        title: Text(
          titre,
          style: TextStyle(
            fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
            color: actif ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textSecondary,
        backgroundColor: AppColors.card,
        // Pas de traits au-dessus et en dessous quand il est déplié
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: sousRubriques,
      ),
    );
  }

  /// Une sous-rubrique (décalée à droite, sous le titre du module).
  Widget _sousRubrique(String titre, Function() onTap) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 72, right: 16),
      title: Text(
        titre,
        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      ),
      onTap: onTap,
    );
  }

  /// Carte du bas : avatar, nom, e-mail et bouton de déconnexion.
  Widget _carteUtilisateur(Utilisateur utilisateur) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            AvatarUtilisateur(
              avatar: utilisateur.avatar,
              initiales: utilisateur.initiales,
              taille: 42,
              couleur: Colors.white,
              fond: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    utilisateur.nomComplet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    utilisateur.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Se déconnecter',
              onPressed: _seDeconnecter,
              icon: Icon(Icons.logout, color: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }
}
