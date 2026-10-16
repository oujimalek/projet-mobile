import 'package:flutter/material.dart';

import '../../data/models/service.dart';
import '../../data/resultat.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'module2_widgets.dart';

/// M2 - Nouvelle publication (écran 03) ou modification d'un service.
///
/// Un formulaire pour proposer ou demander un service. Quand on publie,
/// l'écran se ferme et renvoie le Service créé à la liste.
///
/// Avec [service], le formulaire est pré-rempli et enregistre les
/// modifications. Pour un service commun, le jour et les heures ne changent pas.
class ServiceFormScreen extends StatefulWidget {
  final Service? service; // null = nouvelle publication

  const ServiceFormScreen({super.key, this.service});

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
  bool _commun = false; // true = service commun hebdomadaire
  String? _jour; // jour du service commun
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin;
  String? _erreurCommun; // message sous la zone du service commun
  bool _enCours = false; // true pendant l'enregistrement

  bool get _modification => widget.service != null;

  @override
  void initState() {
    super.initState();
    final Service? service = widget.service;
    if (service != null) {
      _titreController.text = service.titre;
      _descriptionController.text = service.description;
      _disponibiliteController.text = service.disponibilite ?? '';
      _jePropose = service.estOffre;
      _categorie = service.categorie;
      _commun = service.estCommun;
    }
  }

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

  /// "18:05" pour une heure choisie.
  String _texteHeure(TimeOfDay heure) {
    final String h = heure.hour.toString().padLeft(2, '0');
    final String m = heure.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _choisirHeure(bool debut) async {
    final TimeOfDay? choisie = await showTimePicker(
      context: context,
      initialTime: (debut ? _heureDebut : _heureFin) ??
          const TimeOfDay(hour: 18, minute: 0),
    );
    if (choisie == null || !mounted) {
      return;
    }
    setState(() {
      if (debut) {
        _heureDebut = choisie;
      } else {
        _heureFin = choisie;
      }
      _erreurCommun = null;
    });
  }

  /// Appelé quand on touche "Publier" (ou "Enregistrer").
  Future<void> _publier() async {
    // On vérifie les champs du Form, puis la catégorie et le service commun
    final bool champsValides = _formKey.currentState!.validate();
    final String? refusCommun = (_commun && !_modification)
        ? ServiceRepository.refusPublication(
            titre: 'xxx',
            description: 'xxxxxxxxxx',
            categorie: _categorie ?? 'Bricolage',
            estCommun: true,
            jour: _jour,
            heureDebut: _heureDebut == null ? null : _texteHeure(_heureDebut!),
            heureFin: _heureFin == null ? null : _texteHeure(_heureFin!),
          )
        : null;
    setState(() {
      _erreurCategorie = _categorie == null;
      _erreurCommun = refusCommun;
    });
    if (!champsValides || _categorie == null || refusCommun != null) {
      return;
    }

    setState(() {
      _enCours = true;
    });
    final String disponibilite = _disponibiliteController.text.trim();
    final Resultat<Service> resultat;
    if (_modification) {
      final Resultat<void> modif = await _repository.modifierService(
        widget.service!.id,
        titre: _titreController.text.trim(),
        description: _descriptionController.text.trim(),
        categorie: _categorie!,
        estOffre: _jePropose,
        disponibilite: disponibilite,
      );
      resultat = modif.estSucces
          ? Resultat.succes(widget.service!.copyWith(
              titre: _titreController.text.trim(),
              description: _descriptionController.text.trim(),
              categorie: _categorie,
              estOffre: _jePropose,
              disponibilite: disponibilite,
            ))
          : Resultat.echec(modif.erreur!);
    } else {
      resultat = await _repository.ajouterService(
        titre: _titreController.text.trim(),
        description: _descriptionController.text.trim(),
        categorie: _categorie!,
        estOffre: _jePropose,
        disponibilite: disponibilite.isEmpty ? null : disponibilite,
        estCommun: _commun,
        jour: _jour,
        heureDebut: _heureDebut == null ? null : _texteHeure(_heureDebut!),
        heureFin: _heureFin == null ? null : _texteHeure(_heureFin!),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    if (!resultat.estSucces) {
      afficherMessage(context, resultat.erreur!);
      return;
    }
    afficherMessage(
      context,
      _modification ? 'Service modifié' : 'Service publié',
    );
    // On ferme l'écran et on renvoie le service à la liste
    Navigator.of(context).pop(resultat.donnee);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: _modification ? 'Modifier le service' : 'Nouvelle publication',
          ),
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
                            if (!estPremier && !_modification) {
                              _commun = false; // un service commun est une offre
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      const _Etiquette('Catégorie'),
                      _pastillesCategories(),
                      if (_erreurCategorie)
                        Padding(
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
                      if (_jePropose || _modification) ...[
                        const SizedBox(height: 20),
                        _zoneServiceCommun(),
                      ],
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
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: PrimaryButton(
                texte: _modification ? 'Enregistrer' : 'Publier',
                // null = bouton désactivé pendant l'enregistrement
                onPressed: _enCours ? null : _publier,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Service commun" : un service hebdomadaire (jour, heure de début, heure
  /// de fin). Les créneaux des 4 prochaines semaines sont créés à la publication.
  /// En modification, le jour et les heures sont affichés mais ne changent pas.
  Widget _zoneServiceCommun() {
    if (_modification) {
      final Service service = widget.service!;
      if (!service.estCommun) {
        return const SizedBox.shrink();
      }
      return Text(
        'Service commun : chaque ${service.jour}, '
        '${service.heureDebut ?? '?'} – ${service.heureFin ?? '?'} '
        '(le jour et les heures ne sont pas modifiables)',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Service commun hebdomadaire',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Les créneaux des 4 prochaines semaines sont créés',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          value: _commun,
          activeTrackColor: AppColors.secondary,
          activeThumbColor: AppColors.card,
          onChanged: (valeur) {
            setState(() {
              _commun = valeur;
              _erreurCommun = null;
            });
          },
        ),
        if (_commun) ...[
          const _Etiquette('Jour'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String jour in ServiceRepository.jours)
                PastilleChoix(
                  texte: jour,
                  actif: _jour == jour,
                  onTap: () {
                    setState(() {
                      _jour = jour;
                      _erreurCommun = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _choisirHeure(true),
                  child: Text(
                    _heureDebut == null
                        ? 'Heure de début'
                        : 'Début ${_texteHeure(_heureDebut!)}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _choisirHeure(false),
                  child: Text(
                    _heureFin == null
                        ? 'Heure de fin'
                        : 'Fin ${_texteHeure(_heureFin!)}',
                  ),
                ),
              ),
            ],
          ),
          if (_erreurCommun != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _erreurCommun!,
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
        ],
      ],
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
