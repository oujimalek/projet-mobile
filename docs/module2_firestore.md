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
| `services/{id}` | publier, modifier, supprimer son service | membres actifs du quartier |
| `demandes/{id}` | envoyer une demande, changer son statut, marquer « évaluée » | les 2 personnes concernées |
| `demandes/{id}/messages/{id}` | chat : envoyer, marquer « lu » | les 2 personnes concernées |
| `evaluations/{demandeId}` | évaluer une demande réalisée | membres actifs du quartier |
| `creneaux/{id}` | créer les créneaux d'un service commun, s'inscrire, se désister, les supprimer avec le service | membres actifs du quartier |

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
  créneaux libres des 4 prochaines semaines en **un seul batch**. Si le batch
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
- **Note moyenne et services rendus** : calculés avec `average('note')` et
  `count()` sur `evaluations` où `evalueId == uid`. Rien n'est stocké dans le
  profil.
- **Accueil** : `ServiceRepository().getServices()` reste synchrone. Le
  premier appel démarre l'écoute des services ; il ne lève jamais
  d'exception et ne garde aucun abonnement si l'écoute est impossible (pas
  connecté, pas de quartier, Firebase absent). Comme l'accueil ne se redessine
  pas quand la liste arrive, « Derniers services » s'affiche au plus tard au
  prochain rafraîchissement de l'accueil.

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
| `evaluations` : `evalueId ==` + `average` / `count` | agrégation sur un champ (automatique) |
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
  modèles, règles métier, repositories et écrans, sans Internet.
- Non testé automatiquement (pas de package de faux Firestore dans le
  projet) : les transactions, les batchs et les règles de sécurité réelles.
  À vérifier sur téléphone, voir le rapport de livraison.
