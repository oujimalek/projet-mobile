# Tests des règles Firestore

Ces tests vérifient `firestore.rules` sur l'**émulateur** Firestore, avec le projet fictif `demo-houmani`. Ils ne touchent jamais au vrai projet Firebase.

## Prérequis (une seule fois)

- Node.js 18 ou plus récent, et `firebase-tools` (`npm install -g firebase-tools`).
- Java 21 ou plus récent, exigé par l'émulateur. Si `java -version` affiche une version plus ancienne, pointe `JAVA_HOME` vers un JDK 21+ dans le terminal. Le JDK fourni avec Android Studio (`jbr`) convient.
- Dans ce dossier, lance `npm install`.

## Lancer

Depuis la **racine** du dépôt :

```
firebase emulators:exec --only firestore --project demo-houmani "npm --prefix test_regles test"
```

Les lignes `PERMISSION_DENIED` affichées pendant les tests sont normales : ce sont les refus que les tests `assertFails` attendent. Seul le résumé final compte (`fail 0`).

## Ajouter les tests de son module

Crée un fichier `regles_mX.test.js` sur le modèle de `regles_m1.test.js` :

- prépare les données avec `withSecurityRulesDisabled` ;
- utilise `assertSucceeds` pour ce qui doit passer ;
- utilise `assertFails` pour ce qui doit être refusé.
