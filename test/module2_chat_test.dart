import 'package:flutter/material.dart';
// Evaluation existe aussi dans flutter_test : on la masque pour éviter tout conflit
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:google_fonts/google_fonts.dart';

import 'package:houmani/data/models/demande_service.dart';
import 'package:houmani/data/models/message_chat.dart';
import 'package:houmani/data/models/statut_demande.dart';
import 'package:houmani/data/services/chat_repository.dart';
import 'package:houmani/data/services/service_repository.dart';
import 'package:houmani/screens/module2/chat_screen.dart';
import 'package:houmani/screens/module2/mes_demandes_screen.dart';
import 'package:houmani/theme/app_theme.dart';

/// Affiche un écran dans une MaterialApp avec le thème Houmani.
Future<void> afficher(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ecran));
  await tester.pumpAndSettle();
}

void main() {
  final ServiceRepository serviceRepository = ServiceRepository();
  final ChatRepository chat = ChatRepository();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Les listes sont static : on remet tout à zéro, sans réponse automatique
  setUp(() {
    ChatRepository.reponseAutomatiqueActive = false;
    serviceRepository.reinitialiser();
    chat.reinitialiser();
  });

  tearDown(() {
    ChatRepository.reponseAutomatiqueActive = true;
    chat.reinitialiser();
  });

  /// Copie d'une demande de départ avec un autre statut.
  DemandeService avecStatut(String id, StatutDemande statut) {
    return serviceRepository.getDemandeParId(id)!.copyWith(statut: statut);
  }

  group('Chat : peutDiscuter', () {
    test('faux en attente et refusée', () {
      expect(
        chat.peutDiscuter(avecStatut('d2', StatutDemande.enAttente)),
        isFalse,
      );
      expect(
        chat.peutDiscuter(avecStatut('d2', StatutDemande.refusee)),
        isFalse,
      );
    });

    test('vrai acceptée et réalisée', () {
      expect(
        chat.peutDiscuter(avecStatut('d2', StatutDemande.acceptee)),
        isTrue,
      );
      expect(
        chat.peutDiscuter(avecStatut('d2', StatutDemande.realisee)),
        isTrue,
      );
      // Côté auteur du service (demande reçue)
      expect(
        chat.peutDiscuter(serviceRepository.getDemandeParId('d5')!),
        isTrue,
      );
    });

    test('faux pour une personne étrangère à la demande', () {
      // h1 : Salma G. et Karim M., réalisée, mais je n'y suis pour rien
      expect(
        chat.peutDiscuter(serviceRepository.getDemandeParId('h1')!),
        isFalse,
      );
    });

    test('getInterlocuteur donne l\'autre personne', () {
      expect(
        chat.getInterlocuteur(serviceRepository.getDemandeParId('d2')!),
        'Nizar H.',
      );
      expect(
        chat.getInterlocuteur(serviceRepository.getDemandeParId('d5')!),
        'Sarra A.',
      );
    });
  });

  group('Chat : messages', () {
    test(
      'données de départ : 4 messages, triés du plus ancien au plus récent',
      () {
        expect(chat.getMessages('d2').length, 3);
        expect(chat.getMessages('d5').length, 1);

        final List<MessageChat> messages = chat.getMessages('d2');
        expect(messages.first.id, 'm1');
        expect(messages.last.id, 'm3');
        expect(chat.dernierMessage('d2')!.id, 'm3');
        expect(chat.dernierMessage('d1'), isNull);
      },
    );

    test('envoyerMessage : refusé si vide, espaces seulement ou trop long', () {
      expect(chat.envoyerMessage('d2', ''), isFalse);
      expect(chat.envoyerMessage('d2', '    '), isFalse);
      expect(chat.envoyerMessage('d2', 'a' * 501), isFalse);
      expect(chat.getMessages('d2').length, 3);
    });

    test('envoyerMessage : refusé si la demande n\'est pas acceptée', () {
      expect(chat.envoyerMessage('d1', 'Salam'), isFalse); // en attente
      expect(chat.envoyerMessage('h1', 'Salam'), isFalse); // étrangère
      expect(chat.envoyerMessage('inconnue', 'Salam'), isFalse);
    });

    test('envoyerMessage : accepté (500 caractères au maximum)', () {
      expect(chat.envoyerMessage('d2', '  Merci Nizar !  '), isTrue);
      expect(chat.envoyerMessage('d2', 'a' * 500), isTrue);

      final List<MessageChat> messages = chat.getMessages('d2');
      expect(messages.length, 5);
      expect(messages[3].texte, 'Merci Nizar !'); // espaces retirés
      expect(messages[3].auteur, serviceRepository.getMonNom());
    });

    test('nombreNonLus et marquerCommeLus', () {
      expect(chat.nombreNonLus('d2'), 1);
      expect(chat.nombreNonLus('d5'), 1);

      chat.marquerCommeLus('d2');
      expect(chat.nombreNonLus('d2'), 0);
      expect(chat.nombreNonLus('d5'), 1); // l'autre conversation ne change pas
    });

    test('mes propres messages ne comptent pas comme non lus', () {
      chat.envoyerMessage('d2', 'Salam');
      expect(chat.nombreNonLus('d2'), 1);
    });
  });

  group('Chat : écrans', () {
    testWidgets('"Contacter" ouvre le chat, on écrit et on envoie', (
      WidgetTester tester,
    ) async {
      await afficher(tester, const MesDemandesScreen());

      // Badge des messages non lus et aperçu du dernier message
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('Nizar : Passe avant 19h'), findsOneWidget);

      // d2 (acceptée) est la première demande avec un bouton "Contacter"
      await tester.tap(find.text('Contacter').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Nizar H.'), findsOneWidget);
      expect(
        find.text('Salam Amira ! Oui bien sûr, je suis là après 17h.'),
        findsOneWidget,
      );
      expect(find.text('Aujourd\'hui'), findsWidgets);

      // Le bouton envoyer est désactivé tant que le champ est vide
      final Finder boutonEnvoi = find.widgetWithIcon(IconButton, Icons.send);
      expect(tester.widget<IconButton>(boutonEnvoi).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Je passe vers 18h');
      await tester.pump();
      expect(tester.widget<IconButton>(boutonEnvoi).onPressed, isNotNull);

      await tester.tap(boutonEnvoi);
      await tester.pumpAndSettle();
      expect(find.text('Je passe vers 18h'), findsOneWidget);
      expect(tester.widget<IconButton>(boutonEnvoi).onPressed, isNull);

      // Retour : le badge a disparu, l'aperçu montre mon message
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(chat.nombreNonLus('d2'), 0);
      expect(find.text('1'), findsNothing);
      expect(find.text('Toi : Je passe vers 18h'), findsOneWidget);
    });

    testWidgets('un message rapide remplit le champ', (
      WidgetTester tester,
    ) async {
      await afficher(tester, const ChatScreen(demandeId: 'd2'));

      await tester.tap(find.text('À quelle heure ?'));
      await tester.pump();

      final TextField champ = tester.widget<TextField>(find.byType(TextField));
      expect(champ.controller!.text, 'À quelle heure ?');
    });

    testWidgets('conversation vide : message d\'accueil', (
      WidgetTester tester,
    ) async {
      // d4 (Youssef T.) vient d'être acceptée : aucun message pour l'instant
      serviceRepository.changerStatutDemande('d4', StatutDemande.acceptee);
      await afficher(tester, const ChatScreen(demandeId: 'd4'));

      expect(
        find.text('Aucun message. Dis bonjour à Youssef 👋'),
        findsOneWidget,
      );
    });

    testWidgets('demande en attente : pas de champ de saisie', (
      WidgetTester tester,
    ) async {
      await afficher(tester, const ChatScreen(demandeId: 'd1'));

      expect(
        find.text('Le chat est disponible une fois la demande acceptée.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('demande réalisée : le chat reste lisible et on peut écrire', (
      WidgetTester tester,
    ) async {
      serviceRepository.changerStatutDemande('d2', StatutDemande.realisee);
      await afficher(tester, const ChatScreen(demandeId: 'd2'));

      expect(find.text('Réalisée'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Merci beaucoup !');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pumpAndSettle();
      expect(chat.getMessages('d2').length, 4);
    });

    testWidgets('la réponse automatique arrive après environ 2 secondes', (
      WidgetTester tester,
    ) async {
      ChatRepository.reponseAutomatiqueActive = true;
      await afficher(tester, const ChatScreen(demandeId: 'd2'));

      await tester.enterText(find.byType(TextField), 'Salam');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pump();

      // Pendant l'attente : "Nizar écrit…"
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Nizar écrit…'), findsOneWidget);
      expect(find.text('D\'accord, ça marche !'), findsNothing);

      // Après 2 secondes : la réponse est là
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Nizar écrit…'), findsNothing);
      expect(find.text('D\'accord, ça marche !'), findsOneWidget);
      expect(chat.nombreNonLus('d2'), 0); // l'écran ouvert l'a déjà lue
    });

    testWidgets('écran fermé avant la réponse : aucun plantage', (
      WidgetTester tester,
    ) async {
      ChatRepository.reponseAutomatiqueActive = true;
      await afficher(tester, const MesDemandesScreen());

      await tester.tap(find.text('Contacter').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Salam');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pump();

      // On quitte le chat avant la réponse
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);

      // La réponse arrive quand même, comme "non lue", sans erreur
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(chat.nombreNonLus('d2'), 1);
    });
  });
}
