import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../resultat.dart';

/// M2 - Une annonce (titre + description) proposée à l'utilisateur.
/// [parIA] = true si elle vient de l'IA, false si c'est la mise en forme
/// locale (IA indisponible).
class AnnonceProposee {
  final String titre;
  final String description;
  final bool parIA;

  const AnnonceProposee({
    required this.titre,
    required this.description,
    required this.parIA,
  });
}

/// M2 - (IA) "Améliorer avec l'IA" sur le formulaire d'un service.
///
/// Le texte est envoyé à notre serveur Cloudflare (push_worker/, route
/// /ameliorer, IA gratuite Workers AI). Le serveur vérifie que l'utilisateur
/// est un membre actif du quartier. Seuls le titre, la description et la
/// catégorie sont envoyés : aucun nom de personne.
///
/// Sans réseau (ou si l'IA répond mal), on ne bloque pas l'utilisateur :
/// [rangerLocalement] corrige les espaces, les majuscules et la ponctuation.
/// L'utilisateur voit toujours la proposition AVANT qu'elle remplace son texte.
class AideRedactionM2 {
  AideRedactionM2._(); // pas d'instance

  static const String adresse =
      'https://houmani-push.houmani-push.workers.dev/ameliorer';

  // Remplaçables dans les tests
  static http.Client client = http.Client();
  static Future<String?> Function() jeton = _jetonFirebase;
  static Duration delaiMax = const Duration(seconds: 30);

  static const int titreMax = 60;
  static const int descriptionMax = 400;

  /// Remet les valeurs par défaut (après un test).
  static void reinitialiser() {
    client = http.Client();
    jeton = _jetonFirebase;
    delaiMax = const Duration(seconds: 30);
  }

  static Future<String?> _jetonFirebase() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  /// La proposition pour ce titre et cette description : celle de l'IA si
  /// possible, sinon la mise en forme locale. Échec seulement si le texte
  /// est vide (rien à améliorer).
  static Future<Resultat<AnnonceProposee>> ameliorer({
    required String quartierId,
    required String titre,
    required String description,
    String? categorie,
  }) async {
    if (titre.trim().isEmpty && description.trim().isEmpty) {
      return const Resultat.echec('Écris d\'abord un titre et une description');
    }
    final AnnonceProposee locale = rangerLocalement(titre, description);
    // Le serveur refuse les textes trop longs : on les coupe avant
    final String titreEnvoye = _couper(titre.trim(), 120);
    final String descriptionEnvoyee = _couper(description.trim(), 1000);
    if (titreEnvoye.isEmpty || descriptionEnvoyee.isEmpty || quartierId.isEmpty) {
      return Resultat.succes(locale);
    }
    try {
      final String? idToken = await jeton();
      if (idToken == null) {
        return Resultat.succes(locale);
      }
      final http.Response reponse = await client
          .post(
            Uri.parse(adresse),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'quartierId': quartierId,
              'titre': titreEnvoye,
              'description': descriptionEnvoyee,
              'categorie': categorie ?? '',
            }),
          )
          .timeout(delaiMax);
      if (reponse.statusCode != 200) {
        return Resultat.succes(locale);
      }
      final AnnonceProposee? ia =
          depuisReponse(jsonDecode(utf8.decode(reponse.bodyBytes)));
      return Resultat.succes(ia ?? locale);
    } catch (e) {
      // Pas de réseau, délai dépassé, JSON illisible : mise en forme locale
      return Resultat.succes(locale);
    }
  }

  /// Lit la réponse du serveur { titre, description } (null si invalide).
  static AnnonceProposee? depuisReponse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final String titre = _couper((json['titre'] ?? '').toString().trim(), titreMax);
    final String description = _couper(
        (json['description'] ?? '').toString().trim(), descriptionMax);
    if (titre.length < 3 || description.length < 10) {
      return null;
    }
    return AnnonceProposee(titre: titre, description: description, parIA: true);
  }

  /// Mise en forme locale, sans réseau :
  /// - espaces en trop retirés, pas d'espace avant , et . ;
  /// - une espace après , . ! ? ;
  /// - majuscule au début de chaque phrase ;
  /// - titre sans point final, description terminée par . ! ou ?
  static AnnonceProposee rangerLocalement(String titre, String description) {
    String t = _phrases(_espaces(titre));
    while (t.endsWith('.')) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    String d = _phrases(_espaces(description));
    if (d.isNotEmpty && !'.!?'.contains(d[d.length - 1])) {
      d = '$d.';
    }
    return AnnonceProposee(
      titre: _couper(t, titreMax),
      description: _couper(d, descriptionMax),
      parIA: false,
    );
  }

  static String _espaces(String texte) {
    return texte
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r' +([,.])'), (m) => m[1]!)
        // une espace après la ponctuation, sauf dans un nombre (12.5, 3,5)
        .replaceAllMapped(
          RegExp(r'([,.!?])(?=[^\s\d,.!?)])'),
          (m) => '${m[1]} ',
        )
        .trim();
  }

  static String _phrases(String texte) {
    final StringBuffer resultat = StringBuffer();
    bool debut = true;
    for (int i = 0; i < texte.length; i++) {
      final String c = texte[i];
      if (debut && c.trim().isNotEmpty) {
        resultat.write(c.toUpperCase());
        debut = false;
      } else {
        resultat.write(c);
      }
      if ('.!?'.contains(c)) {
        debut = true;
      }
    }
    return resultat.toString();
  }

  static String _couper(String texte, int max) {
    return texte.length <= max ? texte : texte.substring(0, max).trimRight();
  }
}
