# M3 · Signalements : règles et index à déployer

Liste tenue à jour par le module 3. **Rien n'est encore appliqué** dans
`firestore.rules` ni `firestore.indexes.json` : tout sera relu avec le
responsable du module 1, fusionné avec les changements du module 4, puis
déployé **en une seule fois** (`firebase deploy --only firestore`).

Légende : ✅ nécessaire (le code l'utilise déjà) · 💡 conseillé (sécurité).

## Récapitulatif

| # | Changement | Fichier | Pourquoi | Étape |
|---|---|---|---|---|
| 1 | Index `auteurId ↑, date ↓` | `firestore.indexes.json` | Onglet « Mes signalements » | ✅ 2 |
| 2 | Champ `danger` (bool) | `firestore.rules` | Case « Danger pour les personnes » (création + modification) | ✅ 2 |
| 3 | Pas de confirmation sur un signalement clôturé | `firestore.rules` | Le serveur vérifie ce que l'app refuse déjà | 💡 2 |
| 4 | Création : liste blanche des champs + types | `firestore.rules` | Aujourd'hui n'importe quel champ passe | 💡 2 |
| 5 | Champ `position` (GeoPoint, optionnel) | `firestore.rules` | « Utiliser ma position », « Voir sur la carte » | ✅ 5 |
| 6 | Champ `photoUrl` (Cloudinary, optionnel) | `firestore.rules` | Photo du signalement | ✅ 6 |

Le **bloc M3 complet** qui regroupe 2 à 6 est à la fin (section 7) : c'est
lui qu'il faut coller dans `firestore.rules`.

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

- Création : accepté aujourd'hui (la règle ne liste pas les champs) ; on
  vérifie son type.
- Modification par l'auteur : `danger` doit entrer dans `changeSeulement`,
  sinon cocher / décocher la case est refusé (« Action non autorisée »).

## 3. Pas de confirmation sur un signalement clôturé 💡

L'app refuse déjà (« Ce signalement est déjà clôturé ») quand le statut est
`resolu` ou `refuse`. Le serveur vérifie la même chose dans
`match /confirmations/{uidConfirmation}` (voir section 7).

## 4. Création : liste blanche des champs 💡

Aujourd'hui la règle de création ne limite ni les champs ni leurs types.
La section 7 n'accepte que les champs connus, une catégorie existante, un
titre de 3 à 80 caractères et une date : les mêmes limites que
`SignalementRepository.refusSignalement` dans l'app.

## 5. Champ `position` (GeoPoint, optionnel) ✅

Rempli par « Utiliser ma position » (`Localisation.positionActuelle()` du
module 1). L'app ne l'écrit **que s'il existe** (jamais `position: null`) ;
`lieu` reste le texte lisible (adresse Nominatim ou saisie).

- Création et modification : si le champ est là, il doit être un `latlng`.
- Modification : `position` entre dans `changeSeulement`. Retirer le point
  d'un signalement publié envoie `FieldValue.delete()` : la clé est alors
  « changée » (donc dans la liste) et absente après (donc acceptée).

## 6. Champ `photoUrl` (Cloudinary, optionnel) ✅

Adresse https de la photo, envoyée par l'app sur le compte Cloudinary de
l'équipe (preset `houmani_signalements`, voir `docs/module3_photos.md`).

- Si le champ est là : un texte qui **commence par
  `https://res.cloudinary.com/pu3lxdrf/`** (notre compte). Sans cette
  vérification, n'importe qui pourrait afficher une image d'un autre site
  dans l'application.
- L'app vérifie la même chose avant d'écrire
  (`SignalementRepository.refusPhoto`).
- Modification : `photoUrl` entre dans `changeSeulement` (changer ou
  retirer la photo, comme `position`).

En règles Firestore, `matches()` doit correspondre au texte ENTIER ; le
point s'écrit `[.]` :

```
d.photoUrl.matches('https://res[.]cloudinary[.]com/pu3lxdrf/.+')
```

`docs/schema_firestore.md`, section 5, ajouter les lignes :

| Champ Dart | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `danger` | `danger` | bool | « Danger pour les personnes », compte dans le score d'urgence (calculé dans l'app, pas stocké) |
| `position` (`PointGps?`) | `position` | geopoint | Optionnel ; absent si l'utilisateur n'a pas utilisé le GPS |
| `photoUrl` | `photoUrl` | string | Optionnel ; `https://res.cloudinary.com/pu3lxdrf/...` |

