# M3 · Signalements : la base locale SQFlite

Ce document explique **pourquoi** et **comment** le module 3 utilise une base
SQLite sur le téléphone (package `sqflite`), en plus de Cloud Firestore.

## 1. Pourquoi SQFlite, alors que Firestore a déjà un cache hors ligne ?

Firestore garde bien une copie des documents lus et met en attente les
écritures faites hors ligne. Mais ce cache est **une boîte noire** : on ne
peut ni le lister, ni le filtrer en SQL, ni y ranger ce qui n'est pas un
document Firestore. Le module 3 a besoin de quatre choses qu'il ne fait pas :

| Besoin | Cache de Firestore | Notre base SQLite |
|---|---|---|
| **Brouillon** d'un formulaire pas encore envoyé | ❌ Ce n'est pas un document Firestore | ✅ Table `brouillons`, privée, sur le téléphone |
| **File d'envoi visible** (« En attente d'envoi », Réessayer, Annuler, nombre d'essais, dernière erreur) | ❌ Écritures en attente cachées ; `await add()` ne se termine **jamais** hors ligne | ✅ Table `envois_en_attente` affichée dans la liste |
| **Photo locale** à envoyer plus tard (étape 6) | ❌ Un fichier ne va pas dans Firestore | ✅ Colonne `photo_locale` (chemin du fichier) |
| **Requêtes locales** : filtrer par statut, catégorie, auteur, trier | ⚠️ Possible seulement avec les requêtes et les index Firestore | ✅ `WHERE` / `ORDER BY` en SQL, index SQLite |

En plus, on **maîtrise** ce qui est gardé et quand : la liste hors ligne
affiche « Hors ligne — dernière mise à jour à HH:mm ».

## 2. Qui fait quoi

```
Écrans du module 3
   │
   ▼
SyncSignalementsM3            le « chef d'orchestre » : en ligne ou pas ?
   ├── ConnexionM3            réseau présent ? (connectivity_plus)
   ├── SignalementRepository  Cloud Firestore (en ligne)
   └── BaseLocaleM3           SQLite (brouillons, file, cache)
```

| Fichier | Rôle |
|---|---|
| `lib/data/services/base_locale_m3.dart` | Les tables et les requêtes SQL (`openDatabase`, `onCreate`, `insert`, `query`, `update`, `delete`, `rawQuery`, `rawUpdate`, `transaction`, `batch`) |
| `lib/data/services/sync_signalements_m3.dart` | Décide entre Firestore et SQLite ; envoie la file au retour du réseau |
| `lib/data/services/connexion_m3.dart` | Réseau présent ? Prévient quand il revient |

Le contrat `SignalementRepository` n'a presque pas changé : un seul
ajout, `ajouterSignalement` accepte un id déjà choisi (voir 4.2).

## 3. Les tables

```sql
brouillons          (utilisateur_id PK, titre, description, categorie_id,
                     lieu, danger, photo_locale, date_modification)
envois_en_attente   (id PK AUTOINCREMENT, id_document UNIQUE, utilisateur_id,
                     quartier_id, titre, description, categorie_id, lieu,
                     danger, photo_locale, date_creation,
                     etat 'en_attente' | 'echec', nb_tentatives, derniere_erreur)
signalements_cache  (PK (quartier_id, id), titre, description, categorie_id,
                     statut, date, lieu, auteur_id, auteur_nom,
                     nb_confirmations, danger, photo_url)
                     + index (quartier_id, statut, date DESC)
mises_a_jour_cache  (quartier_id PK, date)
```

SQLite n'a ni booléen ni date : `danger` vaut 0 ou 1, les dates sont en
millisecondes (`millisecondsSinceEpoch`).

### Version 2 (étape 5 : GPS et adresse) : une vraie migration

```sql
ALTER TABLE brouillons         ADD COLUMN latitude REAL;  -- + longitude
ALTER TABLE envois_en_attente  ADD COLUMN latitude REAL;  -- + longitude
ALTER TABLE signalements_cache ADD COLUMN latitude REAL;  -- + longitude
CREATE TABLE adresses_cache (cle TEXT PRIMARY KEY, adresse TEXT, date INTEGER)
```

- Nouveau téléphone : `onCreate` crée la version 1 puis applique la
  version 2.
- Téléphone déjà en version 1 : `onUpgrade(1 → 2)` ajoute seulement les
  colonnes et la table : **les brouillons et la file d'envoi sont gardés**
  (testé dans `test/module3_adresse_test.dart`).
