// =====================================================================
// M3 - Base SQLite locale du module Signalements (package sqflite).
//
// POURQUOI SQFLITE, alors que Firestore a déjà son propre cache hors ligne ?
// (détails : docs/module3_sqflite.md)
//
// 1. Brouillons : un formulaire pas encore envoyé n'est PAS un document
//    Firestore. Le cache de Firestore ne garde que ce qui a été écrit dans
//    Firestore ; un brouillon doit rester sur le téléphone, privé.
// 2. File d'envoi VISIBLE : Firestore garde bien ses écritures hors ligne,
//    mais en cachette (pas de liste, pas d'état, pas de "Réessayer", pas
//    d'"Annuler", et `await add()` ne se termine jamais hors ligne). Notre
//    table envois_en_attente montre chaque envoi, son état, le nombre
//    d'essais et la dernière erreur.
// 3. Photos (étape 6) : un fichier local ne peut pas aller dans Firestore.
//    La file garde le chemin de la photo jusqu'à l'envoi sur Cloudinary.
// 4. Requêtes SQL locales : filtrer le cache (statut, catégorie, auteur)
//    et trier, sans réseau ni index composite Firestore.
// 5. Maîtrise : on sait exactement ce qui est gardé, et quand
//    (« dernière mise à jour à HH:mm »).
//
// Tables :
//   brouillons          : 1 brouillon par utilisateur (formulaire en cours)
//   envois_en_attente   : signalements créés hors ligne, à envoyer
//   signalements_cache  : derniers signalements chargés, par quartier
//   mises_a_jour_cache  : heure du dernier chargement complet, par quartier
//   adresses_cache      : adresses déjà trouvées par Nominatim (version 2)
// Version 3 : envois_en_attente.photo_url (photo déjà sur Cloudinary)
// =====================================================================

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quartier.dart' show PointGps;
import '../models/signalement.dart';

/// Lit un point GPS rangé en deux colonnes REAL (null si pas de point).
PointGps? lirePosition(Map<String, Object?> ligne) {
  final Object? latitude = ligne['latitude'];
  final Object? longitude = ligne['longitude'];
  if (latitude is num && longitude is num) {
    return PointGps(latitude.toDouble(), longitude.toDouble());
  }
  return null;
}

/// Un brouillon : le formulaire de création pas encore envoyé.
class Brouillon {
  final String utilisateurId; // un brouillon par utilisateur
  final String titre;
  final String description;
  final String? categorieId;
  final String lieu;
  final bool danger;
  final String? photoLocale; // chemin d'une photo sur le téléphone (étape 6)
  final PointGps? position; // "Utiliser ma position" (version 2)
  final DateTime dateModification;

  const Brouillon({
    required this.utilisateurId,
    this.titre = '',
    this.description = '',
    this.categorieId,
    this.lieu = '',
    this.danger = false,
    this.photoLocale,
    this.position,
    required this.dateModification,
  });

  /// Rien n'a été saisi : inutile de le garder.
  bool get estVide =>
      titre.trim().isEmpty &&
      description.trim().isEmpty &&
      lieu.trim().isEmpty &&
      categorieId == null &&
      !danger &&
      photoLocale == null &&
      position == null;

  Map<String, Object?> toMap() {
    return {
      'utilisateur_id': utilisateurId,
      'titre': titre,
      'description': description,
      'categorie_id': categorieId,
      'lieu': lieu,
      'danger': danger ? 1 : 0, // SQLite n'a pas de booléen : 0 / 1
      'photo_locale': photoLocale,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'date_modification': dateModification.millisecondsSinceEpoch,
    };
  }

  factory Brouillon.fromMap(Map<String, Object?> ligne) {
    return Brouillon(
      utilisateurId: ligne['utilisateur_id'] as String,
      titre: ligne['titre'] as String? ?? '',
      description: ligne['description'] as String? ?? '',
      categorieId: ligne['categorie_id'] as String?,
      lieu: ligne['lieu'] as String? ?? '',
      danger: ligne['danger'] == 1,
      photoLocale: ligne['photo_locale'] as String?,
      position: lirePosition(ligne),
      dateModification: DateTime.fromMillisecondsSinceEpoch(
        ligne['date_modification'] as int,
      ),
    );
  }
}

