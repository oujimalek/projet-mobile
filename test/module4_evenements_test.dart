import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/sondage.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module4/evenement_detail_screen.dart';
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
      expect((await depot.getParticipants(fete.id)).donnee, ['Amira B.']);

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
