import 'package:flutter/material.dart';

import '../../data/models/signalement.dart';
import '../../data/resultat.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';

/// M3 - Signalements : création OU modification d'un signalement.
///
/// L'utilisateur choisit une catégorie dans une GridView, donne un titre,
/// décrit le problème, coche "Danger pour les personnes" si besoin, peut
/// ajouter une photo (bouton visuel pour l'instant) et indique le lieu.
///
/// - `CreateSignalementScreen()` : nouveau signalement ;
/// - `CreateSignalementScreen(signalement: s)` : l'auteur modifie [s]
///   (seulement tant qu'il est en attente).
///
/// En cas de succès, l'écran se ferme avec `Navigator.pop(context, true)`.
class CreateSignalementScreen extends StatefulWidget {
  final Signalement? signalement; // null = création, sinon modification

  const CreateSignalementScreen({super.key, this.signalement});

  @override
  State<CreateSignalementScreen> createState() {
    return _CreateSignalementScreenState();
  }
}

class _CreateSignalementScreenState extends State<CreateSignalementScreen> {
  // Formulaire et contrôleurs des champs
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _localisationController = TextEditingController();

  // État de l'écran
  String? _categorieChoisie; // id de la catégorie, null = rien de choisi
  bool _erreurCategorie = false; // true = afficher "Choisis une catégorie"
  bool _danger = false; // case "Danger pour les personnes"
  bool _enChargement = false; // true pendant l'envoi

  /// true = on modifie un signalement existant.
  bool get _modeModification => widget.signalement != null;

  @override
  void initState() {
    super.initState();
    // Modification : on pré-remplit le formulaire
    final Signalement? existant = widget.signalement;
    if (existant != null) {
      _titreController.text = existant.titre;
      _descriptionController.text = existant.description;
      _localisationController.text = existant.lieu;
      _categorieChoisie = existant.categorieId;
      _danger = existant.danger;
    }
  }

  @override
  void dispose() {
    _titreController.dispose();
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

  /// Appelé quand on touche "Publier" (ou "Enregistrer").
  Future<void> _publier() async {
    // On vérifie les champs du Form, et qu'une catégorie a été choisie
    final bool champsValides = _formKey.currentState!.validate();
    setState(() {
      _erreurCategorie = _categorieChoisie == null;
    });
    final String? categorieId = _categorieChoisie;
    if (!champsValides || categorieId == null) {
      return;
    }

    // Le signalement tel que saisi. L'auteur, le statut, la date et le
    // compteur sont remplis par le repository (création) ou gardés
    // (modification).
    final Signalement? existant = widget.signalement;
    final Signalement saisi = Signalement(
      id: existant?.id ?? '',
      titre: _titreController.text,
      description: _descriptionController.text,
      categorieId: categorieId,
      statut: existant?.statut ?? StatutSignalement.enAttente,
      date: existant?.date ?? DateTime.now(),
      lieu: _localisationController.text,
      auteurId: existant?.auteurId ?? '',
      auteurNom: existant?.auteurNom ?? '',
      nbConfirmations: existant?.nbConfirmations ?? 0,
      danger: _danger,
    );

    setState(() {
      _enChargement = true;
    });
    final Resultat<void> resultat = _modeModification
        ? await SignalementRepository().modifierSignalement(saisi)
        : await SignalementRepository().ajouterSignalement(saisi);
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });

    if (!resultat.estSucces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultat.erreur!)),
      );
      return;
    }

    // Succès : on revient à l'écran précédent avec "true"
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }
    // Pas d'écran précédent (ouvert comme onglet) : on vide le formulaire
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Yaatik saha ! Signalement publié.',
            'Yaatik saha ! Tablighek tbaath.')),
      ),
    );
    _formKey.currentState!.reset();
    _titreController.clear();
    _descriptionController.clear();
    _localisationController.clear();
    setState(() {
      _categorieChoisie = null;
      _danger = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // En-tête blanc arrondi, comme sur la maquette
          AppHeader(
            titre: _modeModification
                ? tr('Modifier le signalement', 'Badel it-tabligh')
                : tr('Nouveau signalement', 'Tabligh jdid'),
          ),

          // ----- Partie qui défile : catégories + champs -----
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    tr('Catégorie', 'Naw3'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _grilleCategories(),
                  // Message d'erreur (texte vide s'il n'y a pas d'erreur)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _erreurCategorie ? 'Choisis une catégorie' : '',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: tr('Titre', 'El 3onwen'),
                    hint: tr('Ex : Lampadaire en panne', 'Ex : Dhaw tafi'),
                    controller: _titreController,
                    validator: SignalementRepository.refusTitre,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: tr('Description', 'Chnoua sar'),
                    hint: tr('Décris ce qui se passe...', 'Ekteb chnoua sar...'),
                    controller: _descriptionController,
                    lignes: 3,
                    validator: SignalementRepository.refusDescription,
                  ),
                  const SizedBox(height: 12),
                  _caseDanger(),
                  const SizedBox(height: 16),
                  _boutonPhoto(),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: tr('Localisation', 'Win'),
                    hint: 'Bloc B, 2e étage',
                    controller: _localisationController,
                    validator: SignalementRepository.refusLieu,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _utiliserMaPosition,
                      child: Text(
                        tr('Utiliser ma position', 'Esta3mel blasti'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                PrimaryButton(
                  texte: _texteBouton(),
                  onPressed: _enChargement ? null : _publier,
                ),
                const SizedBox(height: 10),
                Text(
                  tr('Tous les membres de la houma seront notifiés.',
                      'Ga3 jiran el houma bech ya3rfou.'),
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

  /// Le texte du bouton du bas selon le mode et le chargement.
  String _texteBouton() {
    if (_enChargement) {
      return tr('Envoi...', 'Yab3ath...');
    }
    if (_modeModification) {
      return tr('Enregistrer', 'Sajjel');
    }
    return tr('Publier le signalement', 'Ab3ath it-tabligh');
  }

  /// La case "Danger pour les personnes" (compte dans l'urgence).
  Widget _caseDanger() {
    // Material (et pas Container) : la ListTile dessine son effet de clic
    // sur le Material le plus proche
    return Material(
      color: _danger ? AppColors.incidentLight : AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        side: BorderSide(
          color: _danger ? AppColors.incident : AppColors.border,
        ),
      ),
      child: CheckboxListTile(
        value: _danger,
        onChanged: (valeur) {
          setState(() {
            _danger = valeur ?? false;
          });
        },
        activeColor: AppColors.incident,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          tr('Danger pour les personnes', 'Fama khatar 3al nes'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          tr('Fils électriques, trou, risque de chute...',
              'Khyout dhaw, 7ofra, tnajjem tetzala9...'),
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  /// La grille des 5 catégories (3 par ligne).
  Widget _grilleCategories() {
    // On construit une tuile par catégorie avec une boucle
    final List<Widget> tuiles = [];
    for (final categorie in SignalementRepository.categories) {
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
            // Choix d'une photo : à venir (étape photo du module 3)
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
          child: Text(
            tr('+ Ajouter une photo', '+ Zid taswira'),
            style: const TextStyle(fontWeight: FontWeight.w600),
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