/// Les 2 états d'un envoi en attente.
class EtatEnvoi {
  EtatEnvoi._();
  static const String enAttente = 'en_attente'; // pas encore essayé (ou relancé)
  static const String echec = 'echec'; // le dernier essai a échoué
}

/// Un signalement créé hors ligne, en attente d'envoi.
class EnvoiEnAttente {
  final int? id; // clé SQLite (null avant l'insertion)
  // Id du futur document Firestore, choisi AVANT l'envoi : si un envoi est
  // rejoué, il réécrit le même document (pas de doublon).
  final String idDocument;
  final String utilisateurId;
  final String quartierId;
  final String titre;
  final String description;
  final String categorieId;
  final String lieu;
  final bool danger;
  final String? photoLocale; // étape 6 : photo à envoyer avant le signalement
  final PointGps? position; // point GPS gardé hors ligne (version 2)
  // Adresse Cloudinary de la photo, dès qu'elle est envoyée (version 3) :
  // si Firestore échoue ensuite, on ne renvoie pas la photo une 2e fois.
  final String? photoUrl;
  final DateTime dateCreation;
  final String etat; // EtatEnvoi.enAttente ou EtatEnvoi.echec
  final int nbTentatives;
  final String? derniereErreur;

  const EnvoiEnAttente({
    this.id,
    required this.idDocument,
    required this.utilisateurId,
    required this.quartierId,
    required this.titre,
    required this.description,
    required this.categorieId,
    required this.lieu,
    this.danger = false,
    this.photoLocale,
    this.position,
    this.photoUrl,
    required this.dateCreation,
    this.etat = EtatEnvoi.enAttente,
    this.nbTentatives = 0,
    this.derniereErreur,
  });

  bool get estEnEchec => etat == EtatEnvoi.echec;

  /// Le signalement à envoyer (auteur, statut et compteur sont imposés par
  /// le repository au moment de l'envoi).
  Signalement versSignalement() {
    return Signalement(
      id: idDocument,
      titre: titre,
      description: description,
      categorieId: categorieId,
      statut: StatutSignalement.enAttente,
      date: dateCreation,
      lieu: lieu,
      auteurId: utilisateurId,
      auteurNom: '',
      danger: danger,
      position: position,
      photoUrl: photoUrl,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id, // null : SQLite choisit (AUTOINCREMENT)
      'id_document': idDocument,
      'utilisateur_id': utilisateurId,
      'quartier_id': quartierId,
      'titre': titre,
      'description': description,
      'categorie_id': categorieId,
      'lieu': lieu,
      'danger': danger ? 1 : 0,
      'photo_locale': photoLocale,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'date_creation': dateCreation.millisecondsSinceEpoch,
      'etat': etat,
      'nb_tentatives': nbTentatives,
      'derniere_erreur': derniereErreur,
      'photo_url': photoUrl,
    };
  }

  factory EnvoiEnAttente.fromMap(Map<String, Object?> ligne) {
    return EnvoiEnAttente(
      id: ligne['id'] as int,
      idDocument: ligne['id_document'] as String,
      utilisateurId: ligne['utilisateur_id'] as String,
      quartierId: ligne['quartier_id'] as String,
      titre: ligne['titre'] as String,
      description: ligne['description'] as String,
      categorieId: ligne['categorie_id'] as String,
      lieu: ligne['lieu'] as String,
      danger: ligne['danger'] == 1,
      photoLocale: ligne['photo_locale'] as String?,
      position: lirePosition(ligne),
      dateCreation: DateTime.fromMillisecondsSinceEpoch(
        ligne['date_creation'] as int,
      ),
      etat: ligne['etat'] as String,
      nbTentatives: ligne['nb_tentatives'] as int,
      derniereErreur: ligne['derniere_erreur'] as String?,
      photoUrl: ligne['photo_url'] as String?,
    );
  }
}

