import 'package:flutter/material.dart';

import '../data/models/signalement.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_card.dart';
import '../widgets/arch_date_block.dart';
import '../widgets/houmani_logo.dart';
import '../widgets/nail_divider.dart';
import '../widgets/status_badge.dart';
import 'module1/connexion_screen.dart';
import 'module2/services_list_screen.dart';
import 'module3/create_signalement_screen.dart';
import 'module4/sondage_screen.dart';

/// Écran d'accueil de démonstration.
/// Il liste les 4 modules et ouvre l'écran de chacun avec Navigator.push.
///
/// Ce fichier n'a PAS besoin d'être modifié en phase 2 : chaque membre
/// remplace seulement le contenu de son propre écran.
class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  /// Ouvre un écran par-dessus l'écran actuel.
  void _ouvrir(BuildContext context, Widget ecran) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return ecran;
        },
      ),
    );
  }

  /// Quand on touche un onglet de la barre du bas.
  void _onOngletTouche(BuildContext context, int index) {
    if (index == 1) _ouvrir(context, const ServicesListScreen());
    if (index == 2) _ouvrir(context, const CreateSignalementScreen());
    if (index == 3) _ouvrir(context, const SondageScreen());
    if (index == 4) _ouvrir(context, const ConnexionScreen());
    // index 0 = Accueil : on y est déjà
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _enTete(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Les 4 modules',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _carteModule(
                  context,
                  numero: 1,
                  titre: 'Utilisateurs',
                  ecranNom: 'Connexion',
                  icone: Icons.person,
                  ecran: const ConnexionScreen(),
                ),
                _carteModule(
                  context,
                  numero: 2,
                  titre: 'Services',
                  ecranNom: 'Liste des services',
                  icone: Icons.handshake,
                  ecran: const ServicesListScreen(),
                ),
                _carteModule(
                  context,
                  numero: 3,
                  titre: 'Signalements',
                  ecranNom: 'Création de signalement',
                  icone: Icons.campaign,
                  ecran: const CreateSignalementScreen(),
                ),
                _carteModule(
                  context,
                  numero: 4,
                  titre: 'Événements',
                  ecranNom: 'Sondage',
                  icone: Icons.event,
                  ecran: const SondageScreen(),
                ),
                const NailDivider(),
                _apercuComposants(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        indexActif: 0,
        onTap: (index) {
          _onOngletTouche(context, index);
        },
      ),
    );
  }

  /// En-tête teal avec le logo et le message de bienvenue.
  Widget _enTete() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: const HoumaniLogo(taille: 48),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ahla bik !',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Houmani, l\'application de ton quartier',
                  style: TextStyle(color: AppColors.primaryLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Une carte cliquable qui ouvre l'écran d'un module.
  Widget _carteModule(
    BuildContext context, {
    required int numero,
    required String titre,
    required String ecranNom,
    required IconData icone,
    required Widget ecran,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () {
          _ouvrir(context, ecran);
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(icone, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'M$numero · $titre',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ecranNom,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Petit aperçu des composants communs (badges de statut, date en arc).
  Widget _apercuComposants() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Composants communs',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(statut: StatutSignalement.enCours),
              StatusBadge(statut: StatutSignalement.resolu),
              StatusBadge(statut: StatutSignalement.refuse),
              StatusBadge(statut: StatutSignalement.enAttente),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ArchDateBlock(date: DateTime(2026, 10, 17)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Fête des voisins\nYaatik saha !',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
