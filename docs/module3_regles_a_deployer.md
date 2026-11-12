# M3 · Signalements : règles et index à déployer

Liste tenue à jour par le module 3. **Rien n'est encore appliqué** dans
`firestore.rules` ni `firestore.indexes.json` : tout sera relu avec le
responsable du module 1, fusionné avec les changements du module 4, puis
déployé **en une seule fois** (`firebase deploy --only firestore`).

Légende : ✅ nécessaire dès maintenant (le code l'utilise déjà) ·
🕓 étape suivante (le code n'existe pas encore) · 💡 conseillé (sécurité).

## Récapitulatif

| # | Changement | Fichier | Pourquoi | Étape |
|---|---|---|---|---|
| 1 | Index `auteurId ↑, date ↓` | `firestore.indexes.json` | Onglet « Mes signalements » | ✅ 2 |
| 2 | Champ `danger` (bool) | `firestore.rules` | Case « Danger pour les personnes » (création + modification) | ✅ 2 |
| 3 | Pas de confirmation sur un signalement clôturé | `firestore.rules` | Le serveur vérifie ce que l'app refuse déjà | 💡 2 |
| 4 | Création : liste blanche des champs + types | `firestore.rules` | Aujourd'hui n'importe quel champ passe | 💡 2 |
| 5 | Champ `position` (GeoPoint, optionnel) | `firestore.rules` | « Utiliser ma position », carte, anti-doublon | ✅ 5 |
| 6 | Champ `photoUrl` (texte) | `firestore.rules` | Photo Cloudinary | 🕓 6 |
| 7 | Sous-collection `historique` + note admin | `firestore.rules` | Historique des statuts | 🕓 8 |
| 8 | Champ `photoApresUrl` (admin, à la résolution) | `firestore.rules` | Photo avant / après | 🕓 8 |

Pas de changement de règle pour `confirmer()` : l'app écrit
`nbConfirmations: FieldValue.increment(1)`. Firestore évalue les règles sur
le document APRÈS l'incrément, donc
`request.resource.data.nbConfirmations == resource.data.nbConfirmations + 1`
reste vrai (et deux confirmations simultanées ne s'annulent plus).

---

## 1. Index « Mes signalements » ✅

`getMesSignalements()` : `where('auteurId', isEqualTo: uid)` +
`orderBy('date', descending: true)`. Sans cet index, Firestore répond
`failed-precondition` (« Requête impossible pour le moment (index manquant ?) »).

À ajouter dans le tableau `indexes` de `firestore.indexes.json` :

```json
{
  "collectionGroup": "signalements",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "auteurId", "order": "ASCENDING" },
    { "fieldPath": "date", "order": "DESCENDING" }
  ]
}
```

## 2. Champ `danger` ✅

- Création : déjà accepté (la règle ne liste pas les champs), mais on vérifie le type.
- Modification par l'auteur : `danger` doit entrer dans `changeSeulement`,
  sinon cocher / décocher la case est refusé (« Action non autorisée »).

```
allow create: if membreDe(q)
  && request.resource.data.auteurId == monUid()
  && request.resource.data.statut == 'enAttente'
  && request.resource.data.nbConfirmations == 0
  && request.resource.data.get('danger', false) is bool;

// L'auteur corrige son signalement tant qu'il est en attente.
allow update: if membreDe(q)
  && resource.data.auteurId == monUid()
  && resource.data.statut == 'enAttente'
  && changeSeulement(['titre', 'description', 'categorieId', 'lieu', 'danger'])
  && request.resource.data.get('danger', false) is bool;
```

`docs/schema_firestore.md`, section 5, ajouter la ligne :

| Champ Dart | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `danger` | `danger` | bool | « Danger pour les personnes », compte dans le score d'urgence (calculé dans l'app, pas stocké) |

## 3. Pas de confirmation sur un signalement clôturé 💡

L'app refuse déjà (« Ce signalement est déjà clôturé ») quand le statut est
`resolu` ou `refuse`. Côté serveur, dans `match /confirmations/{uidConfirmation}` :

```
allow create: if membreDe(q)
  && uidConfirmation == monUid()
  && get(chemin()).data.auteurId != monUid()
  && get(chemin()).data.statut in ['enAttente', 'enCours']
  && getAfter(chemin()).data.nbConfirmations
     == get(chemin()).data.nbConfirmations + 1;
```

## 4. Création : liste blanche des champs 💡

Aujourd'hui la règle de création ne limite ni les champs ni leurs types.
Proposition (à compléter avec `position` et `photoUrl` aux étapes 5 et 6) :

```
allow create: if membreDe(q)
  && request.resource.data.keys().hasOnly(['titre', 'description',
       'categorieId', 'statut', 'date', 'lieu', 'auteurId', 'auteurNom',
       'nbConfirmations', 'danger'])
  && request.resource.data.auteurId == monUid()
  && request.resource.data.statut == 'enAttente'
  && request.resource.data.nbConfirmations == 0
  && request.resource.data.categorieId in
       ['electricite', 'eau', 'ordures', 'travaux', 'incident']
  && request.resource.data.titre is string
  && request.resource.data.titre.size() >= 3
  && request.resource.data.titre.size() <= 80
  && request.resource.data.date is timestamp
  && request.resource.data.get('danger', false) is bool;
```

Mêmes limites que `SignalementRepository.refusSignalement` dans l'app.
Depuis l'étape 5 : ajouter `'position'` à la liste `hasOnly([...])`.

## 5. Champ `position` (GeoPoint, optionnel) ✅

Rempli par « Utiliser ma position » (`Localisation.positionActuelle()` du
module 1). L'app ne l'écrit **que s'il existe** (jamais `position: null`).
`lieu` reste le texte lisible (adresse Nominatim ou saisie).

- Création : déjà acceptée aujourd'hui (pas de liste blanche), mais on
  vérifie le type si le champ est là.
- Modification par l'auteur : `position` doit entrer dans `changeSeulement`,
  sinon ajouter ou déplacer le point est refusé.

```
allow create: if membreDe(q)
  && request.resource.data.auteurId == monUid()
  && request.resource.data.statut == 'enAttente'
  && request.resource.data.nbConfirmations == 0
  && request.resource.data.get('danger', false) is bool
  && (!('position' in request.resource.data)
      || request.resource.data.position is latlng);

allow update: if membreDe(q)
  && resource.data.auteurId == monUid()
  && resource.data.statut == 'enAttente'
  && changeSeulement(['titre', 'description', 'categorieId', 'lieu',
       'danger', 'position'])
  && request.resource.data.get('danger', false) is bool
  && (!('position' in request.resource.data)
      || request.resource.data.position is latlng);
```

Avec la liste blanche (section 4), ajouter `'position'` à `hasOnly([...])`.

`docs/schema_firestore.md`, section 5, ajouter la ligne :

| Champ Dart | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `position` (`PointGps?`) | `position` | geopoint | Optionnel ; absent si l'utilisateur n'a pas utilisé le GPS |

Limite : retirer le point d'un signalement déjà publié n'efface pas le
champ dans Firestore (il faudrait `FieldValue.delete()`, que la règle
devrait aussi accepter). Pas prévu pour l'instant.

## 6. Champ `photoUrl` 🕓 étape 6

URL Cloudinary de la photo. À ajouter :
- liste blanche de création + `changeSeulement` de l'auteur ;
- type : `request.resource.data.get('photoUrl', '') is string`.

## 7. Historique des statuts + note admin 🕓 étape 8

À écrire avec l'étape 8. Idée : `signalements/{id}/historique/{entreeId}` =
`{statut, note, parId, parNom, date}`. Lecture : membre ; création : admin
seulement (dans le même WriteBatch que le changement de statut) ; jamais
modifiée ni supprimée.

## 8. Photo « après » à la résolution 🕓 étape 8

L'admin ajoute `photoApresUrl` en passant à `resolu`. La règle admin
deviendrait `changeSeulement(['statut', 'photoApresUrl'])`.

---

## Points à connaître (sans changement prévu)

- **Fiches orphelines** : supprimer un signalement laisse ses documents
  `confirmations/*` (Firestore ne supprime pas les sous-collections, et la
  règle interdit de les effacer). Invisibles pour l'app, sans danger.
- **Date du client** : `date` vient du téléphone (`DateTime.now()`). Pour
  l'imposer côté serveur il faudrait `FieldValue.serverTimestamp()` et
  `request.resource.data.date == request.time`.
