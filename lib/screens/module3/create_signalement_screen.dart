import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../data/models/quartier.dart' show PointGps;
import '../../data/models/signalement.dart';
import '../../data/resultat.dart';
import '../../data/services/adresse_m3.dart';
import '../../data/services/base_locale_m3.dart';
import '../../data/services/localisation.dart'; // M1 (import seulement)
import '../../data/services/photos_m3.dart';
import '../../data/services/signalement_repository.dart';
import '../../data/services/sync_signalements_m3.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module3.dart';

/// M3 - Signalements : création OU modification d'un signalement.
///
/// L'utilisateur choisit une catégorie dans une GridView, donne un titre,
/// décrit le problème, coche "Danger pour les personnes" si besoin, peut
/// ajoute une photo (appareil photo ou galerie, envoyée sur Cloudinary) et
/// indique le lieu (texte, ou "Utiliser ma position" : GPS + adresse).
///
/// - `CreateSignalementScreen()` : nouveau signalement ;
/// - `CreateSignalementScreen(signalement: s)` : l'auteur modifie [s]
///   (seulement tant qu'il est en attente).
///
/// En cas de succès, l'écran se ferme avec :
///   - création : `Navigator.pop(context, etat)` (EtatPublicationM3 : envoyé,
///     ou gardé dans SQLite faute de réseau) ;
///   - modification : `Navigator.pop(context, true)`.
///
/// Création : le formulaire est enregistré tout seul comme brouillon
/// (SQLite) ; à la prochaine ouverture, on propose de le reprendre.
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
  bool _localisationEnCours = false; // GPS + adresse en cours
  PointGps? _position; // point GPS ("Utiliser ma position"), optionnel

  // Photo : un fichier choisi sur le téléphone (pas encore envoyé), ou la
  // photo déjà en ligne d'un signalement modifié
  String? _photoLocale; // copie dans le dossier de l'application
  String? _photoUrlExistante; // modification : null après "Retirer"
  bool _photoEnCours = false; // appareil photo / galerie ouverts

  // Brouillon (création seulement)
  final SyncSignalementsM3 _sync = SyncSignalementsM3.instance;
  Brouillon? _brouillonTrouve; // proposé avec "Reprendre le brouillon"
  Timer? _minuteurBrouillon; // enregistre 1 s après la dernière frappe
  bool _termine = false; // publié : plus de brouillon à garder

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
      _position = existant.position;
      _photoUrlExistante = existant.photoUrl;
      return;
    }
    // Création : brouillon automatique à chaque frappe
    _titreController.addListener(_formulaireModifie);
    _descriptionController.addListener(_formulaireModifie);
    _localisationController.addListener(_formulaireModifie);
    _chercherBrouillon();
  }

  @override
  void dispose() {
    _minuteurBrouillon?.cancel();
    // On quitte sans publier : le brouillon est gardé (lu AVANT dispose)
    if (!_modeModification && !_termine) {
      _sync.enregistrerBrouillon(_brouillonActuel());
    }
    // Modification abandonnée : la nouvelle photo choisie ne sert plus
    // (pas de brouillon en modification)
    if (_modeModification) {
      PhotosM3.supprimerLocale(_photoLocale);
    }
    _titreController.dispose();
    _descriptionController.dispose();
    _localisationController.dispose();
    super.dispose();
  }

  // =====================================================================
  // Brouillon (table SQLite "brouillons")
  // =====================================================================

  /// Y a-t-il un brouillon d'une visite précédente ?
  Future<void> _chercherBrouillon() async {
    final Brouillon? brouillon = await _sync.lireBrouillon();
    if (!mounted || brouillon == null || brouillon.estVide) {
      return;
    }
    setState(() {
      _brouillonTrouve = brouillon;
    });
  }

  /// Le formulaire tel qu'il est maintenant.
  Brouillon _brouillonActuel() {
    return Brouillon(
      utilisateurId: UtilisateurRepository().getUtilisateurConnecte().id,
      titre: _titreController.text,
      description: _descriptionController.text,
      categorieId: _categorieChoisie,
      lieu: _localisationController.text,
      danger: _danger,
      position: _position,
      photoLocale: _photoLocale,
      dateModification: DateTime.now(),
    );
  }

  /// Un champ a changé : on enregistre 1 s après la dernière modification
  /// (pas à chaque lettre).
  void _formulaireModifie() {
    if (_modeModification || _termine) {
      return;
    }
    _minuteurBrouillon?.cancel();
    _minuteurBrouillon = Timer(const Duration(seconds: 1), () {
      _sync.enregistrerBrouillon(_brouillonActuel());
    });
  }

  /// "Reprendre" : on remet le brouillon dans le formulaire.
  void _reprendreBrouillon() {
    final Brouillon? brouillon = _brouillonTrouve;
    if (brouillon == null) {
      return;
    }
    _titreController.text = brouillon.titre;
    _descriptionController.text = brouillon.description;
    _localisationController.text = brouillon.lieu;
    setState(() {
      _categorieChoisie = brouillon.categorieId;
      _danger = brouillon.danger;
      _position = brouillon.position;
      // La photo du brouillon, si elle est toujours sur le téléphone
      final String? photo = brouillon.photoLocale;
      _photoLocale = photo != null && File(photo).existsSync() ? photo : null;
      _brouillonTrouve = null;
    });
  }

  /// "Supprimer" le brouillon proposé.
  Future<void> _jeterBrouillon() async {
    setState(() {
      _brouillonTrouve = null;
    });
    await _sync.supprimerBrouillon(avecPhoto: true); // sa photo aussi
  }

  // =====================================================================
  // Photo (PhotosM3 : image_picker + Cloudinary)
  // =====================================================================

  /// "Prendre une photo" ou "Choisir dans la galerie".
  Future<void> _choisirSource() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(tr('Prendre une photo', 'Sawwer')),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(tr('Choisir dans la galerie', 'Ikhtar mel galerie')),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source != null) {
      await _choisirPhoto(source);
    }
  }

  /// Ouvre l'appareil photo / la galerie, puis garde une copie de la photo
  /// dans le dossier de l'application (elle peut attendre l'envoi).
  Future<void> _choisirPhoto(ImageSource source) async {
    setState(() {
      _photoEnCours = true;
    });
    final Resultat<String?> choix = await PhotosM3.choisir(source);
    String? erreur = choix.erreur;
    String? copie;
    final String? chemin = choix.donnee;
    if (choix.estSucces && chemin != null) {
      final Resultat<String> gardee = await PhotosM3.garderSurTelephone(chemin);
      erreur = gardee.erreur;
      copie = gardee.donnee;
    }
    if (!mounted) {
      await PhotosM3.supprimerLocale(copie);
      return;
    }
    final String? ancienne = _photoLocale;
    setState(() {
      _photoEnCours = false;
      if (copie != null) {
        _photoLocale = copie;
      }
    });
    if (erreur != null) {
      afficherMessageM3(context, erreur);
      return;
    }
    if (copie != null) {
      await PhotosM3.supprimerLocale(ancienne); // remplacée
      _formulaireModifie();
    }
  }

  /// "Retirer" : plus de photo (la copie locale est supprimée).
  Future<void> _retirerPhoto() async {
    final String? ancienne = _photoLocale;
    setState(() {
      _photoLocale = null;
      _photoUrlExistante = null;
    });
    await PhotosM3.supprimerLocale(ancienne);
    _formulaireModifie();
  }

  /// "Utiliser ma position" :
  ///   1. le GPS du téléphone (Localisation du module 1, ses messages d'erreur) ;
  ///   2. l'adresse de ce point (AdresseM3 : cache SQLite, puis Nominatim).
  /// Le point est gardé même si l'adresse n'est pas trouvée (hors ligne) :
  /// l'utilisateur écrit alors le lieu lui-même.
  Future<void> _utiliserMaPosition() async {
    setState(() {
      _localisationEnCours = true;
    });
    final Resultat<PointGps> gps = await Localisation.positionActuelle();
    if (!mounted) {
      return;
    }
    if (!gps.estSucces) {
      setState(() {
        _localisationEnCours = false;
      });
      afficherMessageM3(context, gps.erreur!); // message du module 1
      return;
    }
    final PointGps point = gps.donnee!;
    setState(() {
      _position = point;
    });
    _formulaireModifie(); // le brouillon garde aussi le point

    final Resultat<String> adresse = await AdresseM3.adresseDe(point);
    if (!mounted) {
      return;
    }
    setState(() {
      _localisationEnCours = false;
    });
    if (adresse.estSucces) {
      _localisationController.text = adresse.donnee!;
    } else {
      afficherMessageM3(context, adresse.erreur!);
    }
  }

  /// La croix : on retire le point GPS (le texte du lieu reste).
  void _retirerPosition() {
    setState(() {
      _position = null;
    });
    _formulaireModifie();
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
      position: _position,
      // Modification : la photo en ligne gardée (null si "Retirer") ;
      // une nouvelle photo locale est envoyée au moment d'enregistrer
      photoUrl: _photoUrlExistante,
    );

    setState(() {
      _enChargement = true;
    });
    if (_modeModification) {
      await _enregistrerModification(saisi);
    } else {
      await _publierNouveau(saisi);
    }
  }

  /// Modification : seulement en ligne (Firestore n'enverrait pas tout de
  /// suite, et l'écran attendrait).
  Future<void> _enregistrerModification(Signalement saisi) async {
    Resultat<void> resultat;
    final String? nouvellePhoto = _photoLocale;
    if (!await _sync.estEnLigne()) {
      resultat = Resultat.echec(tr(
        'Pas de connexion Internet : la modification se fait en ligne',
        'Ma famech connexion : el ta3dil yetsna3 en ligne',
      ));
    } else if (nouvellePhoto != null) {
      // Nouvelle photo : d'abord sur Cloudinary, puis son adresse dans Firestore
      final Resultat<String> photo = await PhotosM3.envoyerFichier(nouvellePhoto);
      resultat = photo.estSucces
          ? await SignalementRepository()
              .modifierSignalement(saisi.copyWith(photoUrl: photo.donnee))
          : Resultat.echec(photo.erreur!);
    } else {
      resultat = await SignalementRepository().modifierSignalement(saisi);
    }
    if (resultat.estSucces) {
      _photoLocale = null; // envoyée : la copie locale ne sert plus
      await PhotosM3.supprimerLocale(nouvellePhoto);
    }
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      afficherMessageM3(context, resultat.erreur!);
      return;
    }
    Navigator.of(context).pop(true);
  }

  /// Création : SyncSignalementsM3 envoie à Firestore, ou garde dans la
  /// file SQLite s'il n'y a pas de réseau.
  Future<void> _publierNouveau(Signalement saisi) async {
    final Resultat<EtatPublicationM3> resultat =
        await _sync.publier(saisi, photoLocale: _photoLocale);
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      afficherMessageM3(context, resultat.erreur!);
      return;
    }

    // Publié (ou mis en file) : le brouillon ne sert plus
    _termine = true;
    _minuteurBrouillon?.cancel();
    await _sync.supprimerBrouillon();
    if (!mounted) {
      return;
    }
    final EtatPublicationM3 etat = resultat.donnee!;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(etat);
      return;
    }
    // Pas d'écran précédent (ouvert comme onglet) : on vide le formulaire
    afficherMessageM3(
      context,
      etat == EtatPublicationM3.envoye
          ? tr('Yaatik saha ! Signalement publié.',
              'Yaatik saha ! Tablighek tbaath.')
          : tr('Pas de connexion : ton signalement sera envoyé automatiquement.',
              'Ma famech connexion : tablighek yetb3ath wa7dou ba3d.'),
    );
    _termine = false;
    _formKey.currentState!.reset();
    _titreController.clear();
    _descriptionController.clear();
    _localisationController.clear();
    setState(() {
      _categorieChoisie = null;
      _danger = false;
      _position = null;
      _photoLocale = null; // envoyée, ou gardée par la file d'envoi
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
                  if (_brouillonTrouve != null) _carteBrouillon(),
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
                    child: TextButton.icon(
                      onPressed:
                          _localisationEnCours ? null : _utiliserMaPosition,
                      // Petit indicateur de chargement à la place de l'icône
                      icon: _localisationEnCours
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 18),
                      label: Text(
                        _localisationEnCours
                            ? tr('Localisation...', 'Nlawej...')
                            : tr('Utiliser ma position', 'Esta3mel blasti'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_position != null) _lignePosition(),
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

  /// "Position GPS enregistrée (36.86250, 10.17000)" + croix pour la retirer.
  Widget _lignePosition() {
    final PointGps point = _position!;
    return Row(
      children: [
        Icon(Icons.location_on, size: 18, color: AppColors.success),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${tr('Position GPS enregistrée', 'Blasa GPS msajla')} '
            '(${texteCoordonnees(point)})',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        IconButton(
          tooltip: tr('Retirer la position', 'Na77i el blasa'),
          onPressed: _retirerPosition,
          icon: Icon(Icons.close, size: 18, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// L'aperçu : la photo choisie (fichier) ou celle déjà en ligne
  /// (miniature Cloudinary), avec "Changer" et "Retirer".
  Widget _apercuPhoto(String? locale, String? enLigne) {
    final Widget image = locale != null
        ? Image.file(
            File(locale),
            key: const ValueKey('photo_apercu'),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, erreur, trace) => _photoIndisponible(),
          )
        : Image.network(
            PhotosM3.miniature(enLigne!, largeur: 800, hauteur: 450),
            key: const ValueKey('photo_apercu'),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, erreur, trace) => _photoIndisponible(),
          );
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: image,
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _choisirSource,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(tr('Changer', 'Badel')),
            ),
            TextButton.icon(
              onPressed: _retirerPhoto,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(tr('Retirer la photo', 'Na77i it-taswira')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _photoIndisponible() {
    return Container(
      height: 180,
      color: AppColors.backgroundSecondary,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
    );
  }

  /// "Tu as un brouillon" : Reprendre / Supprimer.
  Widget _carteBrouillon() {
    final Brouillon brouillon = _brouillonTrouve!;
    final String titre = brouillon.titre.trim().isEmpty
        ? tr('Sans titre', 'Bla 3onwen')
        : brouillon.titre.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Tu as un brouillon', 'Andek brouillon'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '« $titre » · ${depuisQuandM3(brouillon.dateModification)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          // Wrap : les boutons passent à la ligne sur un petit écran
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _jeterBrouillon,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: Text(tr('Supprimer', 'Fasakh')),
              ),
              TextButton(
                onPressed: _reprendreBrouillon,
                child: Text(tr('Reprendre le brouillon', 'Kammel el brouillon')),
              ),
            ],
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
          _formulaireModifie();
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
        _formulaireModifie();
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

  /// La zone photo : chargement, aperçu (Changer / Retirer), ou le bouton
  /// "+ Ajouter une photo" en pointillés.
  Widget _boutonPhoto() {
    if (_photoEnCours) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: const CircularProgressIndicator(),
      );
    }
    final String? locale = _photoLocale;
    final String? enLigne = _photoUrlExistante;
    if (locale != null || enLigne != null) {
      return _apercuPhoto(locale, enLigne);
    }
    return CustomPaint(
      painter: _BordurePointillee(),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _choisirSource,
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
