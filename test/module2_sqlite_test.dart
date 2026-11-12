import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/services/base_locale_m2.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// M2 - Base SQLite du module Services (favoris, consultations, brouillon).
// Base en mémoire (sqflite_common_ffi) : chaque test repart d'une base vide.
Service _service(String id, String titre, String categorie,
    {bool estOffre = true}) {
  return Service(
    id: id,
    titre: titre,
    description: 'Description du service $titre',
    categorie: categorie,
    auteurNom: 'Voisin $id',
    estOffre: estOffre,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // L'utilisateur connecté vu par la base (les tests le changent)
  String moi = 'u1';

  setUp(() async {
    await BaseLocaleM2.fermer();
    BaseLocaleM2.cheminPourTests = inMemoryDatabasePath;
    moi = 'u1';
    BaseLocaleM2.utilisateurActuel = () => moi;
  });

  tearDown(() async {
    await BaseLocaleM2.fermer();
    BaseLocaleM2.utilisateurActuel = BaseLocaleM2.uidConnecte;
  });

  group('plusieurs comptes sur le même téléphone', () {
    test('chacun ne voit que ses favoris, consultations et brouillon', () async {
      final Service perceuse = _service('s1', 'Perceuse', 'Prêt d\'outils');
      await BaseLocaleM2.ajouterFavori(perceuse);
      await BaseLocaleM2.noterConsultation(perceuse);
      await BaseLocaleM2.enregistrerBrouillon(
          BrouillonService(titre: 'Cours de maths', majLe: DateTime(2026, 11, 1)));

      moi = 'u2';
      expect(await BaseLocaleM2.favoris(), isEmpty);
      expect(await BaseLocaleM2.estFavori('s1'), isFalse);
      expect(await BaseLocaleM2.vusRecemment(), isEmpty);
      expect(await BaseLocaleM2.categoriesPreferees(), isEmpty);
      expect(await BaseLocaleM2.lireBrouillon(), isNull);

      // u2 met le MÊME service en favori, puis le retire : u1 le garde
      await BaseLocaleM2.ajouterFavori(perceuse);
      expect(await BaseLocaleM2.estFavori('s1'), isTrue);
      await BaseLocaleM2.retirerFavori('s1');
      // u2 a son propre brouillon ; le supprimer ne touche pas celui de u1
      await BaseLocaleM2.enregistrerBrouillon(
          BrouillonService(titre: 'Vélo', majLe: DateTime(2026, 11, 2)));
      await BaseLocaleM2.supprimerBrouillon();

      moi = 'u1';
      expect(await BaseLocaleM2.idsFavoris(), {'s1'});
      expect(await BaseLocaleM2.vusRecemment(), {'s1': 'Perceuse'});
      expect(await BaseLocaleM2.categoriesPreferees(), {'Prêt d\'outils': 1});
      expect((await BaseLocaleM2.lireBrouillon())!.titre, 'Cours de maths');
    });

    test('les jours fériés (publics) sont partagés', () async {
      await BaseLocaleM2.enregistrerJoursFeries(2026, {'2026-12-17': 'Révolution'});
      moi = 'u2';
      expect(await BaseLocaleM2.joursFeries(2026), {'2026-12-17': 'Révolution'});
    });

    test('la limite de consultations est comptée par compte', () async {
      for (int i = 0; i < BaseLocaleM2.maxConsultations; i++) {
        await BaseLocaleM2.noterConsultation(_service('a$i', 'A', 'Cuisine'),
            date: DateTime(2026, 1, 1).add(Duration(minutes: i)));
      }
      moi = 'u2';
      await BaseLocaleM2.noterConsultation(_service('b', 'B', 'Cuisine'));
      moi = 'u1';
      // u1 garde ses 100 consultations : celle de u2 n'en a effacé aucune
      expect(await BaseLocaleM2.categoriesPreferees(),
          {'Cuisine': BaseLocaleM2.maxConsultations});
    });
  });

  group('migration version 2 → 3', () {
    late Directory dossier;
    late String chemin;

    setUp(() async {
      dossier = Directory.systemTemp.createTempSync('houmani_m2_v2_');
      chemin = '${dossier.path}/houmani_m2.db';
      // Un téléphone resté en version 2 (sans utilisateur_id), avec des données
      final Database ancienne = await databaseFactory.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE favoris (service_id TEXT PRIMARY KEY, '
                'titre TEXT NOT NULL, categorie TEXT NOT NULL, '
                "auteur_nom TEXT NOT NULL DEFAULT '', "
                'est_offre INTEGER NOT NULL DEFAULT 1, ajoute_le INTEGER NOT NULL)');
            await db.execute('CREATE TABLE consultations (id INTEGER PRIMARY KEY '
                'AUTOINCREMENT, service_id TEXT NOT NULL, titre TEXT NOT NULL, '
                'categorie TEXT NOT NULL, date INTEGER NOT NULL)');
            await db.execute('CREATE TABLE brouillon_service (id INTEGER PRIMARY '
                "KEY CHECK (id = 1), titre TEXT NOT NULL DEFAULT '', "
                "description TEXT NOT NULL DEFAULT '', "
                "disponibilite TEXT NOT NULL DEFAULT '', categorie TEXT, "
                'est_offre INTEGER NOT NULL DEFAULT 1, maj_le INTEGER NOT NULL)');
            await db.execute('CREATE TABLE jours_feries (date TEXT PRIMARY KEY, '
                'annee INTEGER NOT NULL, nom TEXT NOT NULL)');
          },
        ),
      );
      await ancienne.insert('favoris', {'service_id': 's1', 'titre': 'Perceuse',
          'categorie': 'Outils', 'auteur_nom': 'Sami', 'est_offre': 1, 'ajoute_le': 1});
      await ancienne.insert('consultations',
          {'service_id': 's1', 'titre': 'Perceuse', 'categorie': 'Outils', 'date': 1});
      await ancienne.insert('brouillon_service', {'id': 1, 'titre': 'Ancien brouillon',
          'est_offre': 1, 'maj_le': 1});
      await ancienne.insert('jours_feries',
          {'date': '2026-12-17', 'annee': 2026, 'nom': 'Révolution'});
      await ancienne.close();
      await BaseLocaleM2.fermer();
      BaseLocaleM2.cheminPourTests = chemin;
    });

    tearDown(() async {
      await BaseLocaleM2.fermer();
      dossier.deleteSync(recursive: true);
    });

    test('les anciennes lignes vont au premier compte connecté', () async {
      expect(await BaseLocaleM2.idsFavoris(), {'s1'});
      expect(await BaseLocaleM2.vusRecemment(), {'s1': 'Perceuse'});
      expect((await BaseLocaleM2.lireBrouillon())!.titre, 'Ancien brouillon');
      expect(await BaseLocaleM2.joursFeries(2026), {'2026-12-17': 'Révolution'});

      // Un autre compte ne les voit pas, même après réouverture
      await BaseLocaleM2.fermer();
      moi = 'u2';
      expect(await BaseLocaleM2.favoris(), isEmpty);
      expect(await BaseLocaleM2.lireBrouillon(), isNull);
    });

    test('base ouverte sans compte connecté : lignes gardées pour plus tard',
        () async {
      moi = '';
      expect(await BaseLocaleM2.favoris(), isEmpty);
      moi = 'u1';
      expect(await BaseLocaleM2.idsFavoris(), {'s1'});
    });
  });

  group('favoris', () {
    test('base vide : aucun favori', () async {
      expect(await BaseLocaleM2.favoris(), isEmpty);
      expect(await BaseLocaleM2.estFavori('s1'), isFalse);
    });

    test('basculer ajoute puis retire', () async {
      final Service perceuse = _service('s1', 'Perceuse', 'Prêt d\'outils');
      expect(await BaseLocaleM2.basculerFavori(perceuse), isTrue);
      expect(await BaseLocaleM2.estFavori('s1'), isTrue);
      expect(await BaseLocaleM2.basculerFavori(perceuse), isFalse);
      expect(await BaseLocaleM2.estFavori('s1'), isFalse);
    });

    test('les favoris gardent titre et catégorie, le plus récent d\'abord',
        () async {
      await BaseLocaleM2.ajouterFavori(
        _service('s1', 'Perceuse', 'Prêt d\'outils'),
        date: DateTime(2026, 1, 1),
      );
      await BaseLocaleM2.ajouterFavori(
        _service('s2', 'Courses du samedi', 'Courses', estOffre: false),
        date: DateTime(2026, 1, 2),
      );
      final List<FavoriService> favoris = await BaseLocaleM2.favoris();
      expect(favoris.length, 2);
      expect(favoris.first.serviceId, 's2');
      expect(favoris.first.titre, 'Courses du samedi');
      expect(favoris.first.estOffre, isFalse);
      expect(favoris.last.categorie, 'Prêt d\'outils');
      expect(await BaseLocaleM2.idsFavoris(), {'s1', 's2'});
    });

    test('ajouter deux fois le même service : une seule ligne', () async {
      final Service perceuse = _service('s1', 'Perceuse', 'Prêt d\'outils');
      await BaseLocaleM2.ajouterFavori(perceuse);
      await BaseLocaleM2.ajouterFavori(perceuse);
      expect((await BaseLocaleM2.favoris()).length, 1);
    });
  });

  group('consultations', () {
    test('vus récemment : chaque service une fois, le plus récent d\'abord',
        () async {
      final Service a = _service('a', 'Perceuse', 'Bricolage');
      final Service b = _service('b', 'Garde du soir', 'Garde d\'enfants');
      final Service c = _service('c', 'Courses', 'Courses');
      await BaseLocaleM2.noterConsultation(a, date: DateTime(2026, 1, 1, 10));
      await BaseLocaleM2.noterConsultation(b, date: DateTime(2026, 1, 1, 11));
      await BaseLocaleM2.noterConsultation(a, date: DateTime(2026, 1, 1, 12));
      await BaseLocaleM2.noterConsultation(c, date: DateTime(2026, 1, 1, 9));

      final Map<String, String> vus = await BaseLocaleM2.vusRecemment();
      expect(vus.keys.toList(), ['a', 'b', 'c']);
      expect(vus['b'], 'Garde du soir');

      final Map<String, String> deux =
          await BaseLocaleM2.vusRecemment(limite: 2);
      expect(deux.keys.toList(), ['a', 'b']);
    });

    test('catégories préférées : COUNT + GROUP BY, la plus vue d\'abord',
        () async {
      await BaseLocaleM2.noterConsultation(_service('a', 'A', 'Bricolage'));
      await BaseLocaleM2.noterConsultation(_service('b', 'B', 'Bricolage'));
      await BaseLocaleM2.noterConsultation(_service('a', 'A', 'Bricolage'));
      await BaseLocaleM2.noterConsultation(_service('c', 'C', 'Courses'));

      final Map<String, int> categories =
          await BaseLocaleM2.categoriesPreferees();
      expect(categories, {'Bricolage': 3, 'Courses': 1});
      expect(categories.keys.first, 'Bricolage');
    });

    test('la table ne garde que les dernières consultations', () async {
      final Service a = _service('a', 'A', 'Bricolage');
      final DateTime debut = DateTime(2026, 1, 1);
      for (int i = 0; i < BaseLocaleM2.maxConsultations + 10; i++) {
        await BaseLocaleM2.noterConsultation(
          a,
          date: debut.add(Duration(minutes: i)),
        );
      }
      final Map<String, int> categories =
          await BaseLocaleM2.categoriesPreferees();
      expect(categories['Bricolage'], BaseLocaleM2.maxConsultations);
    });
  });

  group('brouillon de publication', () {
    test('pas de brouillon au départ', () async {
      expect(await BaseLocaleM2.lireBrouillon(), isNull);
    });

    test('enregistrer puis relire', () async {
      await BaseLocaleM2.enregistrerBrouillon(BrouillonService(
        titre: 'Échelle à prêter',
        description: 'Une grande échelle',
        disponibilite: 'Ce week-end',
        categorie: 'Prêt d\'outils',
        estOffre: true,
        majLe: DateTime(2026, 1, 1),
      ));
      final BrouillonService? brouillon = await BaseLocaleM2.lireBrouillon();
      expect(brouillon, isNotNull);
      expect(brouillon!.titre, 'Échelle à prêter');
      expect(brouillon.disponibilite, 'Ce week-end');
      expect(brouillon.categorie, 'Prêt d\'outils');
      expect(brouillon.estOffre, isTrue);
    });

    test('un seul brouillon : le nouveau remplace l\'ancien', () async {
      await BaseLocaleM2.enregistrerBrouillon(
        BrouillonService(titre: 'Premier', majLe: DateTime(2026, 1, 1)),
      );
      await BaseLocaleM2.enregistrerBrouillon(BrouillonService(
        titre: 'Second',
        estOffre: false,
        majLe: DateTime(2026, 1, 2),
      ));
      final BrouillonService? brouillon = await BaseLocaleM2.lireBrouillon();
      expect(brouillon!.titre, 'Second');
      expect(brouillon.estOffre, isFalse);
      expect(brouillon.categorie, isNull);
    });

    test('un brouillon vide efface l\'ancien', () async {
      await BaseLocaleM2.enregistrerBrouillon(
        BrouillonService(titre: 'Premier', majLe: DateTime(2026, 1, 1)),
      );
      await BaseLocaleM2.enregistrerBrouillon(
        BrouillonService(titre: '   ', majLe: DateTime(2026, 1, 2)),
      );
      expect(await BaseLocaleM2.lireBrouillon(), isNull);
    });

    test('supprimer le brouillon (après publication)', () async {
      await BaseLocaleM2.enregistrerBrouillon(
        BrouillonService(titre: 'Premier', majLe: DateTime(2026, 1, 1)),
      );
      await BaseLocaleM2.supprimerBrouillon();
      expect(await BaseLocaleM2.lireBrouillon(), isNull);
    });
  });
}
