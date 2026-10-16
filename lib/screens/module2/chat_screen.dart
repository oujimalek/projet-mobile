import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/models/message_chat.dart';
import '../../data/resultat.dart';
import '../../data/services/chat_repository.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Chat entre le demandeur et l'auteur d'un service.
///
/// Accessible depuis "Mes demandes" (bouton "Contacter") quand la demande
/// est acceptée ou réalisée. S'ouvre en plein écran. Les messages arrivent
/// en direct (Firestore).
class ChatScreen extends StatefulWidget {
  final String demandeId; // id de la demande dont on affiche la conversation

  const ChatScreen({super.key, required this.demandeId});

  @override
  State<ChatScreen> createState() {
    return _ChatScreenState();
  }
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatRepository _chat = ChatRepository();
  final ServiceRepository _repository = ServiceRepository();
  final TextEditingController _champController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Flux créés UNE fois (voir FluxM2)
  late final Stream<DemandeService?> _fluxDemande = _repository.ecouterDemande(
    widget.demandeId,
  );
  late final Stream<List<MessageChat>> _fluxMessages = _chat.ecouterMessages(
    widget.demandeId,
  );

  // Les messages rapides proposés au-dessus du champ
  static const List<String> _messagesRapides = [
    'Je suis disponible',
    'À quelle heure ?',
    'Où est-ce qu\'on se retrouve ?',
    'Merci beaucoup !',
  ];

  bool _enCours = false; // true pendant l'envoi d'un message
  bool _marquageEnCours = false; // évite de marquer deux fois les mêmes messages
  int _nombreAffiche = 0; // pour descendre quand un message arrive

  @override
  void dispose() {
    _champController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Fait défiler la liste jusqu'au dernier message (après l'affichage).
  void _descendre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Marque comme lus les messages de l'interlocuteur qui viennent d'arriver.
  void _marquerCommeLus() {
    if (_marquageEnCours) {
      return;
    }
    _marquageEnCours = true;
    _chat.marquerCommeLus(widget.demandeId).whenComplete(() {
      _marquageEnCours = false;
    });
  }

  /// Envoie le texte du champ, puis vide le champ.
  Future<void> _envoyer(DemandeService demande) async {
    setState(() {
      _enCours = true;
    });
    final Resultat<void> resultat = await _chat.envoyerMessage(
      demande,
      _champController.text,
    );
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
    _champController.clear();
    setState(() {});
  }

  /// Un message rapide remplit le champ (on peut le modifier avant d'envoyer).
  void _remplirChamp(String texte) {
    _champController.text = texte;
    _champController.selection = TextSelection.collapsed(offset: texte.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FluxM2<DemandeService?>(
        flux: _fluxDemande,
        construire: (context, demande) {
          if (demande == null) {
            return const MessageEtat(texte: 'Cette demande n\'existe plus');
          }
          final String moi = _repository.getMonId();
          final bool peutDiscuter = ChatRepository.peutDiscuter(demande, moi);
          final String interlocuteur = ChatRepository.interlocuteur(demande, moi);

          return Column(
            children: [
              _entete(demande, interlocuteur),
              if (peutDiscuter) ...[
                Expanded(child: _listeMessages(interlocuteur)),
                _zoneSaisie(demande),
              ] else
                const Expanded(
                  child: MessageEtat(
                    texte: 'Le chat est disponible une fois la demande acceptée.',
                    icone: Icons.chat_bubble_outline,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// L'en-tête : retour, avatar, nom, titre du service et statut.
  Widget _entete(DemandeService demande, String interlocuteur) {
    final String titre = demande.serviceTitre.isNotEmpty
        ? demande.serviceTitre
        : 'Service supprimé';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 12,
        16,
        16,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: Icon(Icons.arrow_back, color: AppColors.primary),
          ),
          AvatarInitiales(nom: interlocuteur, taille: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  interlocuteur,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    BadgeStatutDemande(statut: demande.statut),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// La liste des messages, avec les séparateurs de date.
  Widget _listeMessages(String interlocuteur) {
    return FluxM2<List<MessageChat>>(
      flux: _fluxMessages,
      construire: (context, messages) {
        final String moi = _repository.getMonId();

        // Nouveau message : on descend, et on marque les messages reçus comme lus
        if (messages.length != _nombreAffiche) {
          _nombreAffiche = messages.length;
          _descendre();
        }
        if (ChatRepository.compterNonLus(messages, moi) > 0) {
          _marquerCommeLus();
        }

        if (messages.isEmpty) {
          return MessageEtat(
            texte: 'Aucun message. Dis bonjour à ${prenomDe(interlocuteur)} 👋',
            icone: Icons.chat_bubble_outline,
          );
        }

        final List<Widget> elements = [];
        DateTime? jourPrecedent;
        for (final message in messages) {
          if (jourPrecedent == null || !memeJour(jourPrecedent, message.date)) {
            elements.add(_separateurDate(message.date));
          }
          jourPrecedent = message.date;
          elements.add(_bulle(message, message.auteurId == moi));
        }

        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          children: elements,
        );
      },
    );
  }

  /// "Aujourd'hui", "Hier", sinon la date en français.
  Widget _separateurDate(DateTime date) {
    final DateTime maintenant = DateTime.now();
    String texte = dateCourte(date);
    if (memeJour(date, maintenant)) {
      texte = 'Aujourd\'hui';
    } else if (memeJour(date, maintenant.subtract(const Duration(days: 1)))) {
      texte = 'Hier';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: PastilleTexte(
          texte: texte,
          couleur: AppColors.textSecondary,
          fond: AppColors.backgroundSecondary,
        ),
      ),
    );
  }

  /// Une bulle : à droite (moi, bleue) ou à gauche (l'autre, claire).
  Widget _bulle(MessageChat message, bool estMoi) {
    final double largeurMax = MediaQuery.of(context).size.width * 0.75;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: largeurMax),
          child: Column(
            crossAxisAlignment: estMoi
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: estMoi
                      ? AppColors.primary
                      : AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(estMoi ? 18 : 4),
                    bottomRight: Radius.circular(estMoi ? 4 : 18),
                  ),
                ),
                child: Text(
                  message.texte,
                  style: TextStyle(
                    fontSize: 15,
                    color: estMoi ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _heure(message.date),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// L'heure d'un message, par exemple "09:05".
  String _heure(DateTime date) {
    final String heures = date.hour.toString().padLeft(2, '0');
    final String minutes = date.minute.toString().padLeft(2, '0');
    return '$heures:$minutes';
  }

  /// Messages rapides + champ de saisie + bouton envoyer.
  Widget _zoneSaisie(DemandeService demande) {
    final bool peutEnvoyer = _champController.text.trim().isNotEmpty && !_enCours;

    return Container(
      color: AppColors.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final texte in _messagesRapides) ...[
                      PastilleChoix(
                        texte: texte,
                        actif: false,
                        onTap: () {
                          _remplirChamp(texte);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _champController,
                      minLines: 1,
                      maxLines: 4, // 4 lignes visibles au maximum
                      maxLength: ChatRepository.longueurMax,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) {
                            return null; // pas de compteur affiché
                          },
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Écris un message…',
                      ),
                      onChanged: (valeur) {
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    // null = bouton désactivé (champ vide ou envoi en cours)
                    onPressed: peutEnvoyer ? () => _envoyer(demande) : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
