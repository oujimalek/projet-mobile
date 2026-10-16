import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/services/cache_local.dart';

// Tests du cache local (Hive) dans un dossier temporaire.
void main() {
  late Directory dossier;
  late CacheLocal cache;

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
    dateDemande: DateTime.fromMillisecondsSinceEpoch(1760000000123),
  );

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('houmani_cache_');
    cache = CacheLocal(dossier: dossier.path);
  });

  tearDown(() async {
    await cache.fermer();
    await Hive.close();
    try {
      dossier.deleteSync(recursive: true);
    } catch (e) {
      // Windows peut garder le fichier un moment : on ignore
    }
  });

  group('CacheLocal', () {
    test('cache vide : lireUtilisateur renvoie null', () async {
      expect(await cache.lireUtilisateur(), isNull);
    });

    test('cache vide : lireQuartier renvoie null', () async {
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

    test('quartier : la position et le contour sont gardés', () async {
      await cache.enregistrerQuartier(const Quartier(
        id: 'q1',
        nom: 'El Yasmine',
        localisation: 'Ariana',
        position: PointGps(36.8625, 10.17),
        contour: [PointGps(36.864, 10.168), PointGps(36.861, 10.172)],
      ));
      final Quartier? q = await cache.lireQuartier();
      expect(q!.position!.latitude, 36.8625);
      expect(q.position!.longitude, 10.17);
      expect(q.contour.length, 2);
      expect(q.contour[1].longitude, 10.172);
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

    test('thème : vide au départ, puis on relit le choix', () async {
      expect(await cache.lireTheme(), isNull);
      await cache.enregistrerTheme('sombre');
      expect(await cache.lireTheme(), 'sombre');
    });

    test('vider garde le thème (réglage du téléphone)', () async {
      await cache.enregistrerUtilisateur(amira);
      await cache.enregistrerTheme('clair');
      await cache.vider();
      expect(await cache.lireUtilisateur(), isNull);
      expect(await cache.lireTheme(), 'clair');
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
}
