import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'module4_widgets.dart';

/// M4 - Formulaire d'un événement : création, ou modification si
/// [evenement] est donné. Renvoie `true` (Navigator.pop) une fois enregistré.
class EvenementFormScreen extends StatefulWidget {
  final Evenement? evenement; // null = nouvel événement

  const EvenementFormScreen({super.key, this.evenement});

  @override
  State<EvenementFormScreen> createState() {
    return _EvenementFormScreenState();
  }
}

class _EvenementFormScreenState extends State<EvenementFormScreen> {
  final EvenementRepository _depot = EvenementRepository();
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final TextEditingController _titre = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _lieu = TextEditingController();
  final TextEditingController _places = TextEditingController(); // vide = sans limite

  CategorieEvenement _categorie = CategorieEvenement.fete;
  DateTime? _jour; // la date choisie (sans l'heure)
  TimeOfDay? _heureDebut;
  TimeOfDay? _heureFin; // optionnelle
  bool _enChargement = false;
  String? _message; // erreur affichée au-dessus du bouton

  bool get _estModification => widget.evenement != null;

  @override
  void initState() {
    super.initState();
    // Modification : on pré-remplit avec l'événement existant
    final Evenement? existant = widget.evenement;
    if (existant != null) {
      _titre.text = existant.titre;
      _description.text = existant.description;
      _lieu.text = existant.lieu;
      if (existant.placesMax > 0) {
        _places.text = '${existant.placesMax}';
      }
      _categorie = existant.categorie;
      _jour = DateTime(existant.date.year, existant.date.month, existant.date.day);
      _heureDebut = TimeOfDay.fromDateTime(existant.date);
      final DateTime? fin = existant.dateFin;
      if (fin != null) {
        _heureFin = TimeOfDay.fromDateTime(fin);
      }
    }
  }

  @override
  void dispose() {
    _titre.dispose();
    _description.dispose();
    _lieu.dispose();
    _places.dispose();
    super.dispose();
  }