/// M3 - Accès à la base SQLite locale (requêtes SQL écrites à la main).
///
/// Les méthodes peuvent lever une exception SQLite : c'est
/// SyncSignalementsM3 qui les attrape (l'application continue sans cache).
class BaseLocaleM3 {
  /// La base utilisée par l'application. Les tests en mettent une neuve,
  /// en mémoire : `BaseLocaleM3.instance = BaseLocaleM3(chemin: inMemoryDatabasePath)`.
  static BaseLocaleM3 instance = BaseLocaleM3();

  static const String nomFichier = 'houmani_m3.db';
  /// Version du schéma :
  ///   1 : brouillons, envois_en_attente, signalements_cache, mises_a_jour_cache
  ///   2 : + colonnes latitude / longitude (GPS) et table adresses_cache
  ///   3 : + colonne photo_url dans envois_en_attente (photo déjà envoyée)
  static const int version = 3;

  /// Chemin de la base (null : le dossier des bases de l'application).
  final String? chemin;

  BaseLocaleM3({this.chemin});

  Database? _ouverte; // ouverte une seule fois, au premier usage

  /// La base ouverte (créée au premier lancement par [_creerTables]).
  /// Si l'ouverture échoue, on réessaiera au prochain appel.
  Future<Database> get base async {
    final Database? dejaOuverte = _ouverte;
    if (dejaOuverte != null) {
      return dejaOuverte;
    }
    final Database nouvelle = await _ouvrir();
    _ouverte = nouvelle;
    return nouvelle;
  }

  Future<Database> _ouvrir() async {
    final String fichier =
        chemin ?? join(await getDatabasesPath(), nomFichier);
    return openDatabase(
      fichier,
      version: version,
      // Nouveau téléphone : on crée tout (version 1 puis les ajouts)
      onCreate: (db, version) async {
        await creerTablesVersion1(db);
        await _migrerVersVersion2(db);
        await _migrerVersVersion3(db);
      },
      // Téléphone qui avait une version plus ancienne : on ajoute seulement
      // ce qui manque, SANS effacer ses brouillons ni sa file d'envoi.
      // (1 → 3 passe par 2 : chaque étape une seule fois, dans l'ordre)
      onUpgrade: (db, ancienne, nouvelle) async {
        if (ancienne < 2) {
          await _migrerVersVersion2(db);
        }
        if (ancienne < 3) {
          await _migrerVersVersion3(db);
        }
      },
    );
  }

  /// Version 3 : l'adresse Cloudinary d'une photo déjà envoyée.
  Future<void> _migrerVersVersion3(Database db) async {
    await db.execute('ALTER TABLE envois_en_attente ADD COLUMN photo_url TEXT');
  }

  /// Version 2 : le point GPS (deux colonnes REAL, NULL si pas de point) et
  /// le cache des adresses de Nominatim.
  Future<void> _migrerVersVersion2(Database db) async {
    for (final String table in [
      'brouillons',
      'envois_en_attente',
      'signalements_cache',
    ]) {
      await db.execute('ALTER TABLE $table ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE $table ADD COLUMN longitude REAL');
    }
    // cle = latitude,longitude arrondies à 4 décimales (environ 11 m)
    await db.execute('''
      CREATE TABLE adresses_cache (
        cle TEXT PRIMARY KEY,
        adresse TEXT NOT NULL,
        date INTEGER NOT NULL
      )
    ''');
  }

