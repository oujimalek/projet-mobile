import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/models/message_chat.dart';
import '../../data/models/statut_demande.dart';
import '../../data/resultat.dart';
import '../../data/services/chat_repository.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'chat_screen.dart';
import 'evaluation_screen.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Mes demandes (écran 04).
///
/// Deux onglets : les demandes que j'ai envoyées et celles que j'ai reçues
/// pour mes services. On peut accepter, refuser, terminer et évaluer.
/// Les listes se mettent à jour toutes seules (Firestore en direct).
class MesDemandesScreen extends StatefulWidget {
  const MesDemandesScreen({super.key});

  @override
  State<MesDemandesScreen> createState() {
    return _MesDemandesScreenState();
  }
}

class _MesDemandesScreenState extends State<MesDemandesScreen> {
  final ServiceRepository _repository = ServiceRepository();

  // Flux créés UNE fois (voir FluxM2)
  late final Stream<List<DemandeService>> _fluxEnvoyees = _repository
      .ecouterDemandesEnvoyees();
  late final Stream<List<DemandeService>> _fluxRecues = _repository
      .ecouterDemandesRecues();

  bool _afficherEnvoyees = true; // true = onglet "Envoyées", false = "Reçues"
  bool _enCours = false; // true pendant une écriture : boutons désactivés

