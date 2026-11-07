import '../models/demande_service.dart';
import '../models/message_chat.dart';
import '../models/statut_demande.dart';
import '../resultat.dart';
import 'firebase_chat_repository.dart';

/// M2 - Accès aux messages du chat entre le demandeur et l'auteur d'un
/// service : le CONTRAT.
///
/// Implémentations :
/// - FirebaseChatRepository : Cloud Firestore, sous-collection
///   quartiers/{q}/demandes/{demandeId}/messages (celle de l'application) ;
/// - MockChatRepository (dans test/) : messages en mémoire pour les tests.
///
/// Les messages arrivent en direct (Stream) : plus d'écouteur manuel.
abstract class ChatRepository {
  /// Longueur maximale d'un message.
  static const int longueurMax = 500;

  /// L'implémentation utilisée par toute l'application.
  static ChatRepository instance = FirebaseChatRepository();

  /// `ChatRepository()` renvoie l'instance ci-dessus (pas de nouvel objet).
  factory ChatRepository() {
    return instance;
  }

  // =====================================================================
  // Règles et calculs sans réseau (communs à Firebase et au mock)
  // =====================================================================

  /// true si [moiId] peut discuter pour cette demande : elle doit être
  /// acceptée ou réalisée, et je suis le demandeur ou l'auteur du service.
  static bool peutDiscuter(DemandeService demande, String moiId) {
    if (demande.statut != StatutDemande.acceptee &&
        demande.statut != StatutDemande.realisee) {
      return false;
    }
    return demande.demandeurId == moiId || demande.auteurServiceId == moiId;
  }

  /// Le nom de l'autre personne de la conversation.
  static String interlocuteur(DemandeService demande, String moiId) {
    if (demande.demandeurId == moiId) {
      return demande.auteurServiceNom;
    }
    return demande.demandeurNom;
  }

  /// Pourquoi ce [texte] ne peut pas être envoyé (null : il peut).
  static String? refusMessage(DemandeService demande, String texte, String moiId) {
    if (!peutDiscuter(demande, moiId)) {
      return 'Le chat est disponible une fois la demande acceptée';
    }
    final String propre = texte.trim();
    if (propre.isEmpty) {
      return 'Écris un message';
    }
    if (propre.length > longueurMax) {
      return 'Message trop long ($longueurMax caractères au maximum)';
    }
    return null;
  }

  /// Le nombre de messages de l'autre personne que [moiId] n'a pas lus.
  static int compterNonLus(List<MessageChat> messages, String moiId) {
    int total = 0;
    for (final MessageChat message in messages) {
      if (message.auteurId != moiId && !message.lu) {
        total++;
      }
    }
    return total;
  }

  // =====================================================================
  // Lecture et écriture
  // =====================================================================

  /// Les messages d'une demande, du plus ancien au plus récent, en direct.
  Stream<List<MessageChat>> ecouterMessages(String demandeId);

  /// Envoie un message pour cette demande (voir [refusMessage]).
  Future<Resultat<void>> envoyerMessage(DemandeService demande, String texte);

  /// Marque comme lus les messages de l'interlocuteur dans cette demande.
  Future<Resultat<void>> marquerCommeLus(String demandeId);
}
