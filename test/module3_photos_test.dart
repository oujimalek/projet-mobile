import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// PAS d'import de package:houmani/main.dart (voir module3_signalements_test.dart)
import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/base_locale_m3.dart';
import 'package:houmani/data/services/firestore_commun.dart';
import 'package:houmani/data/services/photos_m3.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/sync_signalements_m3.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module3/create_signalement_screen.dart';
import 'package:houmani/screens/module3/signalement_detail_screen.dart';
import 'package:houmani/screens/module3/signalements_screen.dart';
import 'package:houmani/screens/module3/widgets_module3.dart';
import 'package:houmani/theme/app_theme.dart';

import 'fausse_connexion_m3.dart';
import 'mock_signalement_repository.dart';
import 'mock_utilisateur_repository.dart';
import 'outils_test_m3.dart';

const String urlPhoto =
    'https://res.cloudinary.com/pu3lxdrf/image/upload/v1731400000/houmani/signalements/abc123.jpg';

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(360, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.actuel, home: ecran));
  await tester.pumpAndSettle();
}

/// Un signalement valable à publier.
Signalement saisie() {
  return Signalement(
    id: '',
    titre: 'Trou dans la chaussée',
    description: 'Un trou profond devant le bloc C',
    categorieId: 'travaux',
    statut: StatutSignalement.enAttente,
    date: DateTime.now(),
    lieu: 'Bloc C',
    auteurId: '',
    auteurNom: '',
  );
}

