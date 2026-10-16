import 'package:flutter/material.dart';
// Evaluation existe aussi dans flutter_test : on la masque pour éviter tout conflit
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/message_chat.dart';
import 'package:houmani/data/models/service.dart';
import 'package:houmani/data/models/statut_demande.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/chat_repository.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
import 'package:houmani/screens/module2/chat_screen.dart';
import 'package:houmani/screens/module2/mes_demandes_screen.dart';
import 'package:houmani/theme/app_theme.dart';

import 'mock_chat_repository.dart';
import 'mock_service_repository.dart';
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
  late MockServiceRepository depot;
  late MockChatRepository chat;
  late Utilisateur amira;

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

  late Service serviceDeNizar;
  late DemandeService acceptee; // ma demande (Amira) chez Nizar

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Dépôts VIDES avant chaque test : aucune donnée de démo, aucune réponse
  // automatique. Utilisateur connecté : Amira B. (mock du module 1).
  setUp(() {
    utilisateurs = MockUtilisateurRepository();
    UtilisateurRepository.instance = utilisateurs;
    depot = MockServiceRepository();
    ServiceRepository.instance = depot;
    chat = MockChatRepository();
    ChatRepository.instance = chat;
    amira = utilisateurs.getUtilisateurConnecte();
    utilisateurs.ajouterCompte(nizar, 'pw');
    utilisateurs.ajouterCompte(sarra, 'pw');
    serviceDeNizar = depot.ajouterServiceDe(nizar, titre: 'Perceuse à prêter');
    acceptee = depot.ajouterDemandeDe(amira, serviceDeNizar, statut: StatutDemande.acceptee);
  });

  Future<void> devenir(Utilisateur utilisateur) async {
    await utilisateurs.connexion(utilisateur.email, 'pw');
  }

  DemandeService avecStatut(StatutDemande statut) {
    return acceptee.copyWith(statut: statut);
  }

  group('Chat : règles sans réseau', () {
    test('peutDiscuter : faux en attente et refusée, vrai acceptée et réalisée', () {
      expect(ChatRepository.peutDiscuter(avecStatut(StatutDemande.enAttente), amira.id), isFalse);
      expect(ChatRepository.peutDiscuter(avecStatut(StatutDemande.refusee), amira.id), isFalse);
      expect(ChatRepository.peutDiscuter(avecStatut(StatutDemande.acceptee), amira.id), isTrue);
      expect(ChatRepository.peutDiscuter(avecStatut(StatutDemande.realisee), amira.id), isTrue);
    });

    test('peutDiscuter : faux pour quelqu\'un qui n\'est pas dans la demande', () {
      expect(ChatRepository.peutDiscuter(acceptee, nizar.id), isTrue); // l'auteur
      expect(ChatRepository.peutDiscuter(acceptee, sarra.id), isFalse); // un tiers
    });

    test('interlocuteur : l\'autre personne', () {
      expect(ChatRepository.interlocuteur(acceptee, amira.id), 'Nizar H.');
      expect(ChatRepository.interlocuteur(acceptee, nizar.id), 'Amira B.');
    });

    test('refusMessage : vide, trop long, chat fermé', () {
      expect(ChatRepository.refusMessage(acceptee, '   ', amira.id), isNotNull);
      expect(
        ChatRepository.refusMessage(acceptee, 'a' * (ChatRepository.longueurMax + 1), amira.id),
        isNotNull,
      );
      expect(
        ChatRepository.refusMessage(avecStatut(StatutDemande.enAttente), 'Salam', amira.id),
        isNotNull,
      );
      expect(ChatRepository.refusMessage(acceptee, 'Salam', amira.id), isNull);
      expect(
        ChatRepository.refusMessage(acceptee, 'a' * ChatRepository.longueurMax, amira.id),
        isNull,
      );
    });

    test('compterNonLus : seulement les messages de l\'autre, pas encore lus', () {
      final DateTime maintenant = DateTime.now();
      final List<MessageChat> messages = [
        MessageChat(id: '1', demandeId: 'd', auteurId: nizar.id, auteurNom: 'Nizar H.', texte: 'a', date: maintenant),
        MessageChat(id: '2', demandeId: 'd', auteurId: nizar.id, auteurNom: 'Nizar H.', texte: 'b', date: maintenant, lu: true),
        MessageChat(id: '3', demandeId: 'd', auteurId: amira.id, auteurNom: 'Amira B.', texte: 'c', date: maintenant),
      ];
      expect(ChatRepository.compterNonLus(messages, amira.id), 1);
      expect(ChatRepository.compterNonLus(messages, nizar.id), 1);
    });

    test('MessageChat : toMap puis fromMap', () {
      final MessageChat message = MessageChat(
        id: 'm1',
        demandeId: 'd1',
        auteurId: 'u1',
        auteurNom: 'Amira B.',
        texte: 'Salam',
        date: DateTime(2026, 10, 1),
      );
      final Map<String, dynamic> map = message.toMap();
      expect(map['auteurId'], 'u1');
      expect(map['lu'], false);
      expect(map.containsKey('demandeId'), isFalse); // dans le chemin
      final MessageChat vide = MessageChat.fromMap('m2', 'd1', {});
      expect(vide.texte, '');
      expect(vide.demandeId, 'd1');
      expect(vide.lu, isFalse);
    });
  });

  group('Chat : repository (mock)', () {
    test('au départ, aucun message et aucune réponse automatique', () async {
      expect(await chat.ecouterMessages(acceptee.id).first, isEmpty);
      final Resultat<void> resultat = await chat.envoyerMessage(acceptee, 'Salam Nizar');
      expect(resultat.estSucces, isTrue);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(chat.messages.length, 1); // personne ne répond tout seul
    });

    test('envoyerMessage : l\'auteur est l\'utilisateur connecté (uid + nom)', () async {
      await chat.envoyerMessage(acceptee, '  Salam Nizar  ');
      final MessageChat message = chat.messages.single;
      expect(message.auteurId, amira.id);
      expect(message.auteurNom, 'Amira B.');
      expect(message.texte, 'Salam Nizar');
      expect(message.lu, isFalse);
      expect(message.demandeId, acceptee.id);
    });

    test('envoyerMessage : refusé si le chat est fermé, vide ou trop long', () async {
      expect((await chat.envoyerMessage(avecStatut(StatutDemande.enAttente), 'Salam')).estSucces, isFalse);
      expect((await chat.envoyerMessage(acceptee, '   ')).estSucces, isFalse);
      expect(
        (await chat.envoyerMessage(acceptee, 'a' * (ChatRepository.longueurMax + 1))).estSucces,
        isFalse,
      );
      expect(chat.messages, isEmpty);
    });

    test('les messages arrivent en direct, du plus ancien au plus récent', () async {
      final Future<List<List<MessageChat>>> listes = chat.ecouterMessages(acceptee.id).take(3).toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      chat.ajouterMessageDe(nizar, acceptee.id, 'Premier');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      chat.ajouterMessageDe(amira, acceptee.id, 'Deuxième');
      final List<List<MessageChat>> recues = await listes;
      expect(recues[0], isEmpty);
      expect(recues[1].length, 1);
      expect(recues[2].map((m) => m.texte).toList(), ['Premier', 'Deuxième']);
    });

    test('marquerCommeLus : seulement les messages de l\'autre', () async {
      chat.ajouterMessageDe(nizar, acceptee.id, 'Salut');
      chat.ajouterMessageDe(amira, acceptee.id, 'Salam');
      await chat.marquerCommeLus(acceptee.id);
      final List<MessageChat> messages = chat.messages;
      expect(messages[0].lu, isTrue); // reçu : lu
      expect(messages[1].lu, isFalse); // le mien : au destinataire de le lire
    });

    test('erreur de connexion : dans le Stream et dans le Resultat', () async {
      chat.erreur = 'Serveur injoignable, vérifie ta connexion Internet';
      await expectLater(chat.ecouterMessages(acceptee.id), emitsError(chat.erreur));
      expect((await chat.envoyerMessage(acceptee, 'Salam')).erreur, chat.erreur);
    });

    test('personne n\'est connecté', () async {
      await devenir(sarra);
      await utilisateurs.supprimerCompte('pw');
      await expectLater(
        chat.ecouterMessages(acceptee.id),
        emitsError('Tu n\'es pas connecté'),
      );
      expect((await chat.envoyerMessage(acceptee, 'Salam')).erreur, 'Tu n\'es pas connecté');
    });
  });

  group('Écran : chat', () {
    testWidgets('sans message : invitation à dire bonjour', (WidgetTester tester) async {
      await afficher(tester, ChatScreen(demandeId: acceptee.id));
      expect(find.textContaining('Aucun message. Dis bonjour à Nizar'), findsOneWidget);
      expect(find.text('Nizar H.'), findsOneWidget); // en-tête
      expect(find.text('Perceuse à prêter'), findsOneWidget);
    });

    testWidgets('envoyer un message : il s\'affiche, le champ est vidé', (WidgetTester tester) async {
      await afficher(tester, ChatScreen(demandeId: acceptee.id));

      await tester.enterText(find.byType(TextField), 'Salam Nizar');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(find.text('Salam Nizar'), findsOneWidget); // la bulle
      expect(chat.messages.single.auteurId, amira.id);
      expect(find.text(''), findsWidgets); // le champ est vide
      final TextField champ = tester.widget(find.byType(TextField));
      expect(champ.controller!.text, isEmpty);
    });

    testWidgets('le bouton Envoyer est désactivé avec un champ vide', (WidgetTester tester) async {
      await afficher(tester, ChatScreen(demandeId: acceptee.id));
      final IconButton bouton = tester.widget(find.widgetWithIcon(IconButton, Icons.send));
      expect(bouton.onPressed, isNull);
    });

    testWidgets('un message reçu s\'affiche en direct et est marqué comme lu', (WidgetTester tester) async {
      await afficher(tester, ChatScreen(demandeId: acceptee.id));
      chat.ajouterMessageDe(nizar, acceptee.id, 'Passe avant 19h');
      await tester.pumpAndSettle();
      expect(find.text('Passe avant 19h'), findsOneWidget);
      expect(chat.messages.single.lu, isTrue);
    });

    testWidgets('messages rapides : remplissent le champ', (WidgetTester tester) async {
      await afficher(tester, ChatScreen(demandeId: acceptee.id));
      // La rangée de messages rapides défile : on amène celui-ci à l'écran
      await tester.ensureVisible(find.text('Merci beaucoup !'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merci beaucoup !'));
      await tester.pump();
      final TextField champ = tester.widget(find.byType(TextField));
      expect(champ.controller!.text, 'Merci beaucoup !');
    });

    testWidgets('demande en attente : le chat est fermé', (WidgetTester tester) async {
      final DemandeService attente = depot.ajouterDemandeDe(
        amira,
        depot.ajouterServiceDe(sarra, titre: 'Courses'),
      );
      await afficher(tester, ChatScreen(demandeId: attente.id));
      expect(find.text('Le chat est disponible une fois la demande acceptée.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('demande inconnue : message clair', (WidgetTester tester) async {
      await afficher(tester, const ChatScreen(demandeId: 'inconnue'));
      expect(find.text('Cette demande n\'existe plus'), findsOneWidget);
    });

    testWidgets('erreur de connexion lisible', (WidgetTester tester) async {
      depot.erreur = 'Serveur injoignable, vérifie ta connexion Internet';
      await afficher(tester, ChatScreen(demandeId: acceptee.id));
      expect(find.text('Serveur injoignable, vérifie ta connexion Internet'), findsOneWidget);
    });
  });

  group('Mes demandes → chat', () {
    testWidgets('Contacter ouvre le chat de la demande', (WidgetTester tester) async {
      chat.ajouterMessageDe(nizar, acceptee.id, 'Passe avant 19h');
      await afficher(tester, const MesDemandesScreen());
      expect(find.text('1'), findsOneWidget); // badge "non lu"

      await tester.tap(find.text('Contacter'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Passe avant 19h'), findsWidgets);
    });
  });
}
