import 'package:flutter/material.dart';

import '../../data/models/service.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'module2_widgets.dart';

/// M2 - Nouvelle publication (écran 03).
///
/// Un formulaire pour proposer ou demander un service. Quand on publie,
/// l'écran se ferme et renvoie le Service créé à la liste.
class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({super.key});

  @override
  State<ServiceFormScreen> createState() {
    return _ServiceFormScreenState();
  }
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final ServiceRepository _repository = ServiceRepository();

  // Clé du formulaire : permet d'appeler validate() sur tous les champs
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Contrôleurs : permettent de lire le texte saisi
  final TextEditingController _titreController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _disponibiliteController =
      TextEditingController();

  // État de l'écran
  bool _jePropose = true; // true = "Je propose", false = "Je demande"
  String? _categorie; // null = aucune catégorie choisie
  bool _erreurCategorie = false; // true = afficher "Choisis une catégorie"

  @override
  void dispose() {
    // On libère les contrôleurs quand l'écran est fermé
    _titreController.dispose();
    _descriptionController.dispose();
    _disponibiliteController.dispose();
    super.dispose();
  }

  /// Les catégories du repository, sans le filtre "Tous".
  List<String> _categories() {
    final List<String> resultat = [];
    for (final categorie in _repository.getCategories()) {
      if (categorie != 'Tous') {
        resultat.add(categorie);
      }
    }
    return resultat;
  }

  /// Titre : au moins 3 caractères.
  String? _validerTitre(String? valeur) {
    if (valeur == null || valeur.trim().length < 3) {
      return 'Le titre doit avoir au moins 3 caractères';
    }
    return null;
  }

  /// Description : au moins 10 caractères.
  String? _validerDescription(String? valeur) {
    if (valeur == null || valeur.trim().length < 10) {
      return 'La description doit avoir au moins 10 caractères';
    }
    return null;
  }

  /// Appelé quand on touche "Publier".
  void _publier() {
    // On vérifie les champs du Form, puis la catégorie
    final bool champsValides = _formKey.currentState!.validate();
    setState(() {
      _erreurCategorie = _categorie == null;
    });
    if (!champsValides || _categorie == null) {
      return;
    }

    final String disponibilite = _disponibiliteController.text.trim();
    final Service service = _repository.ajouterService(
      titre: _titreController.text.trim(),
      description: _descriptionController.text.trim(),
      categorie: _categorie!,
      estOffre: _jePropose,
      disponibilite: disponibilite.isEmpty ? null : disponibilite,
    );

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Service publié')));
    // On ferme l'écran et on renvoie le service à la liste
    Navigator.of(context).pop(service);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Nouvelle publication'),
          Expanded(
            // Le Form est DANS le ListView (comme sur l'écran de connexion) :
            // ainsi les messages d'erreur des champs restent affichés
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Etiquette('Type de publication'),
                      DeuxOnglets(
                        premier: 'Je propose',
                        second: 'Je demande',
                        premierActif: _jePropose,
                        onChoix: (estPremier) {
                          setState(() {
                            _jePropose = estPremier;
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      const _Etiquette('Catégorie'),
                      _pastillesCategories(),
                      if (_erreurCategorie)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Choisis une catégorie',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      AppTextField(
                        label: 'Titre',
                        hint: _jePropose
                            ? 'Ex : Perceuse à prêter'
                            : 'Ex : Cherche une échelle',
                        controller: _titreController,
                        validator: _validerTitre,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Description',
                        hint: 'Explique en quelques mots',
                        lignes: 4,
                        controller: _descriptionController,
                        validator: _validerDescription,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Disponibilité (optionnel)',
                        hint: 'Ex : Ce week-end',
                        controller: _disponibiliteController,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ----- Partie fixe en bas : bouton de publication -----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: PrimaryButton(texte: 'Publier', onPressed: _publier),
            ),
          ),
        ],
      ),
    );
  }

  /// Les catégories en pastilles (dorées quand elles sont choisies).
  Widget _pastillesCategories() {
    final List<Widget> pastilles = [];
    for (final categorie in _categories()) {
      pastilles.add(
        PastilleChoix(
          texte: categorie,
          actif: _categorie == categorie,
          onTap: () {
            setState(() {
              _categorie = categorie;
              _erreurCategorie = false;
            });
          },
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: pastilles);
  }
}

/// Petit libellé au-dessus d'une zone du formulaire.
class _Etiquette extends StatelessWidget {
  final String texte;

  const _Etiquette(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
