import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/resultat.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Évaluation d'un service rendu (écran 05).
///
/// L'utilisateur donne une note de 1 à 5 étoiles, choisit des tags et peut
/// ajouter un petit mot. Le bouton reste désactivé tant qu'aucune étoile
/// n'est choisie.
class EvaluationScreen extends StatefulWidget {
  final String demandeId; // id de la demande réalisée à évaluer

  const EvaluationScreen({super.key, required this.demandeId});

  @override
  State<EvaluationScreen> createState() {
    return _EvaluationScreenState();
  }
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  final ServiceRepository _repository = ServiceRepository();

  // Flux créé UNE fois (voir FluxM2)
  late final Stream<DemandeService?> _fluxDemande = _repository.ecouterDemande(
    widget.demandeId,
  );
  final TextEditingController _messageController = TextEditingController();

  // Le texte qui accompagne chaque note (de 1 à 5 étoiles)
  static const List<String> _textesNote = [
    'Décevant',
    'Moyen',
    'Bien',
    'Très bien',
    'Excellent',
  ];

  int _note = 0; // 0 = aucune étoile choisie
  final List<String> _tagsChoisis = [];
  bool _enCours = false; // true pendant l'envoi : bouton désactivé

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// Appelé quand on touche "Envoyer l'évaluation".
  Future<void> _envoyer(DemandeService demande) async {
    // On garde les tags dans l'ordre du repository
    final List<String> tags = [];
    for (final tag in _repository.getTagsEvaluation()) {
      if (_tagsChoisis.contains(tag)) {
        tags.add(tag);
      }
    }
    final String message = _messageController.text.trim();

    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.evaluer(
      demandeId: demande.id,
      note: _note,
      tags: tags,
      message: message.isEmpty ? null : message,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });

    afficherMessage(
      context,
      resultat.estSucces ? 'Merci pour ton évaluation !' : resultat.erreur!,
    );
    if (resultat.estSucces) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Évaluer le service'),
          Expanded(
            child: FluxM2<DemandeService?>(
              flux: _fluxDemande,
              construire: (context, demande) {
                if (demande == null) {
                  return const MessageEtat(
                    texte: 'Cette demande n\'existe plus',
                  );
                }
                return _contenu(demande);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenu(DemandeService demande) {
    final String titreService =
        demande.serviceTitre.isNotEmpty ? demande.serviceTitre : 'Service';
    final String auteur = demande.auteurServiceNom;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              Center(child: AvatarInitiales(nom: auteur, taille: 72)),
              const SizedBox(height: 12),
              Text(
                'Comment s\'est passé le service avec ${prenomDe(auteur)} ?',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                titreService,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _etoiles(),
              const SizedBox(height: 6),
              Text(
                _note == 0 ? 'Touche une étoile' : _textesNote[_note - 1],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _note == 0 ? AppColors.textSecondary : AppColors.secondary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Ce que tu as apprécié',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _tags(),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Un petit mot (optionnel)',
                hint: 'Écris un message pour ${prenomDe(auteur)}',
                lignes: 3,
                controller: _messageController,
              ),
            ],
          ),
        ),
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
              texte: 'Envoyer l\'évaluation',
              // null = bouton désactivé (aucune étoile choisie ou envoi en cours)
              onPressed: (_note == 0 || _enCours)
                  ? null
                  : () {
                      _envoyer(demande);
                    },
            ),
          ),
        ),
      ],
    );
  }

  /// Les 5 étoiles cliquables.
  Widget _etoiles() {
    final List<Widget> etoiles = [];
    for (int i = 1; i <= 5; i++) {
      etoiles.add(
        IconButton(
          tooltip: '$i sur 5',
          onPressed: () {
            setState(() {
              _note = i;
            });
          },
          icon: Icon(
            i <= _note ? Icons.star : Icons.star_border,
            size: 40,
            color: AppColors.secondary,
          ),
        ),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: etoiles);
  }

  /// Les tags sélectionnables (on peut en choisir plusieurs).
  Widget _tags() {
    final List<Widget> pastilles = [];
    for (final tag in _repository.getTagsEvaluation()) {
      pastilles.add(PastilleChoix(
        texte: tag,
        actif: _tagsChoisis.contains(tag),
        onTap: () {
          setState(() {
            if (_tagsChoisis.contains(tag)) {
              _tagsChoisis.remove(tag);
            } else {
              _tagsChoisis.add(tag);
            }
          });
        },
      ));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: pastilles);
  }
}
