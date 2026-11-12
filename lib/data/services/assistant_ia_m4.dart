import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/evenement.dart';
import '../resultat.dart';
import 'firestore_commun.dart';
import 'limite_ia.dart';

/// M4 - (IA) Une idée de l'assistant du leader : un événement à organiser,
/// un sondage à lancer, ou un conseil. [raison] explique pourquoi (avec les
/// chiffres de la houma).
class SuggestionIA {
  final String type; // 'evenement', 'sondage' ou 'conseil'
  final String titre; // titre de l'événement ou du conseil, ou la question
  final String raison;
  final CategorieEvenement categorie; // événement seulement
  final DateTime? date; // événement seulement (jour + heure)
  final List<String> choix; // sondage seulement

  const SuggestionIA({
    required this.type,
    required this.titre,
    required this.raison,
    this.categorie = CategorieEvenement.autre,
    this.date,
    this.choix = const [],
  });

  bool get estEvenement => type == 'evenement';
  bool get estSondage => type == 'sondage';

  /// Lit une idée telle que le serveur l'enregistre (null si illisible).
  static SuggestionIA? depuisMap(Map<String, dynamic> map) {
    final String type = map['type']?.toString() ?? '';
    final String raison = map['raison']?.toString() ?? '';
    if (type == 'evenement') {
      final String titre = map['titre']?.toString() ?? '';
      if (titre.isEmpty) {
        return null;
      }
      return SuggestionIA(
        type: type,
        titre: titre,
        raison: raison,
        categorie: _categorie(map['categorie']?.toString()),
        date: _date(map['date']?.toString(), map['heure']?.toString()),
      );
    }
    if (type == 'sondage') {
      final String question = map['question']?.toString() ?? '';
      final List<String> choix = [];
      for (final Object? un in (map['choix'] as List?) ?? const []) {
        final String texte = un?.toString().trim() ?? '';
        if (texte.isNotEmpty) {
          choix.add(texte);
        }
      }
      if (question.isEmpty || choix.length < 2) {
        return null;
      }
      return SuggestionIA(type: type, titre: question, raison: raison, choix: choix);
    }
    if (type == 'conseil') {
      final String titre = map['titre']?.toString() ?? '';
      if (titre.isEmpty) {
        return null;
      }
      return SuggestionIA(type: type, titre: titre, raison: raison);
    }
    return null;
  }

  static CategorieEvenement _categorie(String? nom) {
    for (final CategorieEvenement c in CategorieEvenement.values) {
      if (c.name == nom) {
        return c;
      }
    }
    return CategorieEvenement.autre;
  }

  /// "2026-11-22" + "14:00" -> DateTime (null si la date manque).
  static DateTime? _date(String? jour, String? heure) {
    if (jour == null || jour.isEmpty) {
      return null;
    }
    final DateTime? d = DateTime.tryParse(jour);
    if (d == null) {
      return null;
    }
    int h = 18;
    int m = 0;
    final List<String> morceaux = (heure ?? '').split(':');
    if (morceaux.length == 2) {
      h = int.tryParse(morceaux[0]) ?? 18;
      m = int.tryParse(morceaux[1]) ?? 0;
    }
    return DateTime(d.year, d.month, d.day, h, m);
  }
}

/// M4 - (IA) Les idées de l'assistant pour une houma, et leur date.
class IdeesIA {
  final List<SuggestionIA> suggestions;
  final DateTime? date;

  const IdeesIA({required this.suggestions, this.date});

  /// Lit une liste d'idées (maps), en ignorant celles qui sont mal formées.
  static List<SuggestionIA> lireListe(Object? liste) {
    final List<SuggestionIA> resultat = [];
    for (final Object? un in (liste as List?) ?? const []) {
      if (un is Map) {
        final SuggestionIA? s = SuggestionIA.depuisMap(Map<String, dynamic>.from(un));
        if (s != null) {
          resultat.add(s);
        }
      }
    }
    return resultat;
  }
}

/// M4 - (IA) L'assistant du leader. Les idées sont préparées par notre
/// serveur Cloudflare (dossier push_worker/, IA gratuite Workers AI) :
/// - chaque lundi matin, tout seul, pour chaque houma ;
/// - ou tout de suite avec [actualiser].
/// Elles sont rangées dans quartiers/{q}/suggestionsIA/courant, lisible
/// seulement par les leaders et l'admin. Aucun nom n'est envoyé à l'IA.
class AssistantIAM4 {
  AssistantIAM4._();

  static const String adresse =
      'https://houmani-push.houmani-push.workers.dev/suggestions';

  /// Les dernières idées enregistrées (null s'il n'y en a pas encore).
  static Future<Resultat<IdeesIA?>> lire(String quartierId) {
    return FirestoreCommun.executer(() async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirestoreCommun
          .collectionDuQuartier(quartierId, 'suggestionsIA')
          .doc('courant')
          .get();
      final Map<String, dynamic>? donnees = doc.data();
      if (donnees == null) {
        return null;
      }
      return IdeesIA(
        suggestions: IdeesIA.lireListe(donnees['suggestions']),
        date: FirestoreCommun.lireDate(donnees['date']),
      );
    });
  }

  /// Demande de nouvelles idées tout de suite (environ 5 à 20 secondes).
  static Future<Resultat<IdeesIA>> actualiser(String quartierId) async {
    try {
      final String? jeton = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (jeton == null) {
        return const Resultat.echec('Connecte-toi pour utiliser l\'assistant');
      }
      final http.Response reponse = await http
          .post(
            Uri.parse(adresse),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'idToken': jeton, 'quartierId': quartierId}),
          )
          .timeout(const Duration(seconds: 60));
      final String? limite = LimiteIA.message(reponse);
      if (limite != null) {
        return Resultat.echec(limite);
      }
      if (reponse.statusCode == 403) {
        return const Resultat.echec('L\'assistant est réservé aux leaders et à l\'admin');
      }
      if (reponse.statusCode != 200) {
        return const Resultat.echec('L\'assistant ne répond pas, réessaie plus tard');
      }
      final Map<String, dynamic> corps =
          jsonDecode(utf8.decode(reponse.bodyBytes)) as Map<String, dynamic>;
      final List<SuggestionIA> idees = IdeesIA.lireListe(corps['suggestions']);
      if (idees.isEmpty) {
        return const Resultat.echec('Pas de nouvelle idée cette fois, réessaie');
      }
      return Resultat.succes(IdeesIA(suggestions: idees, date: DateTime.now()));
    } catch (e) {
      return const Resultat.echec('Pas de connexion à l\'assistant');
    }
  }
}
