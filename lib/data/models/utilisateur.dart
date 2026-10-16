import 'package:cloud_firestore/cloud_firestore.dart';

/// Où en est le compte d'un membre dans sa houma.
/// Dans Firestore, on enregistre le nom (`statut.name`, ex : "enAttente").
enum StatutUtilisateur {
  enAttente, // inscrit, attend la validation de l'administrateur
  actif, // validé : accès complet à la houma
  bloque, // bloqué par l'administrateur
  refuse, // demande refusée : peut choisir un autre quartier
}

/// Le rôle d'un membre dans sa houma.
enum RoleUtilisateur {
  resident, // membre normal
  admin, // administrateur du quartier : valide les inscriptions
}

/// M1 - Un utilisateur (habitant) de Houmani.
class Utilisateur {
  final String id;
  final String prenom;
  final String nom;
  final String email; // peut être vide (optionnel à l'inscription)
  final String telephone;
  final String? quartierId; // id du document quartiers/{id}, null = pas encore choisi
  final String quartier; // ex : "Résidence El Yasmine" (Firestore : quartierNom)
  final String residence; // ex : "Résidence El Yasmine, Bloc B" (utilisé par M3)
  final String logement; // ex : "Bloc B - Appt 12" (visible par l'admin seulement)

  final StatutUtilisateur statut;
  final RoleUtilisateur role;
  final List<String> competences; // ex : ["Bricolage", "Informatique"]

  // Statistiques affichées sur le profil
  final int servicesRendus;
  final double noteMoyenne;
  final int nbSignalements;

  // Date de la demande d'inscription (affichée dans la liste de l'admin)
  final DateTime? dateDemande;

  // Avatar choisi dans la galerie (ex : "chat"), vide = initiales
  final String avatar;

  // Raison donnée par l'admin quand il refuse ou bloque (vide sinon)
  final String motif;

  const Utilisateur({
    required this.id,
    required this.prenom,
    required this.nom,
    required this.email,
    required this.telephone,
    required this.quartier,
    required this.residence,
    // Les champs suivants ont une valeur par défaut :
    // l'ancien code qui ne les donne pas continue de fonctionner
    this.quartierId,
    this.logement = '',
    this.statut = StatutUtilisateur.actif,
    this.role = RoleUtilisateur.resident,
    this.competences = const [],
    this.servicesRendus = 0,
    this.noteMoyenne = 0,
    this.nbSignalements = 0,
    this.dateDemande,
    this.avatar = '',
    this.motif = '',
  });

  String get nomComplet => '$prenom $nom';

  /// Les initiales, pour l'avatar (ex : "Amira Ben Salah" donne "AB").
  String get initiales {
    String resultat = '';
    if (prenom.isNotEmpty) {
      resultat = resultat + prenom[0];
    }
    if (nom.isNotEmpty) {
      resultat = resultat + nom[0];
    }
    return resultat.toUpperCase();
  }

  bool get estAdmin => role == RoleUtilisateur.admin;

  /// Renvoie une copie de l'utilisateur avec certains champs modifiés.
  /// Les champs non donnés gardent leur valeur actuelle.
  /// Exemple : utilisateur.copier(statut: StatutUtilisateur.actif)
  Utilisateur copier({
    String? prenom,
    String? nom,
    String? email,
    String? telephone,
    String? quartierId,
    String? quartier,
    String? residence,
    String? logement,
    StatutUtilisateur? statut,
    List<String>? competences,
    DateTime? dateDemande,
    String? avatar,
    String? motif,
  }) {
    return Utilisateur(
      id: id,
      prenom: prenom ?? this.prenom,
      nom: nom ?? this.nom,
      email: email ?? this.email,
      telephone: telephone ?? this.telephone,
      quartierId: quartierId ?? this.quartierId,
      quartier: quartier ?? this.quartier,
      residence: residence ?? this.residence,
      logement: logement ?? this.logement,
      statut: statut ?? this.statut,
      role: role,
      competences: competences ?? this.competences,
      servicesRendus: servicesRendus,
      noteMoyenne: noteMoyenne,
      nbSignalements: nbSignalements,
      dateDemande: dateDemande ?? this.dateDemande,
      avatar: avatar ?? this.avatar,
      motif: motif ?? this.motif,
    );
  }

  // ---------------------------------------------------------------------
  // Firestore : document utilisateurs/{id}  (voir docs/schema_firestore.md)
  // ---------------------------------------------------------------------

  /// Les champs enregistrés dans Firestore. L'id est le nom du document,
  /// et les statistiques (servicesRendus...) ne sont pas stockées.
  Map<String, dynamic> toMap() {
    return {
      'prenom': prenom,
      'nom': nom,
      'email': email,
      'telephone': telephone,
      'quartierId': quartierId,
      'quartierNom': quartier,
      'residence': residence,
      'logement': logement,
      'statut': statut.name, // enum → texte, ex : "enAttente"
      'role': role.name,
      'competences': competences,
      'avatar': avatar,
      'motif': motif,
      'dateDemande': dateDemande, // DateTime → Timestamp (fait par Firestore)
    };
  }

  /// Construit un utilisateur à partir d'un document Firestore.
  /// Un champ absent prend une valeur par défaut (pas de plantage).
  factory Utilisateur.fromMap(String id, Map<String, dynamic> map) {
    final Timestamp? date = map['dateDemande'];
    return Utilisateur(
      id: id,
      prenom: map['prenom'] ?? '',
      nom: map['nom'] ?? '',
      email: map['email'] ?? '',
      telephone: map['telephone'] ?? '',
      quartierId: map['quartierId'],
      quartier: map['quartierNom'] ?? '',
      residence: map['residence'] ?? '',
      logement: map['logement'] ?? '',
      statut: _statutDepuisTexte(map['statut']),
      role: map['role'] == RoleUtilisateur.admin.name
          ? RoleUtilisateur.admin
          : RoleUtilisateur.resident,
      competences: List<String>.from(map['competences'] ?? []),
      avatar: map['avatar'] ?? '',
      motif: map['motif'] ?? '',
      dateDemande: date?.toDate(),
    );
  }

  /// "actif" donne StatutUtilisateur.actif. Texte inconnu : en attente
  /// (le cas le plus prudent : aucun accès).
  static StatutUtilisateur _statutDepuisTexte(String? texte) {
    for (final StatutUtilisateur statut in StatutUtilisateur.values) {
      if (statut.name == texte) {
        return statut;
      }
    }
    return StatutUtilisateur.enAttente;
  }
}
