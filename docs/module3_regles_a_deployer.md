# M3 · Signalements : règles et index à déployer

**État : prêts dans la branche, PAS encore déployés.** Le bloc M3 de
`firestore.rules` et l'index de `firestore.indexes.json` sont écrits et
testés sur l'émulateur (`test_regles/regles_m3.test.js`). Les règles des
autres modules (M1, M2, M4) n'ont pas été modifiées.

## 1. Ce qui change

| # | Changement | Fichier | Pourquoi |
|---|---|---|---|
| 1 | Index `signalements` : `auteurId ↑, date ↓` | `firestore.indexes.json` | Onglet « Mes signalements » (sinon `failed-precondition`) |
| 2 | Création : liste blanche des champs + types | `firestore.rules` | Avant : n'importe quel champ passait |
| 3 | Contenu valide (création ET correction) | `firestore.rules` | Catégorie connue, titre 3 à 80 caractères, description ≥ 10, lieu ≥ 2 (comme l'app) |
| 4 | Champ `danger` (bool) | `firestore.rules` | Case « Danger pour les personnes » |
| 5 | Champ `position` (point GPS, optionnel) | `firestore.rules` | « Utiliser ma position », « Voir sur la carte » |
| 6 | Champ `photoUrl` (optionnel, préfixe `https://res.cloudinary.com/pu3lxdrf/`) | `firestore.rules` | Photo du signalement, seulement de NOTRE compte Cloudinary |
| 7 | L'auteur corrige aussi `danger`, `position`, `photoUrl` (et peut les retirer avec `FieldValue.delete()`) | `firestore.rules` | Écran de modification |
| 8 | Pas de confirmation sur un signalement résolu ou refusé | `firestore.rules` | Le serveur vérifie ce que l'app refuse déjà |
| 9 | Sous-collection `historique` (étapes des statuts + note de l'admin) | `firestore.rules` | Frise de l'historique dans le détail |

⚠️ **À déployer AVANT (ou avec) la version de l'app qui a l'historique** :
l'app écrit la 1re étape dans le même lot que la création. Avec les
anciennes règles (sans `historique`), ce lot est refusé et **plus aucun
signalement ne peut être créé**.

### L'historique (n° 9)

`quartiers/{q}/signalements/{id}/historique/{id automatique}` =
`{ statut, note, date, parId, parNom }`.

- **Lire** : membre actif du quartier.
- **Créer**, seulement dans le même `WriteBatch` que :
  - la **création** du signalement : 1re étape `enAttente`, par l'auteur
    (`!exists(signalement)` et `getAfter(signalement).auteurId == moi`) ;
  - un **changement de statut par l'admin** : le statut change vraiment
    (`get(...).statut != étape.statut`) et l'étape recopie le nouveau
    (`getAfter(...).statut == étape.statut`) ; pour `refuse`, une note de
    3 caractères au moins.
- Toujours : champs connus seulement, `parId == moi`, note de 200
  caractères au plus.
- **Jamais** modifiée ni supprimée.

`docs/schema_firestore.md`, section 5, ajouter :

| Champ | Type | Remarque |
|---|---|---|
| `statut` | string | Le statut à cette étape |
| `note` | string | `''` si pas de note ; obligatoire (3 à 200) pour `refuse` |
| `date` | timestamp | |
| `parId`, `parNom` | string | L'auteur (1re étape) ou l'admin |

**Inchangé :** lecture (membre actif), changement de statut par l'admin,
compteur « moi aussi » (`FieldValue.increment(1)` respecte déjà
`nbConfirmations == ancien + 1`), suppression (auteur en attente, ou admin).

`docs/schema_firestore.md`, section 5, ajouter les lignes :

| Champ Dart | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `danger` | `danger` | bool | « Danger pour les personnes », compte dans le score d'urgence (calculé dans l'app, pas stocké) |
| `position` (`PointGps?`) | `position` | geopoint | Optionnel ; absent si l'utilisateur n'a pas utilisé le GPS |
| `photoUrl` | `photoUrl` | string | Optionnel ; `https://res.cloudinary.com/pu3lxdrf/...` |

## 2. Tester avant de déployer (émulateur)

Depuis la racine du dépôt (voir `test_regles/README.md`) :

```
firebase emulators:exec --only firestore --project demo-houmani "npm --prefix test_regles test"
```

Résultat attendu : `fail 0` (M1 + M3 + M4 ; dernier passage : 133 tests,
dont 38 pour M3). Les lignes `PERMISSION_DENIED` sont les refus attendus.

## 3. Déployer (une seule fois, après validation de l'équipe)

```
firebase deploy --only firestore:rules,firestore:indexes
```

### Check-list

1. **Comparer avec les règles en ligne** : console Firebase → Firestore
   Database → Règles. Si elles contiennent des changements absents du
   dépôt (fait à la main dans la console), les reporter d'abord dans
   `firestore.rules`, sinon le déploiement les écrase.
2. Être sur la branche qui contient les règles de **tous** les modules
   (M1, M2, M3, M4) : un déploiement remplace le fichier entier.
3. Lancer les tests de l'émulateur (section 2) : `fail 0`.
4. Déployer avec la commande ci-dessus.
5. Si la commande propose de **supprimer des index** qui existent en ligne
   mais pas dans `firestore.indexes.json` : répondre **N** (non). Ils
   servent peut-être à un autre module ; on les ajoutera au fichier.
6. Attendre que le nouvel index soit **« Activé »** (console → Firestore →
   Index ; quelques minutes) avant de tester « Mes signalements ».
7. Vérifier dans l'app : créer un signalement avec photo et position,
   le corriger, le confirmer depuis un autre compte, changer son statut
   avec le compte admin.

## 4. Points à connaître (sans changement prévu)

- **Fiches orphelines** : supprimer un signalement laisse ses documents
  `confirmations/*` et `historique/*` (Firestore ne supprime pas les
  sous-collections, et les règles interdisent de les effacer). Invisibles
  pour l'app, sans danger.
- **Date du client** : `date` vient du téléphone (`DateTime.now()`). Pour
  l'imposer côté serveur il faudrait `FieldValue.serverTimestamp()` et
  `request.resource.data.date == request.time`.
- **Photos sur Cloudinary** : supprimer un signalement ne supprime pas sa
  photo sur Cloudinary (il faudrait la clé secrète, qui ne doit jamais être
  dans l'app). Voir `docs/module3_photos.md`.
- **Anciens signalements** : un document créé avant ces règles et qui ne
  les respecte pas (ex. titre de 2 caractères) ne pourra plus être corrigé
  par son auteur tant qu'il n'est pas valide ; l'admin peut toujours
  changer son statut ou le supprimer.
