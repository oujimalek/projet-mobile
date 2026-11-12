import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/service.dart';
import 'utilisateur_repository.dart';

/// M2 - (SQLite) Un service mis en favori, gardé SUR LE TÉLÉPHONE.
/// Table `favoris`. Le titre est recopié : la liste s'affiche sans réseau.
class FavoriService {
  final String serviceId;
  final String titre;
  final String categorie;
  final String auteurNom;
  final bool estOffre;
  final DateTime ajouteLe;

  const FavoriService({
    required this.serviceId,
    required this.titre,
    required this.categorie,
    required this.auteurNom,
    required this.estOffre,
    required this.ajouteLe,
  });

  factory FavoriService.fromMap(Map<String, Object?> map) {
    return FavoriService(
      serviceId: map['service_id'] as String,
      titre: (map['titre'] as String?) ?? '',
      categorie: (map['categorie'] as String?) ?? '',
      auteurNom: (map['auteur_nom'] as String?) ?? '',
      estOffre: map['est_offre'] == 1,
      ajouteLe: DateTime.fromMillisecondsSinceEpoch(map['ajoute_le'] as int),
    );
  }
}

/// M2 - (SQLite) Le brouillon du formulaire « Nouvelle publication » :
/// gardé quand on quitte l'écran sans publier, proposé à la réouverture.
/// Table `brouillon_service` (une ligne par utilisateur).
class BrouillonService {
  final String titre;
  final String description;
  final String disponibilite;
  final String? categorie;
  final bool estOffre;
  final DateTime majLe;

  const BrouillonService({
    required this.titre,
    this.description = '',
    this.disponibilite = '',
    this.categorie,
    this.estOffre = true,
    required this.majLe,
  });

  /// Un brouillon vide ne vaut pas la peine d'être gardé.
  bool get estVide =>
      titre.trim().isEmpty &&
      description.trim().isEmpty &&
      disponibilite.trim().isEmpty;

  Map<String, Object?> toMap() {
    return {
      'titre': titre,
      'description': description,
      'disponibilite': disponibilite,
      'categorie': categorie,
      'est_offre': estOffre ? 1 : 0,
      'maj_le': majLe.millisecondsSinceEpoch,
    };
  }

