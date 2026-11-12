import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quartier.dart';
import '../models/utilisateur.dart';

/// Une ligne de l'historique des connexions (écran Paramètres → Sécurité).
class ConnexionLocale {
  final String methode; // "email", "telephone" ou "sms"
  final DateTime date;

  const ConnexionLocale({required this.methode, required this.date});
}

/// M1 - Base locale SQLite du module Utilisateurs (fichier houmani_m1.db).
///
/// Tables :
/// - profil : le profil connecté (1 ligne) ;
/// - quartier + quartier_points : son quartier et les coins du contour ;
/// - preferences : thème et langue (clé → valeur) ;
/// - voisins : copie de l'annuaire, lisible sans Internet ;
/// - historique_connexions : les dernières connexions sur ce téléphone ;
/// - geocodage : adresses déjà cherchées sur la carte (vérification admin).
///
/// À quoi ça sert :
/// - au redémarrage, le profil s'affiche tout de suite, avant Firebase ;
/// - sans Internet, l'app montre la dernière version connue ;
/// - l'utilisateur voit quand et comment son compte a été ouvert ici.
///
/// La base n'est qu'une copie : en cas d'erreur, on fait comme si elle
/// était vide (try/catch partout), elle ne doit jamais faire planter l'app.
class CacheLocal {
  static const String nomFichier = 'houmani_m1.db';
  static const int version = 2; // v2 : table geocodage

  /// Une adresse vérifiée est gardée 30 jours (une rue ne bouge pas).
  static const Duration dureeGeocodage = Duration(days: 30);

  /// On garde au plus ce nombre de connexions dans l'historique.
  static const int maxConnexions = 20;

  static const String _cleTheme = 'theme';
  static const String _cleLangue = 'langue';
  static const String _cleMeteo = 'meteo'; // dernière météo reçue (JSON)

  /// Dossier du fichier .db. null = dossier des bases de l'app (cas normal).
  /// Les tests donnent un dossier temporaire.
  final String? dossier;

  CacheLocal({this.dossier});

  // Une seule connexion par fichier, partagée par tous les CacheLocal
  // (le dépôt, le thème et la langue utilisent le même fichier).
  static final Map<String, Database> _bases = {};

  Future<String> _chemin() async {
    return join(dossier ?? await getDatabasesPath(), nomFichier);
  }

