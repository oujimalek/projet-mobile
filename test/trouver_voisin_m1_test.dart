import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/trouver_voisin_m1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// M1 - "Qui peut m'aider ?" : l'IA choisit des compétences, l'application
// retrouve les voisins. Le serveur est un MockClient : aucune vraie requête.

Utilisateur _voisin(String id, String prenom, List<String> competences) {
  return Utilisateur(
    id: id,
    prenom: prenom,
    nom: 'Test',
    email: '$id@test.tn',
    telephone: '',
    quartier: 'El Yasmine',
    residence: 'El Yasmine',
    quartierId: 'q1',
    competences: competences,
  );
}

final List<Utilisateur> _voisins = [
  _voisin('u1', 'Sami', ['Plomberie', 'Bricolage']),
  _voisin('u2', 'Leila', ['plomberie', 'Cuisine']),
  _voisin('u3', 'Karim', ['Informatique']),
  _voisin('u4', 'Nour', ['Cours de maths']),
  _voisin('u5', 'Hedi', []),
];

void main() {
  late int requetes;
  late Map<String, dynamic> envoye;
  late http.Response reponse;

  setUp(() {
    requetes = 0;
    envoye = {};
    reponse = http.Response(
      jsonEncode({
        'correspondances': [
          {'competence': 'Plomberie', 'raison': 'Une fuite, c\'est de la plomberie.'},
          {'competence': 'Bricolage', 'raison': 'Pour démonter le tuyau.'},
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    TrouverVoisinM1.jeton = () async => 'jeton-test';
    TrouverVoisinM1.client = MockClient((requete) async {
      requetes++;
      envoye = jsonDecode(requete.body) as Map<String, dynamic>;
      return reponse;
    });
  });

  tearDown(TrouverVoisinM1.reinitialiser);

  Future<Resultat<ReponseBesoin>> trouver(String besoin,
      {List<Utilisateur>? voisins}) {
    return TrouverVoisinM1.trouver(
      quartierId: 'q1',
      besoin: besoin,
      voisins: voisins ?? _voisins,
    );
  }

  group('fonctions pures', () {
    test('compétences sans doublon, les plus fréquentes d\'abord', () {
      expect(TrouverVoisinM1.competencesDistinctes(_voisins), [
        'Plomberie', // 2 voisins ("plomberie" = même compétence)
        'Bricolage',
        'Cours de maths',
        'Cuisine',
        'Informatique',
      ]);
    });

    test('au plus 80 compétences, 40 caractères chacune', () {
      final List<Utilisateur> beaucoup = [
        _voisin('x', 'X', [for (int i = 0; i < 100; i++) 'Comp $i', 'a' * 41]),
      ];
      final List<String> liste = TrouverVoisinM1.competencesDistinctes(beaucoup);
      expect(liste.length, 80);
      expect(liste.every((c) => c.length <= 40), isTrue);
    });

    test('voisinsAvec ignore les majuscules', () {
      final List<Utilisateur> qui =
          TrouverVoisinM1.voisinsAvec('PLOMBERIE', _voisins);
      expect(qui.map((v) => v.id), ['u1', 'u2']);
    });

    test('longueur du besoin', () {
      expect(TrouverVoisinM1.besoinValide('ab'), isFalse);
      expect(TrouverVoisinM1.besoinValide('  fuite  '), isTrue);
      expect(TrouverVoisinM1.besoinValide('a' * 301), isFalse);
    });
  });

  group('recherche locale (sans réseau)', () {
    test('mot proche : "plombier" trouve Plomberie', () {
      final List<Correspondance> r =
          TrouverVoisinM1.rechercheLocale('je cherche un plombier', _voisins);
      expect(r.map((c) => c.competence), ['Plomberie']);
      expect(r.first.voisins.length, 2);
    });

    test('dictionnaire : "fuite" et "ordinateur"', () {
      expect(
        TrouverVoisinM1.rechercheLocale('Mon évier a une fuite', _voisins)
            .map((c) => c.competence),
        ['Plomberie'],
      );
      expect(
        TrouverVoisinM1.rechercheLocale('mon ordinateur est lent', _voisins)
            .map((c) => c.competence),
        ['Informatique'],
      );
      expect(
        TrouverVoisinM1.rechercheLocale('aide pour les devoirs', _voisins)
            .map((c) => c.competence),
        ['Cours de maths'],
      );
    });

    test('rien de proche : liste vide', () {
      expect(TrouverVoisinM1.rechercheLocale('un parapluie', _voisins), isEmpty);
    });
  });

  group('lecture de la réponse', () {
    test('compétence inventée ou en double : ignorée', () {
      final List<Correspondance>? r = TrouverVoisinM1.depuisReponse({
        'correspondances': [
          {'competence': 'plomberie', 'raison': 'a'},
          {'competence': 'Plomberie', 'raison': 'doublon'},
          {'competence': 'Astronaute', 'raison': 'inventée'},
          'pas un objet',
          {'competence': 'Cuisine'},
        ],
      }, _voisins);
      expect(r!.map((c) => c.competence), ['Plomberie', 'Cuisine']);
      expect(r.first.voisins.map((v) => v.id), ['u1', 'u2']);
      expect(r.last.raison, '');
    });

    test('au plus 3', () {
      final List<Correspondance>? r = TrouverVoisinM1.depuisReponse({
        'correspondances': [
          for (final c in ['Plomberie', 'Bricolage', 'Cuisine', 'Informatique'])
            {'competence': c},
        ],
      }, _voisins);
      expect(r!.length, 3);
    });

    test('réponse mal formée : null', () {
      expect(TrouverVoisinM1.depuisReponse(null, _voisins), isNull);
      expect(TrouverVoisinM1.depuisReponse({'x': 1}, _voisins), isNull);
      expect(TrouverVoisinM1.depuisReponse([1], _voisins), isNull);
    });
  });

  group('trouver (serveur simulé)', () {
    test('réponse de l\'IA, voisins retrouvés', () async {
      final Resultat<ReponseBesoin> r = await trouver('ma machine à laver fuit');
      expect(r.estSucces, isTrue);
      expect(r.donnee!.parIA, isTrue);
      expect(r.donnee!.correspondances.map((c) => c.competence),
          ['Plomberie', 'Bricolage']);
      expect(r.donnee!.correspondances.first.raison, contains('plomberie'));
      expect(requetes, 1);
    });

    test('aucun nom ni identifiant envoyé', () async {
      await trouver('ma machine à laver fuit');
      expect(envoye.keys.toSet(),
          {'idToken', 'quartierId', 'besoin', 'competences'});
      final String corps = jsonEncode(envoye);
      for (final Utilisateur v in _voisins) {
        expect(corps.contains(v.prenom), isFalse);
        expect(corps.contains(v.email), isFalse);
        expect(corps.contains('"${v.id}"'), isFalse);
      }
    });

    test('besoin trop court : échec, aucune requête', () async {
      final Resultat<ReponseBesoin> r = await trouver('a');
      expect(r.estSucces, isFalse);
      expect(requetes, 0);
    });

    test('personne n\'a de compétence : liste vide, aucune requête', () async {
      final Resultat<ReponseBesoin> r =
          await trouver('une fuite', voisins: [_voisin('u5', 'Hedi', [])]);
      expect(r.donnee!.correspondances, isEmpty);
      expect(requetes, 0);
    });

    test('pas de réseau : recherche locale', () async {
      TrouverVoisinM1.client = MockClient((requete) async {
        throw const SocketException('pas de réseau');
      });
      final Resultat<ReponseBesoin> r = await trouver('mon robinet fuit');
      expect(r.donnee!.parIA, isFalse);
      expect(r.donnee!.correspondances.map((c) => c.competence), ['Plomberie']);
    });

    test('pas connecté : recherche locale, aucune requête', () async {
      TrouverVoisinM1.jeton = () async => null;
      final Resultat<ReponseBesoin> r = await trouver('mon robinet fuit');
      expect(r.donnee!.parIA, isFalse);
      expect(requetes, 0);
    });

    test('serveur 403 : recherche locale', () async {
      reponse = http.Response('{"erreur":"x"}', 403);
      final Resultat<ReponseBesoin> r = await trouver('mon robinet fuit');
      expect(r.donnee!.parIA, isFalse);
    });

    test('réponse mal formée : recherche locale', () async {
      reponse = http.Response('{"autre":1}', 200);
      final Resultat<ReponseBesoin> r = await trouver('mon robinet fuit');
      expect(r.donnee!.parIA, isFalse);
    });

    test('trop lent : recherche locale', () async {
      TrouverVoisinM1.delaiMax = const Duration(milliseconds: 50);
      TrouverVoisinM1.client = MockClient((requete) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return reponse;
      });
      final Resultat<ReponseBesoin> r = await trouver('mon robinet fuit');
      expect(r.donnee!.parIA, isFalse);
    });
  });
}
