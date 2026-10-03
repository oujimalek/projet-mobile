import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';

/// M3 - Signalements : création d'un signalement.
///
/// L'utilisateur choisit une catégorie dans une GridView, décrit le problème,
/// peut ajouter une photo (bouton visuel pour l'instant) et indique le lieu.
class CreateSignalementScreen extends StatefulWidget {
  const CreateSignalementScreen({super.key});

  @override
  State<CreateSignalementScreen> createState() {
    return _CreateSignalementScreenState();
  }
}

class _CreateSignalementScreenState extends State<CreateSignalementScreen> {
  final SignalementRepository _repository = SignalementRepository();

  // Formulaire et contrôleurs des champs
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _localisationController = TextEditingController();

  // État de l'écran
  String? _categorieChoisie; // id de la catégorie, null = rien de choisi
  bool _erreurCategorie = false; // true = afficher "Choisis une catégorie"
  String _message = ''; // message affiché après la publication

  @override
  void dispose() {
    _descriptionController.dispose();
    _localisationController.dispose();
    super.dispose();
  }

  /// "Utiliser ma position" : on remplit le lieu avec la résidence
  /// de l'utilisateur connecté (en attendant la vraie géolocalisation).
  void _utiliserMaPosition() {
    _localisationController.text =
        UtilisateurRepository().getUtilisateurConnecte().residence;
  }

  /// Champ obligatoire : renvoie un message si le texte est vide.
  String? _validerObligatoire(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Champ obligatoire';
    }
    return null;
  }

  /// Appelé quand on touche "Publier le signalement".
  void _publier() {
    // On vérifie les champs du Form
    final bool champsValides = _formKey.currentState!.validate();

    setState(() {
      // On vérifie aussi qu'une catégorie a été choisie
      _erreurCategorie = _categorieChoisie == null;

      final String? id = _categorieChoisie;
      if (champsValides && id != null) {
        final CategorieSignalement categorie = _repository.getCategorieParId(id);
        _message = 'Yaatik saha ! Signalement "${categorie.nom}" publié.';
      } else {
        _message = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // En-tête blanc arrondi, comme sur la maquette
          const AppHeader(titre: 'Nouveau signalement'),

          // ----- Partie qui défile : catégories + champs -----
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'Catégorie',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  _grilleCategories(),
                  // Message d'erreur (texte vide s'il n'y a pas d'erreur)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _erreurCategorie ? 'Choisis une catégorie' : '',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Description',
                    hint: 'Décris ce qui se passe...',
                    controller: _descriptionController,
                    lignes: 3,
                    validator: _validerObligatoire,
                  ),
                  const SizedBox(height: 16),
                  _boutonPhoto(),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Localisation',
                    hint: 'Bloc B, 2e étage',
                    controller: _localisationController,
                    validator: _validerObligatoire,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _utiliserMaPosition,
                      child: const Text(
                        'Utiliser ma position',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ----- Partie fixe en bas : bouton de publication -----
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  texte: 'Publier le signalement',
                  onPressed: _publier,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tous les membres de la houma seront notifiés.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La grille des 5 catégories (3 par ligne).
  Widget _grilleCategories() {
    // On construit une tuile par catégorie avec une boucle
    final List<Widget> tuiles = [];
    for (final categorie in _repository.getCategories()) {
      tuiles.add(_tuileCategorie(categorie));
    }

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.3,
      // La grille est dans une ListView : elle prend juste la place
      // nécessaire (shrinkWrap) et ne défile pas toute seule (physics).
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tuiles,
    );
  }

  /// Une tuile de catégorie : fond clair, bordure colorée si sélectionnée.
  Widget _tuileCategorie(CategorieSignalement categorie) {
    final bool choisie = _categorieChoisie == categorie.id;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      onTap: () {
        setState(() {
          _categorieChoisie = categorie.id;
          _erreurCategorie = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: categorie.couleurClaire,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: choisie ? categorie.couleur : categorie.couleurClaire,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pastille de la couleur de la catégorie
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: categorie.couleur,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              categorie.nom,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Zone "+ Ajouter une photo" en pointillés (bouton visuel pour l'instant).
  Widget _boutonPhoto() {
    return CustomPaint(
      painter: _BordurePointillee(),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () {
            // Choix d'une photo : à venir
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
          child: const Text(
            '+ Ajouter une photo',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Dessine une bordure arrondie en pointillés (zone d'ajout de photo).
class _BordurePointillee extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint pinceau = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Le contour complet du rectangle arrondi
    final Path contour = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppTheme.radiusSmall),
        ),
      );

    // On ne dessine qu'un morceau sur deux : 6 px de trait, 4 px de vide
    const double trait = 6;
    const double vide = 4;
    for (final morceau in contour.computeMetrics()) {
      double position = 0;
      while (position < morceau.length) {
        canvas.drawPath(
          morceau.extractPath(position, position + trait),
          pinceau,
        );
        position += trait + vide;
      }
    }
  }

  @override
  bool shouldRepaint(_BordurePointillee ancien) {
    return false;
  }
}
