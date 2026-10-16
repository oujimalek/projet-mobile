import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/demande_service.dart';
import '../models/message_chat.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'chat_repository.dart';
import 'firebase_service_repository.dart';
import 'firestore_commun.dart';
import 'service_repository.dart';

/// M2 - Version Cloud Firestore de ChatRepository (celle de l'application).
///
/// Écrit UNIQUEMENT dans quartiers/{q}/demandes/{demandeId}/messages.
class FirebaseChatRepository implements ChatRepository {
  CollectionReference<Map<String, dynamic>> _messages(String demandeId) {
    return ContexteM2.collection('demandes').doc(demandeId).collection('messages');
  }

  @override
  Stream<List<MessageChat>> ecouterMessages(String demandeId) {
    return ContexteM2.proteger(() {
      return _messages(demandeId).orderBy('date').snapshots().map((s) {
        final List<MessageChat> liste = [];
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs) {
          liste.add(MessageChat.fromMap(d.id, demandeId, d.data()));
        }
        return liste;
      });
    });
  }

  @override
  Future<Resultat<void>> envoyerMessage(DemandeService demande, String texte) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final String? refus = ChatRepository.refusMessage(demande, texte, utilisateur.id);
      if (refus != null) {
        throw RefusM2(refus);
      }
      final MessageChat message = MessageChat(
        id: '',
        demandeId: demande.id,
        auteurId: utilisateur.id,
        auteurNom: ServiceRepository.nomCourt(utilisateur),
        texte: texte.trim(),
        date: DateTime.now(),
        lu: false,
      );
      await _messages(demande.id).add(message.toMap());
    });
  }

  @override
  Future<Resultat<void>> marquerCommeLus(String demandeId) {
    return ContexteM2.executer(() async {
      final Utilisateur utilisateur = ContexteM2.connecte();
      final QuerySnapshot<Map<String, dynamic>> nonLus =
          await _messages(demandeId).where('lu', isEqualTo: false).get();
      // Les règles n'autorisent que le destinataire : jamais mes propres messages
      final WriteBatch batch = FirestoreCommun.base.batch();
      int nombre = 0;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in nonLus.docs) {
        if (d.data()['auteurId'] != utilisateur.id) {
          batch.update(d.reference, {'lu': true});
          nombre++;
        }
      }
      if (nombre > 0) {
        await batch.commit();
      }
    });
  }
}
