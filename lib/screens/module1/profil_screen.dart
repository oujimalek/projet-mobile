import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 6, profil de l'utilisateur connecté.
///
/// Onglet "Profil" de la barre du bas : avatar, résidence, statistiques,
/// compétences et liens vers les autres modules.
/// Un administrateur voit en plus le lien "Membres du quartier".
class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});

  @override
  State<ProfilScreen> createState() {
    return _ProfilScreenState();
  }
}

class _ProfilScreenState extends State<ProfilScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  // Nombre de demandes en attente (affiché à l'admin), chargé au démarrage
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
    final int nombre =
        await _repository.compterMembres(StatutUtilisateur.enAttente);
    if (!mounted) {
      return;
    }
    setState(() {
      _enAttente = nombre;
    });
  }

  /// Ouvre un écran, puis redessine le profil au retour
  /// (les données ont pu changer : profil modifié, membres validés...).
  Future<void> _ouvrirPuisRafraichir(String chemin) async {
    await context.push(chemin);
    if (mounted) {
      setState(() {});
      _chargerDemandesEnAttente();
    }
  }

  Future<void> _seDeconnecter() async {
    await _repository.deconnexion();
    if (mounted) {
      // go : on remplace tout, pas de retour vers le profil
      context.go('/connexion');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = _repository.getUtilisateurConnecte();

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _enTete(context, utilisateur),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----- Statistiques -----
                Row(
                  children: [
                    _carteStat('${utilisateur.servicesRendus}', 'Services\nrendus',
                        AppColors.secondary),
                    const SizedBox(width: 10),
                    _carteStat(utilisateur.noteMoyenne.toStringAsFixed(1),
                        'Note\nmoyenne', AppColors.primary),
                    const SizedBox(width: 10),
                    _carteStat('${utilisateur.nbSignalements}', 'Signalements\n',
                        AppColors.secondary),
                  ],
                ),
                const SizedBox(height: 20),

                // ----- Compétences -----
                const Text(
                  'Compétences',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                _competences(utilisateur),
                const SizedBox(height: 20),

                // ----- Liens -----
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: _liens(context, utilisateur)),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _seDeconnecter,
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text(
                      'Se déconnecter',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// En-tête blanc : titre, bouton "Modifier", avatar, nom et résidence.
  Widget _enTete(BuildContext context, Utilisateur utilisateur) {
    final List<Widget> pastilles = [const Pastille(texte: 'Résident')];
    if (utilisateur.estAdmin) {
      pastilles.add(
        const Pastille(
          texte: 'Admin',
          couleur: AppColors.secondary,
          fond: AppColors.secondaryLight,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mon profil',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: () {
                  _ouvrirPuisRafraichir('/modifier-profil');
                },
                child: const Pastille(
                  texte: 'Modifier',
                  couleur: AppColors.secondary,
                  fond: AppColors.secondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AvatarInitiales(
                initiales: utilisateur.initiales,
                taille: 76,
                couleur: Colors.white,
                fond: AppColors.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      utilisateur.nomComplet,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // "Résidence El Yasmine, Bloc B" → "Résidence El Yasmine · Bloc B"
                      utilisateur.residence.replaceAll(', ', ' · '),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: pastilles),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Une petite carte de statistique (valeur colorée + libellé).
  Widget _carteStat(String valeur, String libelle, Color couleur) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              valeur,
              style: TextStyle(
                color: couleur,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              libelle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Les compétences en pastilles dorées, puis "+ Ajouter".
  Widget _competences(Utilisateur utilisateur) {
    final List<Widget> pastilles = [];
    for (final String competence in utilisateur.competences) {
      pastilles.add(
        Pastille(
          texte: competence,
          couleur: AppColors.secondary,
          fond: AppColors.secondaryLight,
        ),
      );
    }
    pastilles.add(
      BoutonAjouter(
        onTap: () {
          _ouvrirPuisRafraichir('/modifier-profil');
        },
      ),
    );
    return Wrap(spacing: 8, runSpacing: 8, children: pastilles);
  }

  /// Les lignes de la carte de liens.
  List<Widget> _liens(BuildContext context, Utilisateur utilisateur) {
    final List<Widget> lignes = [];

    // Réservé à l'administrateur : gérer les membres du quartier
    if (utilisateur.estAdmin) {
      lignes.add(
        _ligneLien(
          'Membres du quartier',
          detail: _enAttente > 0 ? '$_enAttente en attente' : null,
          onTap: () {
            _ouvrirPuisRafraichir('/profil/membres');
          },
        ),
      );
      lignes.add(const Divider(height: 1, color: AppColors.border));
    }

    // go : ces liens ouvrent l'onglet du module correspondant
    lignes.add(_ligneLien('Mes services', onTap: () => context.go('/services')));
    lignes.add(const Divider(height: 1, color: AppColors.border));
    lignes.add(
      _ligneLien('Mes signalements', onTap: () => context.go('/signalements')),
    );
    lignes.add(const Divider(height: 1, color: AppColors.border));
    lignes.add(
      _ligneLien('Mes événements', onTap: () => context.go('/evenements')),
    );
    lignes.add(const Divider(height: 1, color: AppColors.border));
    lignes.add(
      _ligneLien(
        'Paramètres',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paramètres : bientôt disponible')),
          );
        },
      ),
    );
    return lignes;
  }

  Widget _ligneLien(String titre, {String? detail, required Function() onTap}) {
    final List<Widget> fin = [];
    if (detail != null) {
      fin.add(
        Pastille(
          texte: detail,
          couleur: AppColors.badgeEnAttente,
          fond: AppColors.badgeEnAttenteFond,
        ),
      );
    }
    fin.add(const Icon(Icons.chevron_right, color: AppColors.textSecondary));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                titre,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            ...fin,
          ],
        ),
      ),
    );
  }
}
