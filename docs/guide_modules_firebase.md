# Guide : brancher son module sur Firebase

Pour les modules 2 (Services), 3 (Signalements) et 4 (Événements).
Le module 1 (Utilisateurs) suit déjà ce modèle : prenez-le comme exemple.

Avant de commencer, lisez `docs/schema_firestore.md` : il donne vos
collections, vos champs et les règles de sécurité.

---

## 1. Les 4 pièces d'un module

| Fichier | Rôle | Exemple M1 |
|---|---|---|
| `lib/data/services/x_repository.dart` | Le **contrat** : `abstract class` avec des `Future` | `utilisateur_repository.dart` |
| `lib/data/services/firebase_x_repository.dart` | La version **Firebase** (celle de l'app) | `firebase_utilisateur_repository.dart` |
| `test/mock_x_repository.dart` | Des **données fictives** pour les tests | `test/mock_utilisateur_repository.dart` |
| `lib/data/models/x.dart` | Le modèle, avec `toMap()` et `fromMap(id, map)` | `models/utilisateur.dart` |

Les écrans n'appellent que le contrat : ils ne savent pas si les données
viennent de Firebase ou du mock.

## 2. Le contrat (classe abstraite)

```dart
abstract class SignalementRepository {
  /// L'implémentation utilisée par toute l'application.
  static SignalementRepository instance = FirebaseSignalementRepository();

  /// Les écrans écrivent toujours `SignalementRepository()` : on renvoie
  /// l'instance ci-dessus (pas de nouvel objet).
  factory SignalementRepository() {
    return instance;
  }

  Future<Resultat<List<Signalement>>> getSignalements();
  Future<Resultat<void>> ajouterSignalement(Signalement signalement);
}
```

Les tests remplacent l'instance dans `setUp` :

```dart
setUp(() {
  SignalementRepository.instance = MockSignalementRepository();
});
```

## 3. `Resultat<T>` : succès ou erreur

Tout appel réseau peut échouer (pas d'Internet, droits refusés). Au lieu
de lever une exception dans l'écran, le repository renvoie un `Resultat`
(`lib/data/resultat.dart`) :

- `Resultat.succes(donnee)` : `resultat.donnee` contient la valeur ;
- `Resultat.echec('message')` : `resultat.erreur` contient un message en
  français, prêt à afficher.

## 4. La version Firebase, avec `FirestoreCommun`

`lib/data/services/firestore_commun.dart` regroupe ce qui est pareil pour
tous les modules :

| Outil | À quoi il sert |
|---|---|
| `FirestoreCommun.collectionDuQuartier(quartierId, 'signalements')` | Le chemin `quartiers/{q}/signalements` |
| `FirestoreCommun.executer(() async { ... })` | `try/catch` + `Resultat` en une ligne, message d'erreur en français |
| `FirestoreCommun.lireDate(map['date'])` | Timestamp → `DateTime?` |
| `FirestoreCommun.lireEnum(Statut.values, map['statut'], Statut.enAttente)` | Texte → enum, avec une valeur par défaut |

Le quartier de l'utilisateur connecté vient du module 1 :

```dart
final String quartierId =
    UtilisateurRepository().getUtilisateurConnecte().quartierId ?? '';
```

Exemple complet (module 3) :

```dart
class FirebaseSignalementRepository implements SignalementRepository {
  CollectionReference<Map<String, dynamic>> get _signalements {
    final String quartierId =
        UtilisateurRepository().getUtilisateurConnecte().quartierId ?? '';
    return FirestoreCommun.collectionDuQuartier(quartierId, 'signalements');
  }

  @override
  Future<Resultat<List<Signalement>>> getSignalements() {
    return FirestoreCommun.executer(() async {
      final QuerySnapshot<Map<String, dynamic>> resultat =
          await _signalements.orderBy('date', descending: true).get();
      final List<Signalement> liste = [];
      for (final document in resultat.docs) {
        liste.add(Signalement.fromMap(document.id, document.data()));
      }
      return liste;
    });
  }

  @override
  Future<Resultat<void>> ajouterSignalement(Signalement signalement) {
    return FirestoreCommun.executer(() async {
      await _signalements.add(signalement.toMap());
    });
  }
}
```

## 5. Le modèle : `toMap()` et `fromMap(id, map)`

```dart
Map<String, dynamic> toMap() {
  return {
    'titre': titre,
    'statut': statut.name,       // enum → texte, ex "enAttente"
    'date': date,                // DateTime → Timestamp (fait par Firestore)
    'auteurId': auteurId,        // l'uid, pour les règles de sécurité
    'auteurNom': auteur,         // le nom, recopié pour l'affichage
  };
}

factory Signalement.fromMap(String id, Map<String, dynamic> map) {
  return Signalement(
    id: id,                      // l'id est le nom du document
    titre: map['titre'] ?? '',   // champ absent : valeur par défaut
    statut: FirestoreCommun.lireEnum(
      StatutSignalement.values, map['statut'], StatutSignalement.enAttente),
    date: FirestoreCommun.lireDate(map['date']) ?? DateTime.now(),
    ...
  );
}
```

Pas de génération de code (`build_runner`) : tout est écrit à la main.

## 6. Dans l'écran : chargement, succès, erreur

Comme dans le cours : un `StatefulWidget`, un booléen et `setState`.

```dart
bool _enChargement = false;

Future<void> _envoyer() async {
  setState(() {
    _enChargement = true;
  });
  final Resultat<void> resultat =
      await SignalementRepository().ajouterSignalement(nouveau);
  if (!mounted) {
    return; // l'écran a été fermé pendant l'attente
  }
  setState(() {
    _enChargement = false;
  });
  if (!resultat.estSucces) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultat.erreur!)),
    );
    return;
  }
  context.pop();
}

// Dans build : bouton désactivé pendant le chargement
PrimaryButton(
  texte: 'Envoyer',
  onPressed: _enChargement ? null : _envoyer,
),
```

Pour une liste, `FutureBuilder` marche aussi (`ConnectionState.waiting`
→ indicateur de chargement).

## 7. Points à ne pas oublier

- **Compteurs protégés** (`nbConfirmations`, `nbParticipants`) : écrire la
  fiche et le compteur dans le **même `WriteBatch`**, sinon les règles
  refusent (voir le schéma, règle n°4).
- **Index** : une requête qui filtre sur un champ et trie sur un autre a
  besoin d'un index composite. Ceux du schéma sont déjà dans
  `firestore.indexes.json`. S'il en manque un, l'erreur
  `failed-precondition` affiche dans la console un lien qui le crée ;
  ajoutez-le aussi dans `firestore.indexes.json`.
- **M2, demandes** : on ne peut lire que ses propres demandes, donc la
  requête doit filtrer `where('demandeurId', isEqualTo: monUid)` ou
  `where('auteurServiceId', isEqualTo: monUid)`.
- Ne modifiez pas `firestore.rules` seul : demandez au responsable du
  module 1 (les règles protègent les 4 modules).

## 8. Avoir un compte de test

L'application utilise maintenant le vrai Firebase : il faut un compte
**validé**. Le compte de démo `demo@houmani.tn` n'existe plus.

1. Récupérez `android/app/google-services.json` et
   `lib/firebase_options.dart` auprès du responsable du module 1 (ils ne
   sont pas sur GitHub).
2. Dans l'application : **S'inscrire**, cliquer sur le lien reçu par
   e-mail, puis entrer le code du quartier (ex. `YAS72B`).
3. Demandez à un admin de vous **accepter** dans « Membres du quartier »
   (ou, dans la console Firebase → Firestore → `utilisateurs` → votre
   document : `statut` = `actif`).
4. Pour tester les écrans admin : `role` = `admin` dans la console.
5. Relancez l'application ou appuyez sur « Vérifier ma demande ».

## 9. Les tests

- `flutter test` ne touche jamais Firebase : les tests utilisent le mock.
- Avant chaque commit : `flutter analyze` puis `flutter test`.