  /// Change le statut d'une demande, puis affiche un message.
  Future<void> _changerStatut(
    DemandeService demande,
    StatutDemande statut,
    String message,
  ) async {
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _repository.changerStatutDemande(
      demande.id,
      statut,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enCours = false;
    });
    afficherMessage(context, resultat.estSucces ? message : resultat.erreur!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Mes demandes'),
          Expanded(
            child: FluxM2<List<DemandeService>>(
              flux: _fluxEnvoyees,
              construire: (context, envoyees) {
                return FluxM2<List<DemandeService>>(
                  flux: _fluxRecues,
                  construire: (context, recues) {
                    return _contenu(envoyees, recues);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenu(List<DemandeService> envoyees, List<DemandeService> recues) {
    final List<DemandeService> demandes = _afficherEnvoyees ? envoyees : recues;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: DeuxOnglets(
            premier: 'Envoyées (${envoyees.length})',
            second: 'Reçues (${recues.length})',
            premierActif: _afficherEnvoyees,
            onChoix: (estPremier) {
              setState(() {
                _afficherEnvoyees = estPremier;
              });
            },
          ),
        ),
        Expanded(
          child: demandes.isEmpty
              ? MessageEtat(
                  texte: _afficherEnvoyees
                      ? 'Tu n\'as envoyé aucune demande'
                      : 'Tu n\'as reçu aucune demande',
                  icone: Icons.inbox_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: demandes.length,
                  itemBuilder: (context, index) {
                    return _CarteDemande(
                      // Le statut dans la clé : quand la demande est acceptée,
                      // la carte se recrée et écoute alors le chat
                      key: ValueKey(
                        '${demandes[index].id}_${demandes[index].statut.name}',
                      ),
                      demande: demandes[index],
                      estEnvoyee: _afficherEnvoyees,
                      enCours: _enCours,
                      repository: _repository,
                      onChangerStatut: _changerStatut,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// La carte d'une demande : service, personne, date, statut, boutons.
/// Elle écoute elle-même les messages de sa demande (aperçu et non lus).
class _CarteDemande extends StatefulWidget {
  final DemandeService demande;
  final bool estEnvoyee;
  final bool enCours;
  final ServiceRepository repository;
  final Future<void> Function(DemandeService, StatutDemande, String)
  onChangerStatut;

  const _CarteDemande({
    super.key,
    required this.demande,
    required this.estEnvoyee,
    required this.enCours,
    required this.repository,
    required this.onChangerStatut,
  });

  @override
  State<_CarteDemande> createState() {
    return _CarteDemandeState();
  }
}

class _CarteDemandeState extends State<_CarteDemande> {
  final ChatRepository _chat = ChatRepository();

  // Les messages de la demande, seulement si on peut discuter
  late final Stream<List<MessageChat>>? _fluxMessages =
      ChatRepository.peutDiscuter(widget.demande, widget.repository.getMonId())
      ? _chat.ecouterMessages(widget.demande.id)
      : null;

  @override
  Widget build(BuildContext context) {
    final DemandeService demande = widget.demande;
    final String titre = demande.serviceTitre.isNotEmpty
        ? demande.serviceTitre
        : 'Service supprimé';

    // La personne concernée : l'auteur du service (envoyées) ou le demandeur (reçues)
    final String personne = widget.estEnvoyee
        ? demande.auteurServiceNom
        : demande.demandeurNom;
    final String phrase = widget.estEnvoyee
        ? 'Service de $personne'
        : 'Demandé par $personne';

    final Stream<List<MessageChat>>? flux = _fluxMessages;
    if (flux == null) {
      return _carte(demande, titre, personne, phrase, const []);
    }
    return StreamBuilder<List<MessageChat>>(
      stream: flux,
      builder: (context, instantane) {
        return _carte(
          demande,
          titre,
          personne,
          phrase,
          instantane.data ?? const [],
        );
      },
    );
  }

  Widget _carte(
    DemandeService demande,
    String titre,
    String personne,
    String phrase,
    List<MessageChat> messages,
  ) {
    final Widget? actions = _actions(demande, messages);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AvatarInitiales(nom: personne),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titre,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$phrase · ${depuisQuand(demande.dateDemande)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BadgeStatutDemande(statut: demande.statut),
                if (actions != null) ...[const SizedBox(height: 12), actions],
              ],
            ),
          ),
          _apercuMessage(messages),
        ],
      ),
    );
  }

  /// Le dernier message de la conversation, en une ligne grise sous la carte.
  Widget _apercuMessage(List<MessageChat> messages) {
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    final MessageChat dernier = messages.last;
    final String auteur = dernier.auteurId == widget.repository.getMonId()
        ? 'Toi'
        : prenomDe(dernier.auteurNom);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Text(
        '$auteur : ${dernier.texte}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  /// Le bouton "Contacter", avec le nombre de messages non lus en badge rond.
  Widget _boutonContacter(DemandeService demande, List<MessageChat> messages) {
    final int nonLus = ChatRepository.compterNonLus(
      messages,
      widget.repository.getMonId(),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SecondaryButton(
          texte: 'Contacter',
          onPressed: () {
            ouvrirEcran(context, ChatScreen(demandeId: demande.id));
          },
        ),
        if (nonLus > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$nonLus',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Les boutons d'une demande selon son statut (null = aucun bouton).
  Widget? _actions(DemandeService demande, List<MessageChat> messages) {
    final bool libre = !widget.enCours; // false = boutons désactivés

    // Reçue et en attente : Refuser / Accepter
    if (!widget.estEnvoyee && demande.statut == StatutDemande.enAttente) {
      return Row(
        children: [
          Expanded(
            child: SecondaryButton(
              texte: 'Refuser',
              onPressed: libre
                  ? () {
                      widget.onChangerStatut(
                        demande,
                        StatutDemande.refusee,
                        'Demande refusée',
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              texte: 'Accepter',
              onPressed: libre
                  ? () {
                      widget.onChangerStatut(
                        demande,
                        StatutDemande.acceptee,
                        'Demande acceptée',
                      );
                    }
                  : null,
            ),
          ),
        ],
      );
    }

    // Acceptée : Contacter / Terminée
    if (demande.statut == StatutDemande.acceptee) {
      return Row(
        children: [
          Expanded(child: _boutonContacter(demande, messages)),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              texte: 'Terminée',
              onPressed: libre
                  ? () {
                      widget.onChangerStatut(
                        demande,
                        StatutDemande.realisee,
                        'Service marqué comme réalisé',
                      );
                    }
                  : null,
            ),
          ),
        ],
      );
    }

    // Réalisée : Contacter (le chat reste lisible), puis évaluer côté Envoyées
    if (demande.statut == StatutDemande.realisee) {
      final List<Widget> boutons = [_boutonContacter(demande, messages)];
      if (widget.estEnvoyee) {
        boutons.add(const SizedBox(height: 12));
        if (demande.evaluee) {
          boutons.add(
            Text(
              'Service évalué, merci !',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          );
        } else {
          boutons.add(
            PrimaryButton(
              texte: 'Évaluer le service',
              icone: Icons.star_outline,
              onPressed: () {
                ouvrirEcran(context, EvaluationScreen(demandeId: demande.id));
              },
            ),
          );
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: boutons,
      );
    }

    return null;
  }
}
