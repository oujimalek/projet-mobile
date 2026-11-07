# Module 2 · Services : branché sur Firestore

Ce document décrit ce que le module 2 lit et écrit dans Firestore, ce qui
manque dans les fichiers communs (règles, schéma) et ce qu'il faut demander à
Mohamed (responsable du module 1).

Les noms des collections et des champs sont **exactement** ceux de
[`schema_firestore.md`](schema_firestore.md) (section 4). Une seule ligne est
ajoutée : `heureDebut` / `heureFin` sur les services (voir §4).

## 1. Ce que le module écrit (et rien d'autre)

Toutes sous `quartiers/{quartierId}/`, avec le `quartierId` de l'utilisateur
connecté (`UtilisateurRepository().getUtilisateurConnecte().quartierId`) :

| Collection | Écrit par | Lecture |
|---|---|---|
| `services/{id}` | publier, modifier, supprimer son service ; pour un service commun : participants de la rotation, créneaux « faits » (son auteur seulement) | membres actifs du quartier |
| `demandes/{id}` | envoyer une demande, changer son statut, marquer « évaluée » | les 2 personnes concernées |
| `demandes/{id}/messages/{id}` | chat : envoyer, marquer « lu » | les 2 personnes concernées |
| `evaluations/{demandeId}` | évaluer une demande réalisée | membres actifs du quartier |
| `creneaux/{id}` | créer les créneaux d'un service commun (au départ et en « Prolonger le planning »), s'inscrire / confirmer son tour, se désister, les supprimer avec le service | membres actifs du quartier |

Le module 2 **lit** seulement l'utilisateur connecté (module 1). Il n'écrit
jamais dans `utilisateurs`, `quartiers/{q}` (le document du quartier),
`codesQuartier`, `telephones`, ni dans une collection d'un autre module.

## 2. Exemples de documents

`services/{id}`
```
titre: "Nettoyage des escaliers"
description: "On nettoie ensemble les escaliers du bloc."
categorie: "Bricolage"
auteurId: "Xk3…9a"          (uid Firebase Auth)
auteurNom: "Amira B."
auteurBloc: "Bloc B"
estOffre: true
estCommun: true
jour: "Samedi"              (service commun seulement)
heureDebut: "09:00"         (service commun seulement)  ← AJOUT, voir §4
heureFin: "10:00"           (service commun seulement)  ← AJOUT, voir §4
disponibilite: "Chaque samedi"   (absent si vide)
datePublication: <timestamp>
```

`services/{id}` d'un service commun **en rotation automatique** : les champs
suivants s'ajoutent (voir §3bis). Un service en « inscription libre » n'a aucun
de ces champs et reste identique à avant.
```
modeRotation: true
participantsIds:  ["uidSara", "uidKarim", "uidAmira"]   (ordre de passage)
participantsNoms: ["Sara B.", "Karim M.", "Amira T."]    (même ordre)
rotationDepuis: <timestamp 2026-11-10>   (les créneaux à partir de ce jour suivent le cycle)
rotationIndex: 1                         (participant du 1er de ces créneaux)
toursFiges: { "abc_20261109": { id: "uidKarim", nom: "Karim M." } }   (créneau du jour figé)
creneauxFaits: { "abc_20261102": { faitLe: <timestamp 2026-11-02 21:05>,
                                    parId: "uidSara", parNom: "Sara B." } }
```
`creneauxFaits` existe aussi pour un service en inscription libre dès que
l'auteur marque un créneau « Fait » (`parId` / `parNom` vides si personne
n'était de service).
`prix`, `duree` et `recuperation` existent dans le schéma mais le formulaire
ne les propose pas : ils sont lus (et affichés) s'ils existent.

`demandes/{id}` : l'id est `{serviceId}_{uidDuDemandeur}` (une demande par
voisin et par service, impossible d'en créer deux)
```
serviceId: "abc123"
serviceTitre: "Perceuse à prêter"
demandeurId: "uid1"   demandeurNom: "Amira B."
auteurServiceId: "uid2"   auteurServiceNom: "Karim M."
statut: "enAttente"         (enAttente | acceptee | refusee | realisee)
dateDemande: <timestamp>
evaluee: false
```

`demandes/{id}/messages/{id}`
```
auteurId: "uid1"   auteurNom: "Amira B."
texte: "Salam, je passe vers 18 h ?"
date: <timestamp>
lu: false
```

