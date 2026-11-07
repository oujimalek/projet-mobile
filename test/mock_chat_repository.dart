import 'dart:async';

import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/message_chat.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/chat_repository.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M2 - Implémentation "en mémoire" de ChatRepository, pour les TESTS.
///
/// Aucun message au départ, et aucune réponse automatique. Mêmes règles que
/// FirebaseChatRepository (ChatRepository.refusMessage). Sans Internet.
class MockChatRepository implements ChatRepository {
  final List<MessageChat> _messages = [];
  int _compteur = 0;

  final StreamController<void> _changements = StreamController<void>.broadcast();

  /// Si ce n'est pas null : lectures et écritures échouent avec ce message.
  String? erreur;

  /// Les messages enregistrés (pour vérifier les tests).
  List<MessageChat> get messages => List.of(_messages);

  /// Ajoute directement un message écrit par [auteur].
  MessageChat ajouterMessageDe(
    Utilisateur auteur,
    String demandeId,
    String texte, {
    bool lu = false,
  }) {
    _compteur++;
    final MessageChat message = MessageChat(
      id: 'm$_compteur',
      demandeId: demandeId,
      auteurId: auteur.id,
      auteurNom: ServiceRepository.nomCourt(auteur),
      texte: texte,
      date: DateTime.now().add(Duration(seconds: _compteur)),
      lu: lu,
    );
    _messages.add(message);
    _changements.add(null);
    return message;
  }

  Utilisateur _moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  String? _refusAcces() {
    if (erreur != null) {
      return erreur;
    }
    final Utilisateur moi = _moi();
    if (moi.id.isEmpty) {
      return 'Tu n\'es pas connecté';
    }
    if ((moi.quartierId ?? '').isEmpty) {
      return 'Choisis d\'abord ton quartier';
    }
    return null;
  }

  List<MessageChat> _de(String demandeId) {
    final List<MessageChat> liste =
        _messages.where((m) => m.demandeId == demandeId).toList();
    liste.sort((a, b) => a.date.compareTo(b.date));
    return liste;
  }

  @override
  Stream<List<MessageChat>> ecouterMessages(String demandeId) async* {
    final String? refus = _refusAcces();
    if (refus != null) {
      throw refus;
    }
    yield _de(demandeId);
    await for (final _ in _changements.stream) {
      yield _de(demandeId);
    }
  }

  @override
  Future<Resultat<void>> envoyerMessage(DemandeService demande, String texte) async {
    final String? acces = _refusAcces();
    if (acces != null) {
      return Resultat.echec(acces);
    }
    final Utilisateur moi = _moi();
    final String? refus = ChatRepository.refusMessage(demande, texte, moi.id);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    ajouterMessageDe(moi, demande.id, texte.trim());
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> marquerCommeLus(String demandeId) async {
    final String? acces = _refusAcces();
    if (acces != null) {
      return Resultat.echec(acces);
    }
    final String moiId = _moi().id;
    bool change = false;
    for (int i = 0; i < _messages.length; i++) {
      final MessageChat message = _messages[i];
      if (message.demandeId == demandeId &&
          message.auteurId != moiId &&
          !message.lu) {
        _messages[i] = MessageChat(
          id: message.id,
          demandeId: message.demandeId,
          auteurId: message.auteurId,
          auteurNom: message.auteurNom,
          texte: message.texte,
          date: message.date,
          lu: true,
        );
        change = true;
      }
    }
    if (change) {
      _changements.add(null);
    }
    return const Resultat.succes(null);
  }
}
