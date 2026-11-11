import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/sondage.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/models/vie_evenement.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/statistiques_m4.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module4/calendrier_screen.dart';
import 'package:houmani/screens/module4/evenement_detail_screen.dart';
import 'package:houmani/screens/module4/graphique_sondage.dart';
import 'package:houmani/screens/module4/nouveautes_m4.dart';
import 'package:houmani/screens/module4/evenement_form_screen.dart';
import 'package:houmani/screens/module4/evenements_screen.dart';
import 'package:houmani/screens/module4/sondage_form_screen.dart';
import 'package:houmani/screens/module4/sondage_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'mock_evenement_repository.dart';
import 'mock_utilisateur_repository.dart';

/// Affiche un écran dans une MaterialApp avec le thème Houmani.
Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockEvenementRepository depot;
  late Utilisateur amira; // connectée par défaut (admin dans le mock M1)

  final Utilisateur nizar = Utilisateur(
    id: 'u30',
    prenom: 'Nizar',
    nom: 'Hamdi',
    email: 'nizar@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc B',
  );
  final Utilisateur sarra = Utilisateur(
    id: 'u31',
    prenom: 'Sarra',
    nom: 'Ayari',
    email: 'sarra@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine, Bloc A',
  );

  final DateTime demain = DateTime.now().add(const Duration(days: 1));
  final DateTime hier = DateTime.now().subtract(const Duration(days: 1));

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Dépôts VIDES avant chaque test. Utilisateur connecté : Amira B.
  setUp(() {
    utilisateurs = MockUtilisateurRepository();
    UtilisateurRepository.instance = utilisateurs;
    depot = MockEvenementRepository();
    EvenementRepository.instance = depot;
    amira = utilisateurs.getUtilisateurConnecte();
    utilisateurs.ajouterCompte(nizar, 'pw');
    utilisateurs.ajouterCompte(sarra, 'pw');
  });

  Future<void> devenir(Utilisateur utilisateur) async {
    await utilisateurs.connexion(utilisateur.email, 'pw');
  }

  group('Modèles : toMap / fromMap', () {
    test('Evenement : aller-retour avec les noms de champs du schéma', () {
      final Evenement evenement = Evenement(
        id: 'e1',
        titre: 'Fête des voisins',
        description: 'Chacun apporte un plat',
        date: DateTime(2026, 12, 20, 18, 30),
        lieu: 'Jardin',
        organisateurId: 'u1',
        organisateur: 'Amira B.',
        participants: 4,
      );
      final Map<String, dynamic> map = evenement.toMap();

      expect(map.containsKey('id'), isFalse); // l'id est le nom du document
      expect(map['organisateurNom'], 'Amira B.');
      expect(map['nbParticipants'], 4);

      // Firestore relit la date sous forme de Timestamp
      map['date'] = Timestamp.fromDate(evenement.date);
      final Evenement relu = Evenement.fromMap('e1', map);
      expect(relu.id, 'e1');
      expect(relu.titre, 'Fête des voisins');
      expect(relu.date, DateTime(2026, 12, 20, 18, 30));
      expect(relu.organisateurId, 'u1');
      expect(relu.organisateur, 'Amira B.');
      expect(relu.participants, 4);
    });

    test('Evenement.fromMap : champs absents → valeurs par défaut', () {
      final Evenement relu = Evenement.fromMap('e2', {});
      expect(relu.titre, '');
      expect(relu.organisateur, '');
      expect(relu.participants, 0);
    });

    test('Sondage : seuls les textes des options sont stockés', () {
      final Sondage sondage = Sondage(
        id: 'p1',
        question: 'Quelle date ?',
        options: const [
          OptionSondage(texte: 'Mardi', votes: 3),
          OptionSondage(texte: 'Jeudi', votes: 1),
        ],
        dateFin: DateTime(2026, 12, 1),
        proposeParId: 'u1',
        proposePar: 'Amira B.',
      );
      final Map<String, dynamic> map = sondage.toMap();
      expect(map['options'], ['Mardi', 'Jeudi']);
      expect(map['proposeParNom'], 'Amira B.');
      expect(map.containsKey('votes'), isFalse);

      map['dateFin'] = Timestamp.fromDate(sondage.dateFin);
      final Sondage relu =
          Sondage.fromMap('p1', map, votes: [5, 2], nombreMembres: 40);
      expect(relu.options[0].texte, 'Mardi');
      expect(relu.options[0].votes, 5);
      expect(relu.totalVotes, 7);
      expect(relu.nombreMembres, 40);
      expect(relu.dateFin, DateTime(2026, 12, 1));
    });

    test('Sondage.fromMap : votes manquants → 0', () {
      final Sondage relu = Sondage.fromMap('p2', {
        'question': 'Q',
        'options': ['A', 'B', 'C'],
      });
      expect(relu.options.length, 3);
      expect(relu.totalVotes, 0);
    });
  });

  group('Règles métier (sans réseau)', () {
    test('refusEvenement : titre, lieu, date passée, longueurs', () {
      String? refus({
        String titre = 'Fête',
        String description = '',
        String lieu = 'Jardin',
        DateTime? date,
      }) {
        return EvenementRepository.refusEvenement(
          titre: titre,
          description: description,
          lieu: lieu,
          date: date ?? demain,
        );
      }

      expect(refus(), isNull);
      expect(refus(titre: '   '), isNotNull);
      expect(refus(titre: 'a' * (EvenementRepository.titreMax + 1)), isNotNull);
      expect(
        refus(description: 'a' * (EvenementRepository.descriptionMax + 1)),
        isNotNull,
      );
      expect(refus(lieu: ''), isNotNull);
      expect(refus(date: hier), isNotNull);
    });

    test('refusSondage : question, au moins 2 choix remplis, date de fin', () {
      expect(
        EvenementRepository.refusSondage(
            question: 'Q ?', options: ['A', 'B'], dateFin: demain),
        isNull,
      );
      expect(
        EvenementRepository.refusSondage(
            question: ' ', options: ['A', 'B'], dateFin: demain),
        isNotNull,
      );
      // Un choix vide ne compte pas
      expect(
        EvenementRepository.refusSondage(
            question: 'Q ?', options: ['A', '  '], dateFin: demain),
        isNotNull,
      );
      expect(
        EvenementRepository.refusSondage(
          question: 'Q ?',
          options: List.filled(EvenementRepository.optionsMax + 1, 'X'),
          dateFin: demain,
        ),
        isNotNull,
      );
      expect(
        EvenementRepository.refusSondage(
            question: 'Q ?', options: ['A', 'B'], dateFin: hier),
        isNotNull,
      );
    });

    test('refusVote : déjà voté, sondage terminé, choix invalide', () {
      final Sondage ouvert = Sondage(
        id: 'p',
        question: 'Q',
        options: const [OptionSondage(texte: 'A'), OptionSondage(texte: 'B')],
        dateFin: demain,
      );
      final Sondage termine = Sondage(
        id: 'p',
        question: 'Q',
        options: ouvert.options,
        dateFin: hier,
      );
      expect(EvenementRepository.refusVote(ouvert, 1, null), isNull);
      expect(EvenementRepository.refusVote(ouvert, 0, 1), isNotNull);
      expect(EvenementRepository.refusVote(termine, 0, null), isNotNull);
      expect(EvenementRepository.refusVote(ouvert, 2, null), isNotNull);
      expect(EvenementRepository.refusVote(ouvert, -1, null), isNotNull);
    });

    test('peutSupprimer : l\'auteur ou l\'admin seulement', () {
      expect(EvenementRepository.peutSupprimer(nizar, nizar.id), isTrue);
      expect(EvenementRepository.peutSupprimer(sarra, nizar.id), isFalse);
      expect(amira.estAdmin, isTrue);
      expect(EvenementRepository.peutSupprimer(amira, nizar.id), isTrue);
    });

    test('nomCourt : prénom + initiale du nom', () {
      expect(EvenementRepository.nomCourt(nizar), 'Nizar H.');
    });
  });

  group('Événements (mock)', () {
    test('créer : l\'utilisateur connecté est l\'organisateur, 0 participant', () async {
      final Resultat<void> resultat = await depot.creerEvenement(
        titre: '  Nettoyage  ',
        description: 'Gants fournis',
        date: demain,
        lieu: 'Parking',
        categorie: CategorieEvenement.nettoyage,
      );
      expect(resultat.estSucces, isTrue);
      final Evenement cree = depot.evenements.single;
      expect(cree.titre, 'Nettoyage');
      expect(cree.categorie, CategorieEvenement.nettoyage);
      expect(cree.organisateurId, amira.id);
      expect(cree.participants, 0);
    });

    test('créer : refusé si la fin est avant le début', () async {
      final Resultat<void> resultat = await depot.creerEvenement(
        titre: 'Fête',
        description: '',
        date: demain,
        dateFin: demain.subtract(const Duration(hours: 1)),
        lieu: 'Jardin',
        categorie: CategorieEvenement.fete,
      );
      expect(resultat.estSucces, isFalse);
    });

    test('modifier : l\'admin peut modifier l\'événement d\'un autre', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      // Amira est admin dans le mock M1
      final Resultat<void> resultat = await depot.modifierEvenement(
        fete.copyWith(lieu: 'Salle commune'),
      );
      expect(resultat.estSucces, isTrue);
      expect(depot.evenements.single.lieu, 'Salle commune');
    });

    test('droits : seuls l\'organisateur et l\'admin voient les participants', () {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      expect(EvenementRepository.peutVoirParticipants(nizar, fete), isTrue);
      expect(EvenementRepository.peutVoirParticipants(amira, fete), isTrue);
      expect(EvenementRepository.peutVoirParticipants(sarra, fete), isFalse);
    });

    test('créer : refusé si la date est passée', () async {
      final Resultat<void> resultat = await depot.creerEvenement(
        titre: 'Fête',
        description: '',
        date: hier,
        lieu: 'Jardin',
        categorie: CategorieEvenement.fete,
      );
      expect(resultat.estSucces, isFalse);
      expect(depot.evenements, isEmpty);
    });

    test('participer puis se retirer : le compteur suit', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);

      expect((await depot.participer(fete.id)).estSucces, isTrue);
      expect(depot.evenements.single.participants, 1);
      expect((await depot.estInscrit(fete.id)).donnee, isTrue);
      expect((await depot.getParticipants(fete.id)).donnee!.map((p) => p.nom), ['Amira B.']);

      // Deux fois : refusé, le compteur ne bouge pas
      expect((await depot.participer(fete.id)).estSucces, isFalse);
      expect(depot.evenements.single.participants, 1);

      expect((await depot.seRetirer(fete.id)).estSucces, isTrue);
      expect(depot.evenements.single.participants, 0);
      expect((await depot.estInscrit(fete.id)).donnee, isFalse);
      expect((await depot.seRetirer(fete.id)).estSucces, isFalse);
    });

    test('modifier : un simple voisin ne peut pas, le compteur ne change pas', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await depot.participer(fete.id); // Amira participe

      // Sarra n'est ni l'organisatrice ni l'admin
      await devenir(sarra);
      final Evenement modifie = depot.evenements.single.copyWith(lieu: 'Salle');
      expect((await depot.modifierEvenement(modifie)).estSucces, isFalse);

      await devenir(nizar);
      expect((await depot.modifierEvenement(modifie)).estSucces, isTrue);
      expect(depot.evenements.single.lieu, 'Salle');
      expect(depot.evenements.single.participants, 1);
    });

    test('supprimer : refusé pour un simple voisin, accepté pour l\'admin', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);

      await devenir(sarra);
      expect((await depot.supprimerEvenement(fete.id)).estSucces, isFalse);

      // Retour à Amira (admin) : compte de démo du mock M1
      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      expect(utilisateurs.getUtilisateurConnecte().estAdmin, isTrue);
      expect((await depot.supprimerEvenement(fete.id)).estSucces, isTrue);
      expect(depot.evenements, isEmpty);
    });

    test('getEvenements (accueil) : seulement ceux à venir, du plus proche', () {
      depot.ajouterEvenementDe(nizar, titre: 'Passé', date: hier);
      depot.ajouterEvenementDe(nizar,
          titre: 'Loin', date: DateTime.now().add(const Duration(days: 30)));
      depot.ajouterEvenementDe(nizar, titre: 'Proche', date: demain);

      final List<Evenement> aVenir = depot.getEvenements();
      expect(aVenir.map((e) => e.titre), ['Proche', 'Loin']);
    });

    test('erreur réseau : message rangé dans le Resultat', () async {
      depot.erreur = 'Serveur injoignable';
      final Resultat<List<Evenement>> resultat = await depot.chargerEvenements();
      expect(resultat.estSucces, isFalse);
      expect(resultat.erreur, 'Serveur injoignable');
    });
  });

  group('Sondages (mock)', () {
    test('créer : les choix vides sont ignorés', () async {
      final Resultat<void> resultat = await depot.creerSondage(
        question: 'Quelle date ?',
        options: ['Mardi', ' ', 'Jeudi'],
        dateFin: demain,
      );
      expect(resultat.estSucces, isTrue);
      final Sondage cree = depot.sondages.single;
      expect(cree.options.map((o) => o.texte), ['Mardi', 'Jeudi']);
      expect(cree.proposeParId, amira.id);
    });

    test('voter : un seul vote, compté dans le sondage', () async {
      final Sondage sondage = depot.ajouterSondageDe(nizar);
      depot.ajouterVoteDe(sarra, sondage, 0);

      expect((await depot.getMonVote(sondage.id)).donnee, isNull);
      expect((await depot.voter(sondage, 1)).estSucces, isTrue);
      expect((await depot.getMonVote(sondage.id)).donnee, 1);
      expect((await depot.voter(sondage, 0)).estSucces, isFalse);

      final Sondage relu = (await depot.chargerSondages()).donnee!.single;
      expect(relu.options[0].votes, 1); // Sarra
      expect(relu.options[1].votes, 1); // Amira
    });

    test('voter : refusé si le sondage est terminé', () async {
      final Sondage termine = depot.ajouterSondageDe(nizar, dateFin: hier);
      expect((await depot.voter(termine, 0)).estSucces, isFalse);
    });

    test('getSondageActif : l\'ouvert qui se termine le plus tôt', () {
      expect(depot.getSondageActif(), isNull);
      depot.ajouterSondageDe(nizar, question: 'Terminé', dateFin: hier);
      depot.ajouterSondageDe(nizar,
          question: 'Plus tard',
          dateFin: DateTime.now().add(const Duration(days: 10)));
      depot.ajouterSondageDe(nizar, question: 'Bientôt', dateFin: demain);
      expect(depot.getSondageActif()!.question, 'Bientôt');
    });
  });

  group('SondageScreen', () {
    testWidgets('aucun sondage : message', (tester) async {
      await afficher(tester, const SondageScreen());
      expect(find.text('Aucun sondage en cours dans ta houma'), findsOneWidget);
    });

    testWidgets('erreur de chargement : message et bouton Réessayer', (tester) async {
      depot.erreur = 'Serveur injoignable';
      await afficher(tester, const SondageScreen());
      expect(find.text('Serveur injoignable'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('voter : le vote est enregistré et affiché', (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(
        nizar,
        question: 'Quelle date pour la fête ?',
        options: ['Samedi', 'Dimanche'],
      );
      depot.ajouterVoteDe(sarra, sondage, 0);

      await afficher(tester, const SondageScreen());
      expect(find.text('Quelle date pour la fête ?'), findsOneWidget);
      expect(find.text('Proposé par Nizar H. · se termine dans 2 jours'),
          findsOneWidget);

      await tester.tap(find.text('Dimanche'));
      await tester.pump();
      await tester.tap(find.text('Confirmer mon vote'));
      await tester.pumpAndSettle();

      expect(find.text('Vote enregistré'), findsOneWidget);
      expect(find.text('2 votes au total'), findsOneWidget);
      expect((await depot.getMonVote(sondage.id)).donnee, 1);
    });

    testWidgets('déjà voté : le vote est affiché, bouton désactivé', (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(nizar);
      depot.ajouterVoteDe(amira, sondage, 0);

      await afficher(tester, const SondageScreen());
      expect(find.text('Vote enregistré'), findsOneWidget);
      expect(find.text('Yaatik saha, ton vote est enregistré !'), findsOneWidget);
    });

    testWidgets('ouvert par id : affiche ce sondage, pas le sondage en cours', (tester) async {
      depot.ajouterSondageDe(nizar, question: 'Bientôt fini ?', dateFin: demain);
      final Sondage autre = depot.ajouterSondageDe(nizar,
          question: 'Plus tard ?',
          dateFin: DateTime.now().add(const Duration(days: 9)));
      await afficher(tester, SondageScreen(sondageId: autre.id));
      expect(find.text('Plus tard ?'), findsOneWidget);
      expect(find.text('Bientôt fini ?'), findsNothing);
    });
  });

  group('EvenementsScreen', () {
    testWidgets('liste vide : message d\'invitation', (tester) async {
      await afficher(tester, const EvenementsScreen());
      expect(find.textContaining('Aucun événement pour l\'instant'), findsOneWidget);
    });

    testWidgets('à venir et passés, filtre par catégorie et recherche', (tester) async {
      depot.ajouterEvenementDe(nizar, titre: 'Fête des voisins', date: demain);
      depot.ajouterEvenementDe(nizar,
          titre: 'Grand nettoyage',
          date: demain.add(const Duration(days: 1)),
          categorie: CategorieEvenement.nettoyage);
      depot.ajouterEvenementDe(nizar, titre: 'Ancienne réunion', date: hier);

      await afficher(tester, const EvenementsScreen());
      expect(find.text('À venir'), findsOneWidget);
      expect(find.text('Passés'), findsOneWidget);
      expect(find.text('Fête des voisins'), findsOneWidget);
      expect(find.text('Ancienne réunion'), findsOneWidget);

      // Catégorie "Nettoyage" (la puce, pas la pastille de la carte)
      await tester.tap(find.text('Nettoyage').first);
      await tester.pumpAndSettle();
      expect(find.text('Grand nettoyage'), findsOneWidget);
      expect(find.text('Fête des voisins'), findsNothing);

      // On retire la catégorie, puis on cherche "fête"
      await tester.tap(find.text('Nettoyage').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fête');
      await tester.pumpAndSettle();
      expect(find.text('Fête des voisins'), findsOneWidget);
      expect(find.text('Grand nettoyage'), findsNothing);
    });

    testWidgets('onglet Sondages : en cours et terminés', (tester) async {
      depot.ajouterSondageDe(nizar, question: 'Ouvert ?');
      depot.ajouterSondageDe(nizar, question: 'Fini ?', dateFin: hier);
      await afficher(tester, const EvenementsScreen());
      await tester.tap(find.text('Sondages'));
      await tester.pumpAndSettle();
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Terminés'), findsOneWidget);
      expect(find.text('Ouvert ?'), findsOneWidget);
      expect(find.text('Fini ?'), findsOneWidget);
    });
  });

  group('EvenementDetailScreen', () {
    testWidgets('participer puis se retirer', (tester) async {
      await devenir(sarra); // simple voisine
      final Evenement fete = depot.ajouterEvenementDe(nizar, titre: 'Fête des voisins');

      await afficher(tester, EvenementDetailScreen(evenementId: fete.id));
      expect(find.text('Fête des voisins'), findsOneWidget);
      expect(find.text('0 participant'), findsOneWidget);
      // Sarra n'est ni organisatrice ni admin : pas de liste de noms
      expect(find.textContaining('Seuls l\'organisateur et l\'admin'), findsOneWidget);

      await tester.tap(find.text('Je participe'));
      await tester.pumpAndSettle();
      expect(find.text('1 participant'), findsOneWidget);
      expect(find.text('Me retirer'), findsOneWidget);

      // Le message de confirmation (SnackBar) cache le bas : on attend qu'il parte
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Me retirer'));
      await tester.pumpAndSettle();
      expect(find.text('0 participant'), findsOneWidget);
    });

    testWidgets('l\'organisateur voit les noms des participants', (tester) async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await depot.participer(fete.id); // Amira participe
      await devenir(nizar);

      await afficher(tester, EvenementDetailScreen(evenementId: fete.id));
      expect(find.text('Amira B.'), findsOneWidget);
    });

    testWidgets('événement passé : on ne peut plus participer', (tester) async {
      final Evenement ancien = depot.ajouterEvenementDe(nizar, date: hier);
      await afficher(tester, EvenementDetailScreen(evenementId: ancien.id));
      expect(find.text('Cet événement est terminé'), findsOneWidget);
      expect(find.text('Je participe'), findsNothing);
    });
  });

  group('Lot 1 : annuler, officiel, partage, résultats cachés', () {
    test('annuler : plus d\'inscription, rétablir : de nouveau possible', () async {
      final Evenement fete = depot.ajouterEvenementDe(amira); // l'admin organise
      expect((await depot.annulerEvenement(fete, true)).estSucces, isTrue);
      expect(depot.evenements.single.annule, isTrue);
      expect(depot.getEvenements(), isEmpty); // plus sur l'accueil

      await devenir(sarra);
      final Resultat<void> refus = await depot.participer(fete.id);
      expect(refus.estSucces, isFalse);
      expect(refus.erreur, 'Cet événement est annulé');
      // Une voisine ne peut pas rétablir
      expect((await depot.annulerEvenement(fete, false)).estSucces, isFalse);

      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      expect((await depot.annulerEvenement(fete, false)).estSucces, isTrue);
      await devenir(sarra);
      expect((await depot.participer(fete.id)).estSucces, isTrue);
    });

    test('officiel : les événements de l\'admin, pas ceux d\'un leader', () async {
      await depot.creerEvenement(
        titre: 'Assemblée', description: '', date: demain,
        lieu: 'Salle', categorie: CategorieEvenement.reunion,
      ); // Amira est admin
      expect(depot.evenements.single.officiel, isTrue);

      await utilisateurs.changerRole(sarra.id, RoleUtilisateur.leader);
      await devenir(sarra);
      await depot.creerEvenement(
        titre: 'Foot', description: '', date: demain,
        lieu: 'Terrain', categorie: CategorieEvenement.sport,
      );
      expect(depot.evenements.last.officiel, isFalse);
    });

    test('Firestore : annule et officiel sont relus', () {
      final Evenement relu = Evenement.fromMap('e', {'annule': true, 'officiel': true});
      expect(relu.annule, isTrue);
      expect(relu.officiel, isTrue);
      expect(Evenement.fromMap('e', {}).annule, isFalse);
    });

    test('texte d\'invitation partagé', () {
      final Evenement fete = Evenement(
        id: 'e', titre: 'Fête des voisins', description: '',
        date: DateTime(2026, 11, 14, 18, 0), lieu: 'Jardin', organisateur: 'Salma G.',
      );
      final String texte = EvenementRepository.texteInvitation(fete);
      expect(texte, contains('Fête des voisins'));
      expect(texte, contains('14/11/2026 à 18:00'));
      expect(texte, contains('📍 Jardin'));
      expect(texte, contains('Organisé par Salma G.'));
    });

    testWidgets('liste : l\'événement officiel est en tête, badges', (tester) async {
      depot.ajouterEvenementDe(nizar, titre: 'Normal', date: demain);
      depot.ajouterEvenementDe(amira,
          titre: 'Réunion officielle', date: demain.add(const Duration(days: 3)));
      depot.ajouterEvenementDe(nizar,
          titre: 'Annulé', date: demain, annule: true, officiel: false);
      await afficher(tester, const EvenementsScreen());
      expect(find.text('Officiel'), findsOneWidget);
      expect(find.text('Annulé'), findsWidgets);
      final double yOfficiel = tester.getTopLeft(find.text('Réunion officielle')).dy;
      final double yNormal = tester.getTopLeft(find.text('Normal')).dy;
      expect(yOfficiel, lessThan(yNormal));
    });

    testWidgets('sondage : résultats cachés avant de voter, compte à rebours', (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(nizar, options: ['Oui', 'Non']);
      depot.ajouterVoteDe(sarra, sondage, 0);
      depot.nombreMembres = 5;
      await afficher(tester, SondageScreen(sondageId: sondage.id));
      expect(find.text('Vote pour voir les résultats'), findsOneWidget);
      expect(find.text('1 vote'), findsNothing); // pas de résultat par choix
      expect(find.textContaining('4 voisins n\'ont pas encore voté'), findsOneWidget);
      expect(find.textContaining('Plus que'), findsOneWidget);

      await tester.tap(find.text('Non'));
      await tester.pump();
      await tester.tap(find.text('Confirmer mon vote'));
      await tester.pumpAndSettle();
      expect(find.text('Vote pour voir les résultats'), findsNothing);
      expect(find.text('1 vote'), findsNWidgets(2)); // Oui : 1, Non : 1
    });
  });

  group('Lot 2 : places, peut-être, calendrier, graphique', () {
    test('places : complet → plus d\'inscription ; se retirer libère une place', () async {
      final Evenement atelier = depot.ajouterEvenementDe(nizar, placesMax: 1);
      expect(atelier.placesRestantes, 1);
      await devenir(sarra);
      expect((await depot.participer(atelier.id)).estSucces, isTrue);
      expect(depot.evenements.single.estComplet, isTrue);

      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      final Resultat<void> refus = await depot.participer(atelier.id);
      expect(refus.erreur, 'Cet événement est complet');

      await devenir(sarra);
      await depot.seRetirer(atelier.id);
      expect(depot.evenements.single.estComplet, isFalse);
    });

    test('refusPlaces : jamais moins que les inscrits', () {
      expect(EvenementRepository.refusPlaces(0), isNull); // sans limite
      expect(EvenementRepository.refusPlaces(20, inscrits: 5), isNull);
      expect(EvenementRepository.refusPlaces(3, inscrits: 5), isNotNull);
      expect(EvenementRepository.refusPlaces(-1), isNotNull);
    });

    test('peut-être : le compteur suit', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await depot.changerInteret(fete.id, true);
      expect(depot.evenements.single.interesses, 1);
      expect((await depot.estInteresse(fete.id)).donnee, isTrue);
      await depot.changerInteret(fete.id, true); // deux fois : rien ne change
      expect(depot.evenements.single.interesses, 1);
      await depot.changerInteret(fete.id, false);
      expect(depot.evenements.single.interesses, 0);
    });

    testWidgets('détail : complet et peut-être', (tester) async {
      final Evenement plein = depot.ajouterEvenementDe(nizar, placesMax: 1);
      await devenir(sarra);
      await depot.participer(plein.id);
      await devenir(nizar);
      await afficher(tester, EvenementDetailScreen(evenementId: plein.id));
      expect(find.text('Complet'), findsOneWidget);
      // Complet : on propose la liste d'attente
      expect(find.text('Rejoindre la liste d\'attente (0)'), findsOneWidget);
    });

    testWidgets('détail : bouton Peut-être', (tester) async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await devenir(sarra);
      await afficher(tester, EvenementDetailScreen(evenementId: fete.id));
      await tester.tap(find.text('Peut-être'));
      await tester.pumpAndSettle();
      expect(find.text('1 peut-être'), findsOneWidget);
      expect(find.text('Je ne suis plus intéressé'), findsOneWidget);
    });

    testWidgets('calendrier : les événements du jour choisi', (tester) async {
      final DateTime aujourdhui = DateTime.now();
      depot.ajouterEvenementDe(nizar,
          titre: 'Ce soir',
          date: DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day, 23, 0));
      await afficher(tester, const CalendrierScreen());
      expect(find.text('Calendrier'), findsOneWidget);
      expect(find.text('Ce soir'), findsOneWidget); // le jour choisi = aujourd'hui
    });

    testWidgets('sondage : camembert après le vote', (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(nizar, options: ['Oui', 'Non']);
      depot.ajouterVoteDe(sarra, sondage, 0);
      await afficher(tester, SondageScreen(sondageId: sondage.id));
      expect(find.byType(GraphiqueSondage), findsNothing); // pas encore voté
      await tester.tap(find.text('Oui'));
      await tester.pump();
      await tester.tap(find.text('Confirmer mon vote'));
      await tester.pumpAndSettle();
      expect(find.byType(GraphiqueSondage), findsOneWidget);
      expect(find.text('100 %'), findsWidgets);
    });
  });

  group('Lot 3 : qui apporte quoi, questions, avis', () {
    test('objets : l\'organisateur ajoute, un voisin s\'en charge, un autre non', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await devenir(sarra);
      expect((await depot.ajouterObjet(fete, 'Chaises')).estSucces, isFalse);

      await devenir(nizar);
      expect((await depot.ajouterObjet(fete, 'Chaises')).estSucces, isTrue);
      final ObjetAApporter chaises = (await depot.getObjets(fete.id)).donnee!.single;

      await devenir(sarra);
      expect((await depot.prendreObjet(fete.id, chaises, true)).estSucces, isTrue);
      final ObjetAApporter pris = (await depot.getObjets(fete.id)).donnee!.single;
      expect(pris.prisParNom, 'Sarra A.');

      // Amira ne peut pas le prendre à Sarra
      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      expect((await depot.prendreObjet(fete.id, pris, true)).estSucces, isFalse);
    });

    test('questions : vide refusé ; l\'organisateur supprime, un tiers non', () async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await devenir(sarra);
      expect((await depot.ajouterCommentaire(fete.id, '  ')).estSucces, isFalse);
      expect((await depot.ajouterCommentaire(fete.id, 'On apporte quoi ?')).estSucces,
          isTrue);
      final Commentaire question = (await depot.getCommentaires(fete.id)).donnee!.single;

      await utilisateurs.changerRole(sarra.id, RoleUtilisateur.resident);
      await devenir(nizar); // l'organisateur
      expect((await depot.supprimerCommentaire(fete.id, question.id)).estSucces, isTrue);
    });

    test('avis : seulement les participants, après l\'événement, une fois', () async {
      final Evenement ancien = depot.ajouterEvenementDe(nizar, date: hier);
      final Evenement futur = depot.ajouterEvenementDe(nizar);
      await devenir(sarra);
      // Pas participante
      expect((await depot.donnerAvis(ancien, 5, '')).estSucces, isFalse);

      // On l'inscrit "à la main" (l'événement est passé : participer() refuse)
      expect(EvenementRepository.refusAvis(ancien, 5, participe: true, dejaDonne: false),
          isNull);
      expect(EvenementRepository.refusAvis(futur, 5, participe: true, dejaDonne: false),
          isNotNull);
      expect(EvenementRepository.refusAvis(ancien, 0, participe: true, dejaDonne: false),
          isNotNull);
      expect(EvenementRepository.refusAvis(ancien, 4, participe: true, dejaDonne: true),
          isNotNull);
    });

    test('moyenne des avis', () {
      expect(EvenementRepository.moyenne([]), isNull);
      expect(
        EvenementRepository.moyenne(const [
          AvisEvenement(id: 'a', nom: 'A', note: 5),
          AvisEvenement(id: 'b', nom: 'B', note: 4),
        ]),
        4.5,
      );
    });

    testWidgets('détail : poser une question', (tester) async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await devenir(sarra);
      await afficher(tester, EvenementDetailScreen(evenementId: fete.id));
      await tester.scrollUntilVisible(find.text('Questions (0)'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.widgetWithText(TextField, 'Pose une question...'),
          'Il faut apporter quoi ?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('Questions (1)'), findsOneWidget);
      expect(find.text('Il faut apporter quoi ?'), findsOneWidget);
    });

    testWidgets('détail : l\'organisateur ajoute un objet à apporter', (tester) async {
      final Evenement fete = depot.ajouterEvenementDe(nizar);
      await devenir(nizar);
      await afficher(tester, EvenementDetailScreen(evenementId: fete.id));
      await tester.scrollUntilVisible(find.text('Qui apporte quoi ?'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(
          find.widgetWithText(TextField, 'Ajouter : chaises, boissons...'), 'Boissons');
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      expect(find.text('Boissons'), findsOneWidget);
      expect(find.text('Je l\'apporte'), findsOneWidget);
    });
  });

  group('Lot 4 : export, sondages de date, sondages d\'événement, nouveautés', () {
    test('export : la liste des participants en texte', () {
      final Evenement fete = Evenement(
        id: 'e', titre: 'Fête', description: '', lieu: 'Jardin',
        date: DateTime(2026, 11, 14, 18), organisateur: 'X', placesMax: 10,
      );
      final String texte = EvenementRepository.texteListeParticipants(fete, const [
        Participant(id: 'a', nom: 'Salma G.'),
        Participant(id: 'b', nom: 'Youssef T.'),
      ]);
      expect(texte, contains('Participants — Fête (14/11/2026)'));
      expect(texte, contains('1. Salma G.'));
      expect(texte, contains('2. Youssef T.'));
      expect(texte, contains('Total : 2 / 10 places'));
    });

    test('sondage de date : choix = dates, date gagnante', () async {
      final DateTime samedi = DateTime(2026, 11, 21, 18, 0);
      final DateTime dimanche = DateTime(2026, 11, 22, 10, 30);
      expect(EvenementRepository.texteChoixDate(samedi), 'sam. 21/11 · 18:00');

      await depot.creerSondage(
        question: 'Quelle date pour la fête ?',
        options: const [],
        dateFin: demain,
        dates: [samedi, dimanche],
      );
      final Sondage cree = depot.sondages.single;
      expect(cree.estSondageDeDate, isTrue);
      expect(cree.options.map((o) => o.texte),
          ['sam. 21/11 · 18:00', 'dim. 22/11 · 10:30']);

      depot.ajouterVoteDe(sarra, cree, 1);
      final Sondage relu = (await depot.chargerSondages()).donnee!.single;
      expect(relu.indexGagnant, 1);
      expect(relu.dates[relu.indexGagnant!], dimanche);
    });

    test('sondage rattaché à un événement', () async {
      final Evenement fete = depot.ajouterEvenementDe(amira);
      await depot.creerSondage(
        question: 'Quelle musique ?',
        options: ['Malouf', 'Mezoued'],
        dateFin: demain,
        evenementId: fete.id,
      );
      await depot.creerSondage(
        question: 'Autre sondage',
        options: ['A', 'B'],
        dateFin: demain,
      );
      final List<Sondage> deLaFete = (await depot.chargerSondagesDe(fete.id)).donnee!;
      expect(deLaFete.map((s) => s.question), ['Quelle musique ?']);
    });

    test('nouveautés : publiés par d\'autres après ma dernière visite', () {
      final DateTime visite = DateTime(2026, 11, 10);
      final List<Evenement> evenements = [
        Evenement(id: 'a', titre: 'Nouveau', description: '', lieu: '',
            date: demain, organisateur: 'X', organisateurId: 'u30',
            dateCreation: DateTime(2026, 11, 11)),
        Evenement(id: 'b', titre: 'Ancien', description: '', lieu: '',
            date: demain, organisateur: 'X', organisateurId: 'u30',
            dateCreation: DateTime(2026, 11, 9)),
        Evenement(id: 'c', titre: 'Le mien', description: '', lieu: '',
            date: demain, organisateur: 'Moi', organisateurId: 'u1',
            dateCreation: DateTime(2026, 11, 11)),
        Evenement(id: 'd', titre: 'Sans date', description: '', lieu: '',
            date: demain, organisateur: 'X'),
      ];
      final List<Sondage> sondages = [
        Sondage(id: 'p', question: 'Q', options: const [], dateFin: demain,
            proposeParId: 'u31', dateCreation: DateTime(2026, 11, 12)),
      ];
      expect(NouveautesM4.compter(evenements, sondages, visite, 'u1'), 2);
    });

    testWidgets('sondage de date : l\'auteur crée l\'événement à la date gagnante',
        (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(
        amira, // admin : peut organiser
        question: 'Quelle date ?',
        dates: [DateTime(2026, 12, 5, 19, 0), DateTime(2026, 12, 6, 19, 0)],
      );
      depot.ajouterVoteDe(sarra, sondage, 0);
      await afficher(tester, SondageScreen(sondageId: sondage.id));
      expect(find.text('Créer l\'événement le sam. 05/12 · 19:00'), findsOneWidget);
    });

    testWidgets('formulaire : interrupteur « Sondage de date »', (tester) async {
      await afficher(tester, const SondageFormScreen());
      expect(find.text('Ajouter une date'), findsNothing);
      await tester.tap(find.text('Sondage de date'));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter une date'), findsOneWidget);
      expect(find.text('Choix 1'), findsNothing);
    });
  });

  group('Lot 5 : liste d\'attente, statistiques', () {
    test('liste d\'attente : seulement si complet ; la place libérée lui revient', () async {
      final Evenement atelier = depot.ajouterEvenementDe(nizar, placesMax: 1);

      // Pas complet : on s'inscrit directement, pas de liste d'attente
      await devenir(sarra);
      expect((await depot.rejoindreAttente(atelier)).estSucces, isFalse);
      expect((await depot.participer(atelier.id)).estSucces, isTrue); // complet

      // Amira (admin) arrive trop tard : liste d'attente
      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      expect((await depot.rejoindreAttente(depot.evenements.single)).estSucces, isTrue);
      expect((await depot.getAttente(atelier.id)).donnee!.single.nom, 'Amira B.');

      // Sarra se retire : la place revient à Amira, pas à Nizar
      await devenir(sarra);
      await depot.seRetirer(atelier.id);
      await devenir(nizar);
      final Resultat<void> nizarRefuse = await depot.participer(atelier.id);
      expect(nizarRefuse.estSucces, isFalse);
      expect(nizarRefuse.erreur, contains('liste d\'attente'));

      await utilisateurs.connexion(
        MockUtilisateurRepository.emailDemo,
        MockUtilisateurRepository.motDePasseDemo,
      );
      expect((await depot.participer(atelier.id)).estSucces, isTrue);
      expect((await depot.getAttente(atelier.id)).donnee, isEmpty); // sortie de la liste
    });

    test('refusParticipation : priorité aux premiers de la liste', () {
      final Evenement deuxLibres = Evenement(
        id: 'e', titre: 'T', description: '', lieu: '', date: demain,
        organisateur: 'X', placesMax: 10, participants: 8,
      );
      final List<String> attente = ['a', 'b', 'c'];
      expect(EvenementRepository.refusParticipation(deuxLibres, attente: attente, moiId: 'a'),
          isNull);
      expect(EvenementRepository.refusParticipation(deuxLibres, attente: attente, moiId: 'b'),
          isNull);
      expect(EvenementRepository.refusParticipation(deuxLibres, attente: attente, moiId: 'c'),
          isNotNull);
      expect(EvenementRepository.refusParticipation(deuxLibres, attente: attente, moiId: 'z'),
          isNotNull);
    });

    test('statistiques : totaux, moyenne, taux de vote, par mois', () {
      final DateTime maintenant = DateTime(2026, 11, 11, 12);
      final List<Evenement> evenements = [
        Evenement(id: 'a', titre: 'Passé', description: '', lieu: '',
            date: DateTime(2026, 10, 3), organisateur: 'X', participants: 10),
        Evenement(id: 'b', titre: 'Passé 2', description: '', lieu: '',
            date: DateTime(2026, 11, 2), organisateur: 'X', participants: 4),
        Evenement(id: 'c', titre: 'Futur', description: '', lieu: '',
            date: DateTime(2026, 11, 20), organisateur: 'X', participants: 2),
        Evenement(id: 'd', titre: 'Annulé', description: '', lieu: '',
            date: DateTime(2026, 11, 25), organisateur: 'X', participants: 50,
            annule: true),
      ];
      final List<Sondage> sondages = [
        Sondage(id: 'p', question: 'Q', dateFin: DateTime(2027),
            nombreMembres: 10,
            options: const [OptionSondage(texte: 'A', votes: 4), OptionSondage(texte: 'B', votes: 1)]),
      ];
      final StatistiquesM4 stats = StatistiquesM4.calculer(evenements, sondages, maintenant);
      expect(stats.nbEvenements, 4);
      expect(stats.nbAnnules, 1);
      expect(stats.totalParticipants, 16); // l'annulé ne compte pas
      expect(stats.participationMoyenne, 7); // (10 + 4) / 2 passés
      expect(stats.tauxVoteMoyen, 0.5);
      expect(stats.evenementsParMois, [0, 0, 0, 0, 1, 2]); // oct. 1, nov. 2
      expect(stats.plusPopulaires.first.titre, 'Passé');
    });

    testWidgets('statistiques : l\'admin voit l\'icône, pas un résident', (tester) async {
      await afficher(tester, const EvenementsScreen());
      expect(find.byTooltip('Statistiques'), findsOneWidget);
      await tester.tap(find.byTooltip('Statistiques'));
      await tester.pumpAndSettle();
      expect(find.text('Événements par mois'), findsOneWidget);
    });

    testWidgets('statistiques : pas d\'icône pour une résidente', (tester) async {
      await devenir(sarra);
      await afficher(tester, const EvenementsScreen());
      expect(find.byTooltip('Statistiques'), findsNothing);
    });
  });

  group('Rappels et résultats en direct', () {
    test('rappels : seulement mes événements d\'aujourd\'hui et de demain', () {
      final DateTime maintenant = DateTime(2026, 11, 11, 10, 0);
      final Evenement ceSoir = Evenement(
          id: 'a', titre: 'Ce soir', description: '', lieu: 'Jardin',
          date: DateTime(2026, 11, 11, 18, 0), organisateur: 'X');
      final Evenement demainMatin = Evenement(
          id: 'b', titre: 'Demain', description: '', lieu: 'Parc',
          date: DateTime(2026, 11, 12, 9, 0), organisateur: 'X');
      final Evenement apresDemain = Evenement(
          id: 'c', titre: 'Plus tard', description: '', lieu: 'Salle',
          date: DateTime(2026, 11, 13, 9, 0), organisateur: 'X');
      final Evenement pasInscrit = Evenement(
          id: 'd', titre: 'Pas moi', description: '', lieu: 'Salle',
          date: DateTime(2026, 11, 11, 20, 0), organisateur: 'X');

      final List<Evenement> rappels = EvenementRepository.rappels(
        [apresDemain, demainMatin, ceSoir, pasInscrit],
        {'a', 'b', 'c'},
        maintenant,
      );
      expect(rappels.map((e) => e.id), ['a', 'b']);
      expect(EvenementRepository.texteRappel(ceSoir, maintenant),
          'Rappel : aujourd\'hui à 18:00, Ce soir (Jardin)');
      expect(EvenementRepository.texteRappel(demainMatin, maintenant),
          'Rappel : demain à 09:00, Demain (Parc)');
    });

    testWidgets('sondage : les votes d\'un voisin arrivent en direct', (tester) async {
      final Sondage sondage = depot.ajouterSondageDe(
        nizar,
        question: 'En direct ?',
        options: ['Oui', 'Non'],
      );
      await afficher(tester, SondageScreen(sondageId: sondage.id));
      expect(find.text('0 vote au total'), findsOneWidget);

      depot.voteEnDirect(sarra, sondage, 0); // Sarra vote sur son téléphone
      await tester.pumpAndSettle();
      expect(find.text('1 vote au total'), findsOneWidget);
    });
  });

  group('Rôle Leader', () {
    test('seuls les leaders et l\'admin organisent', () async {
      expect(EvenementRepository.peutOrganiser(amira), isTrue); // admin
      expect(EvenementRepository.peutOrganiser(sarra), isFalse); // résidente

      // Une résidente ne peut créer ni événement ni sondage
      await devenir(sarra);
      final Resultat<void> evenement = await depot.creerEvenement(
        titre: 'Fête',
        description: '',
        date: demain,
        lieu: 'Jardin',
        categorie: CategorieEvenement.fete,
      );
      expect(evenement.estSucces, isFalse);
      expect(evenement.erreur, EvenementRepository.refusOrganiser);
      final Resultat<void> sondage = await depot.creerSondage(
        question: 'Q ?',
        options: ['A', 'B'],
        dateFin: demain,
      );
      expect(sondage.estSucces, isFalse);
      expect(depot.evenements, isEmpty);
      expect(depot.sondages, isEmpty);
    });

    test('l\'admin nomme un leader, qui peut alors organiser', () async {
      expect((await utilisateurs.changerRole(sarra.id, RoleUtilisateur.leader)).estSucces,
          isTrue);

      await devenir(sarra);
      expect(utilisateurs.getUtilisateurConnecte().estLeader, isTrue);
      final Resultat<void> resultat = await depot.creerEvenement(
        titre: 'Tournoi de foot',
        description: '',
        date: demain,
        lieu: 'Terrain',
        categorie: CategorieEvenement.sport,
      );
      expect(resultat.estSucces, isTrue);
      expect(depot.evenements.single.organisateurId, sarra.id);
    });

    test('refusRole : seul l\'admin, jamais sur l\'admin ni vers admin', () async {
      // L'admin ne peut pas être leader, ni donner le rôle d'admin
      expect(UtilisateurRepository.refusRole(amira, amira, RoleUtilisateur.leader),
          isNotNull);
      expect(UtilisateurRepository.refusRole(amira, sarra, RoleUtilisateur.admin),
          isNotNull);
      expect(UtilisateurRepository.refusRole(amira, sarra, RoleUtilisateur.leader),
          isNull);

      // Une résidente ne peut nommer personne
      await devenir(sarra);
      expect((await utilisateurs.changerRole(nizar.id, RoleUtilisateur.leader)).estSucces,
          isFalse);
    });

    test('Firestore : le rôle leader est relu correctement', () {
      final Utilisateur relu = Utilisateur.fromMap('u9', {
        'prenom': 'Salma',
        'nom': 'G',
        'role': 'leader',
        'statut': 'actif',
      });
      expect(relu.estLeader, isTrue);
      expect(Utilisateur.fromMap('u9', {'role': 'inconnu'}).role,
          RoleUtilisateur.resident);
    });

    testWidgets('une résidente ne voit pas le bouton +', (tester) async {
      await devenir(sarra);
      await afficher(tester, const EvenementsScreen());
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.textContaining('Les leaders de ta houma'), findsOneWidget);
    });

    testWidgets('l\'admin voit le bouton +', (tester) async {
      await afficher(tester, const EvenementsScreen());
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('Formulaires', () {
    testWidgets('événement : titre et lieu obligatoires', (tester) async {
      await afficher(tester, const EvenementFormScreen());
      await tester.tap(find.text('Publier l\'événement'));
      await tester.pumpAndSettle();
      expect(find.text('Donne un titre à l\'événement'), findsOneWidget);
      expect(find.text('Indique le lieu'), findsOneWidget);
      expect(depot.evenements, isEmpty);
    });

    testWidgets('sondage : ajouter un choix, au moins 2 choix remplis', (tester) async {
      await afficher(tester, const SondageFormScreen());
      await tester.enterText(find.byType(TextFormField).at(0), 'Quelle date ?');
      await tester.enterText(find.byType(TextFormField).at(1), 'Samedi');
      await tester.tap(find.text('Publier le sondage'));
      await tester.pumpAndSettle();
      expect(find.text('Propose au moins 2 choix'), findsOneWidget);

      await tester.tap(find.text('Ajouter un choix'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(4)); // question + 3 choix
      await tester.enterText(find.byType(TextFormField).at(2), 'Dimanche');
      await tester.tap(find.text('Publier le sondage'));
      await tester.pumpAndSettle();
      expect(depot.sondages.single.options.length, 2); // le choix vide est ignoré
    });
  });
}
