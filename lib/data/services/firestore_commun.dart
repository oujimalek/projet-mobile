import 'package:cloud_firestore/cloud_firestore.dart';

import '../resultat.dart';

/// Outils Firestore partagés par les 4 modules (voir
/// docs/guide_modules_firebase.md).
///
/// Chaque module garde SON repository (contrat abstrait + version
/// Firebase + mock dans test/). Cette classe évite seulement de recopier
/// partout les mêmes petits bouts de code :
/// - le chemin quartiers/{quartierId}/{collection} ;
/// - try/catch FirebaseException → Resultat en échec, message en français ;
/// - la lecture d'une date (Timestamp) ou d'un enum (texte) dans un document.
///
/// Que des méthodes static : on n'a pas besoin de créer d'objet.
class FirestoreCommun {
  FirestoreCommun._(); // pas d'instance

  /// Getter : Firebase n'est appelé qu'au premier usage (les tests qui
  /// n'utilisent pas Firestore ne plantent pas).
  static FirebaseFirestore get base => FirebaseFirestore.instance;

  /// Une collection rangée sous un quartier, ex :
  /// `collectionDuQuartier(quartierId, 'signalements')`
  /// → quartiers/{quartierId}/signalements.
  ///
  /// Tout est rangé par quartier : un voisin ne voit que sa houma
  /// (firestore.rules vérifie qu'il en est membre actif).
  static CollectionReference<Map<String, dynamic>> collectionDuQuartier(
    String quartierId,
    String collection,
  ) {
    return base
        .collection('quartiers')
        .doc(quartierId)
        .collection(collection);
  }

  /// Lance une action Firestore et range la réponse dans un Resultat :
  /// - tout va bien : Resultat.succes(valeur) ;
  /// - FirebaseException : Resultat.echec(message en français).
  ///
  /// Exemple :
  /// ```dart
  /// return FirestoreCommun.executer(() async {
  ///   final snapshot = await collection.get();
  ///   return snapshot.docs.map(...).toList();
  /// });
  /// ```
  static Future<Resultat<T>> executer<T>(Future<T> Function() action) async {
    try {
      final T valeur = await action();
      return Resultat.succes(valeur);
    } on FirebaseException catch (e) {
      return Resultat.echec(messageErreur(e.code));
    }
  }

  /// Traduit les codes d'erreur de Firestore en messages pour l'écran.
  static String messageErreur(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Action non autorisée';
      case 'unavailable':
        return 'Serveur injoignable, vérifie ta connexion Internet';
      case 'not-found':
        return 'Donnée introuvable';
      case 'failed-precondition':
        // Le plus souvent : un index composite manque (firestore.indexes.json)
        return 'Requête impossible pour le moment (index manquant ?)';
      case 'deadline-exceeded':
        return 'Le serveur met trop de temps à répondre, réessaie';
      default:
        return 'Une erreur est survenue ($code)';
    }
  }

  /// Lit une date dans un document. Firestore renvoie un Timestamp ;
  /// champ absent ou d'un autre type : null (pas de plantage).
  static DateTime? lireDate(Object? valeur) {
    if (valeur is Timestamp) {
      return valeur.toDate();
    }
    return null;
  }

  /// Lit un enum rangé sous forme de texte (`statut.name`, ex "enCours").
  /// Texte inconnu ou absent : [parDefaut].
  ///
  /// Exemple : `FirestoreCommun.lireEnum(StatutSignalement.values,
  /// map['statut'], StatutSignalement.enAttente)`
  static T lireEnum<T extends Enum>(
    List<T> valeurs,
    Object? texte,
    T parDefaut,
  ) {
    for (final T valeur in valeurs) {
      if (valeur.name == texte) {
        return valeur;
      }
    }
    return parDefaut;
  }
}
