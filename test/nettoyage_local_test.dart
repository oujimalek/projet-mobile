import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/services/base_locale_m2.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/base_locale_m4.dart';
import 'package:houmani/data/services/nettoyage_local.dart';
import 'package:houmani/data/services/photos_m3.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';

import 'fausse_connexion_m3.dart';
import 'outils_test_m3.dart';

/// Commun - Nettoyage des données locales à la déconnexion (et quand le
/// compte est bloqué, refusé ou supprimé) : le nettoyage M3, puis la
/// fonction commune qui appelle chaque module.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FausseConnexionM3 connexion;
  late Directory dossierBases;

  setUp(() async {
    // M3 : SQLite en mémoire, photos dans un dossier temporaire
    connexion = installerHorsLigneM3();
    // M2 et M4 : un fichier chacun (deux bases ":memory:" ouvertes en même
    // temps seraient la MÊME base pour sqflite)
    dossierBases = Directory.systemTemp.createTempSync('houmani_nettoyage_');
    await BaseLocaleM2.fermer();
    BaseLocaleM2.cheminPourTests = '${dossierBases.path}/m2.db';
    await BaseLocaleM4.fermer();
    BaseLocaleM4.cheminPourTests = '${dossierBases.path}/m4.db';
  });

  tearDown(() async {
    NettoyageLocal.etapes = NettoyageLocal.etapesParDefaut();
    NettoyageLocal.delaiMax = const Duration(seconds: 5);
    BaseLocaleM2.utilisateurActuel = BaseLocaleM2.uidConnecte;
    BaseLocaleM4.utilisateurActuel = BaseLocaleM4.uidConnecte;
    await BaseLocaleM2.fermer();
    await BaseLocaleM4.fermer();
    await nettoyerHorsLigneM3(connexion);
    try {
      dossierBases.deleteSync(recursive: true);
    } catch (erreur) {
      // déjà supprimé
    }
  });

  Service service(String id) {
    return Service(
      id: id,
      titre: 'Perceuse $id',
      description: 'Prêt d\'une perceuse',
      categorie: 'Prêt d\'outils',
      auteurNom: 'Voisin',
      estOffre: true,
    );
  }

  Evenement evenement(String id) {
    return Evenement(
      id: id, titre: 'Fête $id', description: '', lieu: 'Jardin',
      date: DateTime(2026, 11, 20, 18), organisateur: 'X',
      categorie: CategorieEvenement.fete,
    );
  }

  Signalement signalement(String id) {
    return Signalement(
      id: id, titre: 'Lampadaire', description: 'Lampadaire en panne',
      categorieId: 'electricite', statut: StatutSignalement.enAttente,
      date: DateTime(2026, 11, 1), lieu: 'Bloc B', auteurId: 'u1',
      auteurNom: 'Amira',
    );
  }

  EnvoiEnAttente envoi(String idDocument, String uid, {String? photo}) {
    return EnvoiEnAttente(
      idDocument: idDocument, utilisateurId: uid, quartierId: 'q1',
      titre: 'Fuite', description: 'Fuite au parking', categorieId: 'eau',
      lieu: 'Parking', photoLocale: photo, dateCreation: DateTime(2026, 11, 2),
    );
  }

  group('M3 : SyncSignalementsM3.viderUtilisateur', () {
    test('efface brouillon, file et cache de CET utilisateur, et ses photos',
        () async {
      final BaseLocaleM3 base = BaseLocaleM3.instance;
      // Copiées dans photos_m3/, comme une photo choisie dans l'app
      final String maPhoto =
          (await PhotosM3.garderSurTelephone(faussePhoto(nom: 'moi.jpg'))).donnee!;
      final String photoAutre =
          (await PhotosM3.garderSurTelephone(faussePhoto(nom: 'autre.jpg'))).donnee!;
      await base.enregistrerBrouillon(Brouillon(
          utilisateurId: 'u1', titre: 'Brouillon', photoLocale: maPhoto,
          dateModification: DateTime(2026, 11, 1)));
      await base.enregistrerBrouillon(Brouillon(
          utilisateurId: 'u2', titre: 'Autre', dateModification: DateTime(2026, 11, 1)));
      await base.ajouterEnvoi(envoi('d1', 'u1'));
      await base.ajouterEnvoi(envoi('d2', 'u2', photo: photoAutre));
      await base.remplacerCache('q1', [signalement('s1')], DateTime(2026, 11, 3));
      await base.enregistrerAdresse('36.8,10.1', 'Rue de Marseille');

      await SyncSignalementsM3.instance.viderUtilisateur('u1');

      expect(await base.lireBrouillon('u1'), isNull);
      expect(await base.lireEnvois('u1'), isEmpty);
      expect(await base.lireCache('q1'), isEmpty);
      expect(await base.dateMiseAJour('q1'), isNull);
      // Les autres comptes et le cache public des adresses restent
      expect((await base.lireBrouillon('u2'))!.titre, 'Autre');
      expect(await base.lireEnvois('u2'), hasLength(1));
      expect(await base.lireAdresse('36.8,10.1'), 'Rue de Marseille');
      // Ma photo ne sert plus : supprimée ; celle de l'envoi de u2 reste
      expect(File(maPhoto).existsSync(), isFalse);
      expect(File(photoAutre).existsSync(), isTrue);
    });

    test('sans base locale : pas d\'exception', () async {
      await BaseLocaleM3.instance.fermer();
      BaseLocaleM3.instance = BaseLocaleM3(chemin: '/dossier/introuvable/x.db');
      await SyncSignalementsM3.instance.viderUtilisateur('u1');
    });
  });

  group('Commun : NettoyageLocal.viderTout', () {
    test('appelle chaque étape, dans l\'ordre, avec l\'uid', () async {
      final List<String> appels = [];
      NettoyageLocal.etapes = [
        (uid) async => appels.add('m2 $uid'),
        (uid) async => appels.add('m3 $uid'),
        (uid) async => appels.add('m4 $uid'),
      ];
      await NettoyageLocal.viderTout('u1');
      expect(appels, ['m2 u1', 'm3 u1', 'm4 u1']);
    });

    test('une étape en échec ou bloquée n\'empêche pas les suivantes', () async {
      final List<String> appels = [];
      NettoyageLocal.delaiMax = const Duration(milliseconds: 50);
      NettoyageLocal.etapes = [
        (uid) async => throw StateError('pas de base'),
        (uid) => Completer<void>().future, // ne finit jamais (pas de réseau)
        (uid) async => appels.add('fin'),
      ];
      await NettoyageLocal.viderTout('u1');
      expect(appels, ['fin']);
    });

    test('par défaut : M3, rappels M4, push M4', () {
      expect(NettoyageLocal.etapesParDefaut(), hasLength(3));
    });

    test('étapes par défaut : vide M3, GARDE M2 et M4 (lignes par utilisateur)',
        () async {
      NettoyageLocal.delaiMax = const Duration(seconds: 2);
      BaseLocaleM2.utilisateurActuel = () => 'u1';
      BaseLocaleM4.utilisateurActuel = () => 'u1';
      await BaseLocaleM2.ajouterFavori(service('s1'));
      await BaseLocaleM3.instance.enregistrerBrouillon(Brouillon(
          utilisateurId: 'u1', titre: 'Brouillon',
          dateModification: DateTime(2026, 11, 1)));
      await BaseLocaleM4.noterParticipation(evenement('e1'), true);

      // Notifications et push : pas de plugin en test, étapes ignorées
      await NettoyageLocal.viderTout('u1');

      expect(await BaseLocaleM3.instance.lireBrouillon('u1'), isNull);
      // u1 retrouvera ses favoris et son historique à sa prochaine connexion
      expect(await BaseLocaleM2.favoris(), hasLength(1));
      expect(await BaseLocaleM4.historique(), hasLength(1));
    });
  });
}
