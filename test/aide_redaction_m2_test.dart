import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/aide_redaction_m2.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// M2 - "Améliorer avec l'IA". Le serveur est remplacé par un MockClient et
// le jeton Firebase par une fonction : aucune vraie requête.

void main() {
  late int requetes;
  late Map<String, dynamic> envoye;
  late http.Response reponse;

  setUp(() {
    requetes = 0;
    envoye = {};
    reponse = http.Response(
      jsonEncode({
        'titre': 'Perceuse à prêter',
        'description': 'Je prête ma perceuse ce week-end. Passez me voir.',
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    AideRedactionM2.jeton = () async => 'jeton-test';
    AideRedactionM2.client = MockClient((requete) async {
      requetes++;
      envoye = jsonDecode(requete.body) as Map<String, dynamic>;
      return reponse;
    });
  });

  tearDown(AideRedactionM2.reinitialiser);

  Future<Resultat<AnnonceProposee>> ameliorer({
    String titre = 'perceuse a preter',
    String description = 'je prete ma perceuse ce weekend',
    String quartierId = 'q1',
  }) {
    return AideRedactionM2.ameliorer(
      quartierId: quartierId,
      titre: titre,
      description: description,
      categorie: 'Bricolage',
    );
  }

  group('mise en forme locale', () {
    test('espaces, majuscules et ponctuation', () {
      final AnnonceProposee a = AideRedactionM2.rangerLocalement(
        '  perceuse   a preter. ',
        'je prete ma perceuse ,elle marche bien.passez me voir',
      );
      expect(a.titre, 'Perceuse a preter');
      expect(a.description,
          'Je prete ma perceuse, elle marche bien. Passez me voir.');
      expect(a.parIA, isFalse);
    });

    test('les nombres et les fins ! ? sont gardés', () {
      final AnnonceProposee a = AideRedactionM2.rangerLocalement(
        'cours de maths',
        'prix 12.5 dinars, 3,5 heures. qui est partant ?',
      );
      expect(a.description, 'Prix 12.5 dinars, 3,5 heures. Qui est partant ?');
    });

    test('textes trop longs coupés (60 / 400)', () {
      final AnnonceProposee a =
          AideRedactionM2.rangerLocalement('a' * 100, 'b' * 500);
      expect(a.titre.length, AideRedactionM2.titreMax);
      expect(a.description.length, AideRedactionM2.descriptionMax);
    });
  });

  group('lecture de la réponse', () {
    test('réponse valide', () {
      final AnnonceProposee? a = AideRedactionM2.depuisReponse(
          {'titre': 'Échelle', 'description': 'Je cherche une échelle.'});
      expect(a!.titre, 'Échelle');
      expect(a.parIA, isTrue);
    });

    test('réponses invalides', () {
      expect(AideRedactionM2.depuisReponse(null), isNull);
      expect(AideRedactionM2.depuisReponse([1, 2]), isNull);
      expect(AideRedactionM2.depuisReponse({'titre': 'ok'}), isNull);
      expect(
        AideRedactionM2.depuisReponse({'titre': 'x', 'description': 'assez long ici'}),
        isNull,
      );
    });
  });

  group('ameliorer (serveur simulé)', () {
    test('proposition de l\'IA, envoi sans nom de personne', () async {
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.estSucces, isTrue);
      expect(r.donnee!.parIA, isTrue);
      expect(r.donnee!.titre, 'Perceuse à prêter'); // accents (utf8)
      expect(requetes, 1);
      expect(envoye.keys.toSet(),
          {'idToken', 'quartierId', 'titre', 'description', 'categorie'});
      expect(envoye['idToken'], 'jeton-test');
      expect(envoye['quartierId'], 'q1');
    });

    test('textes trop longs coupés avant l\'envoi (120 / 1000)', () async {
      await ameliorer(titre: 't' * 200, description: 'd' * 2000);
      expect((envoye['titre'] as String).length, 120);
      expect((envoye['description'] as String).length, 1000);
    });

    test('texte vide : échec, aucune requête', () async {
      final Resultat<AnnonceProposee> r =
          await ameliorer(titre: ' ', description: '');
      expect(r.estSucces, isFalse);
      expect(requetes, 0);
    });

    test('pas connecté : mise en forme locale, aucune requête', () async {
      AideRedactionM2.jeton = () async => null;
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.donnee!.parIA, isFalse);
      expect(r.donnee!.titre, 'Perceuse a preter');
      expect(requetes, 0);
    });

    test('sans quartier : mise en forme locale, aucune requête', () async {
      final Resultat<AnnonceProposee> r = await ameliorer(quartierId: '');
      expect(r.donnee!.parIA, isFalse);
      expect(requetes, 0);
    });

    test('pas de réseau : mise en forme locale', () async {
      AideRedactionM2.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.estSucces, isTrue);
      expect(r.donnee!.parIA, isFalse);
    });

    for (final int code in [403, 502, 500]) {
      test('serveur $code : mise en forme locale', () async {
        reponse = http.Response('{"erreur":"x"}', code);
        final Resultat<AnnonceProposee> r = await ameliorer();
        expect(r.donnee!.parIA, isFalse);
      });
    }

    test('limite du jour (429) : mise en forme locale + message du serveur',
        () async {
      reponse = http.Response.bytes(
        utf8.encode(jsonEncode({'erreur': 'Limite atteinte. Réessaie demain.'})),
        429,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.donnee!.parIA, isFalse);
      expect(r.donnee!.titre, 'Perceuse a preter');
      expect(r.donnee!.limite, 'Limite atteinte. Réessaie demain.');
    });

    test('autre erreur : pas de message de limite', () async {
      reponse = http.Response('{"erreur":"x"}', 502);
      expect((await ameliorer()).donnee!.limite, isNull);
    });

    test('réponse illisible : mise en forme locale', () async {
      reponse = http.Response('pas du json', 200);
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.donnee!.parIA, isFalse);
    });

    test('trop lent : mise en forme locale après le délai', () async {
      AideRedactionM2.delaiMax = const Duration(milliseconds: 50);
      AideRedactionM2.client = MockClient((requete) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return reponse;
      });
      final Resultat<AnnonceProposee> r = await ameliorer();
      expect(r.donnee!.parIA, isFalse);
    });
  });
}
