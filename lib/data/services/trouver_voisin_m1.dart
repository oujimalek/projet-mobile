import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/utilisateur.dart';
import '../resultat.dart';

/// M1 - Une compétence de la houma utile pour le besoin, et les voisins
/// qui l'ont déclarée.
class Correspondance {
  final String competence;
  final String raison; // phrase de l'IA ('' en recherche locale)
  final List<Utilisateur> voisins;

  const Correspondance({
    required this.competence,
    required this.raison,
    required this.voisins,
  });
}

/// M1 - Le résultat d'une recherche. [parIA] = false : recherche locale par
/// mots-clés (IA indisponible).
class ReponseBesoin {
  final List<Correspondance> correspondances;
  final bool parIA;

  const ReponseBesoin({required this.correspondances, required this.parIA});
}

/// M1 - (IA) "Qui peut m'aider ?" dans l'annuaire des voisins.
///
/// L'utilisateur décrit son besoin ("ma machine à laver fuit"). On envoie
/// au serveur Cloudflare (push_worker/, route /correspondances) le besoin
/// et la LISTE des compétences de la houma, sans aucun nom ni identifiant.
/// L'IA choisit au plus 3 compétences de cette liste ; c'est l'application
/// qui retrouve ensuite les voisins correspondants.
///
/// Sans réseau, [rechercheLocale] compare les mots du besoin avec les
/// compétences (plus un petit dictionnaire : "fuite" -> plomberie...).
class TrouverVoisinM1 {
  TrouverVoisinM1._(); // pas d'instance

  static const String adresse =
      'https://houmani-push.houmani-push.workers.dev/correspondances';

  // Remplaçables dans les tests
  static http.Client client = http.Client();
  static Future<String?> Function() jeton = _jetonFirebase;
  static Duration delaiMax = const Duration(seconds: 30);

  static const int besoinMin = 3;
  static const int besoinMax = 300;
  static const int competencesMax = 80; // limite du serveur
  static const int resultatsMax = 3;

  static void reinitialiser() {
    client = http.Client();
    jeton = _jetonFirebase;
    delaiMax = const Duration(seconds: 30);
  }

  static Future<String?> _jetonFirebase() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  /// true si le besoin a une longueur acceptée (3 à 300 caractères).
  static bool besoinValide(String besoin) {
    final int n = besoin.trim().length;
    return n >= besoinMin && n <= besoinMax;
  }

  /// Les compétences des voisins, sans doublon (majuscules ignorées),
  /// les plus fréquentes d'abord. 40 caractères au plus chacune.
  static List<String> competencesDistinctes(List<Utilisateur> voisins) {
    final Map<String, String> orthographe = {}; // minuscule -> 1re écriture
    final Map<String, int> nombre = {};
    for (final Utilisateur voisin in voisins) {
      for (final String brute in voisin.competences.toSet()) {
        final String competence = brute.trim();
        if (competence.isEmpty || competence.length > 40) {
          continue;
        }
        final String cle = competence.toLowerCase();
        orthographe.putIfAbsent(cle, () => competence);
        nombre[cle] = (nombre[cle] ?? 0) + 1;
      }
    }
    final List<String> cles = orthographe.keys.toList();
    cles.sort((a, b) {
      final int parNombre = nombre[b]!.compareTo(nombre[a]!);
      return parNombre != 0 ? parNombre : a.compareTo(b);
    });
    final List<String> resultat = [];
    for (final String cle in cles.take(competencesMax)) {
      resultat.add(orthographe[cle]!);
    }
    return resultat;
  }

  /// Les voisins qui ont cette compétence (majuscules ignorées).
  static List<Utilisateur> voisinsAvec(
      String competence, List<Utilisateur> voisins) {
    final String cle = competence.trim().toLowerCase();
    final List<Utilisateur> resultat = [];
    for (final Utilisateur voisin in voisins) {
      for (final String c in voisin.competences) {
        if (c.trim().toLowerCase() == cle) {
          resultat.add(voisin);
          break;
        }
      }
    }
    return resultat;
  }

