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

  setUp(() async {
    await BaseLocaleM2.fermer();
    BaseLocaleM2.cheminPourTests = inMemoryDatabasePath;
  });

  tearDown(() async {
    await BaseLocaleM2.fermer();
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