  /// Ouvre la base au premier usage (et crée les tables), puis la réutilise.
  Future<Database> _ouvrir() async {
    final String chemin = await _chemin();
    final Database? deja = _bases[chemin];
    if (deja != null && deja.isOpen) {
      return deja;
    }
    final Database base = await openDatabase(
      chemin,
      version: version,
      onConfigure: (db) async {
        // Active ON DELETE CASCADE (quartier → ses points)
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE profil (
            id TEXT PRIMARY KEY,
            prenom TEXT NOT NULL,
            nom TEXT NOT NULL,
            email TEXT NOT NULL,
            telephone TEXT NOT NULL,
            quartier_id TEXT,
            quartier_nom TEXT NOT NULL,
            residence TEXT NOT NULL,
            logement TEXT NOT NULL,
            statut TEXT NOT NULL,
            role TEXT NOT NULL,
            competences TEXT NOT NULL,
            avatar TEXT NOT NULL,
            motif TEXT NOT NULL,
            date_demande INTEGER
          )''');
        await db.execute('''
          CREATE TABLE quartier (
            id TEXT PRIMARY KEY,
            nom TEXT NOT NULL,
            localisation TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            a_un_admin INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE quartier_points (
            quartier_id TEXT NOT NULL,
            ordre INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            PRIMARY KEY (quartier_id, ordre),
            FOREIGN KEY (quartier_id) REFERENCES quartier(id)
              ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE preferences (
            cle TEXT PRIMARY KEY,
            valeur TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE voisins (
            id TEXT PRIMARY KEY,
            quartier_id TEXT NOT NULL,
            prenom TEXT NOT NULL,
            nom TEXT NOT NULL,
            telephone TEXT NOT NULL,
            logement TEXT NOT NULL,
            avatar TEXT NOT NULL,
            competences TEXT NOT NULL,
            maj_le INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_voisins_quartier ON voisins(quartier_id)');
        // Une ligne par (voisin, compétence) : permet de compter en SQL
        await db.execute('''
          CREATE TABLE voisin_competences (
            voisin_id TEXT NOT NULL,
            competence TEXT NOT NULL,
            PRIMARY KEY (voisin_id, competence),
            FOREIGN KEY (voisin_id) REFERENCES voisins(id)
              ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE historique_connexions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            utilisateur_id TEXT NOT NULL,
            methode TEXT NOT NULL,
            date INTEGER NOT NULL
          )''');
        await _creerGeocodage(db);
      },
      // Téléphone qui avait la version 1 : on ajoute la nouvelle table
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) {
          await _creerGeocodage(db);
        }
      },
    );
    _bases[chemin] = base;
    return base;
  }

  /// Table geocodage : adresse cherchée → point trouvé (NULL : introuvable,
  /// gardé aussi pour ne pas redemander à Nominatim).
  static Future<void> _creerGeocodage(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS geocodage (
        adresse TEXT PRIMARY KEY,
        latitude REAL,
        longitude REAL,
        date INTEGER NOT NULL
      )''');
  }

  // =====================================================================
  // Géocodage des adresses (vérification par l'admin, M1)
  // =====================================================================

  /// Garde le résultat d'une recherche d'adresse. point null : introuvable.
  Future<void> enregistrerGeocodage(
    String adresse,
    PointGps? point, {
    DateTime? date,
  }) async {
    try {
      final Database base = await _ouvrir();
      await base.insert(
        'geocodage',
        {
          'adresse': adresse,
          'latitude': point?.latitude,
          'longitude': point?.longitude,
          'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Le résultat gardé pour cette adresse s'il a moins de 30 jours.
  /// null : jamais cherchée (ou trop ancienne). Sinon un record dont le
  /// point est null si l'adresse était introuvable.
  Future<({PointGps? point})?> lireGeocodage(
    String adresse, {
    DateTime? maintenant,
  }) async {
    try {
      final Database base = await _ouvrir();
      final int limite = (maintenant ?? DateTime.now())
          .subtract(dureeGeocodage)
          .millisecondsSinceEpoch;
      final List<Map<String, Object?>> lignes = await base.query(
        'geocodage',
        where: 'adresse = ? AND date >= ?',
        whereArgs: [adresse, limite],
      );
      if (lignes.isEmpty) {
        return null;
      }
      final Object? lat = lignes.first['latitude'];
      final Object? lng = lignes.first['longitude'];
      if (lat is num && lng is num) {
        return (point: PointGps(lat.toDouble(), lng.toDouble()));
      }
      return (point: null);
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  // =====================================================================
  // Utilisateur connecté (table profil)
  // =====================================================================

  Future<void> enregistrerUtilisateur(Utilisateur utilisateur) async {
    try {
      final Database base = await _ouvrir();
      // Une seule ligne : on remplace l'ancien profil dans une transaction
      await base.transaction((txn) async {
        await txn.delete('profil');
        await txn.insert('profil', {
          'id': utilisateur.id,
          'prenom': utilisateur.prenom,
          'nom': utilisateur.nom,
          'email': utilisateur.email,
          'telephone': utilisateur.telephone,
          'quartier_id': utilisateur.quartierId,
          'quartier_nom': utilisateur.quartier,
          'residence': utilisateur.residence,
          'logement': utilisateur.logement,
          'statut': utilisateur.statut.name,
          'role': utilisateur.role.name,
          // La liste devient un texte JSON : ["Bricolage","Informatique"]
          'competences': jsonEncode(utilisateur.competences),
          'avatar': utilisateur.avatar,
          'motif': utilisateur.motif,
          'date_demande': utilisateur.dateDemande?.millisecondsSinceEpoch,
        });
      });
    } catch (e) {
      // Base indisponible : tant pis, les données sont aussi sur Firebase.
      // On l'écrit quand même dans la console pour ne pas cacher un bug.
      debugPrint('CacheLocal : $e');
    }
  }

  /// Le profil gardé, ou null s'il n'y en a pas.
  Future<Utilisateur?> lireUtilisateur() async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes =
          await base.query('profil', limit: 1);
      if (lignes.isEmpty) {
        return null;
      }
      final Map<String, Object?> ligne = lignes.first;
      final Object? millisecondes = ligne['date_demande'];
      return Utilisateur(
        id: ligne['id'] as String,
        prenom: ligne['prenom'] as String,
        nom: ligne['nom'] as String,
        email: ligne['email'] as String,
        telephone: ligne['telephone'] as String,
        quartierId: ligne['quartier_id'] as String?,
        quartier: ligne['quartier_nom'] as String,
        residence: ligne['residence'] as String,
        logement: ligne['logement'] as String,
        statut: _statut(ligne['statut'] as String),
        role: _role(ligne['role'] as String),
        competences: _liste(ligne['competences'] as String),
        avatar: ligne['avatar'] as String,
        motif: ligne['motif'] as String,
        dateDemande: millisecondes is int
            ? DateTime.fromMillisecondsSinceEpoch(millisecondes)
            : null,
      );
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null; // base abîmée : comme si elle était vide
    }
  }

  // =====================================================================
  // Quartier de l'utilisateur connecté (tables quartier + quartier_points)
  // =====================================================================

  Future<void> enregistrerQuartier(Quartier quartier) async {
    try {
      final Database base = await _ouvrir();
      final PointGps? position = quartier.position;
      await base.transaction((txn) async {
        // Supprimer l'ancien quartier supprime aussi ses points (CASCADE)
        await txn.delete('quartier');
        await txn.insert('quartier', {
          'id': quartier.id,
          'nom': quartier.nom,
          'localisation': quartier.localisation,
          'latitude': position?.latitude,
          'longitude': position?.longitude,
          'a_un_admin': quartier.aUnAdmin ? 1 : 0,
        });
        for (int i = 0; i < quartier.contour.length; i++) {
          await txn.insert('quartier_points', {
            'quartier_id': quartier.id,
            'ordre': i,
            'latitude': quartier.contour[i].latitude,
            'longitude': quartier.contour[i].longitude,
          });
        }
      });
    } catch (e) {
      debugPrint('CacheLocal : $e'); // voir enregistrerUtilisateur
    }
  }

  Future<Quartier?> lireQuartier() async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes =
          await base.query('quartier', limit: 1);
      if (lignes.isEmpty) {
        return null;
      }
      final Map<String, Object?> ligne = lignes.first;
      final String id = ligne['id'] as String;
      final List<Map<String, Object?>> points = await base.query(
        'quartier_points',
        where: 'quartier_id = ?',
        whereArgs: [id],
        orderBy: 'ordre',
      );
      final List<PointGps> contour = [];
      for (final Map<String, Object?> point in points) {
        contour.add(PointGps(
          (point['latitude'] as num).toDouble(),
          (point['longitude'] as num).toDouble(),
        ));
      }
      final Object? lat = ligne['latitude'];
      final Object? lng = ligne['longitude'];
      return Quartier(
        id: id,
        nom: ligne['nom'] as String,
        localisation: ligne['localisation'] as String,
        position: lat is num && lng is num
            ? PointGps(lat.toDouble(), lng.toDouble())
            : null,
        contour: contour,
        aUnAdmin: ligne['a_un_admin'] == 1,
      );
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  /// Efface seulement le quartier (il a été supprimé sur le serveur).
  Future<void> oublierQuartier() async {
    try {
      final Database base = await _ouvrir();
      await base.delete('quartier'); // les points partent avec (CASCADE)
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  // =====================================================================
  // Annuaire des voisins (table voisins) : lisible hors connexion
  // =====================================================================

  /// Remplace la copie des voisins d'un quartier par la liste reçue.
  Future<void> enregistrerVoisins(
    String quartierId,
    List<Utilisateur> voisins,
  ) async {
    try {
      final Database base = await _ouvrir();
      final int maintenant = DateTime.now().millisecondsSinceEpoch;
      await base.transaction((txn) async {
        await txn.delete(
          'voisins',
          where: 'quartier_id = ?',
          whereArgs: [quartierId],
        );
        final Batch lot = txn.batch(); // toutes les lignes en une fois
        for (final Utilisateur voisin in voisins) {
          lot.insert(
            'voisins',
            {
              'id': voisin.id,
              'quartier_id': quartierId,
              'prenom': voisin.prenom,
              'nom': voisin.nom,
              'telephone': voisin.telephone,
              'logement': voisin.logement,
              'avatar': voisin.avatar,
              'competences': jsonEncode(voisin.competences),
              'maj_le': maintenant,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          for (final String competence in voisin.competences.toSet()) {
            lot.insert(
              'voisin_competences',
              {'voisin_id': voisin.id, 'competence': competence},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        await lot.commit(noResult: true);
      });
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Les voisins gardés pour ce quartier, triés par prénom puis nom.
  Future<List<Utilisateur>> lireVoisins(String quartierId) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.query(
        'voisins',
        where: 'quartier_id = ?',
        whereArgs: [quartierId],
        orderBy: 'prenom COLLATE NOCASE, nom COLLATE NOCASE',
      );
      final List<Utilisateur> voisins = [];
      for (final Map<String, Object?> ligne in lignes) {
        voisins.add(Utilisateur(
          id: ligne['id'] as String,
          prenom: ligne['prenom'] as String,
          nom: ligne['nom'] as String,
          email: '',
          telephone: ligne['telephone'] as String,
          quartierId: quartierId,
          quartier: '',
          residence: '',
          logement: ligne['logement'] as String,
          avatar: ligne['avatar'] as String,
          competences: _liste(ligne['competences'] as String),
        ));
      }
      return voisins;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return [];
    }
  }

  /// Date de la dernière copie des voisins (null : jamais copiés).
  Future<DateTime?> dateVoisins(String quartierId) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.rawQuery(
        'SELECT MAX(maj_le) AS maj FROM voisins WHERE quartier_id = ?',
        [quartierId],
      );
      final Object? maj = lignes.first['maj'];
      return maj is int ? DateTime.fromMillisecondsSinceEpoch(maj) : null;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  /// Nombre de voisins par compétence (SQL : JOIN + GROUP BY).
  /// Ex : {"Bricolage": 3, "Informatique": 1}, du plus fréquent au moins.
  Future<Map<String, int>> competencesDuQuartier(String quartierId) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.rawQuery('''
        SELECT c.competence AS competence, COUNT(*) AS nombre
        FROM voisins v
        JOIN voisin_competences c ON c.voisin_id = v.id
        WHERE v.quartier_id = ?
        GROUP BY c.competence
        ORDER BY nombre DESC, competence
      ''', [quartierId]);
      final Map<String, int> resultat = {};
      for (final Map<String, Object?> ligne in lignes) {
        resultat[ligne['competence'] as String] = ligne['nombre'] as int;
      }
      return resultat;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return {};
    }
  }

  // =====================================================================
  // Historique des connexions (table historique_connexions)
  // =====================================================================

  /// Note une connexion réussie. On ne garde que les [maxConnexions]
  /// dernières de cet utilisateur.
  Future<void> noterConnexion(
    String utilisateurId,
    String methode, {
    DateTime? date,
  }) async {
    try {
      final Database base = await _ouvrir();
      await base.insert('historique_connexions', {
        'utilisateur_id': utilisateurId,
        'methode': methode,
        'date': (date ?? DateTime.now()).millisecondsSinceEpoch,
      });
      await base.rawDelete('''
        DELETE FROM historique_connexions
        WHERE utilisateur_id = ? AND id NOT IN (
          SELECT id FROM historique_connexions
          WHERE utilisateur_id = ?
          ORDER BY date DESC, id DESC
          LIMIT ?
        )''', [utilisateurId, utilisateurId, maxConnexions]);
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Les dernières connexions de cet utilisateur, la plus récente d'abord.
  Future<List<ConnexionLocale>> historiqueConnexions(
    String utilisateurId, {
    int limite = 5,
  }) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.query(
        'historique_connexions',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurId],
        orderBy: 'date DESC, id DESC',
        limit: limite,
      );
      final List<ConnexionLocale> connexions = [];
      for (final Map<String, Object?> ligne in lignes) {
        connexions.add(ConnexionLocale(
          methode: ligne['methode'] as String,
          date: DateTime.fromMillisecondsSinceEpoch(ligne['date'] as int),
        ));
      }
      return connexions;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return [];
    }
  }

  // =====================================================================
  // Apparence et langue (table preferences)
  // =====================================================================

  /// Enregistre le thème choisi dans Paramètres (ex : "sombre").
  Future<void> enregistrerTheme(String mode) {
    return _ecrirePreference(_cleTheme, mode);
  }

  /// Le thème enregistré, ou null s'il n'y en a pas.
  Future<String?> lireTheme() {
    return _lirePreference(_cleTheme);
  }

  /// Enregistre la langue choisie dans Paramètres (ex : "derja").
  Future<void> enregistrerLangue(String langue) {
    return _ecrirePreference(_cleLangue, langue);
  }

  /// La langue enregistrée, ou null s'il n'y en a pas.
  Future<String?> lireLangue() {
    return _lirePreference(_cleLangue);
  }

  /// Garde la dernière météo reçue d'Open-Meteo (texte JSON), pour
  /// l'afficher hors ligne et ne pas redemander toutes les minutes.
  Future<void> enregistrerMeteo(String json) {
    return _ecrirePreference(_cleMeteo, json);
  }

  /// La dernière météo gardée, ou null.
  Future<String?> lireMeteo() {
    return _lirePreference(_cleMeteo);
  }

  Future<void> _ecrirePreference(String cle, String valeur) async {
    try {
      final Database base = await _ouvrir();
      await base.insert(
        'preferences',
        {'cle': cle, 'valeur': valeur},
        conflictAlgorithm: ConflictAlgorithm.replace, // remplace l'ancienne
      );
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  Future<String?> _lirePreference(String cle) async {
    try {
      final Database base = await _ouvrir();
      final List<Map<String, Object?>> lignes = await base.query(
        'preferences',
        where: 'cle = ?',
        whereArgs: [cle],
      );
      return lignes.isEmpty ? null : lignes.first['valeur'] as String;
    } catch (e) {
      debugPrint('CacheLocal : $e');
      return null;
    }
  }

  // =====================================================================
  // Nettoyage
  // =====================================================================

  /// Efface le profil, le quartier et les voisins (à la déconnexion : le
  /// téléphone peut être partagé). Le thème, la langue et l'historique
  /// des connexions sont gardés : ce sont des données du téléphone.
  Future<void> vider() async {
    try {
      final Database base = await _ouvrir();
      await base.transaction((txn) async {
        await txn.delete('profil');
        await txn.delete('quartier');
        await txn.delete('voisins');
      });
    } catch (e) {
      debugPrint('CacheLocal : $e');
    }
  }

  /// Ferme la base (utile dans les tests).
  Future<void> fermer() async {
    final String chemin = await _chemin();
    final Database? base = _bases.remove(chemin);
    await base?.close();
  }

  // ----- Outils -----

  static List<String> _liste(String json) {
    final dynamic brut = jsonDecode(json);
    return brut is List ? List<String>.from(brut) : [];
  }

  /// "actif" donne StatutUtilisateur.actif ; inconnu : en attente.
  static StatutUtilisateur _statut(String texte) {
    for (final StatutUtilisateur statut in StatutUtilisateur.values) {
      if (statut.name == texte) {
        return statut;
      }
    }
    return StatutUtilisateur.enAttente;
  }

  /// "admin" donne RoleUtilisateur.admin ; inconnu : resident.
  static RoleUtilisateur _role(String texte) {
    for (final RoleUtilisateur role in RoleUtilisateur.values) {
      if (role.name == texte) {
        return role;
      }
    }
    return RoleUtilisateur.resident;
  }
}