  /// Cherche qui peut aider : l'IA si possible, sinon la recherche locale.
  /// Échec seulement si le besoin est trop court ou trop long.
  static Future<Resultat<ReponseBesoin>> trouver({
    required String quartierId,
    required String besoin,
    required List<Utilisateur> voisins,
  }) async {
    if (!besoinValide(besoin)) {
      return const Resultat.echec('Décris ton besoin en 3 à 300 caractères');
    }
    final List<String> competences = competencesDistinctes(voisins);
    if (competences.isEmpty) {
      // Personne n'a déclaré de compétence : rien à chercher
      return const Resultat.succes(
          ReponseBesoin(correspondances: [], parIA: false));
    }
    final ReponseBesoin locale = ReponseBesoin(
      correspondances: rechercheLocale(besoin, voisins),
      parIA: false,
    );
    if (quartierId.isEmpty) {
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
            // Aucun nom : seulement le besoin et les compétences
            body: jsonEncode({
              'idToken': idToken,
              'quartierId': quartierId,
              'besoin': besoin.trim(),
              'competences': competences,
            }),
          )
          .timeout(delaiMax);
      if (reponse.statusCode != 200) {
        return Resultat.succes(locale);
      }
      final List<Correspondance>? ia = depuisReponse(
        jsonDecode(utf8.decode(reponse.bodyBytes)),
        voisins,
      );
      if (ia == null) {
        return Resultat.succes(locale);
      }
      return Resultat.succes(ReponseBesoin(correspondances: ia, parIA: true));
    } catch (e) {
      return Resultat.succes(locale);
    }
  }

  /// Lit { correspondances: [{competence, raison}] } et retrouve les
  /// voisins. Une compétence que personne n'a (inventée par l'IA) est
  /// ignorée. null si la réponse est mal formée.
  static List<Correspondance>? depuisReponse(
      Object? json, List<Utilisateur> voisins) {
    if (json is! Map || json['correspondances'] is! List) {
      return null;
    }
    final List<Correspondance> resultat = [];
    final Set<String> vues = {};
    for (final Object? un in json['correspondances'] as List) {
      if (un is! Map) {
        continue;
      }
      final String competence = (un['competence'] ?? '').toString().trim();
      if (!vues.add(competence.toLowerCase())) {
        continue; // vide ou déjà vue
      }
      final List<Utilisateur> qui = voisinsAvec(competence, voisins);
      if (competence.isEmpty || qui.isEmpty) {
        continue;
      }
      resultat.add(Correspondance(
        competence: _ecritureDe(competence, qui.first),
        raison: (un['raison'] ?? '').toString().trim(),
        voisins: qui,
      ));
      if (resultat.length >= resultatsMax) {
        break;
      }
    }
    return resultat;
  }

  /// La compétence telle que le voisin l'a écrite.
  static String _ecritureDe(String competence, Utilisateur voisin) {
    for (final String c in voisin.competences) {
      if (c.trim().toLowerCase() == competence.toLowerCase()) {
        return c.trim();
      }
    }
    return competence;
  }

  // ---------- Recherche locale (sans réseau) ----------

  /// Quelques besoins courants -> début du mot de la compétence.
  static const Map<String, List<String>> _indices = {
    'fuite': ['plomb'],
    'robinet': ['plomb'],
    'evier': ['plomb'],
    'lavabo': ['plomb'],
    'toilette': ['plomb'],
    'prise': ['electri'],
    'lampe': ['electri'],
    'courant': ['electri'],
    'disjoncteur': ['electri'],
    'ordinateur': ['informati'],
    'telephone': ['informati'],
    'wifi': ['informati'],
    'internet': ['informati'],
    'imprimante': ['informati'],
    'devoir': ['cours', 'soutien'],
    'examen': ['cours', 'soutien'],
    'bac': ['cours', 'soutien'],
    'meuble': ['bricol', 'menuis'],
    'etagere': ['bricol', 'menuis'],
    'porte': ['bricol', 'menuis', 'serrur'],
    'cle': ['serrur'],
    'voiture': ['mecani'],
    'pneu': ['mecani'],
    'gateau': ['cuisin', 'patiss'],
    'repas': ['cuisin'],
    'plante': ['jardin'],
    'arbre': ['jardin'],
    'peinture': ['peint'],
    'mur': ['peint', 'bricol'],
    'enfant': ['garde', 'baby'],
    'bebe': ['garde', 'baby'],
    'chien': ['animaux'],
    'chat': ['animaux'],
    'demenagement': ['demenag', 'bricol'],
  };

  /// Les compétences dont un mot ressemble à un mot du besoin (même début
  /// sur 5 lettres : "plombier" trouve "Plomberie"), ou que le petit
  /// dictionnaire associe au besoin. 3 au plus, les plus fréquentes d'abord.
  static List<Correspondance> rechercheLocale(
      String besoin, List<Utilisateur> voisins) {
    final List<String> motsBesoin = _mots(besoin);
    final List<String> debuts = [];
    for (final String mot in motsBesoin) {
      final String sansPluriel =
          mot.endsWith('s') ? mot.substring(0, mot.length - 1) : mot;
      debuts.addAll(_indices[mot] ?? _indices[sansPluriel] ?? const []);
    }
    final List<Correspondance> resultat = [];
    for (final String competence in competencesDistinctes(voisins)) {
      final List<String> motsCompetence = _mots(competence);
      bool utile = false;
      for (final String mc in motsCompetence) {
        for (final String mb in motsBesoin) {
          if (_proches(mb, mc)) {
            utile = true;
          }
        }
        for (final String debut in debuts) {
          if (mc.startsWith(debut)) {
            utile = true;
          }
        }
      }
      if (utile) {
        resultat.add(Correspondance(
          competence: competence,
          raison: '',
          voisins: voisinsAvec(competence, voisins),
        ));
        if (resultat.length >= resultatsMax) {
          break;
        }
      }
    }
    return resultat;
  }

  static bool _proches(String a, String b) {
    if (a.length < 4 || b.length < 4) {
      return a == b;
    }
    if (a == b) {
      return true;
    }
    int commun = 0;
    while (commun < a.length && commun < b.length && a[commun] == b[commun]) {
      commun++;
    }
    return commun >= 5 || (commun >= 4 && (commun == a.length || commun == b.length));
  }

  /// Les mots en minuscules, sans accents.
  static List<String> _mots(String texte) {
    const String avec = 'àâäéèêëîïôöùûüç';
    const String sans = 'aaaeeeeiioouuuc';
    final StringBuffer propre = StringBuffer();
    for (final String c in texte.toLowerCase().split('')) {
      final int i = avec.indexOf(c);
      propre.write(i >= 0 ? sans[i] : c);
    }
    return propre
        .toString()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((m) => m.isNotEmpty)
        .toList();
  }
}
