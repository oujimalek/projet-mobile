import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/services/limite_ia.dart';
import 'package:http/http.dart' as http;

// Commun - Réponse 429 du serveur (limite du jour, push_worker/src/limites.js).
void main() {
  http.Response reponse(int code, Object? corps) {
    return http.Response.bytes(utf8.encode(jsonEncode(corps)), code);
  }

  test('429 : le message du serveur (accents compris)', () {
    expect(
      LimiteIA.message(reponse(429, {'erreur': 'Réessaie demain.'})),
      'Réessaie demain.',
    );
  });

  test('429 sans message lisible : message par défaut', () {
    expect(LimiteIA.message(http.Response('pas du json', 429)),
        LimiteIA.messageParDefaut);
    expect(LimiteIA.message(reponse(429, {'erreur': '  '})),
        LimiteIA.messageParDefaut);
  });

  test('autres réponses : pas de limite', () {
    for (final int code in [200, 400, 403, 500, 502]) {
      expect(LimiteIA.message(reponse(code, {'erreur': 'x'})), isNull);
    }
  });
}