  factory BrouillonService.fromMap(Map<String, Object?> map) {
    return BrouillonService(
      titre: (map['titre'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      disponibilite: (map['disponibilite'] as String?) ?? '',
      categorie: map['categorie'] as String?,
      estOffre: map['est_offre'] != 0,
      majLe: DateTime.fromMillisecondsSinceEpoch(map['maj_le'] as int),
    );
  }
}

/// M2 - La base SQLite du module Services, SUR LE TÉLÉPHONE (sqflite).
///
/// Elle garde des données PERSONNELLES, qui ne vont pas dans Firestore :
/// - `favoris` : les services que j'ai mis de côté (étoile) ;
/// - `consultations` : les services que j'ai ouverts, pour « Vus
///   récemment » et mes catégories préférées (COUNT, GROUP BY, MAX) ;
/// - `brouillon_service` : la publication commencée mais pas envoyée ;
/// - `jours_feries` : le cache des jours fériés (service web Nager.Date).
///
/// Le téléphone peut servir à plusieurs comptes : chaque ligne PERSONNELLE
/// porte `utilisateur_id`, et chaque lecture ne prend que les lignes de
/// l'utilisateur connecté. Les jours fériés (publics) sont partagés.
///
/// Que des static. Les méthodes ne lèvent jamais d'exception : si la base
/// n'est pas disponible, on renvoie une valeur vide (l'appli continue).
class BaseLocaleM2 {
  BaseLocaleM2._();

  static const String nomFichier = 'houmani_m2.db';

  /// Version du schéma :
  ///   2 : + table jours_feries
  ///   3 : + colonne utilisateur_id (favoris, consultations, brouillon)
  static const int version = 3;

  /// Les tables dont les lignes appartiennent à un utilisateur.
  static const List<String> tablesPersonnelles = [
    'favoris',
    'consultations',
    'brouillon_service',
  ];

  /// On ne garde que les dernières consultations de chaque utilisateur
  /// (la table ne grossit pas).
  static const int maxConsultations = 100;

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

  // Les lignes d'avant la version 3 (utilisateur_id NULL) ont été données
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
        await db.execute('CREATE TABLE favoris $_colonnesFavoris');
        await db.execute('''
          CREATE TABLE consultations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            service_id TEXT NOT NULL,
            titre TEXT NOT NULL,
            categorie TEXT NOT NULL,
            date INTEGER NOT NULL,
            utilisateur_id TEXT
          )''');
        await db.execute(
            'CREATE INDEX idx_consultations_service ON consultations(service_id)');
        await db.execute(
            'CREATE INDEX idx_consultations_utilisateur ON consultations(utilisateur_id, date)');
        await db.execute('CREATE TABLE brouillon_service $_colonnesBrouillon');
        await _creerJoursFeries(db);
      },
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) {
          await _creerJoursFeries(db);
        }
        if (ancienne < 3) {
          await _migrerVersVersion3(db);
        }
      },
    );
    _base = base;
    await _attribuerOrphelins(base);
    return base;
  }

  /// Un favori par (utilisateur, service) : deux comptes peuvent mettre le
  /// même service en favori.
  static const String _colonnesFavoris = '''(
            utilisateur_id TEXT,
            service_id TEXT NOT NULL,
            titre TEXT NOT NULL,
            categorie TEXT NOT NULL,
            auteur_nom TEXT NOT NULL DEFAULT '',
            est_offre INTEGER NOT NULL DEFAULT 1,
            ajoute_le INTEGER NOT NULL,
            PRIMARY KEY (utilisateur_id, service_id)
          )''';

  /// Un brouillon par utilisateur.
  static const String _colonnesBrouillon = '''(
            utilisateur_id TEXT PRIMARY KEY,
            titre TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            disponibilite TEXT NOT NULL DEFAULT '',
            categorie TEXT,
            est_offre INTEGER NOT NULL DEFAULT 1,
            maj_le INTEGER NOT NULL
          )''';

  /// Version 3 : utilisateur_id sur les tables personnelles. Les lignes
  /// existantes sont gardées, avec utilisateur_id NULL (données ensuite à
  /// l'utilisateur connecté, voir [_attribuerOrphelins]).
  /// - consultations : simple ALTER TABLE ADD COLUMN ;
  /// - favoris et brouillon_service : leur clé change (avant : un service,
  ///   ou une seule ligne id = 1, pour tout le téléphone), et SQLite ne
  ///   sait pas changer une clé : nouvelle table, copie, puis on remplace.
  static Future<void> _migrerVersVersion3(Database db) async {
    await db.execute('ALTER TABLE consultations ADD COLUMN utilisateur_id TEXT');
    await db.execute(
        'CREATE INDEX idx_consultations_utilisateur ON consultations(utilisateur_id, date)');

    await db.execute('CREATE TABLE favoris_v3 $_colonnesFavoris');
    await db.execute(
        'INSERT INTO favoris_v3 (service_id, titre, categorie, auteur_nom, est_offre, ajoute_le) '
        'SELECT service_id, titre, categorie, auteur_nom, est_offre, ajoute_le FROM favoris');
    await db.execute('DROP TABLE favoris');
    await db.execute('ALTER TABLE favoris_v3 RENAME TO favoris');

    await db.execute('CREATE TABLE brouillon_service_v3 $_colonnesBrouillon');
    await db.execute(
        'INSERT INTO brouillon_service_v3 (titre, description, disponibilite, categorie, est_offre, maj_le) '
        'SELECT titre, description, disponibilite, categorie, est_offre, maj_le FROM brouillon_service');
    await db.execute('DROP TABLE brouillon_service');
    await db.execute('ALTER TABLE brouillon_service_v3 RENAME TO brouillon_service');
  }

  /// Les lignes d'avant la version 3 (utilisateur_id NULL) appartiennent à
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

  /// Jours fériés tunisiens reçus de Nager.Date (cache par année).
  static Future<void> _creerJoursFeries(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS jours_feries (
        date TEXT PRIMARY KEY,
        annee INTEGER NOT NULL,
        nom TEXT NOT NULL
      )''');
  }

  /// Ferme la base (tests).
  static Future<void> fermer() async {
    await _base?.close();
    _base = null;
    _orphelinsAttribues = false;
  }

  // =====================================================================
  // Jours fériés (cache du service web Nager.Date)
  // =====================================================================

  /// Remplace les jours fériés gardés pour [annee].
  /// Clé : 'AAAA-MM-JJ', valeur : le nom en français.
  static Future<void> enregistrerJoursFeries(
    int annee,
    Map<String, String> jours,
  ) async {
    try {
      final Database base = await _ouvrir();
      await base.transaction((txn) async {
        await txn.delete('jours_feries', where: 'annee = ?', whereArgs: [annee]);
        for (final MapEntry<String, String> jour in jours.entries) {
          await txn.insert(
            'jours_feries',
            {'date': jour.key, 'annee': annee, 'nom': jour.value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      // pas de cache : on refera la requête la prochaine fois
    }
  }

  /// Les jours fériés gardés pour [annee] (vide si jamais téléchargés).
  static Future<Map<String, String>> joursFeries(int annee) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.query(
        'jours_feries',
        where: 'annee = ?',
        whereArgs: [annee],
        orderBy: 'date',
      );
      final Map<String, String> jours = {};
      for (final Map<String, Object?> ligne in lignes) {
        jours[ligne['date'] as String] = ligne['nom'] as String;
      }
      return jours;
    } catch (e) {
      return {};
    }
  }

  // =====================================================================
  // Favoris
  // =====================================================================

  /// Ajoute le service à MES favoris (ou met à jour son titre).
  static Future<void> ajouterFavori(Service service, {DateTime? date}) async {
    try {
      final Database db = await _ouvrir();
      await db.insert(
        'favoris',
        {
          'utilisateur_id': utilisateurActuel(),
          'service_id': service.id,
          'titre': service.titre,
          'categorie': service.categorie,
          'auteur_nom': service.auteurNom,
          'est_offre': service.estOffre ? 1 : 0,
          'ajoute_le': (date ?? DateTime.now()).millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // le favori est un plus : on ne bloque jamais l'appli
    }
  }

  static Future<void> retirerFavori(String serviceId) async {
    try {
      final Database db = await _ouvrir();
      await db.delete('favoris',
          where: 'utilisateur_id = ? AND service_id = ?',
          whereArgs: [utilisateurActuel(), serviceId]);
    } catch (e) {
      // idem
    }
  }

  static Future<bool> estFavori(String serviceId) async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> r = await db.query(
        'favoris',
        columns: ['service_id'],
        where: 'utilisateur_id = ? AND service_id = ?',
        whereArgs: [utilisateurActuel(), serviceId],
      );
      return r.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Ajoute ou retire ; renvoie le nouvel état (true = en favori).
  static Future<bool> basculerFavori(Service service) async {
    if (await estFavori(service.id)) {
      await retirerFavori(service.id);
      return false;
    }
    await ajouterFavori(service);
    return true;
  }

  /// Tous MES favoris, le plus récent en premier.
  static Future<List<FavoriService>> favoris() async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> lignes = await db.query(
        'favoris',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurActuel()],
        orderBy: 'ajoute_le DESC',
      );
      final List<FavoriService> liste = [];
      for (final Map<String, Object?> ligne in lignes) {
        liste.add(FavoriService.fromMap(ligne));
      }
      return liste;
    } catch (e) {
      return [];
    }
  }

  /// Les ids des favoris (pour filtrer la liste en direct).
  static Future<Set<String>> idsFavoris() async {
    final Set<String> ids = {};
    for (final FavoriService favori in await favoris()) {
      ids.add(favori.serviceId);
    }
    return ids;
  }

  // =====================================================================
  // Consultations
  // =====================================================================

  /// J'ai ouvert le détail de ce service.
  static Future<void> noterConsultation(Service service, {DateTime? date}) async {
    try {
      final Database db = await _ouvrir();
      final String uid = utilisateurActuel();
      await db.insert('consultations', {
        'utilisateur_id': uid,
        'service_id': service.id,
        'titre': service.titre,
        'categorie': service.categorie,
        'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
      });
      // On ne garde que MES [maxConsultations] plus récentes
      await db.rawDelete(
        'DELETE FROM consultations WHERE utilisateur_id = ? AND id NOT IN '
        '(SELECT id FROM consultations WHERE utilisateur_id = ? '
        'ORDER BY date DESC, id DESC LIMIT ?)',
        [uid, uid, maxConsultations],
      );
    } catch (e) {
      // idem
    }
  }

  /// Les derniers services ouverts (chacun une fois), le plus récent d'abord :
  /// id -> titre.
  static Future<Map<String, String>> vusRecemment({int limite = 5}) async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> lignes = await db.rawQuery(
        'SELECT service_id, titre, MAX(date) AS derniere FROM consultations '
        'WHERE utilisateur_id = ? '
        'GROUP BY service_id ORDER BY derniere DESC LIMIT ?',
        [utilisateurActuel(), limite],
      );
      final Map<String, String> vus = {};
      for (final Map<String, Object?> ligne in lignes) {
        vus[ligne['service_id'] as String] = (ligne['titre'] as String?) ?? '';
      }
      return vus;
    } catch (e) {
      return {};
    }
  }

  /// Mes catégories les plus consultées : catégorie -> nombre, de la plus
  /// consultée à la moins consultée (GROUP BY).
  static Future<Map<String, int>> categoriesPreferees() async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> lignes = await db.rawQuery(
        'SELECT categorie, COUNT(*) AS n FROM consultations '
        'WHERE utilisateur_id = ? '
        'GROUP BY categorie ORDER BY n DESC, categorie',
        [utilisateurActuel()],
      );
      final Map<String, int> categories = {};
      for (final Map<String, Object?> ligne in lignes) {
        categories[ligne['categorie'] as String] = ligne['n'] as int;
      }
      return categories;
    } catch (e) {
      return {};
    }
  }

  // =====================================================================
  // Brouillon de publication
  // =====================================================================

  /// Garde le brouillon (un brouillon vide efface l'ancien).
  static Future<void> enregistrerBrouillon(BrouillonService brouillon) async {
    if (brouillon.estVide) {
      await supprimerBrouillon();
      return;
    }
    try {
      final Database db = await _ouvrir();
      await db.insert(
        'brouillon_service',
        {...brouillon.toMap(), 'utilisateur_id': utilisateurActuel()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // idem
    }
  }

  /// MON brouillon (null s'il n'y en a pas).
  static Future<BrouillonService?> lireBrouillon() async {
    try {
      final Database db = await _ouvrir();
      final List<Map<String, Object?>> lignes = await db.query(
        'brouillon_service',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurActuel()],
      );
      if (lignes.isEmpty) {
        return null;
      }
      return BrouillonService.fromMap(lignes.first);
    } catch (e) {
      return null;
    }
  }

  static Future<void> supprimerBrouillon() async {
    try {
      final Database db = await _ouvrir();
      await db.delete('brouillon_service',
          where: 'utilisateur_id = ?', whereArgs: [utilisateurActuel()]);
    } catch (e) {
      // idem
    }
  }
}
