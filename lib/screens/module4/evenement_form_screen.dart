import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/evenement.dart';
import '../../data/models/quartier.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/photos_m4.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'carte_evenement.dart';
import 'module4_widgets.dart';

/// M4 - Formulaire d'un événement : création, ou modification si
/// [evenement] est donné. Renvoie `true` (Navigator.pop) une fois enregistré.
class EvenementFormScreen extends StatefulWidget {
  final Evenement? evenement; // null = nouvel événement
  // Pré-remplissage d'un nouvel événement (ex : la date gagnante d'un sondage)
  final String? titreInitial;
  final DateTime? dateInitiale;

  const EvenementFormScreen({
    super.key,
    this.evenement,
    this.titreInitial,
    this.dateInitiale,
  });

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
  PointGps? _position; // le lieu sur la carte (optionnel)
  String? _photoUrl; // la photo (Cloudinary), optionnelle
  bool _envoiPhoto = false; // photo en cours d'envoi
  bool _enChargement = false;
  String? _message; // erreur affichée au-dessus du bouton

  bool get _estModification => widget.evenement != null;

  @override
  void initState() {
    super.initState();
    // Nouvel événement pré-rempli (sondage de date)
    final DateTime? dateInitiale = widget.dateInitiale;
    if (widget.evenement == null && dateInitiale != null) {
      _titre.text = widget.titreInitial ?? '';
      _jour = DateTime(dateInitiale.year, dateInitiale.month, dateInitiale.day);
      _heureDebut = TimeOfDay.fromDateTime(dateInitiale);
    }
    // Modification : on pré-remplit avec l'événement existant
    final Evenement? existant = widget.evenement;
    if (existant != null) {
      _titre.text = existant.titre;
      _description.text = existant.description;
      _lieu.text = existant.lieu;
      _position = existant.position;
      _photoUrl = existant.photoUrl;
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
  /// L'heure au format français (18:00), pas 6:00 PM.
  String _texteHeure(TimeOfDay heure) {
    return texteHeure(DateTime(2000, 1, 1, heure.hour, heure.minute));
  }

  DateTime _combiner(DateTime jour, TimeOfDay heure) {
    return DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);
  }

  Future<void> _choisirJour() async {
    // Sans ça, le clavier se rouvre sur le dernier champ quand la fenêtre se ferme
    FocusManager.instance.primaryFocus?.unfocus();
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
    FocusManager.instance.primaryFocus?.unfocus();
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
        position: _position,
        photoUrl: _photoUrl,
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
          position: _position,
          sansPosition: _position == null,
          photoUrl: _photoUrl,
          sansPhoto: _photoUrl == null,
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
                              : 'Début ${_texteHeure(_heureDebut!)}',
                          () => _choisirHeure(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _boutonChoix(
                          Icons.schedule_outlined,
                          _heureFin == null
                              ? 'Fin (optionnel)'
                              : 'Fin ${_texteHeure(_heureFin!)}',
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
                  // M4 : le lieu exact sur la carte (optionnel)
                  _choixCarte(),
                  const SizedBox(height: 12),
                  _choixPhoto(),
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

  /// Choisit une photo (galerie ou appareil photo) puis l'envoie tout de
  /// suite à Cloudinary : on garde seulement son adresse.
  Future<void> _ajouterPhoto() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: AppColors.primary),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) {
      return;
    }
    // Photo réduite avant l'envoi : plus rapide, et moins de données mobiles
    final XFile? image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (image == null || !mounted) {
      return;
    }
    setState(() {
      _envoiPhoto = true;
    });
    final Resultat<String> resultat =
        await PhotosM4.envoyer(await image.readAsBytes(), image.name);
    if (!mounted) {
      return;
    }
    setState(() {
      _envoiPhoto = false;
      if (resultat.estSucces) {
        _photoUrl = resultat.donnee;
      } else {
        _message = resultat.erreur;
      }
    });
  }

  /// La photo de l'événement : aperçu, ou bouton « Ajouter une photo ».
  Widget _choixPhoto() {
    final String? photo = _photoUrl;
    if (_envoiPhoto) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Envoi de la photo...'),
          ],
        ),
      );
    }
    if (photo == null) {
      return OutlinedButton.icon(
        onPressed: _ajouterPhoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Ajouter une photo (optionnel)'),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Image.network(
            PhotosM4.miniature(photo),
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: 6,
          top: 6,
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Changer la photo',
                onPressed: _ajouterPhoto,
                icon: const Icon(Icons.edit),
              ),
              IconButton.filledTonal(
                tooltip: 'Retirer la photo',
                onPressed: () {
                  setState(() {
                    _photoUrl = null;
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Le bouton « Placer sur la carte » (ou le lieu déjà choisi).
  Widget _choixCarte() {
    final PointGps? position = _position;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final PointGps? choisi = await ouvrirEcranM4<PointGps>(
                context,
                ChoisirLieuScreen(initial: _position),
              );
              if (choisi != null && mounted) {
                setState(() {
                  _position = choisi;
                });
              }
            },
            icon: Icon(position == null ? Icons.add_location_alt_outlined : Icons.location_on),
            label: Text(position == null
                ? 'Placer sur la carte (optionnel)'
                : 'Lieu placé sur la carte ✓'),
          ),
        ),
        if (position != null)
          IconButton(
            tooltip: 'Retirer le lieu',
            icon: Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: () {
              setState(() {
                _position = null;
              });
            },
          ),
      ],
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
