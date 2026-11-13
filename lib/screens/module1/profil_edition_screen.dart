import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/competences_communes.dart';
import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 7, modification du profil.
///
/// Avatar (galerie), nom, téléphone, bâtiment/appartement et compétences
/// (compétences courantes à cocher + "Autre" pour en préciser d'autres).
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

  // "Autre" coché : affiche le champ pour préciser une compétence hors liste
  bool _autreCoche = false;
  final TextEditingController _autreController = TextEditingController();

  // Avatar choisi dans la galerie ('' = initiales), enregistré à la fin
  String _avatar = '';

  bool _enChargement = false; // true pendant l'enregistrement

  @override
  void initState() {
    super.initState();
    // Les champs sont pré-remplis avec les données actuelles
    final Utilisateur utilisateur = UtilisateurRepository()
        .getUtilisateurConnecte();
    _nomController = TextEditingController(text: utilisateur.nomComplet);
    _telephoneController = TextEditingController(text: utilisateur.telephone);
    _logementController = TextEditingController(text: utilisateur.logement);
    for (final String competence in utilisateur.competences) {
      _competences.add(competence);
    }
    // Des compétences hors liste existent déjà : "Autre" est coché
    _autreCoche = _competencesAutres().isNotEmpty;
    _avatar = utilisateur.avatar;
  }

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _logementController.dispose();
    _autreController.dispose();
    super.dispose();
  }

  String? _validerNom(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return tr('Saisis ton nom complet', 'Ekteb esmek kemel');
    }
    return null;
  }

  String? _validerTelephone(String? valeur) {
    // 8 chiffres, avec ou sans +216 : le numéro sert aussi à se connecter
    if (UtilisateurRepository.normaliserTelephone(valeur ?? '') == null) {
      return tr(
        'Numéro de téléphone invalide (8 chiffres)',
        'Nouméro mouch s7i7 (8 ar9am)',
      );
    }
    return null;
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Texte "Autre" tapé mais pas encore ajouté : on ne le perd pas
    if (_autreCoche) {
      _ajouterAutre();
    }
    setState(() {
      _enChargement = true;
    });
    final Resultat<void> resultat = await UtilisateurRepository()
        .modifierProfil(
          nomComplet: _nomController.text,
          telephone: _telephoneController.text,
          logement: _logementController.text,
          competences: _competences,
          avatar: _avatar,
        );
    if (!mounted) {
      return; // l'écran a été fermé pendant l'attente
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      // On reste sur l'écran pour que l'utilisateur puisse réessayer
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(resultat.erreur!)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Profil enregistré', 'El profil tsajjel'))),
    );
    context.pop(); // retour au profil
  }

  /// Galerie d'avatars (en bas de l'écran) : pas encore d'envoi de vraie
  /// photo, on choisit un dessin ou on revient aux initiales.
  Future<void> _choisirPhoto() async {
    final String? choix = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final List<Widget> avatars = [];
        for (final AvatarGalerie avatar in avatarsGalerie) {
          avatars.add(
            InkWell(
              key: Key('avatar_${avatar.id}'),
              customBorder: const CircleBorder(),
              onTap: () {
                Navigator.of(context).pop(avatar.id);
              },
              child: AvatarUtilisateur(
                avatar: avatar.id,
                initiales: '',
                taille: 64,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Choisis ton avatar', 'A5tar avatar'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: avatars),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(''); // '' = initiales
                },
                child: Text(
                  tr('Utiliser mes initiales', 'Esta3mel el 7rouf lowla'),
                ),
              ),
            ],
          ),
        );
      },
    );

    // null : la galerie a été fermée sans choisir
    if (choix != null) {
      setState(() {
        _avatar = choix;
      });
    }
  }

  /// Compétences précisées par le voisin (hors de la liste courante).
  List<String> _competencesAutres() {
    final List<String> autres = [];
    for (final String competence in _competences) {
      if (!competencesCommunes.contains(competence)) {
        autres.add(competence);
      }
    }
    return autres;
  }

  /// Coche ou décoche une compétence de la liste courante.
  void _basculerCompetence(String competence, bool coche) {
    setState(() {
      if (coche) {
        _competences.add(competence);
      } else {
        _competences.remove(competence);
      }
    });
  }

  /// Coche ou décoche "Autre". Décocher retire les compétences précisées.
  void _basculerAutre(bool coche) {
    setState(() {
      _autreCoche = coche;
      if (!coche) {
        for (final String autre in _competencesAutres()) {
          _competences.remove(autre);
        }
        _autreController.clear();
      }
    });
  }

  /// Ajoute la compétence tapée dans le champ "Autre".
  void _ajouterAutre() {
    final String texte = _autreController.text.trim();
    if (texte.isEmpty) {
      return;
    }
    setState(() {
      // Déjà présente (même sans tenir compte des majuscules) : rien à ajouter
      bool existe = false;
      for (final String competence in _competences) {
        if (competence.toLowerCase() == texte.toLowerCase()) {
          existe = true;
        }
      }
      if (!existe) {
        // Une compétence de la liste tapée à la main : on coche la bonne
        String aAjouter = texte;
        for (final String commune in competencesCommunes) {
          if (commune.toLowerCase() == texte.toLowerCase()) {
            aAjouter = commune;
          }
        }
        _competences.add(aAjouter);
      }
      _autreController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = UtilisateurRepository()
        .getUtilisateurConnecte();

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: tr('Modifier le profil', 'Badel el profil'),
            action: TextButton(
              onPressed: _enChargement ? null : _enregistrer,
              child: Text(
                tr('Enregistrer', 'Sajjel'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            // SingleChildScrollView (et pas ListView) : le Form reste construit
            // même quand on a défilé jusqu'en bas pour enregistrer
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----- Photo (initiales) -----
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: AvatarUtilisateur(
                        avatar: _avatar,
                        initiales: utilisateur.initiales,
                        taille: 88,
                        couleur: AppColors.secondary,
                        fond: AppColors.secondaryLight,
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _choisirPhoto,
                      child: Text(
                        tr('Changer la photo', 'Badel el taswira'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                          label: tr('Nom complet', 'Esmek kemel'),
                          controller: _nomController,
                          validator: _validerNom,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: tr(
                            'Numéro de téléphone',
                            'Nouméro el téléphone',
                          ),
                          controller: _telephoneController,
                          clavier: TextInputType.phone,
                          validator: _validerTelephone,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: tr(
                            'Bâtiment et appartement',
                            'El bloc w el dar',
                          ),
                          hint: tr(
                            'Ex : Bloc B - Appt 12',
                            'Mathalan : Bloc B - Appt 12',
                          ),
                          controller: _logementController,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            'Visible uniquement par l\'administrateur du quartier.',
                            'Ken el admin mta3 el houma ychoufha.',
                          ),
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
                  Text(
                    tr('Compétences', 'Chnowa ta3ref ta3mel'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'Coche ce que tu sais faire. Autre chose ? Coche « Autre » et précise.',
                      'Cochi chnowa ta3ref ta3mel. 7aja o5ra ? Cochi « Autre » w 9oul chnowa.',
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _casesCompetences(),
                  ),
                  if (_autreCoche) ..._zoneAutre(),
                  const SizedBox(height: 32),

                  PrimaryButton(
                    texte: tr(
                      'Enregistrer les modifications',
                      'Sajjel el tabdil',
                    ),
                    onPressed: _enChargement ? null : _enregistrer,
                  ),
                  if (_enChargement) const IndicateurChargement(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Une case (FilterChip) par compétence courante, puis "Autre".
  List<Widget> _casesCompetences() {
    final List<Widget> cases = [];
    for (final String competence in competencesCommunes) {
      cases.add(
        FilterChip(
          label: Text(competence),
          selected: _competences.contains(competence),
          selectedColor: AppColors.secondaryLight,
          checkmarkColor: AppColors.secondary,
          onSelected: (bool coche) {
            _basculerCompetence(competence, coche);
          },
        ),
      );
    }
    cases.add(
      FilterChip(
        label: Text(tr('Autre', 'O5ra')),
        selected: _autreCoche,
        selectedColor: AppColors.secondaryLight,
        checkmarkColor: AppColors.secondary,
        onSelected: _basculerAutre,
      ),
    );
    return cases;
  }

  /// "Autre" coché : les compétences précisées (avec croix) et le champ
  /// pour en ajouter une.
  List<Widget> _zoneAutre() {
    final List<Widget> pastilles = [];
    for (final String autre in _competencesAutres()) {
      pastilles.add(
        Pastille(
          texte: autre,
          couleur: AppColors.secondary,
          fond: AppColors.secondaryLight,
          onSupprimer: () {
            setState(() {
              _competences.remove(autre);
            });
          },
        ),
      );
    }
    return [
      const SizedBox(height: 12),
      if (pastilles.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: pastilles),
      if (pastilles.isNotEmpty) const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _autreController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: tr(
                  'Précise : ex. Cours de piano',
                  '9oul chnowa : mathalan Cours de piano',
                ),
                isDense: true,
              ),
              onSubmitted: (String _) {
                _ajouterAutre();
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _ajouterAutre,
            child: Text(tr('Ajouter', 'Zid')),
          ),
        ],
      ),
    ];
  }
}
