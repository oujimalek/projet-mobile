import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/utilisateur.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 7, modification du profil.
///
/// Nom, téléphone, bâtiment/appartement et compétences (ajout/suppression).
/// "Enregistrer" sauvegarde dans UtilisateurRepository puis revient au profil.
class ProfilEditionScreen extends StatefulWidget {
  const ProfilEditionScreen({super.key});

  @override
  State<ProfilEditionScreen> createState() {
    return _ProfilEditionScreenState();
  }
}

class _ProfilEditionScreenState extends State<ProfilEditionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomController;
  late final TextEditingController _telephoneController;
  late final TextEditingController _logementController;

  // Copie modifiable des compétences (enregistrée seulement à la fin)
  final List<String> _competences = [];

  @override
  void initState() {
    super.initState();
    // Les champs sont pré-remplis avec les données actuelles
    final Utilisateur utilisateur = UtilisateurRepository().getUtilisateurConnecte();
    _nomController = TextEditingController(text: utilisateur.nomComplet);
    _telephoneController = TextEditingController(text: utilisateur.telephone);
    _logementController = TextEditingController(text: utilisateur.logement);
    for (final String competence in utilisateur.competences) {
      _competences.add(competence);
    }
  }

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _logementController.dispose();
    super.dispose();
  }

  String? _validerNom(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Saisis ton nom complet';
    }
    return null;
  }

  String? _validerTelephone(String? valeur) {
    int chiffres = 0;
    final String texte = valeur ?? '';
    for (int i = 0; i < texte.length; i++) {
      if ('0123456789'.contains(texte[i])) {
        chiffres++;
      }
    }
    if (chiffres < 8) {
      return 'Numéro de téléphone invalide (8 chiffres)';
    }
    return null;
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await UtilisateurRepository().modifierProfil(
      nomComplet: _nomController.text,
      telephone: _telephoneController.text,
      logement: _logementController.text,
      competences: _competences,
    );
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil enregistré')),
    );
    context.pop(); // retour au profil
  }

  /// Petite fenêtre pour taper une nouvelle compétence.
  Future<void> _ajouterCompetence() async {
    final TextEditingController controller = TextEditingController();
    final String? nouvelle = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ajouter une compétence'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Ex : Jardinage'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );

    // On ajoute seulement un texte non vide et pas déjà présent
    if (nouvelle != null &&
        nouvelle.isNotEmpty &&
        !_competences.contains(nouvelle)) {
      setState(() {
        _competences.add(nouvelle);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = UtilisateurRepository().getUtilisateurConnecte();

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: 'Modifier le profil',
            action: TextButton(
              onPressed: _enregistrer,
              child: const Text(
                'Enregistrer',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ----- Photo (initiales) -----
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: AvatarInitiales(
                      initiales: utilisateur.initiales,
                      taille: 88,
                      couleur: AppColors.secondary,
                      fond: AppColors.secondaryLight,
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Changement de photo : bientôt disponible'),
                        ),
                      );
                    },
                    child: const Text(
                      'Changer la photo',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ----- Champs -----
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        label: 'Nom complet',
                        controller: _nomController,
                        validator: _validerNom,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Numéro de téléphone',
                        controller: _telephoneController,
                        clavier: TextInputType.phone,
                        validator: _validerTelephone,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Bâtiment et appartement',
                        hint: 'Ex : Bloc B - Appt 12',
                        controller: _logementController,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Visible uniquement par l\'administrateur du quartier.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ----- Compétences -----
                const Text(
                  'Compétences',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: _pastillesCompetences()),
                const SizedBox(height: 32),

                PrimaryButton(
                  texte: 'Enregistrer les modifications',
                  onPressed: _enregistrer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Une pastille avec une croix par compétence, puis "+ Ajouter".
  List<Widget> _pastillesCompetences() {
    final List<Widget> pastilles = [];
    for (final String competence in _competences) {
      pastilles.add(
        Pastille(
          texte: competence,
          couleur: AppColors.secondary,
          fond: AppColors.secondaryLight,
          onSupprimer: () {
            setState(() {
              _competences.remove(competence);
            });
          },
        ),
      );
    }
    pastilles.add(BoutonAjouter(onTap: _ajouterCompetence));
    return pastilles;
  }
}