void main() {
  late MockSignalementRepository depot;
  late FausseConnexionM3 connexion;
  // Faux Cloudinary : chaque envoi est compté ; la réponse est réglable
  late List<String> envoisPhoto;
  late Resultat<String> reponseCloudinary;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    UtilisateurRepository.instance = MockUtilisateurRepository(); // Amira
    depot = MockSignalementRepository();
    SignalementRepository.instance = depot;
    connexion = installerHorsLigneM3();
    envoisPhoto = [];
    reponseCloudinary = const Resultat.succes(urlPhoto);
    PhotosM3.envoi = (octets, nomFichier) async {
      envoisPhoto.add(nomFichier);
      return reponseCloudinary;
    };
  });

  tearDown(() async {
    await nettoyerHorsLigneM3(connexion);
  });

  /// Une photo déjà copiée dans le dossier de l'application.
  Future<String> photoGardee({int taille = 1000}) async {
    return (await PhotosM3.garderSurTelephone(faussePhoto(taille: taille)))
        .donnee!;
  }

  // =====================================================================
  group('PhotosM3 : adresses Cloudinary', () {
    test('Seules nos photos sont valables (préfixe du compte)', () {
      expect(PhotosM3.estPhotoValide(urlPhoto), isTrue);
      expect(PhotosM3.estPhotoValide('https://res.cloudinary.com/autre/image/upload/x.jpg'),
          isFalse);
      expect(PhotosM3.estPhotoValide('http://res.cloudinary.com/pu3lxdrf/x.jpg'),
          isFalse);
      expect(SignalementRepository.refusPhoto(null), isNull);
      expect(SignalementRepository.refusPhoto(urlPhoto), isNull);
      expect(SignalementRepository.refusPhoto('https://exemple.com/x.jpg'),
          'Photo invalide');
    });

    test('Miniature : transformation Cloudinary insérée après /image/upload/', () {
      expect(
        PhotosM3.miniature(urlPhoto, largeur: 800, hauteur: 450),
        'https://res.cloudinary.com/pu3lxdrf/image/upload/'
        'c_fill,w_800,h_450,q_auto,f_auto/v1731400000/houmani/signalements/abc123.jpg',
      );
      expect(PhotosM3.miniature('https://exemple.com/x.jpg'),
          'https://exemple.com/x.jpg'); // pas Cloudinary : inchangée
    });
  });

  // =====================================================================
  group('PhotosM3 : envoi à Cloudinary (faux client HTTP)', () {
    late List<http.Request> requetes;

    setUp(() {
      PhotosM3.envoi = PhotosM3.cloudinary; // le vrai code
      requetes = [];
    });

    void fauxServeur(http.Response reponse) {
      PhotosM3.client = MockClient((requete) async {
        requetes.add(requete);
        return reponse;
      });
    }

    test('Succès : POST non signé, seulement upload_preset (jamais public_id)',
        () async {
      fauxServeur(http.Response(jsonEncode({'secure_url': urlPhoto}), 200));
      final Resultat<String> resultat =
          await PhotosM3.cloudinary(Uint8List.fromList([1, 2, 3]), 'p.jpg');
      expect(resultat.donnee, urlPhoto);

      final http.Request requete = requetes.single;
      expect(requete.method, 'POST');
      expect(requete.url.toString(),
          'https://api.cloudinary.com/v1_1/pu3lxdrf/image/upload');
      final String corps = latin1.decode(requete.bodyBytes);
      expect(corps, contains('name="upload_preset"'));
      expect(corps, contains('houmani_signalements'));
      expect(corps, contains('name="file"; filename="p.jpg"'));
      expect(corps, isNot(contains('public_id')));
      expect(corps, isNot(contains('api_key')));
      expect(corps, isNot(contains('signature')));
    });

    test('Trop lourde : refusée AVANT tout envoi', () async {
      fauxServeur(http.Response('{}', 200));
      final resultat = await PhotosM3.cloudinary(
          Uint8List(PhotosM3.tailleMax + 1), 'grosse.jpg');
      expect(resultat.erreur, PhotosM3.messageTropLourde);
      expect(requetes, isEmpty);
    });

    test('Refusée par Cloudinary (400) : message d\'échec', () async {
      fauxServeur(http.Response('{"error":{"message":"Invalid preset"}}', 400));
      expect((await PhotosM3.cloudinary(Uint8List(10), 'p.jpg')).erreur,
          PhotosM3.messageEchec);
    });

    test('Adresse d\'un autre compte, ou réponse illisible : refusée', () async {
      fauxServeur(http.Response(
          jsonEncode({'secure_url': 'https://res.cloudinary.com/pirate/x.jpg'}), 200));
      expect((await PhotosM3.cloudinary(Uint8List(10), 'p.jpg')).erreur,
          PhotosM3.messageReponse);
      fauxServeur(http.Response('pas du json', 200));
      expect((await PhotosM3.cloudinary(Uint8List(10), 'p.jpg')).erreur,
          PhotosM3.messageReponse);
    });

    test('Pas de réseau ou délai dépassé : erreur réseau (file d\'envoi)',
        () async {
      PhotosM3.client = MockClient((requete) async {
        throw http.ClientException('Failed host lookup');
      });
      final resultat = await PhotosM3.cloudinary(Uint8List(10), 'p.jpg');
      expect(resultat.erreur, PhotosM3.messageReseau);
      expect(SyncSignalementsM3.estErreurReseau(resultat.erreur), isTrue);

      PhotosM3.delaiMax = const Duration(milliseconds: 50);
      PhotosM3.client = MockClient((requete) => Completer<http.Response>().future);
      expect((await PhotosM3.cloudinary(Uint8List(10), 'p.jpg')).erreur,
          PhotosM3.messageReseau);
    });
  });

  // =====================================================================
  group('PhotosM3 : fichiers sur le téléphone', () {
    test('Copie dans photos_m3/, l\'original n\'est pas touché', () async {
      final String choisie = faussePhoto(nom: 'image_picker_123.png');
      final Resultat<String> copie = await PhotosM3.garderSurTelephone(choisie);
      expect(copie.donnee, contains('photos_m3'));
      expect(copie.donnee, endsWith('.png'));
      expect(File(copie.donnee!).lengthSync(), 1000);
      expect(File(choisie).existsSync(), isTrue);
    });

    test('Plus de 5 Mo : refusée dès le choix', () async {
      final String grosse = faussePhoto(taille: PhotosM3.tailleMax + 1);
      expect((await PhotosM3.garderSurTelephone(grosse)).erreur,
          PhotosM3.messageTropLourde);
    });

    test('Fichier disparu : "plus sur le téléphone", sans envoi', () async {
      final resultat = await PhotosM3.envoyerFichier('/nulle/part.jpg');
      expect(resultat.erreur, PhotosM3.messageIntrouvable);
      expect(envoisPhoto, isEmpty);
    });

    test('Nettoyage : seules les photos inutilisées sont supprimées', () async {
      final String brouillon = await photoGardee();
      final String file = await photoGardee();
      final String orpheline = await photoGardee();
      final BaseLocaleM3 base = BaseLocaleM3.instance;
      await base.enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'B',
        photoLocale: brouillon,
        dateModification: DateTime.now(),
      ));
      await base.ajouterEnvoi(EnvoiEnAttente(
        idDocument: 'd1',
        utilisateurId: 'u1',
        quartierId: 'q1',
        titre: 'T',
        description: 'Description',
        categorieId: 'eau',
        lieu: 'L',
        photoLocale: file,
        dateCreation: DateTime.now(),
      ));
      expect(await base.cheminsPhotosUtilises(), {brouillon, file});

      expect(await SyncSignalementsM3.instance.nettoyerPhotos(), 1);
      expect(File(orpheline).existsSync(), isFalse);
      expect(File(brouillon).existsSync(), isTrue);
      expect(File(file).existsSync(), isTrue);
    });
  });

  // =====================================================================
  group('Sync : publier avec une photo', () {
    test('En ligne : photo puis signalement ; copie locale supprimée', () async {
      final String photo = await photoGardee();
      final resultat =
          await SyncSignalementsM3.instance.publier(saisie(), photoLocale: photo);
      expect(resultat.donnee, EtatPublicationM3.envoye);
      expect(envoisPhoto.length, 1);
      expect(depot.tous.last.photoUrl, urlPhoto);
      expect(File(photo).existsSync(), isFalse);
    });

    test('Hors ligne : photo gardée dans la file, envoyée au retour', () async {
      final String photo = await photoGardee();
      connexion.enLigne = false;
      final resultat =
          await SyncSignalementsM3.instance.publier(saisie(), photoLocale: photo);
      expect(resultat.donnee, EtatPublicationM3.misEnFile);
      expect(envoisPhoto, isEmpty); // ni Cloudinary...
      expect(depot.nombreEnvois, 0); // ... ni Firestore
      expect((await SyncSignalementsM3.instance.getEnvois()).single.photoLocale,
          photo);

      connexion.enLigne = true;
      expect(await SyncSignalementsM3.instance.envoyerFile(), 1);
      expect(depot.tous.last.photoUrl, urlPhoto);
      expect(File(photo).existsSync(), isFalse);
    });

    test('Cloudinary injoignable : en file ; refus définitif : erreur affichée',
        () async {
      reponseCloudinary = const Resultat.echec(PhotosM3.messageReseau);
      final enFile = await SyncSignalementsM3.instance
          .publier(saisie(), photoLocale: await photoGardee());
      expect(enFile.donnee, EtatPublicationM3.misEnFile);

      reponseCloudinary = const Resultat.echec(PhotosM3.messageEchec);
      final refus = await SyncSignalementsM3.instance
          .publier(saisie(), photoLocale: await photoGardee());
      expect(refus.erreur, PhotosM3.messageEchec);
      expect((await SyncSignalementsM3.instance.getEnvois()).length, 1);
    });

    test('Photo envoyée mais Firestore injoignable : jamais renvoyée', () async {
      final String photo = await photoGardee();
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      final resultat =
          await SyncSignalementsM3.instance.publier(saisie(), photoLocale: photo);
      expect(resultat.donnee, EtatPublicationM3.misEnFile);
      final EnvoiEnAttente envoi =
          (await SyncSignalementsM3.instance.getEnvois()).single;
      expect(envoi.photoUrl, urlPhoto); // gardée dans SQLite (version 3)

      depot.erreurReseau = null;
      await SyncSignalementsM3.instance.envoyerFile();
      expect(envoisPhoto.length, 1); // une seule fois en tout
      expect(depot.tous.last.photoUrl, urlPhoto);
    });

    test('Dans la file : la photo partie, Firestore en échec, retenté sans la renvoyer',
        () async {
      connexion.enLigne = false;
      await SyncSignalementsM3.instance
          .publier(saisie(), photoLocale: await photoGardee());
      connexion.enLigne = true;
      depot.erreurReseau = FirestoreCommun.messageErreur('unavailable');
      await SyncSignalementsM3.instance.envoyerFile();
      final EnvoiEnAttente envoi =
          (await SyncSignalementsM3.instance.getEnvois()).single;
      expect(envoi.photoUrl, urlPhoto);
      expect(envoi.nbTentatives, 1);

      depot.erreurReseau = null;
      await SyncSignalementsM3.instance.envoyerFile();
      expect(envoisPhoto.length, 1);
      expect(await SyncSignalementsM3.instance.getEnvois(), isEmpty);
    });

    test('Photo supprimée du téléphone avant l\'envoi : signalement envoyé sans',
        () async {
      final String photo = await photoGardee();
      connexion.enLigne = false;
      await SyncSignalementsM3.instance.publier(saisie(), photoLocale: photo);
      File(photo).deleteSync();
      connexion.enLigne = true;
      expect(await SyncSignalementsM3.instance.envoyerFile(), 1);
      expect(depot.tous.last.photoUrl, isNull);
      expect(envoisPhoto, isEmpty);
    });

    test('"Annuler" un envoi supprime aussi sa photo locale', () async {
      final String photo = await photoGardee();
      connexion.enLigne = false;
      await SyncSignalementsM3.instance.publier(saisie(), photoLocale: photo);
      final int id = (await SyncSignalementsM3.instance.getEnvois()).single.id!;
      await SyncSignalementsM3.instance.annuler(id);
      expect(File(photo).existsSync(), isFalse);
    });

    test('Brouillon : la photo remplacée ou jetée est supprimée', () async {
      final String premiere = await photoGardee();
      final String seconde = await photoGardee();
      final SyncSignalementsM3 sync = SyncSignalementsM3.instance;
      Brouillon brouillon(String photo) => Brouillon(
            utilisateurId: 'u1',
            titre: 'Trou',
            photoLocale: photo,
            dateModification: DateTime.now(),
          );
      await sync.enregistrerBrouillon(brouillon(premiere));
      await sync.enregistrerBrouillon(brouillon(premiere)); // même photo : gardée
      expect(File(premiere).existsSync(), isTrue);
      await sync.enregistrerBrouillon(brouillon(seconde));
      expect(File(premiere).existsSync(), isFalse);

      await sync.supprimerBrouillon(); // après publication : photo gardée
      expect(File(seconde).existsSync(), isTrue);
      await sync.enregistrerBrouillon(brouillon(seconde));
      await sync.supprimerBrouillon(avecPhoto: true); // jeté
      expect(File(seconde).existsSync(), isFalse);
    });
  });

  // =====================================================================
  group('SQLite version 3', () {
    test('photo_url d\'un envoi : enregistrée puis relue', () async {
      final BaseLocaleM3 base = BaseLocaleM3.instance;
      final int id = await base.ajouterEnvoi(EnvoiEnAttente(
        idDocument: 'd1',
        utilisateurId: 'u1',
        quartierId: 'q1',
        titre: 'T',
        description: 'Description',
        categorieId: 'eau',
        lieu: 'L',
        dateCreation: DateTime.now(),
      ));
      expect((await base.lireEnvoi(id))!.photoUrl, isNull);
      await base.enregistrerPhotoEnvoyee(id, urlPhoto);
      expect((await base.lireEnvoi(id))!.photoUrl, urlPhoto);
      expect((await base.lireEnvoi(id))!.versSignalement().photoUrl, urlPhoto);
      expect(await (await base.base).getVersion(), 3);
    });
  });

  // =====================================================================
  group('Modèle et repository', () {
    test('photoUrl écrite dans Firestore seulement si elle existe', () {
      final Signalement sans = saisie();
      expect(sans.toMap().containsKey('photoUrl'), isFalse);
      final Map<String, dynamic> map = sans.copyWith(photoUrl: urlPhoto).toMap();
      expect(map['photoUrl'], urlPhoto);
      expect(Signalement.fromMap('x', map).photoUrl, urlPhoto);
    });

    test('Une adresse qui n\'est pas à nous est refusée', () async {
      final resultat = await SignalementRepository().ajouterSignalement(
          saisie().copyWith(photoUrl: 'https://exemple.com/x.jpg'));
      expect(resultat.erreur, 'Photo invalide');
    });

    test('L\'auteur peut retirer la photo de son signalement', () async {
      await SignalementRepository()
          .ajouterSignalement(saisie().copyWith(id: 'p1', photoUrl: urlPhoto));
      final Signalement avec = depot.tous.last;
      final Signalement sans = Signalement(
        id: avec.id,
        titre: avec.titre,
        description: avec.description,
        categorieId: avec.categorieId,
        statut: avec.statut,
        date: avec.date,
        lieu: avec.lieu,
        auteurId: avec.auteurId,
        auteurNom: avec.auteurNom,
      );
      expect((await SignalementRepository().modifierSignalement(sans)).estSucces,
          isTrue);
      expect(depot.tous.last.photoUrl, isNull);
    });
  });

  // =====================================================================
  group('Écrans', () {
    testWidgets('Galerie → aperçu → publier : la photo arrive avec le signalement',
        (WidgetTester tester) async {
      final String choisie = faussePhoto();
      final List<ImageSource> sources = [];
      PhotosM3.choisir = (source) async {
        sources.add(source);
        return Resultat.succes(choisie);
      };
      await afficher(tester, const SignalementsScreen());
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      expect(find.text('Prendre une photo'), findsOneWidget);
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      expect(sources, [ImageSource.gallery]);
      expect(find.byKey(const ValueKey('photo_apercu')), findsOneWidget);
      expect(find.text('Retirer la photo'), findsOneWidget);

      await tester.tap(find.text('Travaux'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Trou');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Un trou profond devant le bloc');
      await tester.enterText(find.byType(TextFormField).at(2), 'Bloc C');
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      expect(find.text('5 signalements'), findsOneWidget);
      expect(depot.tous.last.photoUrl, urlPhoto);
      expect(find.byKey(const ValueKey('icone_photo')), findsOneWidget);
    });

    testWidgets('Appareil photo refusé, ou photo trop lourde : message',
        (WidgetTester tester) async {
      PhotosM3.choisir = (source) async =>
          const Resultat.echec('Autorise Houmani à utiliser l\'appareil photo');
      await afficher(tester, const CreateSignalementScreen());
      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prendre une photo'));
      await tester.pumpAndSettle();
      expect(find.text('Autorise Houmani à utiliser l\'appareil photo'),
          findsOneWidget);

      final String grosse = faussePhoto(taille: PhotosM3.tailleMax + 1);
      PhotosM3.choisir = (source) async => Resultat.succes(grosse);
      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      expect(find.text(PhotosM3.messageTropLourde), findsOneWidget);
      expect(find.byKey(const ValueKey('photo_apercu')), findsNothing);
    });

    testWidgets('Annulé dans la galerie : rien ne change',
        (WidgetTester tester) async {
      PhotosM3.choisir = (source) async => const Resultat.succes(null);
      await afficher(tester, const CreateSignalementScreen());
      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      expect(find.text('+ Ajouter une photo'), findsOneWidget);
    });

    testWidgets('Publier hors ligne avec photo : carte d\'attente avec 📷',
        (WidgetTester tester) async {
      PhotosM3.choisir = (source) async => Resultat.succes(faussePhoto());
      await afficher(tester, const SignalementsScreen());
      connexion.enLigne = false;
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travaux'));
      await tester.enterText(find.byType(TextFormField).at(0), 'Trou');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'Un trou profond devant le bloc');
      await tester.enterText(find.byType(TextFormField).at(2), 'Bloc C');
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();

      expect(find.text('En attente d\'envoi'), findsOneWidget);
      expect(find.byKey(const ValueKey('icone_photo_envoi')), findsOneWidget);
      expect(envoisPhoto, isEmpty);
    });

    testWidgets('Brouillon avec photo : repris avec son aperçu',
        (WidgetTester tester) async {
      await BaseLocaleM3.instance.enregistrerBrouillon(Brouillon(
        utilisateurId: 'u1',
        titre: 'Trou',
        photoLocale: await photoGardee(),
        dateModification: DateTime.now(),
      ));
      await afficher(tester, const CreateSignalementScreen());
      await tester.tap(find.text('Reprendre le brouillon'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo_apercu')), findsOneWidget);
    });

    testWidgets('Modification : retirer la photo en ligne',
        (WidgetTester tester) async {
      await SignalementRepository()
          .ajouterSignalement(saisie().copyWith(id: 'p1', photoUrl: urlPhoto));
      await afficher(
          tester, CreateSignalementScreen(signalement: depot.tous.last));
      expect(find.byKey(const ValueKey('photo_apercu')), findsOneWidget);

      await tester.tap(find.text('Retirer la photo'));
      await tester.pumpAndSettle();
      expect(find.text('+ Ajouter une photo'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(depot.tous.last.photoUrl, isNull);
    });

    testWidgets('Modification : nouvelle photo envoyée puis enregistrée',
        (WidgetTester tester) async {
      await SignalementRepository()
          .ajouterSignalement(saisie().copyWith(id: 'p1'));
      PhotosM3.choisir = (source) async => Resultat.succes(faussePhoto());
      await afficher(
          tester, CreateSignalementScreen(signalement: depot.tous.last));
      await tester.tap(find.text('+ Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(envoisPhoto.length, 1);
      expect(depot.tous.last.photoUrl, urlPhoto);
    });

    testWidgets('Détail : miniature Cloudinary, plein écran au toucher',
        (WidgetTester tester) async {
      await SignalementRepository()
          .ajouterSignalement(saisie().copyWith(id: 'p1', photoUrl: urlPhoto));
      await afficher(tester, const SignalementDetailScreen(signalementId: 'p1'));

      final Image miniature =
          tester.widget(find.byKey(const ValueKey('photo_signalement')));
      expect((miniature.image as NetworkImage).url,
          PhotosM3.miniature(urlPhoto, largeur: 800, hauteur: 450));

      await tester.tap(find.byKey(const ValueKey('photo_signalement')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPleinEcranM3), findsOneWidget);
      final Image grande =
          tester.widget(find.byKey(const ValueKey('photo_plein_ecran')));
      expect((grande.image as NetworkImage).url, urlPhoto); // l'originale
    });
  });
}
