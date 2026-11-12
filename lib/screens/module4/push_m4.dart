import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../data/models/evenement.dart';
import '../../data/services/evenement_repository.dart';
import 'notifications_m4.dart';

/// M4 - (C4) Les notifications PUSH : un nouvel événement est annoncé sur
/// le téléphone de tous les voisins, même application fermée. Gratuit :
///
/// - chaque téléphone s'abonne au sujet "quartier_{id}" de Firebase Cloud
///   Messaging (FCM) ;
/// - la leader (ou l'admin) qui publie appelle notre petit serveur
///   Cloudflare (dossier push_worker/), qui garde la clé secrète, vérifie
///   qu'elle est bien leader/admin du quartier, puis envoie la notification.
///
/// Que des static ; ne lève jamais d'exception (tests, pas de réseau...).
class PushM4 {
  PushM4._();

  /// L'adresse du Worker Cloudflare (pas un secret : il vérifie qui appelle).
  static const String adresseWorker =
      'https://houmani-push.houmani-push.workers.dev/notifier';

  static const String _nomBoite = 'houmani_m4';
  static bool _ecoute = false;

  /// Le sujet FCM d'un quartier.
  static String sujet(String quartierId) => 'quartier_$quartierId';

  /// Le texte de la notification d'un nouvel événement.
  static String corps(Evenement evenement) {
    return '${EvenementRepository.texteChoixDate(evenement.date)} · ${evenement.lieu}';
  }

  /// S'abonne aux annonces de MON quartier (et se désabonne de l'ancien
  /// si j'ai changé de quartier). Appelé à l'ouverture de l'accueil.
  static Future<void> abonner(String? quartierId, {bool organisateur = false}) async {
    try {
      final FirebaseMessaging messagerie = FirebaseMessaging.instance;
      await messagerie.requestPermission();
      Box<dynamic> boite;
      if (Hive.isBoxOpen(_nomBoite)) {
        boite = Hive.box<dynamic>(_nomBoite);
      } else {
        await Hive.initFlutter();
        boite = await Hive.openBox<dynamic>(_nomBoite);
      }
      final String? ancien = boite.get('sujetPush') as String?;
      final String? nouveau = quartierId == null ? null : sujet(quartierId);
      if (ancien != null && ancien != nouveau) {
        await messagerie.unsubscribeFromTopic(ancien);
      }
      if (nouveau != null) {
        await messagerie.subscribeToTopic(nouveau);
      }
      await boite.put('sujetPush', nouveau);
      // (IA) Leaders et admin : les idées de l'assistant du lundi
      final String? ancienLeaders = boite.get('sujetLeaders') as String?;
      final String? leaders =
          (quartierId != null && organisateur) ? 'leaders_$quartierId' : null;
      if (ancienLeaders != null && ancienLeaders != leaders) {
        await messagerie.unsubscribeFromTopic(ancienLeaders);
      }
      if (leaders != null) {
        await messagerie.subscribeToTopic(leaders);
      }
      await boite.put('sujetLeaders', leaders);
      _ecouterAuPremierPlan();
    } catch (e) {
      // pas de Firebase (tests), pas de réseau... : pas de push, c'est tout
    }
  }

  /// Application ouverte : Android n'affiche pas la notification tout
  /// seul, on la montre nous-mêmes (sauf pour celle qui l'a publiée).
  static void _ecouterAuPremierPlan() {
    if (_ecoute) {
      return;
    }
    _ecoute = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final RemoteNotification? notification = message.notification;
      final String? moi = FirebaseAuth.instance.currentUser?.uid;
      if (notification == null || message.data['auteurId'] == moi) {
        return;
      }
      NotificationsM4.afficher(
        notification.title ?? 'Nouvel événement',
        notification.body ?? '',
      );
    });
  }

  /// Annonce un nouvel événement à tout le quartier. Renvoie true si le
  /// serveur a accepté (sinon l'événement est créé quand même).
  static Future<bool> annoncer(Evenement evenement, String quartierId) async {
    try {
      final String? jeton = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (jeton == null) {
        return false;
      }
      final http.Response reponse = await http
          .post(
            Uri.parse(adresseWorker),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'idToken': jeton,
              'quartierId': quartierId,
              'titre': 'Nouvel événement : ${evenement.titre}',
              'corps': corps(evenement),
              'evenementId': evenement.id,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return reponse.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
