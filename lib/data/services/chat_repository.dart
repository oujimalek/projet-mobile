import 'dart:async';

import '../models/demande_service.dart';
import '../models/message_chat.dart';
import '../models/statut_demande.dart';
import 'service_repository.dart';

/// M2 - Accès aux messages du chat entre le demandeur et l'auteur d'un service.
///
/// Comme ServiceRepository, les données sont gardées EN MÉMOIRE dans des
/// listes static : partagées entre les écrans, perdues quand l'app se ferme.
/// Plus tard, seul l'intérieur de ces méthodes changera (vrai chat via API).
class ChatRepository {
  /// Longueur maximale d'un message.
  static const int longueurMax = 500;

  /// SIMULATION POUR LA DÉMO : si true, l'interlocuteur répond tout seul
  /// environ 2 secondes après chaque message. À remplacer par un vrai chat
  /// (API) plus tard. Les tests mettent cette valeur à false.
  static bool reponseAutomatiqueActive = true;

  static const Duration _delaiReponse = Duration(seconds: 2);

  /// Les réponses possibles de la simulation.
  static const List<String> _reponsesAuto = [
    'D\'accord, ça marche !',
    'Je suis dispo samedi matin.',
    'Merci, à tout à l\'heure !',
    'Pas de souci, on fait comme ça.',
  ];

  // ----- Les données en mémoire (static = partagées par tous les écrans) -----
  static List<MessageChat> _messages = _messagesInitiaux();
  static int _compteurReponse = 0; // pour choisir la réponse automatique

  /// Les conversations où l'interlocuteur est en train d'écrire.
  static final List<String> _enEcriture = [];

  /// Les réponses automatiques qui n'ont pas encore été envoyées.
  static final List<Timer> _timers = [];

  /// Les écrans qui veulent être prévenus d'un nouveau message.
  static final List<Function()> _ecouteurs = [];

  final ServiceRepository _serviceRepository = ServiceRepository();

  // =====================================================================
  // Lecture
  // =====================================================================

  /// Les messages d'une demande, du plus ancien au plus récent.
  List<MessageChat> getMessages(String demandeId) {
    final List<MessageChat> resultat = [];
    for (final message in _messages) {
      if (message.demandeId == demandeId) {
        resultat.add(message);
      }
    }
    resultat.sort((a, b) {
      return a.date.compareTo(b.date);
    });
    return resultat;
  }

  /// Le dernier message d'une demande (null s'il n'y en a pas).
  MessageChat? dernierMessage(String demandeId) {
    final List<MessageChat> messages = getMessages(demandeId);
    if (messages.isEmpty) {
      return null;
    }
    return messages.last;
  }

  /// true si l'utilisateur connecté peut discuter pour cette demande :
  /// elle doit être acceptée ou réalisée, et je suis le demandeur ou l'auteur.
  bool peutDiscuter(DemandeService demande) {
    if (demande.statut != StatutDemande.acceptee &&
        demande.statut != StatutDemande.realisee) {
      return false;
    }
    final String moi = _serviceRepository.getMonNom();
    return demande.demandeur == moi || demande.auteurService == moi;
  }

  /// L'autre personne de la conversation.
  String getInterlocuteur(DemandeService demande) {
    if (demande.demandeur == _serviceRepository.getMonNom()) {
      return demande.auteurService;
    }
    return demande.demandeur;
  }

  /// Nombre de messages de l'interlocuteur que je n'ai pas encore lus.
  int nombreNonLus(String demandeId) {
    final String moi = _serviceRepository.getMonNom();
    int total = 0;
    for (final message in _messages) {
      if (message.demandeId == demandeId &&
          message.auteur != moi &&
          !message.lu) {
        total++;
      }
    }
    return total;
  }

  /// true pendant que l'interlocuteur "écrit" sa réponse automatique.
  bool interlocuteurEcrit(String demandeId) {
    return _enEcriture.contains(demandeId);
  }

  // =====================================================================
  // Écriture
  // =====================================================================

  /// Marque comme lus tous les messages de l'interlocuteur.
  void marquerCommeLus(String demandeId) {
    final String moi = _serviceRepository.getMonNom();
    for (int i = 0; i < _messages.length; i++) {
      final MessageChat message = _messages[i];
      if (message.demandeId == demandeId &&
          message.auteur != moi &&
          !message.lu) {
        _messages[i] = message.copyWith(lu: true);
      }
    }
  }

