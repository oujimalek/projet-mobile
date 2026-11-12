import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/services/base_locale_m4.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// M4 - Tests de la base SQLite du module (brouillons + historique), sur une
/// base EN MÉMOIRE (sqflite_common_ffi) : rien n'est écrit sur le disque.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Base neuve avant chaque test
  setUp(() async {
    await BaseLocaleM4.fermer();
    BaseLocaleM4.cheminPourTests = inMemoryDatabasePath;
  });

  tearDown(() async {
    await BaseLocaleM4.fermer();
  });

  Evenement evenement(String id, CategorieEvenement categorie, DateTime date) {
    return Evenement(
      id: id, titre: 'Événement $id', description: '', lieu: 'Jardin',
      date: date, organisateur: 'X', categorie: categorie,
    );
  }

  group('Brouillons (CRUD)', () {
    test('créer, lire, modifier, supprimer', () async {
      final int? id = await BaseLocaleM4.enregistrerBrouillon(BrouillonEvenement(
        titre: 'Fête', lieu: 'Jardin', categorie: CategorieEvenement.fete,
        debut: DateTime(2026, 11, 20, 18), places: 10, majLe: DateTime(2026, 11, 11),
      ));
      expect(id, isNotNull);
      List<BrouillonEvenement> liste = await BaseLocaleM4.brouillons();
      expect(liste.single.titre, 'Fête');
      expect(liste.single.debut, DateTime(2026, 11, 20, 18));
      expect(liste.single.places, 10);

      // Modifier (même id : pas de doublon)
      await BaseLocaleM4.enregistrerBrouillon(BrouillonEvenement(
        id: id, titre: 'Grande fête', categorie: CategorieEvenement.fete,
        majLe: DateTime(2026, 11, 12),
      ));
      liste = await BaseLocaleM4.brouillons();
      expect(liste.length, 1);
      expect(liste.single.titre, 'Grande fête');
      expect(await BaseLocaleM4.nombreBrouillons(), 1);

      await BaseLocaleM4.supprimerBrouillon(id!);
      expect(await BaseLocaleM4.brouillons(), isEmpty);
    });

    test('le plus récemment modifié en premier ; brouillon vide détecté', () async {
      await BaseLocaleM4.enregistrerBrouillon(
          BrouillonEvenement(titre: 'Ancien', majLe: DateTime(2026, 11, 1)));
      await BaseLocaleM4.enregistrerBrouillon(
          BrouillonEvenement(titre: 'Récent', majLe: DateTime(2026, 11, 10)));
      final List<BrouillonEvenement> liste = await BaseLocaleM4.brouillons();
      expect(liste.first.titre, 'Récent');
      expect(BrouillonEvenement(titre: '  ', majLe: DateTime(2026)).estVide, isTrue);
    });
  });

  group('Historique + bilan (SQL)', () {
    test('participations, présences, notes, catégorie préférée, par mois', () async {
      final Evenement match1 = evenement('a', CategorieEvenement.sport, DateTime(2026, 10, 5, 18));
      final Evenement match2 = evenement('b', CategorieEvenement.sport, DateTime(2026, 11, 2, 18));
      final Evenement fete = evenement('c', CategorieEvenement.fete, DateTime(2026, 11, 9, 20));
      await BaseLocaleM4.noterParticipation(match1, true);
      await BaseLocaleM4.noterParticipation(match2, true);
      await BaseLocaleM4.noterParticipation(fete, true);
      await BaseLocaleM4.noterPresence(match1);
      await BaseLocaleM4.noterAvis(match1, 5);
      await BaseLocaleM4.noterAvis(fete, 3);

      final BilanHistorique bilan = await BaseLocaleM4.bilan();
      expect(bilan.nbParticipations, 3);
      expect(bilan.nbPresences, 1);
      expect(bilan.tauxPresence, 33);
      expect(bilan.moyenneNotes, 4.0);
      expect(bilan.categoriePreferee, CategorieEvenement.sport);
      expect(bilan.parMois, {'2026-11': 2, '2026-10': 1});

      // Le plus récent d'abord, filtre par catégorie
      expect((await BaseLocaleM4.historique()).first.evenementId, 'c');
      expect((await BaseLocaleM4.historique(categorie: CategorieEvenement.sport)).length, 2);
    });

    test('se retirer : ne compte plus', () async {
      final Evenement fete = evenement('c', CategorieEvenement.fete, DateTime(2026, 11, 9, 20));
      await BaseLocaleM4.noterParticipation(fete, true);
      await BaseLocaleM4.noterParticipation(fete, false);
      expect((await BaseLocaleM4.bilan()).nbParticipations, 0);
      expect(await BaseLocaleM4.historique(), isEmpty);
    });
  });
}
