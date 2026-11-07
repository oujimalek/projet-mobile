import 'package:flutter/material.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/service_repository.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import 'module2_widgets.dart';

/// M2 - Un participant d'une rotation (uid + nom court).
class ParticipantRotation {
  final String id;
  final String nom;

  const ParticipantRotation({required this.id, required this.nom});
}

/// M2 - Choix des participants d'une rotation et de leur ordre de passage.
///
/// Les participants sont les VRAIS membres actifs du quartier, lus avec le
/// code du module 1 (UtilisateurRepository.getVoisins, en lecture seule).
/// L'utilisateur connecté est toujours proposé en tête sous « Moi » : il est
/// ajouté s'il n'est pas dans la liste des voisins.
///
/// Sert à la création d'un service (minimum 1 participant) et à la gestion
/// depuis le détail (ajouter, retirer, changer l'ordre). Se ferme en
/// renvoyant la liste dans l'ordre choisi.
class ParticipantsRotationScreen extends StatefulWidget {
  final List<ParticipantRotation> initiaux;
  final int minimum;

  const ParticipantsRotationScreen({
    super.key,
    this.initiaux = const [],
    this.minimum = 1,
  });

  @override
  State<ParticipantsRotationScreen> createState() {
    return _ParticipantsRotationScreenState();
  }
}

class _ParticipantsRotationScreenState extends State<ParticipantsRotationScreen> {
  late final List<ParticipantRotation> _choisis = List.of(widget.initiaux);
  List<ParticipantRotation> _candidats = [];
  bool _enChargement = true;
  String _erreur = '';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final UtilisateurRepository membres = UtilisateurRepository();
    final Utilisateur moi = membres.getUtilisateurConnecte();
    final Resultat<List<Utilisateur>> resultat = await membres.getVoisins();
    if (!mounted) {
      return;
    }
    final List<ParticipantRotation> candidats = [];
    // « Moi » toujours en tête, même si getVoisins ne me renvoie pas
    if (moi.id.isNotEmpty) {
      candidats.add(ParticipantRotation(id: moi.id, nom: ServiceRepository.nomCourt(moi)));
    }
    for (final Utilisateur voisin in resultat.donnee ?? const <Utilisateur>[]) {
      if (voisin.id != moi.id) {
        candidats.add(ParticipantRotation(
          id: voisin.id,
          nom: ServiceRepository.nomCourt(voisin),
        ));
      }
    }
    setState(() {
      _candidats = candidats;
      _enChargement = false;
      _erreur = resultat.estSucces ? '' : resultat.erreur!;
    });
  }

  bool _estChoisi(String id) {
    return _choisis.any((p) => p.id == id);
  }

  String _libelle(ParticipantRotation participant) {
    final String moi = UtilisateurRepository().getUtilisateurConnecte().id;
    return participant.id == moi ? 'Moi · ${participant.nom}' : participant.nom;
  }

  @override
  Widget build(BuildContext context) {
    final List<ParticipantRotation> disponibles = [
      for (final ParticipantRotation c in _candidats)
        if (!_estChoisi(c.id)) c,
    ];
    final bool valide = _choisis.length >= widget.minimum;

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Participants de la rotation'),
          Expanded(
            child: _enChargement
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Ordre de passage',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Le 1er créneau revient au 1er participant, le 2e au 2e, '
                        'puis on recommence. Glisse pour changer l\'ordre.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      _listeChoisis(),
                      const SizedBox(height: 20),
                      const Text(
                        'Voisins du quartier',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      if (_erreur.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _erreur,
                            style: TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      if (disponibles.isEmpty && _erreur.isEmpty)
                        Text(
                          'Tous les voisins sont déjà dans la rotation',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      for (final ParticipantRotation voisin in disponibles)
                        _ligneVoisin(voisin),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!valide)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Choisis au moins ${widget.minimum} participant',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  PrimaryButton(
                    texte: 'Valider (${_choisis.length})',
                    onPressed: valide
                        ? () {
                            Navigator.of(context).pop(List<ParticipantRotation>.of(_choisis));
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Les participants choisis, dans l'ordre, avec poignée pour réordonner.
  Widget _listeChoisis() {
    if (_choisis.isEmpty) {
      return Text(
        'Aucun participant choisi',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      onReorderItem: (ancien, nouveau) {
        setState(() {
          final ParticipantRotation deplace = _choisis.removeAt(ancien);
          _choisis.insert(nouveau, deplace);
        });
      },
      children: [
        for (int i = 0; i < _choisis.length; i++)
          Padding(
            key: ValueKey('choisi_${_choisis[i].id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.secondary,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: AppColors.card, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _libelle(_choisis[i]),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      setState(() {
                        _choisis.removeAt(i);
                      });
                    },
                  ),
                  const SizedBox(width: 28), // place de la poignée de glissement
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _ligneVoisin(ParticipantRotation voisin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () {
          setState(() {
            _choisis.add(voisin);
          });
        },
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            AvatarInitiales(nom: voisin.nom, taille: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _libelle(voisin),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.add_circle_outline, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