  /// Le jour + une heure → DateTime.
  DateTime _combiner(DateTime jour, TimeOfDay heure) {
    return DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);
  }

  Future<void> _choisirJour() async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choisi = await showDatePicker(
      context: context,
      initialDate: _jour ?? maintenant,
      firstDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      lastDate: maintenant.add(const Duration(days: 365)),
    );
    if (choisi != null) {
      setState(() {
        _jour = choisi;
      });
    }
  }

  Future<void> _choisirHeure(bool debut) async {
    final TimeOfDay? choisie = await showTimePicker(
      context: context,
      initialTime: (debut ? _heureDebut : _heureFin) ??
          const TimeOfDay(hour: 18, minute: 0),
    );
    if (choisie != null) {
      setState(() {
        if (debut) {
          _heureDebut = choisie;
        } else {
          _heureFin = choisie;
        }
      });
    }
  }

  Future<void> _enregistrer() async {
    // 1. Les champs texte (validateurs du Form)
    if (!_formulaire.currentState!.validate()) {
      return;
    }
    // 2. La date et l'heure (pas dans le Form)
    final DateTime? jour = _jour;
    final TimeOfDay? heureDebut = _heureDebut;
    if (jour == null || heureDebut == null) {
      setState(() {
        _message = 'Choisis la date et l\'heure de début';
      });
      return;
    }
    final DateTime debut = _combiner(jour, heureDebut);
    final TimeOfDay? heureFin = _heureFin;
    final DateTime? fin = heureFin == null ? null : _combiner(jour, heureFin);

    // Places : vide = sans limite (0)
    final int places = int.tryParse(_places.text.trim()) ?? 0;

    // 3. Les règles métier (les mêmes que le repository)
    final String? refus = EvenementRepository.refusEvenement(
          titre: _titre.text,
          description: _description.text,
          lieu: _lieu.text,
          date: debut,
          dateFin: fin,
        ) ??
        EvenementRepository.refusPlaces(places,
            inscrits: widget.evenement?.participants ?? 0);
    if (refus != null) {
      setState(() {
        _message = refus;
      });
      return;
    }

    setState(() {
      _enChargement = true;
      _message = null;
    });
    final Resultat<void> resultat;
    final Evenement? existant = widget.evenement;
    if (existant == null) {
      resultat = await _depot.creerEvenement(
        titre: _titre.text,
        description: _description.text,
        date: debut,
        dateFin: fin,
        lieu: _lieu.text,
        categorie: _categorie,
        placesMax: places,
      );
    } else {
      resultat = await _depot.modifierEvenement(
        existant.copyWith(
          titre: _titre.text,
          description: _description.text,
          date: debut,
          dateFin: fin,
          sansFin: fin == null,
          lieu: _lieu.text,
          categorie: _categorie,
          placesMax: places,
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      setState(() {
        _message = resultat.erreur;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: _estModification ? 'Modifier l\'événement' : 'Nouvel événement',
          ),
          Expanded(
            child: Form(
              key: _formulaire,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  AppTextField(
                    label: 'Titre',
                    hint: 'Ex : Fête des voisins',
                    controller: _titre,
                    validator: (valeur) {
                      if (valeur == null || valeur.trim().isEmpty) {
                        return 'Donne un titre à l\'événement';
                      }
                      if (valeur.trim().length > EvenementRepository.titreMax) {
                        return '${EvenementRepository.titreMax} caractères au maximum';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _titreChamp('Catégorie'),
                  _choixCategorie(),
                  const SizedBox(height: 16),
                  _titreChamp('Date et heure'),
                  _boutonChoix(
                    Icons.calendar_today_outlined,
                    _jour == null ? 'Choisir la date' : texteDate(_jour!),
                    _choisirJour,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _boutonChoix(
                          Icons.schedule,
                          _heureDebut == null
                              ? 'Début'
                              : 'Début ${_heureDebut!.format(context)}',
                          () => _choisirHeure(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _boutonChoix(
                          Icons.schedule_outlined,
                          _heureFin == null
                              ? 'Fin (optionnel)'
                              : 'Fin ${_heureFin!.format(context)}',
                          () => _choisirHeure(false),
                        ),
                      ),
                    ],
                  ),
                  if (_heureFin != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _heureFin = null;
                          });
                        },
                        child: const Text('Retirer l\'heure de fin'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Lieu',
                    hint: 'Ex : Jardin de la résidence',
                    icone: Icons.place_outlined,
                    controller: _lieu,
                    validator: (valeur) {
                      if (valeur == null || valeur.trim().isEmpty) {
                        return 'Indique le lieu';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Nombre de places (vide = sans limite)',
                    hint: 'Ex : 30',
                    icone: Icons.event_seat_outlined,
                    controller: _places,
                    clavier: TextInputType.number,
                    validator: (valeur) {
                      final String texte = (valeur ?? '').trim();
                      if (texte.isNotEmpty && int.tryParse(texte) == null) {
                        return 'Écris un nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Description (optionnelle)',
                    hint: 'Ce qu\'il faut savoir, ce qu\'il faut apporter...',
                    controller: _description,
                    lignes: 4,
                    validator: (valeur) {
                      if ((valeur ?? '').trim().length >
                          EvenementRepository.descriptionMax) {
                        return '${EvenementRepository.descriptionMax} caractères au maximum';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  PrimaryButton(
                    texte: _estModification ? 'Enregistrer' : 'Publier l\'événement',
                    onPressed: _enChargement ? null : _enregistrer,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titreChamp(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texte, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  /// Une puce par catégorie ; la choisie prend la couleur de sa catégorie.
  Widget _choixCategorie() {
    final List<Widget> puces = [];
    for (final CategorieEvenement categorie in CategorieEvenement.values) {
      final bool actif = _categorie == categorie;
      final Color couleur = couleurCategorie(categorie);
      puces.add(
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              _categorie = categorie;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: actif ? fondCategorie(categorie) : AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: actif ? couleur : AppColors.border,
                width: actif ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconeCategorie(categorie), size: 18, color: couleur),
                const SizedBox(width: 6),
                Text(
                  categorie.libelle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: actif ? couleur : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: puces);
  }

  /// Un bouton qui ouvre un sélecteur (date ou heure).
  Widget _boutonChoix(IconData icone, String texte, Function() onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icone, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(texte)),
          ],
        ),
      ),
    );
  }
}