  /// Les tables de la version 1 (publique : les tests s'en servent pour
  /// simuler un téléphone resté en version 1).
  static Future<void> creerTablesVersion1(Database db) async {
    await db.execute('''
      CREATE TABLE brouillons (
        utilisateur_id TEXT PRIMARY KEY,
        titre TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        categorie_id TEXT,
        lieu TEXT NOT NULL DEFAULT '',
        danger INTEGER NOT NULL DEFAULT 0,
        photo_locale TEXT,
        date_modification INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE envois_en_attente (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_document TEXT NOT NULL UNIQUE,
        utilisateur_id TEXT NOT NULL,
        quartier_id TEXT NOT NULL,
        titre TEXT NOT NULL,
        description TEXT NOT NULL,
        categorie_id TEXT NOT NULL,
        lieu TEXT NOT NULL,
        danger INTEGER NOT NULL DEFAULT 0,
        photo_locale TEXT,
        date_creation INTEGER NOT NULL,
        etat TEXT NOT NULL DEFAULT 'en_attente',
        nb_tentatives INTEGER NOT NULL DEFAULT 0,
        derniere_erreur TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE signalements_cache (
        id TEXT NOT NULL,
        quartier_id TEXT NOT NULL,
        titre TEXT NOT NULL,
        description TEXT NOT NULL,
        categorie_id TEXT NOT NULL,
        statut TEXT NOT NULL,
        date INTEGER NOT NULL,
        lieu TEXT NOT NULL,
        auteur_id TEXT NOT NULL,
        auteur_nom TEXT NOT NULL,
        nb_confirmations INTEGER NOT NULL DEFAULT 0,
        danger INTEGER NOT NULL DEFAULT 0,
        photo_url TEXT,
        PRIMARY KEY (quartier_id, id)
      )
    ''');
    // Index : les filtres de la liste (quartier + statut, triés par date)
    await db.execute(
      'CREATE INDEX idx_cache_statut ON signalements_cache '
      '(quartier_id, statut, date DESC)',
    );
    await db.execute('''
      CREATE TABLE mises_a_jour_cache (
        quartier_id TEXT PRIMARY KEY,
        date INTEGER NOT NULL
      )
    ''');
  }

  /// Ferme la base (tests : une base en mémoire disparaît à la fermeture).
  Future<void> fermer() async {
    final Database? ouverte = _ouverte;
    _ouverte = null;
    if (ouverte != null) {
      await ouverte.close();
    }
  }

