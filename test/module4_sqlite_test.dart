import 'dart:io';

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

  // L'utilisateur connecté vu par la base (les tests le changent)
  String moi = 'u1';

  // Base neuve avant chaque test
  setUp(() async {
    await BaseLocaleM4.fermer();
    BaseLocaleM4.cheminPourTests = inMemoryDatabasePath;
    moi = 'u1';
    BaseLocaleM4.utilisateurActuel = () => moi;
  });

  tearDown(() async {
    await BaseLocaleM4.fermer();
    BaseLocaleM4.utilisateurActuel = BaseLocaleM4.uidConnecte;
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

  group('Plusieurs comptes sur le même téléphone', () {
    test('brouillons : chacun les siens (lire, compter, modifier, supprimer)',
        () async {
      final int? id = await BaseLocaleM4.enregistrerBrouillon(
          BrouillonEvenement(titre: 'Fête de u1', majLe: DateTime(2026, 11, 1)));

      moi = 'u2';
      expect(await BaseLocaleM4.brouillons(), isEmpty);
      expect(await BaseLocaleM4.nombreBrouillons(), 0);
      // u2 ne peut ni modifier ni supprimer le brouillon de u1
      await BaseLocaleM4.enregistrerBrouillon(BrouillonEvenement(
          id: id, titre: 'Piraté', majLe: DateTime(2026, 11, 2)));
      await BaseLocaleM4.supprimerBrouillon(id!);

      moi = 'u1';
      expect((await BaseLocaleM4.brouillons()).single.titre, 'Fête de u1');
      expect(await BaseLocaleM4.nombreBrouillons(), 1);
    });

    test('historique et bilan (COUNT, AVG, GROUP BY) par compte', () async {
      final Evenement match = evenement('a', CategorieEvenement.sport, DateTime(2026, 10, 5, 18));
      final Evenement fete = evenement('c', CategorieEvenement.fete, DateTime(2026, 11, 9, 20));
      // u1 : le match (présent, note 5)
      await BaseLocaleM4.noterParticipation(match, true);
      await BaseLocaleM4.noterPresence(match);
      await BaseLocaleM4.noterAvis(match, 5);
      // u2 : le MÊME match et la fête (note 1), absent
      moi = 'u2';
      await BaseLocaleM4.noterParticipation(match, true);
      await BaseLocaleM4.noterParticipation(fete, true);
      await BaseLocaleM4.noterAvis(fete, 1);

      final BilanHistorique bilanU2 = await BaseLocaleM4.bilan();
      expect(bilanU2.nbParticipations, 2);
      expect(bilanU2.nbPresences, 0);
      expect(bilanU2.moyenneNotes, 1.0);
      expect(bilanU2.parMois, {'2026-11': 1, '2026-10': 1});
      expect((await BaseLocaleM4.historique()).length, 2);

      moi = 'u1';
      final BilanHistorique bilanU1 = await BaseLocaleM4.bilan();
      expect(bilanU1.nbParticipations, 1);
      expect(bilanU1.nbPresences, 1);
      expect(bilanU1.moyenneNotes, 5.0);
      expect(bilanU1.categoriePreferee, CategorieEvenement.sport);
      expect(bilanU1.parMois, {'2026-10': 1});
      expect((await BaseLocaleM4.historique()).single.evenementId, 'a');

      // u1 se retire : la participation de u2 au même match reste
      await BaseLocaleM4.noterParticipation(match, false);
      moi = 'u2';
      expect((await BaseLocaleM4.bilan()).nbParticipations, 2);
    });
  });

  group('Migration version 1 → 2', () {
    late Directory dossier;
    late String chemin;

    setUp(() async {
      dossier = Directory.systemTemp.createTempSync('houmani_m4_v1_');
      chemin = '${dossier.path}/houmani_m4.db';
      // Un téléphone resté en version 1 (sans utilisateur_id), avec des données
      final Database ancienne = await databaseFactory.openDatabase(
        chemin,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE brouillons (id INTEGER PRIMARY KEY '
                'AUTOINCREMENT, titre TEXT NOT NULL, '
                "description TEXT NOT NULL DEFAULT '', lieu TEXT NOT NULL DEFAULT '', "
                'categorie TEXT NOT NULL, debut INTEGER, fin INTEGER, '
                'places INTEGER NOT NULL DEFAULT 0, maj_le INTEGER NOT NULL)');
            await db.execute('CREATE TABLE historique (evenement_id TEXT PRIMARY KEY, '
                'titre TEXT NOT NULL, categorie TEXT NOT NULL, date INTEGER NOT NULL, '
                'participe INTEGER NOT NULL DEFAULT 1, '
                'present INTEGER NOT NULL DEFAULT 0, note INTEGER)');
          },
        ),
      );
      await ancienne.insert('brouillons',
          {'titre': 'Ancien brouillon', 'categorie': 'fete', 'maj_le': 1});
      await ancienne.insert('historique', {'evenement_id': 'e1', 'titre': 'Match',
          'categorie': 'sport', 'date': DateTime(2026, 10, 5).millisecondsSinceEpoch,
          'participe': 1, 'present': 1, 'note': 4});
      await ancienne.close();
      await BaseLocaleM4.fermer();
      BaseLocaleM4.cheminPourTests = chemin;
    });

    tearDown(() async {
      await BaseLocaleM4.fermer();
      dossier.deleteSync(recursive: true);
    });

    test('les anciennes lignes vont au premier compte connecté', () async {
      expect((await BaseLocaleM4.brouillons()).single.titre, 'Ancien brouillon');
      final BilanHistorique bilan = await BaseLocaleM4.bilan();
      expect(bilan.nbParticipations, 1);
      expect(bilan.nbPresences, 1);
      expect(bilan.moyenneNotes, 4.0);

      // Un autre compte ne les voit pas, même après réouverture
      await BaseLocaleM4.fermer();
      moi = 'u2';
      expect(await BaseLocaleM4.brouillons(), isEmpty);
      expect((await BaseLocaleM4.bilan()).nbParticipations, 0);
    });
  });
}