- `adresses_cache` : la clé est le point arrondi à 4 décimales (environ
  11 m), ex. `36.8625,10.1700`. La politique de Nominatim demande de ne pas
  redemander le même endroit ; et une adresse déjà trouvée marche hors ligne.

## 4. Les parcours

### 4.1 Publier

1. Le formulaire est validé (mêmes règles qu'en ligne).
2. **On vérifie le réseau AVANT d'appeler Firestore** : hors ligne,
   `await collection.add()` ne rend jamais la main et l'écran resterait
   bloqué sur « Envoi... ».
3. Pas de réseau → ligne dans `envois_en_attente`, message « ton
   signalement sera envoyé automatiquement », carte « En attente d'envoi »
   dans la liste.
4. Réseau présent → Firestore, avec **15 s maximum** (un Wi-Fi peut être
   actif sans Internet). Délai dépassé ou serveur injoignable → la file.
   Refus définitif (droits, formulaire) → message d'erreur, pas de file.

### 4.2 Pas de doublon

L'id du document Firestore est choisi **sur le téléphone, avant l'envoi**
(20 lettres/chiffres, comme Firestore). Si un envoi est rejoué (ex : le
premier a dépassé le délai mais est quand même arrivé), le repository voit
que le document existe déjà et ne le recrée pas.

### 4.3 Envoi automatique de la file

- Au démarrage (`SyncSignalementsM3.demarrer()`) et **à chaque retour du
  réseau** (écoute de `connectivity_plus`).
- Succès → la ligne est supprimée. Échec → `etat = 'echec'`,
  `nb_tentatives + 1`, erreur gardée (`rawUpdate`).
- Après **3 échecs**, plus d'envoi automatique : seulement le bouton
  « Réessayer » (évite de réessayer sans fin un envoi refusé).
- Seuls les envois de l'utilisateur connecté, dans son quartier actuel,
  partent (les règles Firestore refuseraient les autres).

### 4.4 Lire hors ligne

- En ligne : la liste vient de Firestore, puis est **copiée** dans
  `signalements_cache`. Chargement complet (sans filtre) : le cache du
  quartier est **remplacé** dans une transaction (les signalements
  supprimés disparaissent) et l'heure est notée.
- Hors ligne (ou Firestore en échec) : la liste vient du cache, avec les
  **mêmes filtres en SQL** (statut, catégorie, « Mes signalements »), et le
  bandeau « Hors ligne — dernière mise à jour à HH:mm ».
- Le détail hors ligne montre la version du cache, sans les actions
  (confirmer, modifier, supprimer, changer le statut : elles demandent le
  serveur).

### 4.5 Brouillon

- Création seulement. Enregistré 1 s après la dernière frappe, et en
  quittant l'écran sans publier. Un brouillon vide n'est pas gardé.
- À la réouverture : « Tu as un brouillon » → Reprendre / Supprimer.
- Supprimé après la publication (envoyée ou mise en file).

## 5. Robustesse

- Aucune erreur SQLite ne bloque l'application : `SyncSignalementsM3`
  les attrape, l'app continue en ligne comme avant.
- `ConnexionM3.estEnLigne()` attend 3 s au maximum le plugin.
- Plus tard, ajouter une colonne = `version: 2` + `onUpgrade` avec
  `ALTER TABLE` (les données des utilisateurs sont gardées).

## 6. Tests (`test/module3_sqflite_test.dart`)

SQLite tourne sur l'ordinateur avec `sqflite_common_ffi`, dans une base
**en mémoire** neuve pour chaque test ; le réseau est simulé
(`test/fausse_connexion_m3.dart`).

- CRUD de chaque table, filtres SQL, transaction de remplacement du cache ;
- publier en ligne / hors ligne (Firestore pas appelé) / réseau muet
  (délai) / serveur injoignable / refus ;
- la file part quand le réseau revient ; un échec garde la ligne avec
  un essai de plus ; arrêt après 3 échecs ; « Réessayer », « Annuler » ;
  pas de doublon ;
- écrans : bandeau hors ligne, carte « En attente d'envoi » qui disparaît
  au retour du réseau, brouillon repris, détail hors ligne.

## 7. Limites connues

- `connectivity_plus` sait si une interface réseau est active, pas si
  Internet répond : d'où le délai de 15 s sur chaque envoi.
- Le signalement envoyé plus tard prend la date de l'envoi (le
  repository impose `date = maintenant`) ; la date de création est gardée
  dans la file.
- Le cache garde les signalements du dernier chargement : un signalement
  jamais chargé n'est pas lisible hors ligne.
