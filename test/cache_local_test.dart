import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/services/cache_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Tests de la base SQLite du module 1 (houmani_m1.db), dans un dossier
// temporaire (sqflite_common_ffi : SQLite sur l'ordinateur).
void main() {
  late Directory dossier;
  late CacheLocal cache;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final Utilisateur amira = Utilisateur(
    id: 'u1',
    prenom: 'Amira',
    nom: 'Ben Salah',
    email: 'amira@houmani.tn',
    telephone: '+216 22 345 678',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc B',
    logement: 'Bloc B - Appt 12',
    statut: StatutUtilisateur.refuse,
    role: RoleUtilisateur.admin,
    competences: const ['Bricolage', 'Informatique'],
    avatar: 'chat',
    motif: 'Logement inconnu',
    dateDemande: DateTime.fromMillisecondsSinceEpoch(1760000000123),
  );

  Utilisateur voisin(String id, String prenom, List<String> competences) {
    return Utilisateur(
      id: id,
      prenom: prenom,
      nom: 'Test',
      email: '',
      telephone: '2000000$id',
      quartier: '',
      residence: '',
      logement: 'Bloc $id',
      competences: competences,
    );
  }

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('houmani_cache_');
    cache = CacheLocal(dossier: dossier.path);
  });

  tearDown(() async {
    await cache.fermer();
    try {
      dossier.deleteSync(recursive: true);
    } catch (e) {
      // Windows peut garder le fichier un moment : on ignore
    }
  });

  group('CacheLocal : profil et quartier', () {
    test('base vide : lireUtilisateur renvoie null', () async {
      expect(await cache.lireUtilisateur(), isNull);
    });

    test('base vide : lireQuartier renvoie null', () async {
      expect(await cache.lireQuartier(), isNull);
    });

    test('utilisateur : on relit les mêmes valeurs', () async {
      await cache.enregistrerUtilisateur(amira);
      final Utilisateur? u = await cache.lireUtilisateur();

      expect(u, isNotNull);
      expect(u!.id, 'u1');
      expect(u.prenom, 'Amira');
      expect(u.nom, 'Ben Salah');
      expect(u.email, 'amira@houmani.tn');
      expect(u.telephone, '+216 22 345 678');
      expect(u.quartierId, 'q1');
      expect(u.quartier, 'Résidence El Yasmine');
      expect(u.residence, 'Résidence El Yasmine, Bloc B');
      expect(u.logement, 'Bloc B - Appt 12');
      expect(u.statut, StatutUtilisateur.refuse);
      expect(u.role, RoleUtilisateur.admin);
      expect(u.competences, ['Bricolage', 'Informatique']);
      expect(u.avatar, 'chat');
      expect(u.motif, 'Logement inconnu');
    });

    test('utilisateur : la date de demande est gardée à la milliseconde',
        () async {
      await cache.enregistrerUtilisateur(amira);
      final Utilisateur? u = await cache.lireUtilisateur();
      expect(u!.dateDemande!.millisecondsSinceEpoch, 1760000000123);
    });

    test('utilisateur : une date null reste null', () async {
      const Utilisateur sansDate = Utilisateur(
        id: 'u2',
        prenom: 'Youssef',
        nom: 'Trabelsi',
        email: '',
        telephone: '',
        quartier: '',
        residence: '',
      );
      await cache.enregistrerUtilisateur(sansDate);
      final Utilisateur? u = await cache.lireUtilisateur();
      expect(u!.id, 'u2');
      expect(u.dateDemande, isNull);
      expect(u.quartierId, isNull);
    });

    test('utilisateur : un nouvel enregistrement remplace le précédent',
        () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerUtilisateur(amira.copier(prenom: 'Sonia'));
      final Utilisateur? u = await cache.lireUtilisateur();
      expect(u!.prenom, 'Sonia');
    });

    test('quartier : on relit les mêmes valeurs', () async {
      await cache.enregistrerQuartier(const Quartier(
        id: 'q2',
        nom: 'Cité El Wafa',
        localisation: 'Ennasr 1, Ariana',
        aUnAdmin: true,
      ));
      final Quartier? q = await cache.lireQuartier();
      expect(q!.id, 'q2');
      expect(q.nom, 'Cité El Wafa');
      expect(q.localisation, 'Ennasr 1, Ariana');
      expect(q.aUnAdmin, true);
      expect(q.position, isNull);
      expect(q.contour, isEmpty);
    });

    test('quartier : la position et le contour (dans l\'ordre) sont gardés',
        () async {
      await cache.enregistrerQuartier(const Quartier(
        id: 'q1',
        nom: 'El Yasmine',
        localisation: 'Ariana',
        position: PointGps(36.8625, 10.17),
        contour: [
          PointGps(36.864, 10.168),
          PointGps(36.861, 10.172),
          PointGps(36.860, 10.165),
        ],
      ));
      final Quartier? q = await cache.lireQuartier();
      expect(q!.position!.latitude, 36.8625);
      expect(q.position!.longitude, 10.17);
      expect(q.contour.length, 3);
      expect(q.contour[1].longitude, 10.172);
      expect(q.contour[2].latitude, 36.860);
    });

    test('quartier : un nouveau quartier remplace l\'ancien et ses points',
        () async {
      await cache.enregistrerQuartier(const Quartier(
        id: 'q1',
        nom: 'El Yasmine',
        localisation: 'Ariana',
        contour: [PointGps(1, 1), PointGps(2, 2), PointGps(3, 3)],
      ));
      await cache.enregistrerQuartier(
        const Quartier(id: 'q2', nom: 'El Wafa', localisation: 'Ennasr'),
      );
      final Quartier? q = await cache.lireQuartier();
      expect(q!.id, 'q2');
      expect(q.contour, isEmpty);
    });

    test('vider efface l\'utilisateur et le quartier', () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerQuartier(
        const Quartier(id: 'q1', nom: 'El Yasmine', localisation: 'Ariana'),
      );
      await cache.vider();
      expect(await cache.lireUtilisateur(), isNull);
      expect(await cache.lireQuartier(), isNull);
    });

    test('oublierQuartier efface le quartier mais garde l\'utilisateur',
        () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerQuartier(
        const Quartier(id: 'q1', nom: 'El Yasmine', localisation: 'Ariana'),
      );
      await cache.oublierQuartier();
      expect(await cache.lireQuartier(), isNull);
      expect((await cache.lireUtilisateur())?.id, amira.id);
    });

    test('les données restent sur le disque après fermer()', () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerQuartier(
        const Quartier(id: 'q1', nom: 'El Yasmine', localisation: 'Ariana'),
      );
      await cache.fermer();

      // Nouveau cache sur le même dossier
      cache = CacheLocal(dossier: dossier.path);
      final Utilisateur? u = await cache.lireUtilisateur();
      final Quartier? q = await cache.lireQuartier();
      expect(u!.prenom, 'Amira');
      expect(q!.nom, 'El Yasmine');
    });
  });

  group('CacheLocal : préférences', () {
    test('thème : vide au départ, puis on relit le choix', () async {
      expect(await cache.lireTheme(), isNull);
      await cache.enregistrerTheme('sombre');
      expect(await cache.lireTheme(), 'sombre');
      await cache.enregistrerTheme('clair');
      expect(await cache.lireTheme(), 'clair');
    });

    test('vider garde le thème (réglage du téléphone)', () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerTheme('clair');
      await cache.vider();
      expect(await cache.lireUtilisateur(), isNull);
      expect(await cache.lireTheme(), 'clair');
    });

    test('langue : vide au départ, puis on relit le choix', () async {
      expect(await cache.lireLangue(), isNull);
      await cache.enregistrerLangue('derja');
      expect(await cache.lireLangue(), 'derja');
    });

    test('vider garde la langue (réglage du téléphone)', () async {
      await cache.enregistrerLangue('derja');
      await cache.vider();
      expect(await cache.lireLangue(), 'derja');
    });
  });

  group('CacheLocal : annuaire des voisins', () {
    test('vide au départ (liste vide, pas de date)', () async {
      expect(await cache.lireVoisins('q1'), isEmpty);
      expect(await cache.dateVoisins('q1'), isNull);
    });

    test('on relit les voisins triés par prénom, avec leurs compétences',
        () async {
      await cache.enregistrerVoisins('q1', [
        voisin('2', 'youssef', ['Plomberie']),
        voisin('1', 'Amira', ['Bricolage', 'Informatique']),
      ]);
      final List<Utilisateur> voisins = await cache.lireVoisins('q1');
      expect(voisins.length, 2);
      expect(voisins[0].prenom, 'Amira');
      expect(voisins[0].competences, ['Bricolage', 'Informatique']);
      expect(voisins[0].telephone, '20000001');
      expect(voisins[1].logement, 'Bloc 2');
      expect(await cache.dateVoisins('q1'), isNotNull);
    });

    test('une nouvelle liste remplace l\'ancienne (pas de doublon)', () async {
      await cache.enregistrerVoisins('q1', [voisin('1', 'Amira', [])]);
      await cache.enregistrerVoisins('q1', [voisin('2', 'Sonia', [])]);
      final List<Utilisateur> voisins = await cache.lireVoisins('q1');
      expect(voisins.single.prenom, 'Sonia');
    });

    test('chaque quartier a sa propre liste', () async {
      await cache.enregistrerVoisins('q1', [voisin('1', 'Amira', [])]);
      await cache.enregistrerVoisins('q2', [voisin('2', 'Sonia', [])]);
      expect((await cache.lireVoisins('q1')).single.prenom, 'Amira');
      expect((await cache.lireVoisins('q2')).single.prenom, 'Sonia');
    });

    test('compétences du quartier : comptées en SQL (GROUP BY)', () async {
      await cache.enregistrerVoisins('q1', [
        voisin('1', 'Amira', ['Bricolage', 'Informatique']),
        voisin('2', 'Sonia', ['Bricolage']),
        voisin('3', 'Karim', ['Bricolage', 'Cuisine']),
      ]);
      await cache.enregistrerVoisins('q2', [
        voisin('4', 'Ali', ['Cuisine']),
      ]);
      final Map<String, int> competences =
          await cache.competencesDuQuartier('q1');
      expect(competences, {'Bricolage': 3, 'Cuisine': 1, 'Informatique': 1});
      expect(competences.keys.first, 'Bricolage'); // le plus fréquent
    });

    test('vider efface les voisins', () async {
      await cache.enregistrerVoisins('q1', [voisin('1', 'Amira', ['X'])]);
      await cache.vider();
      expect(await cache.lireVoisins('q1'), isEmpty);
      expect(await cache.competencesDuQuartier('q1'), isEmpty);
    });
  });

  group('CacheLocal : historique des connexions', () {
    test('la plus récente d\'abord, limité à 5 par défaut', () async {
      for (int i = 1; i <= 7; i++) {
        await cache.noterConnexion('u1', i.isEven ? 'sms' : 'email',
            date: DateTime(2026, 11, i));
      }
      final List<ConnexionLocale> connexions =
          await cache.historiqueConnexions('u1');
      expect(connexions.length, 5);
      expect(connexions.first.date, DateTime(2026, 11, 7));
      expect(connexions.first.methode, 'email');
      expect(connexions[1].methode, 'sms');
    });

    test('chaque compte a son historique', () async {
      await cache.noterConnexion('u1', 'email');
      await cache.noterConnexion('u2', 'telephone');
      expect((await cache.historiqueConnexions('u1')).single.methode, 'email');
      expect(
        (await cache.historiqueConnexions('u2')).single.methode,
        'telephone',
      );
    });

    test('on garde au plus ${CacheLocal.maxConnexions} connexions', () async {
      for (int i = 0; i < CacheLocal.maxConnexions + 5; i++) {
        await cache.noterConnexion('u1', 'email',
            date: DateTime(2026, 1, 1).add(Duration(hours: i)));
      }
      final List<ConnexionLocale> toutes =
          await cache.historiqueConnexions('u1', limite: 100);
      expect(toutes.length, CacheLocal.maxConnexions);
    });

    test('vider garde l\'historique (donnée du téléphone)', () async {
      await cache.noterConnexion('u1', 'email');
      await cache.vider();
      expect(await cache.historiqueConnexions('u1'), hasLength(1));
    });
  });
}