---

## 7. Le bloc M3 complet proposé (à coller dans `firestore.rules`)

Remplace le bloc `// ---------- M3 · Signalements ----------` actuel.
Les règles « admin change le statut », « compteur moi aussi » et
« supprimer » sont **inchangées**.

```
      // ---------- M3 · Signalements ----------
      match /signalements/{signalementId} {
        function chemin() {
          return /databases/$(database)/documents/quartiers/$(q)/signalements/$(signalementId);
        }
        function maConfirmation() {
          return /databases/$(database)/documents/quartiers/$(q)/signalements/$(signalementId)/confirmations/$(monUid());
        }

        // Le contenu écrit par l'auteur : catégorie connue, titre de 3 à
        // 80 caractères, et les champs optionnels du bon type :
        // danger (bool), position (point GPS), photoUrl (NOTRE Cloudinary).
        function contenuValide() {
          let d = request.resource.data;
          return d.categorieId in ['electricite', 'eau', 'ordures', 'travaux', 'incident']
            && d.titre is string
            && d.titre.size() >= 3
            && d.titre.size() <= 80
            && d.get('danger', false) is bool
            && (!('position' in d) || d.position is latlng)
            && (!('photoUrl' in d)
                || (d.photoUrl is string
                    && d.photoUrl.matches('https://res[.]cloudinary[.]com/pu3lxdrf/.+')));
        }

        allow read: if membreDe(q);

        allow create: if membreDe(q)
          && request.resource.data.keys().hasOnly(['titre', 'description',
               'categorieId', 'statut', 'date', 'lieu', 'auteurId', 'auteurNom',
               'nbConfirmations', 'danger', 'position', 'photoUrl'])
          && request.resource.data.auteurId == monUid()
          && request.resource.data.statut == 'enAttente'
          && request.resource.data.nbConfirmations == 0
          && request.resource.data.date is timestamp
          && contenuValide();

        // L'auteur corrige son signalement tant qu'il est en attente.
        allow update: if membreDe(q)
          && resource.data.auteurId == monUid()
          && resource.data.statut == 'enAttente'
          && changeSeulement(['titre', 'description', 'categorieId', 'lieu',
               'danger', 'position', 'photoUrl'])
          && contenuValide();

        // L'admin change le statut. (inchangé)
        allow update: if adminDe(q)
          && changeSeulement(['statut'])
          && request.resource.data.statut in ['enAttente', 'enCours', 'resolu', 'refuse'];

        // Compteur "moi aussi" (inchangé)
        allow update: if membreDe(q)
          && changeSeulement(['nbConfirmations'])
          && request.resource.data.nbConfirmations == resource.data.nbConfirmations + 1
          && !exists(maConfirmation())
          && existsAfter(maConfirmation());

        allow delete: if (membreDe(q) && resource.data.auteurId == monUid()
                          && resource.data.statut == 'enAttente')
          || adminDe(q);

        // ----- Confirmations (id du document = uid) -----
        match /confirmations/{uidConfirmation} {
          allow read: if membreDe(q);
          allow create: if membreDe(q)
            && uidConfirmation == monUid()
            && get(chemin()).data.auteurId != monUid()
            && get(chemin()).data.statut in ['enAttente', 'enCours']
            && getAfter(chemin()).data.nbConfirmations
               == get(chemin()).data.nbConfirmations + 1;
          allow update, delete: if false;
        }
      }
```

À tester sur l'émulateur (`test_regles/`) avant le déploiement, au moins :
création avec / sans photo, photo d'un autre site refusée, position qui
n'est pas un point refusée, champ inconnu refusé, l'auteur retire sa photo
(`FieldValue.delete()`), confirmation d'un signalement résolu refusée.

---

## Points à connaître (sans changement prévu)

- **Fiches orphelines** : supprimer un signalement laisse ses documents
  `confirmations/*` (Firestore ne supprime pas les sous-collections, et la
  règle interdit de les effacer). Invisibles pour l'app, sans danger.
- **Date du client** : `date` vient du téléphone (`DateTime.now()`). Pour
  l'imposer côté serveur il faudrait `FieldValue.serverTimestamp()` et
  `request.resource.data.date == request.time`.
- **Photos sur Cloudinary** : supprimer un signalement ne supprime pas sa
  photo sur Cloudinary (il faudrait la clé secrète, qui ne doit jamais être
  dans l'app). Voir `docs/module3_photos.md`.
