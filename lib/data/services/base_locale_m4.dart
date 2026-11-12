import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/evenement.dart';
import 'utilisateur_repository.dart';

/// M4 - (SQLite) Un brouillon d'événement, gardé SUR LE TÉLÉPHONE tant qu'il
/// n'est pas publié. Table `brouillons`.
class BrouillonEvenement {
  final int? id; // null tant qu'il n'est pas enregistré (AUTOINCREMENT)
  final String titre;
  final String description;
  final String lieu;
  final CategorieEvenement categorie;
  final DateTime? debut; // jour + heure de début, si déjà choisis
  final DateTime? fin;
  final int places; // 0 = sans limite
  final DateTime majLe; // dernière modification

  const BrouillonEvenement({
    this.id,
    required this.titre,
    this.description = '',
    this.lieu = '',
    this.categorie = CategorieEvenement.fete,
    this.debut,
    this.fin,
    this.places = 0,
    required this.majLe,
  });

  /// Un brouillon vide ne vaut pas la peine d'être gardé.
  bool get estVide =>
      titre.trim().isEmpty && description.trim().isEmpty && lieu.trim().isEmpty;

  /// Les dates sont stockées en millisecondes (SQLite n'a pas de type date).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'titre': titre,
      'description': description,
      'lieu': lieu,
      'categorie': categorie.name,
      'debut': debut?.millisecondsSinceEpoch,
      'fin': fin?.millisecondsSinceEpoch,
      'places': places,
      'maj_le': majLe.millisecondsSinceEpoch,
    };
  }

  factory BrouillonEvenement.fromMap(Map<String, Object?> map) {
    CategorieEvenement categorie = CategorieEvenement.autre;
    for (final CategorieEvenement c in CategorieEvenement.values) {
      if (c.name == map['categorie']) {
        categorie = c;
      }
    }
    return BrouillonEvenement(
      id: map['id'] as int?,
      titre: (map['titre'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      lieu: (map['lieu'] as String?) ?? '',
      categorie: categorie,
      debut: _date(map['debut']),
      fin: _date(map['fin']),
      places: (map['places'] as int?) ?? 0,
      majLe: _date(map['maj_le']) ?? DateTime.now(),
    );
  }

  static DateTime? _date(Object? ms) {
    if (ms is int) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }
}

/// M4 - (SQLite) Une ligne de MON historique : un événement où je me suis
/// inscrit, ma présence (QR) et ma note. Table `historique`.
class LigneHistorique {
  final String evenementId;
  final String titre;
  final CategorieEvenement categorie;
  final DateTime date;
  final bool participe;
  final bool present;
  final int? note; // 1 à 5, null si pas d'avis

  const LigneHistorique({
    required this.evenementId,
    required this.titre,
    required this.categorie,
    required this.date,
    this.participe = true,
    this.present = false,
    this.note,
  });

  factory LigneHistorique.fromMap(Map<String, Object?> map) {
    CategorieEvenement categorie = CategorieEvenement.autre;
    for (final CategorieEvenement c in CategorieEvenement.values) {
      if (c.name == map['categorie']) {
        categorie = c;
      }
    }
    return LigneHistorique(
      evenementId: map['evenement_id'] as String,
      titre: (map['titre'] as String?) ?? '',
      categorie: categorie,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      participe: map['participe'] == 1,
      present: map['present'] == 1,
      note: map['note'] as int?,
    );
  }
}

/// M4 - (SQLite) Le bilan de mon historique, calculé avec des requêtes SQL.
class BilanHistorique {
  final int nbParticipations;
  final int nbPresences;
  final double? moyenneNotes; // null : aucune note
  final CategorieEvenement? categoriePreferee;
  final Map<String, int> parMois; // "2026-11" -> nombre, du plus récent

  const BilanHistorique({
    required this.nbParticipations,
    required this.nbPresences,
    this.moyenneNotes,
    this.categoriePreferee,
    this.parMois = const {},
  });

  /// Pourcentage de présence (QR) sur les événements passés où j'étais inscrit.
  int get tauxPresence =>
      nbParticipations == 0 ? 0 : (nbPresences * 100 / nbParticipations).round();
}

/// M4 - La base SQLite du module, SUR LE TÉLÉPHONE (package sqflite).
///
/// Elle garde des données PERSONNELLES, qui ne vont pas dans Firestore :
/// - `brouillons` : les événements commencés mais pas encore publiés ;
/// - `historique` : mes participations, présences et notes, pour « Mon
///   historique » (statistiques avec COUNT, AVG, GROUP BY).
///
/// Le téléphone peut servir à plusieurs comptes : chaque ligne porte
/// `utilisateur_id`, et chaque lecture (statistiques comprises) ne prend
/// que les lignes de l'utilisateur connecté.
///
/// Que des static. Les méthodes ne lèvent jamais d'exception : si la base
/// n'est pas disponible, on renvoie une liste vide (l'appli continue).
class BaseLocaleM4 {
  BaseLocaleM4._();

  static const String nomFichier = 'houmani_m4.db';

  /// Version du schéma :
  ///   1 : brouillons, historique
  ///   2 : + colonne utilisateur_id (brouillons, historique)
  static const int version = 2;

  /// Les tables dont les lignes appartiennent à un utilisateur.
  static const List<String> tablesPersonnelles = ['brouillons', 'historique'];

  /// Pour les tests : une base en mémoire (sqflite_common_ffi).
  static String? cheminPourTests;

  /// L'uid de l'utilisateur connecté ('' : personne). Les tests le remplacent.
  static String Function() utilisateurActuel = uidConnecte;

  static String uidConnecte() {
    try {
      return UtilisateurRepository().getUtilisateurConnecte().id;
    } catch (e) {
      return '';
    }
  }

  static Database? _base;

  // Les lignes d'avant la version 2 (utilisateur_id NULL) ont été données
  // à l'utilisateur connecté (une seule fois par lancement de l'app)
  static bool _orphelinsAttribues = false;

  static Future<Database> _ouvrir() async {
    final Database? deja = _base;
    if (deja != null && deja.isOpen) {
      await _attribuerOrphelins(deja);
      return deja;
    }
    final String chemin =
        cheminPourTests ?? join(await getDatabasesPath(), nomFichier);
    final Database base = await openDatabase(
      chemin,
      version: version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE brouillons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            titre TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            lieu TEXT NOT NULL DEFAULT '',
            categorie TEXT NOT NULL,
            debut INTEGER,
            fin INTEGER,
            places INTEGER NOT NULL DEFAULT 0,
            maj_le INTEGER NOT NULL,
            utilisateur_id TEXT
          )''');
        await db.execute('CREATE TABLE historique $_colonnesHistorique');
      },
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) {
          await _migrerVersVersion2(db);
        }
      },
    );
    _base = base;
    await _attribuerOrphelins(base);
    return base;
  }

  /// Une ligne par (utilisateur, événement) : deux comptes du même
  /// téléphone peuvent participer au même événement.
  static const String _colonnesHistorique = '''(
            utilisateur_id TEXT,
            evenement_id TEXT NOT NULL,
            titre TEXT NOT NULL,
            categorie TEXT NOT NULL,
            date INTEGER NOT NULL,
            participe INTEGER NOT NULL DEFAULT 1,
            present INTEGER NOT NULL DEFAULT 0,
            note INTEGER,
            PRIMARY KEY (utilisateur_id, evenement_id)
          )''';

  /// Version 2 : utilisateur_id sur les deux tables. Les lignes existantes
  /// sont gardées, avec utilisateur_id NULL (données ensuite à
  /// l'utilisateur connecté, voir [_attribuerOrphelins]).
  /// - brouillons : simple ALTER TABLE ADD COLUMN ;
  /// - historique : sa clé change (avant : un événement pour tout le
  ///   téléphone), et SQLite ne sait pas changer une clé : nouvelle table,
  ///   copie, puis on remplace.
  static Future<void> _migrerVersVersion2(Database db) async {
    await db.execute('ALTER TABLE brouillons ADD COLUMN utilisateur_id TEXT');

    await db.execute('CREATE TABLE historique_v2 $_colonnesHistorique');
    await db.execute(
        'INSERT INTO historique_v2 (evenement_id, titre, categorie, date, participe, present, note) '
        'SELECT evenement_id, titre, categorie, date, participe, present, note FROM historique');
    await db.execute('DROP TABLE historique');
    await db.execute('ALTER TABLE historique_v2 RENAME TO historique');
  }

  /// Les lignes d'avant la version 2 (utilisateur_id NULL) appartiennent à
  /// l'utilisateur qui se servait du téléphone : on les donne au premier
  /// utilisateur connecté qui ouvre la base après la mise à jour.
  static Future<void> _attribuerOrphelins(Database db) async {
    if (_orphelinsAttribues) {
      return;
    }
    final String uid = utilisateurActuel();
    if (uid.isEmpty) {
      return; // personne de connecté : on attend
    }
    await db.transaction((txn) async {
      for (final String table in tablesPersonnelles) {
        await txn.rawUpdate(
          'UPDATE OR IGNORE $table SET utilisateur_id = ? WHERE utilisateur_id IS NULL',
          [uid],
        );
      }
    });
    _orphelinsAttribues = true;
  }

  /// Ferme la base (tests).
  static Future<void> fermer() async {
    await _base?.close();
    _base = null;
    _orphelinsAttribues = false;
  }

  // =====================================================================
  // Brouillons (CRUD)
  // =====================================================================

  /// Crée ou met à jour un brouillon ; renvoie son id (null si erreur).
  static Future<int?> enregistrerBrouillon(BrouillonEvenement brouillon) async {
    try {
      final Database db = await _ouvrir();
      final String uid = utilisateurActuel();
      final Map<String, Object?> valeurs = brouillon.toMap();
      valeurs['utilisateur_id'] = uid;
      final int? id = brouillon.id;
      if (id == null) {
        valeurs.remove('id');
        return await db.insert('brouillons', valeurs);
      }
      // Seulement MON brouillon
      await db.update('brouillons', valeurs,
          where: 'id = ? AND utilisateur_id = ?', whereArgs: [id, uid]);
      return id;
    } catch (e) {
      return null;
    }
  }

  /// Tous MES brouillons, le plus récemment modifié en premier.
  static Future<List<BrouillonEvenement>> brouillons() async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> lignes = await db.query(
        'brouillons',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurActuel()],
        orderBy: 'maj_le DESC',
      );
      final List<BrouillonEvenement> liste = [];
      for (final Map<String, Object?> ligne in lignes) {
        liste.add(BrouillonEvenement.fromMap(ligne));
      }
      return liste;
    } catch (e) {
      return [];
    }
  }

  static Future<int> nombreBrouillons() async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> r = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM brouillons WHERE utilisateur_id = ?',
          [utilisateurActuel()]);
      return (r.first['n'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> supprimerBrouillon(int id) async {
    try {
      final Database db = await _ouvrir();
      await db.delete('brouillons',
          where: 'id = ? AND utilisateur_id = ?',
          whereArgs: [id, utilisateurActuel()]);
    } catch (e) {
      // rien : le brouillon restera, sans gêner l'utilisateur
    }
  }

  // =====================================================================
  // Historique
  // =====================================================================

  /// Je viens de m'inscrire (ou de me retirer) à cet événement.
  static Future<void> noterParticipation(Evenement evenement, bool participe) async {
    try {
      final Database db = await _ouvrir();
      final String uid = utilisateurActuel();
      final int n = await db.update(
        'historique',
        {
          'participe': participe ? 1 : 0,
          'titre': evenement.titre,
          'categorie': evenement.categorie.name,
          'date': evenement.date.millisecondsSinceEpoch,
        },
        where: 'utilisateur_id = ? AND evenement_id = ?',
        whereArgs: [uid, evenement.id],
      );
      if (n == 0 && participe) {
        await db.insert('historique', {
          'utilisateur_id': uid,
          'evenement_id': evenement.id,
          'titre': evenement.titre,
          'categorie': evenement.categorie.name,
          'date': evenement.date.millisecondsSinceEpoch,
          'participe': 1,
          'present': 0,
        });
      }
    } catch (e) {
      // l'historique est un plus : on ne bloque jamais l'appli
    }
  }

  /// J'ai scanné le QR : je suis présent.
  static Future<void> noterPresence(Evenement evenement) async {
    await noterParticipation(evenement, true);
    try {
      final Database db = await _ouvrir();
      await db.update('historique', {'present': 1},
          where: 'utilisateur_id = ? AND evenement_id = ?',
          whereArgs: [utilisateurActuel(), evenement.id]);
    } catch (e) {
      // idem
    }
  }

  /// J'ai noté l'événement (1 à 5).
  static Future<void> noterAvis(Evenement evenement, int note) async {
    await noterParticipation(evenement, true);
    try {
      final Database db = await _ouvrir();
      await db.update('historique', {'note': note},
          where: 'utilisateur_id = ? AND evenement_id = ?',
          whereArgs: [utilisateurActuel(), evenement.id]);
    } catch (e) {
      // idem
    }
  }

  /// Mes événements (inscrit), du plus récent au plus ancien. [categorie] :
  /// seulement cette catégorie (null = toutes).
  static Future<List<LigneHistorique>> historique({CategorieEvenement? categorie}) async {
    try {
      final Database db = await _ouvrir();
      final String uid = utilisateurActuel();
      final List<Map<String, Object?>> lignes = await db.query(
        'historique',
        where: categorie == null
            ? 'utilisateur_id = ? AND participe = 1'
            : 'utilisateur_id = ? AND participe = 1 AND categorie = ?',
        whereArgs: categorie == null ? [uid] : [uid, categorie.name],
        orderBy: 'date DESC',
      );
      final List<LigneHistorique> liste = [];
      for (final Map<String, Object?> ligne in lignes) {
        liste.add(LigneHistorique.fromMap(ligne));
      }
      return liste;
    } catch (e) {
      return [];
    }
  }

  /// MON bilan, avec des requêtes SQL (COUNT, AVG, GROUP BY).
  static Future<BilanHistorique> bilan() async {
    try {
      final Database db = await _ouvrir();
      final List<Object?> moi = [utilisateurActuel()];
      final int participations = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM historique '
              'WHERE utilisateur_id = ? AND participe = 1',
              moi))
          .first['n'] as int;
      final int presences = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM historique '
              'WHERE utilisateur_id = ? AND participe = 1 AND present = 1',
              moi))
          .first['n'] as int;
      final Object? moyenne = (await db.rawQuery(
              'SELECT AVG(note) AS m FROM historique '
              'WHERE utilisateur_id = ? AND note IS NOT NULL',
              moi))
          .first['m'];

      // Catégorie préférée : celle où je suis allé le plus souvent
      final List<Map<String, Object?>> prefs = await db.rawQuery(
          'SELECT categorie, COUNT(*) AS n FROM historique '
          'WHERE utilisateur_id = ? AND participe = 1 '
          'GROUP BY categorie ORDER BY n DESC, categorie LIMIT 1',
          moi);
      CategorieEvenement? preferee;
      if (prefs.isNotEmpty) {
        for (final CategorieEvenement c in CategorieEvenement.values) {
          if (c.name == prefs.first['categorie']) {
            preferee = c;
          }
        }
      }

      // Par mois (heure locale), du plus récent au plus ancien
      final List<Map<String, Object?>> mois = await db.rawQuery(
          "SELECT strftime('%Y-%m', date / 1000, 'unixepoch', 'localtime') AS mois, "
          'COUNT(*) AS n FROM historique '
          'WHERE utilisateur_id = ? AND participe = 1 '
          'GROUP BY mois ORDER BY mois DESC',
          moi);
      final Map<String, int> parMois = {};
      for (final Map<String, Object?> ligne in mois) {
        parMois[ligne['mois'] as String] = ligne['n'] as int;
      }

      return BilanHistorique(
        nbParticipations: participations,
        nbPresences: presences,
        moyenneNotes: moyenne == null ? null : (moyenne as num).toDouble(),
        categoriePreferee: preferee,
        parMois: parMois,
      );
    } catch (e) {
      return const BilanHistorique(nbParticipations: 0, nbPresences: 0);
    }
  }
}
