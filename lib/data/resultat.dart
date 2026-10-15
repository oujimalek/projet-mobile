/// La réponse d'une opération qui peut échouer (réseau, mauvais mot de
/// passe, droits refusés...).
///
/// Au lieu de lever une exception que chaque écran devrait attraper avec
/// try/catch, le repository renvoie TOUJOURS un Resultat :
/// - succès : `donnee` contient la valeur demandée ;
/// - erreur : `erreur` contient un message en français, prêt à afficher.
///
/// Exemple dans un écran :
/// ```dart
/// final Resultat<Utilisateur> resultat =
///     await UtilisateurRepository().connexion(email, motDePasse);
/// if (!resultat.estSucces) {
///   setState(() {
///     _message = resultat.erreur!;
///   });
///   return;
/// }
/// final Utilisateur utilisateur = resultat.donnee!;
/// ```
///
/// Pour une opération qui ne renvoie rien (ex : enregistrer le profil),
/// on écrit `Resultat<void>` et le succès est `Resultat.succes(null)`.
class Resultat<T> {
  final T? donnee;
  final String? erreur;

  /// L'opération a réussi.
  const Resultat.succes(this.donnee) : erreur = null;

  /// L'opération a échoué : message à afficher à l'utilisateur.
  const Resultat.echec(String message)
      : donnee = null,
        erreur = message;

  bool get estSucces => erreur == null;
}
