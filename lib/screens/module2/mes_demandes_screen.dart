import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/models/service.dart';
import '../../data/models/message_chat.dart';
import '../../data/models/statut_demande.dart';
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
class MesDemandesScreen extends StatefulWidget {
  const MesDemandesScreen({super.key});

  @override
  State<MesDemandesScreen> createState() {
    return _MesDemandesScreenState();
  }
}

class _MesDemandesScreenState extends State<MesDemandesScreen> {
  final ServiceRepository _repository = ServiceRepository();
  final ChatRepository _chat = ChatRepository();

  bool _afficherEnvoyees = true; // true = onglet "Envoyées", false = "Reçues"

  /// Change le statut d'une demande, puis affiche un message.
  void _changerStatut(
    DemandeService demande,
    StatutDemande statut,
    String message,
  ) {
    final bool ok = _repository.changerStatutDemande(demande.id, statut);
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? message : 'Action impossible')));
  }

  /// "Contacter" : ouvre le chat, puis rafraîchit la liste au retour
  /// (le badge des messages non lus se met à jour).
  Future<void> _contacter(DemandeService demande) async {
    await ouvrirEcran(context, ChatScreen(demandeId: demande.id));
    if (mounted) {
      setState(() {});
    }
  }

  /// Ouvre l'écran d'évaluation, puis rafraîchit la liste au retour.
  Future<void> _evaluer(DemandeService demande) async {
    await ouvrirEcran(context, EvaluationScreen(demandeId: demande.id));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DemandeService> envoyees = _repository.getDemandesEnvoyees();
    final List<DemandeService> recues = _repository.getDemandesRecues();
    final List<DemandeService> demandes = _afficherEnvoyees ? envoyees : recues;

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Mes demandes'),
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
                ? Center(
                    child: Text(
                      _afficherEnvoyees
                          ? 'Tu n\'as envoyé aucune demande'
                          : 'Tu n\'as reçu aucune demande',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: demandes.length,
                    itemBuilder: (context, index) {
                      return _carteDemande(demandes[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// La carte d'une demande : service, personne, date, statut, boutons.
  Widget _carteDemande(DemandeService demande) {
    final Service? service = _repository.getServiceParId(demande.serviceId);
    final String titre = service != null ? service.titre : 'Service supprimé';

    // La personne concernée : l'auteur du service (envoyées) ou le demandeur (reçues)
    final String personne = _afficherEnvoyees
        ? demande.auteurService
        : demande.demandeur;
    final String phrase = _afficherEnvoyees
        ? 'Service de $personne'
        : 'Demandé par $personne';

    final Widget? actions = _actions(demande);

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
                            style: const TextStyle(
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
          _apercuMessage(demande),
        ],
      ),
    );
  }

  /// Le dernier message de la conversation, en une ligne grise sous la carte.
  Widget _apercuMessage(DemandeService demande) {
    final MessageChat? dernier = _chat.dernierMessage(demande.id);
    if (dernier == null || !_chat.peutDiscuter(demande)) {
      return const SizedBox.shrink();
    }
    final String auteur = dernier.auteur == _repository.getMonNom()
        ? 'Toi'
        : prenomDe(dernier.auteur);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Text(
        '$auteur : ${dernier.texte}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  /// Le bouton "Contacter", avec le nombre de messages non lus en badge rond.
  Widget _boutonContacter(DemandeService demande) {
    final int nonLus = _chat.nombreNonLus(demande.id);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SecondaryButton(
          texte: 'Contacter',
          onPressed: () {
            _contacter(demande);
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
              decoration: const BoxDecoration(
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
  Widget? _actions(DemandeService demande) {
    // Reçue et en attente : Refuser / Accepter
    if (!_afficherEnvoyees && demande.statut == StatutDemande.enAttente) {
      return Row(
        children: [
          Expanded(
            child: SecondaryButton(
              texte: 'Refuser',
              onPressed: () {
                _changerStatut(
                  demande,
                  StatutDemande.refusee,
                  'Demande refusée',
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              texte: 'Accepter',
              onPressed: () {
                _changerStatut(
                  demande,
                  StatutDemande.acceptee,
                  'Demande acceptée',
                );
              },
            ),
          ),
        ],
      );
    }

    // Acceptée : Contacter / Terminée
    if (demande.statut == StatutDemande.acceptee) {
      return Row(
        children: [
          Expanded(child: _boutonContacter(demande)),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              texte: 'Terminée',
              onPressed: () {
                _changerStatut(
                  demande,
                  StatutDemande.realisee,
                  'Service marqué comme réalisé',
                );
              },
            ),
          ),
        ],
      );
    }

    // Réalisée : Contacter (le chat reste lisible), puis évaluer côté Envoyées
    if (demande.statut == StatutDemande.realisee) {
      final List<Widget> boutons = [_boutonContacter(demande)];
      if (_afficherEnvoyees) {
        boutons.add(const SizedBox(height: 12));
        if (demande.evaluee) {
          boutons.add(
            const Text(
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
                _evaluer(demande);
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
