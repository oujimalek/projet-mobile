import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/election.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/election_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module4/election_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'mock_election_repository.dart';
import 'mock_utilisateur_repository.dart';

Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  late MockUtilisateurRepository utilisateurs;
  late MockElectionRepository depot;
  late Utilisateur amira; // admin dans le mock M1

  final DateTime maintenant = DateTime.now();
  final DateTime ilYa2Mois = maintenant.subtract(const Duration(days: 60));

  // Membres actifs du quartier q1 (arrivés il y a 2 mois)
  final Utilisateur nizar = Utilisateur(
    id: 'u30',
    prenom: 'Nizar',
    nom: 'Hamdi',
    email: 'nizar@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine',
    dateDemande: ilYa2Mois,
  );
  final Utilisateur sarra = Utilisateur(
    id: 'u31',
    prenom: 'Sarra',
    nom: 'Ayari',
    email: 'sarra@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine',
    dateDemande: ilYa2Mois,
  );
  // Arrivé il y a 3 jours
  final Utilisateur nouveau = Utilisateur(
    id: 'u32',
    prenom: 'Karim',
    nom: 'Nouri',
    email: 'karim@houmani.tn',
    telephone: '',
    quartierId: 'q1',
    quartier: 'Résidence El Yasmine',
    residence: 'Résidence El Yasmine',
    dateDemande: maintenant.subtract(const Duration(days: 3)),
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    utilisateurs = MockUtilisateurRepository();
    UtilisateurRepository.instance = utilisateurs;
    depot = MockElectionRepository();
    ElectionRepository.instance = depot;
    amira = utilisateurs.getUtilisateurConnecte();
    utilisateurs.ajouterCompte(nizar, 'pw');
    utilisateurs.ajouterCompte(sarra, 'pw');
    utilisateurs.ajouterCompte(nouveau, 'pw');
  });

  Future<void> devenir(Utilisateur utilisateur) async {
    await utilisateurs.connexion(utilisateur.email, 'pw');
  }

  Future<void> redevenirAdmin() async {
    await utilisateurs.connexion(
      MockUtilisateurRepository.emailDemo,
      MockUtilisateurRepository.motDePasseDemo,
    );
  }

  /// Une élection dans la phase voulue.
  Election enCandidatures({bool premiere = false}) {
    return depot.ajouterElection(
      debut: maintenant.subtract(const Duration(hours: 1)),
      finCandidatures: maintenant.add(const Duration(days: 2)),
      finVote: maintenant.add(const Duration(days: 4)),
      premiere: premiere,
    );
  }

  Election enVote() {
    return depot.ajouterElection(
      debut: maintenant.subtract(const Duration(days: 3)),
      finCandidatures: maintenant.subtract(const Duration(hours: 1)),
      finVote: maintenant.add(const Duration(days: 1)),
    );
  }

  Election enDepouillement() {
    return depot.ajouterElection(
      debut: maintenant.subtract(const Duration(days: 6)),
      finCandidatures: maintenant.subtract(const Duration(days: 3)),
      finVote: maintenant.subtract(const Duration(hours: 1)),
      nbPlaces: 1,
    );
  }

  group('Règles (sans réseau)', () {
    test('phases calculées à partir des dates', () {
      expect(enCandidatures().phase(), PhaseElection.candidatures);
      expect(enVote().phase(), PhaseElection.vote);
      expect(enDepouillement().phase(), PhaseElection.depouillement);
    });

    test('nouvelle : 3 j + 2 j, ou 12 h + 12 h si anticipée', () {
      final Election normale = ElectionRepository.nouvelle(
          debut: maintenant, nbPlaces: 3, anticipee: false, premiere: true);
      expect(normale.finCandidatures.difference(maintenant).inDays, 3);
      expect(normale.finVote.difference(maintenant).inDays, 5);
      final Election anticipee = ElectionRepository.nouvelle(
          debut: maintenant, nbPlaces: 3, anticipee: true, premiere: false);
      expect(anticipee.finVote.difference(maintenant).inHours, 24);
    });

    test('candidature : pas l\'admin ; 1 mois d\'ancienneté sauf 1re élection', () {
      final Election ordinaire = enCandidatures();
      final Election premiere = enCandidatures(premiere: true);
      expect(ElectionRepository.refusCandidature(amira, premiere, dejaCandidat: false),
          isNotNull);
      expect(ElectionRepository.refusCandidature(nizar, ordinaire, dejaCandidat: false),
          isNull);
      expect(ElectionRepository.refusCandidature(nouveau, ordinaire, dejaCandidat: false),
          isNotNull);
      expect(ElectionRepository.refusCandidature(nouveau, premiere, dejaCandidat: false),
          isNull);
      expect(ElectionRepository.refusCandidature(nizar, enVote(), dejaCandidat: false),
          isNotNull);
    });

    test('égalité pour la dernière place', () {
      const List<Candidat> candidats = [
        Candidat(id: 'a', nom: 'A', nbVoix: 5),
        Candidat(id: 'b', nom: 'B', nbVoix: 3),
        Candidat(id: 'c', nom: 'C', nbVoix: 3),
      ];
      expect(ElectionRepository.egalite(candidats, 1), isFalse);
      expect(ElectionRepository.egalite(candidats, 2), isTrue);
      expect(ElectionRepository.elusProposes(candidats, 1).single.id, 'a');
    });

    test('prochaine élection : 6 mois après la dernière publiée', () {
      expect(ElectionRepository.prochaineElection(null), isNull);
      final Election publiee = depot.ajouterElection(
        debut: maintenant,
        finCandidatures: maintenant,
        finVote: maintenant,
        publiee: true,
      );
      expect(ElectionRepository.prochaineElection(publiee),
          maintenant.add(ElectionRepository.periodicite));
    });
  });

  group('Parcours complet (mock)', () {
    test('seul l\'admin ouvre ; pas deux élections en même temps', () async {
      await devenir(sarra);
      expect((await depot.ouvrirElection(nbPlaces: 2, anticipee: false)).estSucces,
          isFalse);
      await redevenirAdmin();
      expect((await depot.ouvrirElection(nbPlaces: 2, anticipee: false)).estSucces,
          isTrue);
      expect(depot.elections.single.premiere, isTrue);
      expect((await depot.ouvrirElection(nbPlaces: 2, anticipee: true)).estSucces,
          isFalse);
    });

    test('demandes d\'élection : comptées, puis effacées à l\'ouverture', () async {
      await devenir(sarra);
      await depot.demanderElection(true);
      await devenir(nizar);
      await depot.demanderElection(true);
      await redevenirAdmin();
      expect((await depot.compterDemandes()).donnee, 2);
      await depot.ouvrirElection(nbPlaces: 1, anticipee: true);
      expect((await depot.compterDemandes()).donnee, 0);
    });

    test('vote : une seule voix, pendant le vote', () async {
      final Election election = enVote();
      depot.ajouterCandidat(election, nizar);
      await devenir(sarra);
      expect((await depot.voter(election, nizar.id)).estSucces, isTrue);
      expect((await depot.voter(election, nizar.id)).estSucces, isFalse);
      expect((await depot.getMonVote(election.id)).donnee, nizar.id);
      final List<Candidat> candidats = (await depot.getCandidats(election.id)).donnee!;
      expect(candidats.single.nbVoix, 1);
    });

    test('publier : l\'élu devient leader, l\'ancien leader redevient résident', () async {
      await utilisateurs.changerRole(sarra.id, RoleUtilisateur.leader); // ancienne leader
      final Election election = enDepouillement();
      depot.ajouterCandidat(election, nizar, voix: 4);
      depot.ajouterCandidat(election, sarra, voix: 1);

      final List<Candidat> candidats = (await depot.getCandidats(election.id)).donnee!;
      final Resultat<void> resultat = await depot.publierResultats(
        election,
        ElectionRepository.elusProposes(candidats, 1),
      );
      expect(resultat.estSucces, isTrue);

      final List<Utilisateur> actifs =
          (await utilisateurs.getMembres(StatutUtilisateur.actif)).donnee!;
      expect(actifs.firstWhere((u) => u.id == nizar.id).estLeader, isTrue);
      expect(actifs.firstWhere((u) => u.id == sarra.id).estLeader, isFalse);
      expect(depot.elections.single.publiee, isTrue);
      expect(depot.elections.single.elusNoms, ['Nizar H.']);
    });
  });

  group('ElectionScreen', () {
    testWidgets('aucune élection : membre → demander une élection', (tester) async {
      await devenir(sarra);
      await afficher(tester, const ElectionScreen());
      expect(find.text('Pas encore de leaders élus.'), findsOneWidget);
      await tester.tap(find.text('Demander une nouvelle élection'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer ma demande'), findsOneWidget);
    });

    testWidgets('aucune élection : l\'admin peut l\'ouvrir', (tester) async {
      await afficher(tester, const ElectionScreen());
      await tester.tap(find.text('Ouvrir l\'élection (3 j + 2 j)'));
      await tester.pumpAndSettle();
      expect(find.text('Candidatures ouvertes'), findsOneWidget);
    });

    testWidgets('candidatures : se porter candidat', (tester) async {
      enCandidatures();
      await devenir(nizar);
      await afficher(tester, const ElectionScreen());
      await tester.tap(find.text('Me porter candidat'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Je m\'occupe du jardin');
      await tester.tap(find.text('Me présenter'));
      await tester.pumpAndSettle();
      expect(find.text('Nizar H.'), findsOneWidget);
      expect(find.text('Retirer ma candidature'), findsOneWidget);
    });

    testWidgets('vote : choisir puis confirmer', (tester) async {
      final Election election = enVote();
      depot.ajouterCandidat(election, nizar);
      await devenir(sarra);
      await afficher(tester, const ElectionScreen());
      await tester.tap(find.text('Nizar H.'));
      await tester.pump();
      await tester.tap(find.text('Confirmer mon vote'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ton vote est enregistré'), findsOneWidget);
    });
  });
}
