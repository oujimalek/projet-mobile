import 'package:flutter/material.dart';

import '../../data/models/demande_service.dart';
import '../../data/models/message_chat.dart';
import '../../data/models/service.dart';
import '../../data/services/chat_repository.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Chat entre le demandeur et l'auteur d'un service.
///
/// Accessible depuis "Mes demandes" (bouton "Contacter") quand la demande
/// est acceptée ou réalisée. S'ouvre en plein écran.
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

  // Les messages rapides proposés au-dessus du champ
  static const List<String> _messagesRapides = [
    'Je suis disponible',
    'À quelle heure ?',
    'Où est-ce qu\'on se retrouve ?',
    'Merci beaucoup !',
  ];

  @override
  void initState() {
    super.initState();
    _chat.marquerCommeLus(widget.demandeId);
    _chat.ajouterEcouteur(_surNouveauMessage);
    _descendre(animer: false);
  }

  @override
  void dispose() {
    // On se désabonne : la réponse automatique ne touchera plus cet écran
    _chat.retirerEcouteur(_surNouveauMessage);
    _champController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Appelé quand l'interlocuteur répond (réponse automatique de la démo).
  void _surNouveauMessage() {
    if (!mounted) {
      return;
    }
    _chat.marquerCommeLus(widget.demandeId);
    setState(() {});
    _descendre();
  }

  /// Fait défiler la liste jusqu'au dernier message (après l'affichage).
  void _descendre({bool animer = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final double bas = _scrollController.position.maxScrollExtent;
      if (animer) {
        _scrollController.animateTo(
          bas,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(bas);
      }
    });
  }

  /// Envoie le texte du champ, puis vide le champ.
  void _envoyer() {
    final bool ok = _chat.envoyerMessage(
      widget.demandeId,
      _champController.text,
    );
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message impossible à envoyer')),
      );
      return;
    }
    _champController.clear();
    setState(() {});
    _descendre();
  }

  /// Un message rapide remplit le champ (on peut le modifier avant d'envoyer).
  void _remplirChamp(String texte) {
    _champController.text = texte;
    _champController.selection = TextSelection.collapsed(offset: texte.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final DemandeService? demande = _repository.getDemandeParId(
      widget.demandeId,
    );

    if (demande == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Cette demande n\'existe plus',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final bool peutDiscuter = _chat.peutDiscuter(demande);
    final String interlocuteur = _chat.getInterlocuteur(demande);

    return Scaffold(
      body: Column(
        children: [
          _entete(demande, interlocuteur),
          if (peutDiscuter) ...[
            Expanded(child: _listeMessages(demande, interlocuteur)),
            _zoneSaisie(),
          ] else
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Le chat est disponible une fois la demande acceptée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// L'en-tête : retour, avatar, nom, titre du service et statut.
  Widget _entete(DemandeService demande, String interlocuteur) {
    final Service? service = _repository.getServiceParId(demande.serviceId);
    final String titre = service != null ? service.titre : 'Service supprimé';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 12,
        16,
        16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back, color: AppColors.primary),
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
                        style: const TextStyle(
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
  Widget _listeMessages(DemandeService demande, String interlocuteur) {
    final List<MessageChat> messages = _chat.getMessages(demande.id);
    final bool ecrit = _chat.interlocuteurEcrit(demande.id);

    if (messages.isEmpty && !ecrit) {
      return Center(
        child: Text(
          'Aucun message. Dis bonjour à ${prenomDe(interlocuteur)} 👋',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final String moi = _repository.getMonNom();
    final List<Widget> elements = [];
    DateTime? jourPrecedent;
    for (final message in messages) {
      if (jourPrecedent == null || !memeJour(jourPrecedent, message.date)) {
        elements.add(_separateurDate(message.date));
      }
      jourPrecedent = message.date;
      elements.add(_bulle(message, message.auteur == moi));
    }
    if (ecrit) {
      elements.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${prenomDe(interlocuteur)} écrit…',
            style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: elements,
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
                style: const TextStyle(
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
  Widget _zoneSaisie() {
    final bool peutEnvoyer = _champController.text.trim().isNotEmpty;

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
                    onPressed: peutEnvoyer ? _envoyer : null,
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
