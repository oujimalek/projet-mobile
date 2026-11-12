import 'dart:convert';

import 'package:http/http.dart' as http;

/// Commun - Notre serveur Cloudflare (push_worker/) limite chaque route
/// par utilisateur et par jour (push_worker/src/limites.js) : améliorer
/// une annonce (M2) et « Qui peut m'aider ? » (M1) 20 fois, idées de
/// l'assistant (M4) 5 fois, annonces push (M4) 10 fois. Au-delà, il répond
/// 429 avec { erreur: "message en français" }.
class LimiteIA {
  LimiteIA._();

  static const int statut = 429;

  /// Si le serveur ne donne pas de message lisible.
  static const String messageParDefaut =
      'Limite du jour atteinte : réessaie demain.';

  /// Le message à montrer si la limite du jour est atteinte, sinon null.
  static String? message(http.Response reponse) {
    if (reponse.statusCode != statut) {
      return null;
    }
    try {
      final Object? corps = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (corps is Map) {
        final Object? erreur = corps['erreur'];
        if (erreur is String && erreur.trim().isNotEmpty) {
          return erreur.trim();
        }
      }
    } catch (e) {
      // corps illisible : message par défaut
    }
    return messageParDefaut;
  }
}