`evaluations/{demandeId}` (l'id est celui de la demande : une seule par demande)
```
serviceId: "abc123"
auteurId: "uid1"            (le demandeur, qui note)
evalueId: "uid2"   evalueNom: "Karim M."   (celui qui a rendu le service)
note: 5                     (entier de 1 à 5)
tags: ["Ponctuel", "Sympa"]
message: "Merci !"          (absent si vide)
date: <timestamp>
```

`creneaux/{id}`
```
serviceId: "abc123"   titre: "Nettoyage des escaliers"
date: <timestamp>           (minuit du jour)
heureDebut: "09:00"   heureFin: "10:00"
inscritId: null   inscritNom: null     (TOUJOURS écrits, null si libre)
rappelVeille: false
```
**Aucun champ nouveau sur `creneaux`.** Seule nouveauté : l'identifiant des
créneaux créés par l'application est désormais `{serviceId}_{AAAAMMJJ}`
(ex : `abc123_20261109`), ce qui empêche les doublons si on prolonge le
planning deux fois. Les anciens créneaux (identifiant aléatoire) restent lus
normalement.

Après un **désistement dans un service en rotation**, le créneau est libre
(`inscritId: null`) et `inscritNom` vaut la constante
`CreneauCommun.marqueDesiste` (`"__desiste__"`). C'est un marqueur interne :
il signifie « libre pour tout le monde, sans tour ». Il n'est **jamais
affiché** (les écrans lisent `CreneauCommun.inscrit`, qui renvoie `null`) ; un
test vérifie qu'il n'apparaît qu'à un seul endroit du code.

## 3. Comment le code travaille

- Lectures en `Stream` (la liste se met à jour toute seule) ; écritures en
  `Future<Resultat<T>>` avec des **transactions** pour : envoyer une demande,
  changer un statut, évaluer (évaluation + `evaluee = true` ensemble),
  s'inscrire / se désister.
- Les règles métier (pas de demande sur son propre service ni en double, seul
  l'auteur accepte ou refuse, « réalisée » seulement depuis « acceptée », une
  seule évaluation de 1 à 5 par le demandeur, pas d'inscription sur un
  créneau pris ou passé, désistement de son créneau seulement, seul l'auteur
  modifie ou supprime) sont dans `ServiceRepository` / `ChatRepository`
  (méthodes `static refus…`). Les règles de sécurité Firestore les vérifient
  aussi côté serveur.
- **Publier un service commun** : le service est écrit d'abord, puis les
  créneaux libres (id fixe `{serviceId}_{AAAAMMJJ}`) des 4 prochaines semaines
  en **un seul batch**. Si le batch
  échoue, le service est supprimé (pas de service commun sans créneaux). Les
  deux étapes ne sont pas dans le même batch parce que la règle de création
  d'un créneau lit le service (`get()`), qui doit donc déjà exister.
- **Supprimer un service** (son auteur) : en un seul batch, ses demandes
  `enAttente` passent à `refusee`, ses créneaux sont supprimés et le service
  est supprimé. Les demandes ne sont pas supprimées (voir §4, règle `delete`).
- **Modifier un service** (son auteur, depuis le détail) : titre, description,
  catégorie, type (offre / demande) et disponibilité. Le jour et les heures
  d'un service commun ne changent pas. Le titre des créneaux déjà créés ne
  change pas non plus (les règles n'autorisent que `inscritId`, `inscritNom`
  et `rappelVeille` en modification d'un créneau).
- **Note moyenne et services rendus** : l'application lit les évaluations où
  `evalueId == uid` (égalité sur un seul champ : index automatique) et calcule
  la moyenne et le nombre d'avis elle-même. Aucun `average()` ni `count()` :
  ils demandaient un index composite `evaluations (evalueId, note)` absent de
  `firestore.indexes.json`, ce qui faisait échouer le calcul (« Note
  indisponible », même avec zéro avis). Zéro avis affiche « Pas encore d'avis ».
  Rien n'est stocké dans le profil.
- **Accueil** : `ServiceRepository().getServices()` reste synchrone. Le
  premier appel démarre l'écoute des services ; il ne lève jamais
  d'exception et ne garde aucun abonnement si l'écoute est impossible (pas
  connecté, pas de quartier, Firebase absent). Comme l'accueil ne se redessine
  pas quand la liste arrive, « Derniers services » s'affiche au plus tard au
  prochain rafraîchissement de l'accueil.

## 3bis. Rotation, « Fait », rappel, prolongation (avec les règles ACTUELLES)

Tout fonctionne **sans modifier `firestore.rules`**. L'idée : les créneaux
restent libres dans Firestore ; l'application CALCULE le tour de chacun, et
seul l'auteur du service écrit (sur son service).

### Rotation
- À la création d'un service commun, l'auteur choisit « Inscription libre » ou
  « Rotation automatique » (non modifiable ensuite). En rotation, il choisit
  les participants et leur ordre parmi les **vrais membres actifs du quartier**
  (lus avec `UtilisateurRepository().getVoisins()`, module 1, lecture seule ;
  « Moi » est proposé en tête, ajouté si la liste ne me contient pas). Minimum
  1 participant. Il peut ensuite les modifier depuis le détail du service.
- Calcul (fonction pure `ServiceRepository.calculerTours`) : un créneau à partir
  de `rotationDepuis` prend `participants[(rotationIndex + rang) % n]`, `rang`
  étant sa place parmi ces créneaux (date puis heure). Un créneau présent dans
  `toursFiges` garde son titulaire.
- Quand l'auteur ajoute, retire ou réordonne (`nouvelleAncre`) : le créneau
  d'**aujourd'hui est figé** (copié dans `toursFiges`), le cycle **reprend
  après le dernier créneau passé** (le participant suivant, dans l'ancien
  ordre, encore présent), et les créneaux à partir de **demain** suivent la
  nouvelle liste. Les créneaux passés, faits ou du jour ne changent jamais :
  aucun créneau n'est réécrit.
- Le planning affiche « Tour de Sara » sur chaque créneau à venir, un encart
  « Prochain tour de chacun », et « C'est ton tour » + « Confirmer » pour la
  personne concernée (« Confirmer » ouvre l'inscription existante).
  Un tour non confirmé est **réservé** à son titulaire dans l'interface, jusqu'à
  son désistement (les règles Firestore ne l'imposent pas, voir plus bas).
- Désistement : le créneau devient libre pour tous (marqueur, voir §2).

### « Fait »
- Seul l'auteur du service marque un créneau « Fait », le jour même (dès minuit)
  ou après, une seule fois. L'information est écrite dans la map
  `creneauxFaits` du **service** (`faitLe`, `parId`, `parNom`), jamais sur le
  créneau. Planning : « Fait ✓ » (réalisé), « À faire » (passé, non fait).
- Un créneau fait ne peut plus être désisté ni pris : **contrôlé dans
  l'application** (la transaction relit le service). Les règles actuelles ne
  peuvent pas l'imposer (le créneau ne porte pas l'information). Un client
  modifié pourrait donc encore se désister d'un créneau fait.

### Rappel (dans l'application, sans notification système)
- Bandeau en haut de l'écran Services et du planning : « Rappel : demain, tu es
  de service pour Sortie des poubelles (20:00 - 20:30) » + bouton « Voir ».
  Pour un créneau où je suis inscrit : aujourd'hui toujours, demain seulement si
  « Me rappeler la veille » est coché. Pour un tour calculé à mon nom non
  confirmé : aujourd'hui et demain. Jamais pour un créneau fait ou désisté.
- Lecture seule : services + créneaux des 7 jours à partir d'aujourd'hui.

### Prolonger le planning
- Bouton réservé à l'auteur : crée 4 semaines de créneaux libres après le
  dernier créneau existant, en un batch. Identifiant fixe `{serviceId}_{AAAAMMJJ}` :
  un 2e appui ne crée aucun doublon (les dates déjà présentes sont sautées).
  En rotation, le cycle continue automatiquement (le calcul est fait à
  l'affichage).

### Chaque écriture contre `firestore.rules` (règles actuelles)

| Écriture | Règle actuelle qui l'autorise |
|---|---|
| Créer un service avec les champs de rotation | `services` : `allow create: if membreDe(q) && request.resource.data.auteurId == monUid();` (pas de liste blanche de champs) |
| Changer participants / ordre / ancre (auteur) | `services` : `allow update: if membreDe(q) && resource.data.auteurId == monUid() && request.resource.data.auteurId == monUid();` |
| Marquer « Fait » (`creneauxFaits.<id>` sur le service, auteur) | même règle `services.update` |
| Créer des créneaux, au départ et en prolongation | `creneaux` : `allow create: if membreDe(q) && auteurDuService(request.resource.data.serviceId) && request.resource.data.inscritId == null;` |
| Confirmer son tour / s'inscrire | `creneaux` : `allow update: if membreDe(q) && changeSeulement(['inscritId','inscritNom','rappelVeille']) && resource.data.get('inscritId', null) in [null, monUid()] && request.resource.data.get('inscritId', null) in [null, monUid()];` |
| Se désister (marqueur dans `inscritNom`) | même règle : avant = moi, après = `null` ; `inscritNom` n'est pas contraint |
| Lire évaluations, services, créneaux | `allow read: if membreDe(q);` |

Rien n'est refusé. Les règles imposent seulement ce qu'elles savent vérifier ;
le reste (tour réservé, créneau fait non désistable, « Fait » pas avant la
date) est vérifié par l'application (`ServiceRepository.refus…`).

## 4. Ce qui manque dans les fichiers communs (à demander à Mohamed)

Je n'ai modifié aucun de ces fichiers.

### a) Schéma : une ligne à ajouter dans `docs/schema_firestore.md` §4 (services)

```
| *(nouveau)* | `heureDebut`, `heureFin` | string `"18:00"` ou absent | Service commun : l'heure du créneau |
```
`firestore.rules` n'a pas de liste blanche de champs sur `services` : rien à
changer côté règles pour ces deux champs.

### b) Règle `delete` sur `demandes` (absente)

Aujourd'hui personne ne peut supprimer une demande. Le module 2 ne supprime
rien : à la suppression d'un service, il passe ses demandes `enAttente` à
`refusee` (cette modification est déjà autorisée par la règle « L'auteur du
service accepte ou refuse »). Si l'équipe préfère vraiment **supprimer** ces
demandes, ajouter dans `match /demandes/{demandeId}` :

```
// L'auteur du service supprime une demande en attente de SON service
// (quand il supprime le service).
allow delete: if membreDe(q)
  && monUid() == resource.data.auteurServiceId
  && resource.data.statut == 'enAttente';
```
Le code du module 2 devrait alors être adapté (une ligne dans
`FirebaseServiceRepository.supprimerService`). **Pas urgent.**

### c) Index

Aucun index à ajouter. Les requêtes du module 2 utilisent :

| Requête | Index |
|---|---|
| `services` trié par `datePublication` | un seul champ (automatique) |
| `demandes` : `demandeurId ==` + tri `dateDemande` | déjà dans `firestore.indexes.json` |
| `demandes` : `auteurServiceId ==` + tri `dateDemande` | déjà dans `firestore.indexes.json` |
| `demandes` : `auteurServiceId ==` + `serviceId ==` + `statut ==` (suppression d'un service) | égalités seulement (automatique) |
| `creneaux` : `serviceId ==` + tri `date` | déjà dans `firestore.indexes.json` |
| `creneaux` : `date >=` et `date <` + tri `date` (planning de la semaine) | un seul champ (automatique) |
| `evaluations` : `evalueId ==` (la moyenne est calculée dans l'application) | égalité sur un champ (automatique) |
| `creneaux` : `serviceId ==` (rotation, prolongation, « Fait ») | égalité sur un champ (automatique) ; avec tri `date` : déjà dans `firestore.indexes.json` |
| `messages` triés par `date` | un seul champ (automatique) |

Les index `services` (`categorie`, `estCommun`) existent mais ne sont pas
utilisés : le filtre par catégorie se fait dans l'application.

### d) À savoir sur les règles (pas de changement demandé)

- La création d'un créneau lit le service avec `get()` : une publication de
  service commun fait 4 créneaux (`get()` identiques comptés une seule fois
  par Firestore). Si un jour le nombre de semaines passe à plus de 10, les
  limites d'appels de règles pourraient poser problème.
- `messages` : les règles ne vérifient pas que la demande est `acceptee` ou
  `realisee`. Le module 2 le vérifie dans l'application.
- Les documents créés à la main dans la console, sans `auteurId`, s'affichent
  mais ne peuvent être ni demandés, ni modifiés, ni supprimés.

### e) Le compte de test

Il faut un compte **validé** (`statut: actif`) avec un `quartierId`. Pour
tester les échanges, il en faut **deux** dans le même quartier (deux
téléphones, ou un téléphone et l'émulateur).

## 5. Tests

- `test/mock_service_repository.dart` et `test/mock_chat_repository.dart` :
  données en mémoire, **vides au départ** (aucune donnée de démonstration),
  mêmes règles que Firebase, lectures en `Stream`, avec de quoi simuler une
  erreur réseau ou une écriture lente.
- `test/module2_services_test.dart` et `test/module2_chat_test.dart` :
  modèles, règles métier, repositories et écrans, sans Internet. Couvrent
  notamment : le calcul de la rotation (ordre, reprise du cycle, créneau du
  jour figé, ajout / retrait / changement d'ordre), « Fait » réservé à
  l'auteur et pas avant la date, créneau fait non désistable, le marqueur de
  désistement (jamais affiché), les rappels (aujourd'hui, demain, veille), la
  prolongation sans doublon, « Pas encore d'avis », les lignes vides masquées
  et le refus de demander son propre service.
- Non testé automatiquement (pas de package de faux Firestore dans le
  projet) : les transactions, les batchs et les règles de sécurité réelles.
  À vérifier sur téléphone, voir le rapport de livraison.

## 6. Amélioration future

Aujourd'hui, seul l'auteur du service écrit sur son service : il choisit les
participants et marque les créneaux « Fait ». Pour qu'un voisin puisse
**rejoindre seul la rotation** et **marquer lui-même son créneau « Fait »**, il
faudrait ajouter ces règles dans `firestore.rules` (à demander au responsable
du module 1) :

```
// services — un voisin rejoint / quitte la rotation : seulement MOI,
// seulement ces 2 champs, service commun en rotation
allow update: if membreDe(q)
  && resource.data.estCommun == true
  && resource.data.get('modeRotation', false) == true
  && changeSeulement(['participantsIds', 'participantsNoms'])
  && request.resource.data.participantsIds.size() == request.resource.data.participantsNoms.size()
  && request.resource.data.participantsIds.toSet()
       .difference(resource.data.get('participantsIds', []).toSet()).hasOnly([monUid()])
  && resource.data.get('participantsIds', []).toSet()
       .difference(request.resource.data.participantsIds.toSet()).hasOnly([monUid()]);

// services — l'inscrit marque SON créneau « Fait » (une entrée de creneauxFaits,
// la sienne, et seulement ce champ)
allow update: if membreDe(q)
  && changeSeulement(['creneauxFaits'])
  && request.resource.data.creneauxFaits.diff(resource.data.get('creneauxFaits', {}))
       .affectedKeys().size() == 1
  && request.resource.data.creneauxFaits[request.resource.data.creneauxFaits
       .diff(resource.data.get('creneauxFaits', {})).addedKeys().toList()[0]].parId == monUid();
```

Côté application, il suffirait alors d'ajouter les méthodes `rejoindreRotation`
/ `quitterRotation` (qui appellent `nouvelleAncre`, déjà écrite) et d'autoriser
l'inscrit dans `refusFait`. Ces règles sont une proposition à tester dans
l'émulateur Firebase avant déploiement. Elles ne peuvent toujours pas imposer
« pas avant le jour du créneau » sans lire le créneau (un `get()` sur
`creneaux/{id}` et `request.time`).

### Vraie notification (hors application)

Le rappel actuel n'apparaît que quand l'application est ouverte. Pour une
notification système, il faudrait **ajouter** (aucun de ces éléments n'est dans
le projet) :
- les packages `firebase_messaging` (notifications push) et, pour des rappels
  planifiés sur le téléphone, `flutter_local_notifications` ;
- les permissions : Android 13+ `POST_NOTIFICATIONS` dans `AndroidManifest.xml`,
  et sur iOS les capacités « Push Notifications » et « Background Modes » dans
  Xcode (+ clé APNs dans la console Firebase) ;
- le jeton FCM de chaque téléphone enregistré dans le profil de l'utilisateur
  (module 1, `utilisateurs/{uid}.fcmToken`, avec la règle de mise à jour qui
  va avec) ;
- une **Cloud Function planifiée** (Cloud Scheduler, chaque soir et chaque
  matin) qui lit les créneaux du jour et du lendemain, calcule le titulaire
  (la même logique que `calculerTours`, à porter en TypeScript) et envoie le
  message aux bons jetons, en respectant « Me rappeler la veille » ;
- ou, sans serveur, des notifications locales programmées à l'inscription (mais
  elles ne suivraient pas les changements de rotation).
