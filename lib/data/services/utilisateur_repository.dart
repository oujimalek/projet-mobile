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
    telephone: '+216 20 000 000',
    quartier: 'Cité Ennasr 2',
    residence: 'Résidence Yasmine, Bloc B',
  );

  /// Vérifie l'email et le mot de passe.
  /// Renvoie l'utilisateur si c'est correct, sinon null.
  Utilisateur? connexion(String email, String motDePasse) {
    if (email.trim() == emailDemo && motDePasse == motDePasseDemo) {
      return _utilisateurDemo;
    }
    return null;
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
