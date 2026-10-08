/// Où en est le compte d'un membre dans sa houma.
enum StatutUtilisateur {
  enAttente, // inscrit, attend la validation de l'administrateur
  actif, // validé : accès complet à la houma
  bloque, // bloqué par l'administrateur
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
  final String quartier; // ex : "Résidence El Yasmine"
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
    this.logement = '',
    this.statut = StatutUtilisateur.actif,
    this.role = RoleUtilisateur.resident,
    this.competences = const [],
    this.servicesRendus = 0,
    this.noteMoyenne = 0,
    this.nbSignalements = 0,
    this.dateDemande,
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
    String? telephone,
    String? quartier,
    String? residence,
    String? logement,
    StatutUtilisateur? statut,
    List<String>? competences,
    DateTime? dateDemande,
  }) {
    return Utilisateur(
      id: id,
      prenom: prenom ?? this.prenom,
      nom: nom ?? this.nom,
      email: email,
      telephone: telephone ?? this.telephone,
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
    );
  }
}
