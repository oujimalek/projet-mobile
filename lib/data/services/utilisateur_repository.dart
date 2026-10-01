import '../models/utilisateur.dart';

/// M1 - Accès aux données des utilisateurs.
///
/// Pour l'instant les données sont écrites en dur.
/// Plus tard, seul l'intérieur de ces méthodes changera (appel à une API) :
/// les écrans, eux, ne changeront pas.
class UtilisateurRepository {
  // Compte de démonstration (données fictives, pour tester l'écran de connexion)
  static const String emailDemo = 'demo@houmani.tn';
  static const String motDePasseDemo = 'houmani123';

  static const Utilisateur _utilisateurDemo = Utilisateur(
    id: 'u1',
    prenom: 'Amira',
    nom: 'Ben Salah',
    email: emailDemo,
    telephone: '+216 22 345 678',
    quartier: 'Cité Ennasr 2',
    residence: 'Résidence Yasmine, Bloc B',
  );

  /// Vérifie l'identifiant (e-mail OU téléphone) et le mot de passe.
  /// Renvoie l'utilisateur si c'est correct, sinon null.
  Utilisateur? connexion(String identifiant, String motDePasse) {
    if (motDePasse != motDePasseDemo) {
      return null;
    }

    // Connexion par e-mail
    if (identifiant.trim() == _utilisateurDemo.email) {
      return _utilisateurDemo;
    }

    // Connexion par téléphone : on compare uniquement les chiffres,
    // donc "+216 22 345 678", "22345678" et "22 345 678" sont acceptés
    final String chiffresSaisis = _garderChiffres(identifiant);
    final String chiffresCompte = _garderChiffres(_utilisateurDemo.telephone);
    if (chiffresSaisis.length >= 8 && chiffresCompte.endsWith(chiffresSaisis)) {
      return _utilisateurDemo;
    }
    return null;
  }

  /// Garde seulement les chiffres d'un texte ("+216 22" donne "21622").
  String _garderChiffres(String texte) {
    String chiffres = '';
    for (int i = 0; i < texte.length; i++) {
      if ('0123456789'.contains(texte[i])) {
        chiffres = chiffres + texte[i];
      }
    }
    return chiffres;
  }

  /// L'utilisateur actuellement connecté (fictif pour l'instant).
  Utilisateur getUtilisateurConnecte() {
    return _utilisateurDemo;
  }

  /// La liste des voisins de la résidence.
  List<Utilisateur> getVoisins() {
    return const [
      _utilisateurDemo,
      Utilisateur(
        id: 'u2',
        prenom: 'Youssef',
        nom: 'Trabelsi',
        email: 'youssef@houmani.tn',
        telephone: '+216 22 111 111',
        quartier: 'Cité Ennasr 2',
        residence: 'Résidence Yasmine, Bloc A',
      ),
      Utilisateur(
        id: 'u3',
        prenom: 'Salma',
        nom: 'Gharbi',
        email: 'salma@houmani.tn',
        telephone: '+216 55 222 222',
        quartier: 'Cité Ennasr 2',
        residence: 'Résidence Yasmine, Bloc C',
      ),
    ];
  }
}