  /// Déconnexion : efface le brouillon et la file d'envoi de
  /// [utilisateurId], et le cache des signalements (données du quartier,
  /// réservées à ses membres). Le cache des adresses (public) reste.
  /// Une transaction : tout ou rien.
  Future<void> viderUtilisateur(String utilisateurId) async {
    final Database db = await base;
    await db.transaction((txn) async {
      await txn.delete(
        'brouillons',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurId],
      );
      await txn.delete(
        'envois_en_attente',
        where: 'utilisateur_id = ?',
        whereArgs: [utilisateurId],
      );
      await txn.delete('signalements_cache');
      await txn.delete('mises_a_jour_cache');
    });
  }

  // =====================================================================
  // brouillons
  // =====================================================================

  /// Crée ou remplace le brouillon de l'utilisateur (1 par utilisateur).
  Future<void> enregistrerBrouillon(Brouillon brouillon) async {
    final Database db = await base;
    await db.insert(
      'brouillons',
      brouillon.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Le brouillon de l'utilisateur (null s'il n'en a pas).
  Future<Brouillon?> lireBrouillon(String utilisateurId) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'brouillons',
      where: 'utilisateur_id = ?',
      whereArgs: [utilisateurId],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return Brouillon.fromMap(lignes.first);
  }

  Future<void> supprimerBrouillon(String utilisateurId) async {
    final Database db = await base;
    await db.delete(
      'brouillons',
      where: 'utilisateur_id = ?',
      whereArgs: [utilisateurId],
    );
  }

  // =====================================================================
  // envois_en_attente
  // =====================================================================

  /// Ajoute un envoi ; renvoie sa clé SQLite.
  Future<int> ajouterEnvoi(EnvoiEnAttente envoi) async {
    final Database db = await base;
    return db.insert('envois_en_attente', envoi.toMap());
  }

  /// Les envois de l'utilisateur, du plus ancien au plus récent (ordre d'envoi).
  Future<List<EnvoiEnAttente>> lireEnvois(String utilisateurId) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'envois_en_attente',
      where: 'utilisateur_id = ?',
      whereArgs: [utilisateurId],
      orderBy: 'date_creation ASC',
    );
    final List<EnvoiEnAttente> envois = [];
    for (final Map<String, Object?> ligne in lignes) {
      envois.add(EnvoiEnAttente.fromMap(ligne));
    }
    return envois;
  }

  /// Un envoi (null s'il n'existe plus).
  Future<EnvoiEnAttente?> lireEnvoi(int id) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'envois_en_attente',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return EnvoiEnAttente.fromMap(lignes.first);
  }

  /// Nombre d'envois en attente de l'utilisateur (rawQuery + COUNT).
  Future<int> compterEnvois(String utilisateurId) async {
    final Database db = await base;
    final List<Map<String, Object?>> resultat = await db.rawQuery(
      'SELECT COUNT(*) AS nombre FROM envois_en_attente WHERE utilisateur_id = ?',
      [utilisateurId],
    );
    return resultat.first['nombre'] as int;
  }

  /// Un essai a échoué : état "echec", un essai de plus, l'erreur gardée.
  /// La photo de cet envoi est sur Cloudinary : on garde son adresse.
  Future<void> enregistrerPhotoEnvoyee(int id, String url) async {
    final Database db = await base;
    await db.update(
      'envois_en_attente',
      {'photo_url': url},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Toutes les photos locales encore utiles (brouillons + file d'envoi),
  /// en une requête : UNION enlève les doublons.
  Future<Set<String>> cheminsPhotosUtilises() async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.rawQuery(
      'SELECT photo_locale FROM brouillons WHERE photo_locale IS NOT NULL '
      'UNION '
      'SELECT photo_locale FROM envois_en_attente WHERE photo_locale IS NOT NULL',
    );
    final Set<String> chemins = {};
    for (final Map<String, Object?> ligne in lignes) {
      chemins.add(ligne['photo_locale'] as String);
    }
    return chemins;
  }

  Future<void> marquerEchec(int id, String erreur) async {
    final Database db = await base;
    await db.rawUpdate(
      'UPDATE envois_en_attente '
      'SET etat = ?, nb_tentatives = nb_tentatives + 1, derniere_erreur = ? '
      'WHERE id = ?',
      [EtatEnvoi.echec, erreur, id],
    );
  }

  /// Envoyé (ou annulé par l'utilisateur) : on le retire de la file.
  Future<void> supprimerEnvoi(int id) async {
    final Database db = await base;
    await db.delete('envois_en_attente', where: 'id = ?', whereArgs: [id]);
  }

  // =====================================================================
  // signalements_cache
  // =====================================================================

  Map<String, Object?> _ligneCache(String quartierId, Signalement s) {
    return {
      'id': s.id,
      'quartier_id': quartierId,
      'titre': s.titre,
      'description': s.description,
      'categorie_id': s.categorieId,
      'statut': s.statut.name,
      'date': s.date.millisecondsSinceEpoch,
      'lieu': s.lieu,
      'auteur_id': s.auteurId,
      'auteur_nom': s.auteurNom,
      'nb_confirmations': s.nbConfirmations,
      'danger': s.danger ? 1 : 0,
      'photo_url': s.photoUrl,
      'latitude': s.position?.latitude,
      'longitude': s.position?.longitude,
    };
  }

  Signalement _depuisCache(Map<String, Object?> ligne) {
    StatutSignalement statut = StatutSignalement.enAttente;
    for (final StatutSignalement valeur in StatutSignalement.values) {
      if (valeur.name == ligne['statut']) {
        statut = valeur;
      }
    }
    return Signalement(
      id: ligne['id'] as String,
      titre: ligne['titre'] as String,
      description: ligne['description'] as String,
      categorieId: ligne['categorie_id'] as String,
      statut: statut,
      date: DateTime.fromMillisecondsSinceEpoch(ligne['date'] as int),
      lieu: ligne['lieu'] as String,
      auteurId: ligne['auteur_id'] as String,
      auteurNom: ligne['auteur_nom'] as String,
      nbConfirmations: ligne['nb_confirmations'] as int,
      danger: ligne['danger'] == 1,
      photoUrl: ligne['photo_url'] as String?,
      position: lirePosition(ligne),
    );
  }

  /// Chargement COMPLET de la liste : on remplace tout le cache du quartier
  /// (les signalements supprimés disparaissent) et on note l'heure.
  /// Une transaction : tout ou rien.
  Future<void> remplacerCache(
    String quartierId,
    List<Signalement> signalements,
    DateTime maintenant,
  ) async {
    final Database db = await base;
    await db.transaction((txn) async {
      await txn.delete(
        'signalements_cache',
        where: 'quartier_id = ?',
        whereArgs: [quartierId],
      );
      final Batch batch = txn.batch();
      for (final Signalement s in signalements) {
        batch.insert('signalements_cache', _ligneCache(quartierId, s));
      }
      await batch.commit(noResult: true);
      await txn.insert(
        'mises_a_jour_cache',
        {'quartier_id': quartierId, 'date': maintenant.millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Chargement PARTIEL (avec filtre, ou un seul signalement) : on met à
  /// jour ces lignes sans effacer les autres.
  Future<void> mettreAJourCache(
    String quartierId,
    List<Signalement> signalements,
  ) async {
    final Database db = await base;
    final Batch batch = db.batch();
    for (final Signalement s in signalements) {
      batch.insert(
        'signalements_cache',
        _ligneCache(quartierId, s),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Lit le cache avec des filtres SQL optionnels, du plus récent au plus ancien.
  Future<List<Signalement>> lireCache(
    String quartierId, {
    StatutSignalement? statut,
    String? categorieId,
    String? auteurId,
  }) async {
    final Database db = await base;
    // La clause WHERE est construite selon les filtres choisis
    String where = 'quartier_id = ?';
    final List<Object?> arguments = [quartierId];
    if (statut != null) {
      where = '$where AND statut = ?';
      arguments.add(statut.name);
    }
    if (categorieId != null) {
      where = '$where AND categorie_id = ?';
      arguments.add(categorieId);
    }
    if (auteurId != null) {
      where = '$where AND auteur_id = ?';
      arguments.add(auteurId);
    }
    final List<Map<String, Object?>> lignes = await db.query(
      'signalements_cache',
      where: where,
      whereArgs: arguments,
      orderBy: 'date DESC',
    );
    final List<Signalement> signalements = [];
    for (final Map<String, Object?> ligne in lignes) {
      signalements.add(_depuisCache(ligne));
    }
    return signalements;
  }

  /// Un signalement du cache (null s'il n'y est pas).
  Future<Signalement?> lireDuCache(String quartierId, String id) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'signalements_cache',
      where: 'quartier_id = ? AND id = ?',
      whereArgs: [quartierId, id],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return _depuisCache(lignes.first);
  }

  /// Retire un signalement supprimé du cache.
  Future<void> supprimerDuCache(String quartierId, String id) async {
    final Database db = await base;
    await db.delete(
      'signalements_cache',
      where: 'quartier_id = ? AND id = ?',
      whereArgs: [quartierId, id],
    );
  }

  // =====================================================================
  // adresses_cache (version 2) : réponses de Nominatim déjà reçues
  // =====================================================================

  /// L'adresse déjà trouvée pour cette clé (null : jamais demandée).
  Future<String?> lireAdresse(String cle) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'adresses_cache',
      columns: ['adresse'],
      where: 'cle = ?',
      whereArgs: [cle],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return lignes.first['adresse'] as String;
  }

  Future<void> enregistrerAdresse(String cle, String adresse) async {
    final Database db = await base;
    await db.insert(
      'adresses_cache',
      {
        'cle': cle,
        'adresse': adresse,
        'date': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// L'heure du dernier chargement complet (null : jamais chargé).
  Future<DateTime?> dateMiseAJour(String quartierId) async {
    final Database db = await base;
    final List<Map<String, Object?>> lignes = await db.query(
      'mises_a_jour_cache',
      where: 'quartier_id = ?',
      whereArgs: [quartierId],
    );
    if (lignes.isEmpty) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(lignes.first['date'] as int);
  }
}