  /// Envoie un message. Renvoie false (rien n'est créé) si la demande n'existe
  /// pas, si je ne peux pas discuter, si le texte est vide ou dépasse 500
  /// caractères.
  bool envoyerMessage(String demandeId, String texte) {
    final DemandeService? demande = _serviceRepository.getDemandeParId(
      demandeId,
    );
    if (demande == null || !peutDiscuter(demande)) {
      return false;
    }
    final String propre = texte.trim();
    if (propre.isEmpty || propre.length > longueurMax) {
      return false;
    }

    _messages.add(
      MessageChat(
        id: _serviceRepository.genererId('m'),
        demandeId: demandeId,
        auteur: _serviceRepository.getMonNom(),
        texte: propre,
        date: DateTime.now(),
        lu: false,
      ),
    );

    if (reponseAutomatiqueActive) {
      _programmerReponse(demande);
    }
    return true;
  }

  // =====================================================================
  // Réponse automatique (démo)
  // =====================================================================

  /// Prépare la réponse de l'interlocuteur dans environ 2 secondes.
  void _programmerReponse(DemandeService demande) {
    final String demandeId = demande.id;
    final String interlocuteur = getInterlocuteur(demande);

    if (!_enEcriture.contains(demandeId)) {
      _enEcriture.add(demandeId);
    }
    // Le timer vit dans une liste static : si l'écran est fermé, la réponse
    // est quand même ajoutée (elle sera "non lue"), sans aucun plantage.
    late final Timer timer;
    timer = Timer(_delaiReponse, () {
      _timers.remove(timer);
      _enEcriture.remove(demandeId);
      _messages.add(
        MessageChat(
          id: _serviceRepository.genererId('m'),
          demandeId: demandeId,
          auteur: interlocuteur,
          texte: _reponsesAuto[_compteurReponse % _reponsesAuto.length],
          date: DateTime.now(),
          lu: false,
        ),
      );
      _compteurReponse++;
      _prevenirEcouteurs();
    });
    _timers.add(timer);
  }

  /// Un écran s'abonne pour être prévenu d'un nouveau message.
  void ajouterEcouteur(Function() ecouteur) {
    _ecouteurs.add(ecouteur);
  }

  /// L'écran se désabonne (à appeler dans dispose).
  void retirerEcouteur(Function() ecouteur) {
    _ecouteurs.remove(ecouteur);
  }

  void _prevenirEcouteurs() {
    // Copie de la liste : un écouteur peut se retirer pendant l'appel
    for (final ecouteur in List<Function()>.of(_ecouteurs)) {
      ecouteur();
    }
  }

  // =====================================================================
  // Remise à zéro (utilisée uniquement par les tests)
  // =====================================================================

  /// Remet les données de départ et annule les réponses automatiques en attente.
  void reinitialiser() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _enEcriture.clear();
    _ecouteurs.clear();
    _messages = _messagesInitiaux();
    _compteurReponse = 0;
  }

  // =====================================================================
  // Données de départ
  // =====================================================================

  static List<MessageChat> _messagesInitiaux() {
    final DateTime maintenant = DateTime.now();
    final String moi = ServiceRepository().getMonNom();

    return [
      // ----- d2 : ma demande acceptée chez Nizar H. -----
      MessageChat(
        id: 'm1',
        demandeId: 'd2',
        auteur: moi,
        texte: 'Salam Nizar, je peux passer chercher la perceuse demain ?',
        date: maintenant.subtract(const Duration(hours: 5)),
        lu: true,
      ),
      MessageChat(
        id: 'm2',
        demandeId: 'd2',
        auteur: 'Nizar H.',
        texte: 'Salam Amira ! Oui bien sûr, je suis là après 17h.',
        date: maintenant.subtract(const Duration(hours: 4)),
        lu: true,
      ),
      MessageChat(
        id: 'm3',
        demandeId: 'd2',
        auteur: 'Nizar H.',
        texte: 'Passe avant 19h si tu peux, je sors ensuite. Merci !',
        date: maintenant.subtract(const Duration(minutes: 30)),
        lu: false,
      ),

      // ----- d5 : la demande de Sarra A. pour mon service -----
      MessageChat(
        id: 'm4',
        demandeId: 'd5',
        auteur: 'Sarra A.',
        texte: 'Salam Amira, merci d\'avoir accepté ! Tu es disponible quand ?',
        date: maintenant.subtract(const Duration(hours: 3)),
        lu: false,
      ),
    ];
  }
}
