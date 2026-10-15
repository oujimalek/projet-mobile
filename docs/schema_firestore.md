# Houmani : schéma de la base Firestore (4 modules)

Ce document décrit **où** chaque donnée est rangée dans Firestore, **quels champs**
elle a, et **qui** a le droit de la lire ou de l'écrire.

- Les règles de sécurité correspondantes sont dans [`firestore.rules`](../firestore.rules)
  (brouillon, pas encore déployé).
- Pour les modules 2, 3 et 4 c'est une **proposition** : chaque responsable de
  module l'applique dans sa propre branche. Ce document ne modifie aucun de
  leurs fichiers.

## 1. Les idées de base (à lire en premier)

**Firestore en 30 secondes.** Les données sont rangées en *collections*
(comme des dossiers) qui contiennent des *documents* (comme des fiches).
Chaque document a un identifiant et des champs (`titre: "Perceuse"`,
`date: ...`). Un document peut contenir des *sous-collections*.

**Règle n°1 : tout est rangé par quartier.** Un voisin ne doit voir que son
quartier. Donc toutes les données partagées sont **dans** le quartier :

```
quartiers/{quartierId}/services/...
quartiers/{quartierId}/signalements/...
```

Pourquoi des sous-collections plutôt qu'un champ `quartierId` dans chaque
document d'une grande collection `services` ?
- **Impossible d'oublier le filtre.** Avec un champ, chaque requête doit
  contenir `.where('quartierId', ...)`, sinon Firebase la refuse.
  Avec le chemin, le quartier est déjà dans l'adresse.
- **Règles plus simples** : « membre actif de *ce* quartier » se lit dans
  le chemin.
- **Moins d'index** à créer (voir section 7).

Seuls `utilisateurs` et `codesQuartier` restent à la racine. Un compte en attente
peut encore changer de quartier, et on cherche un utilisateur par son `uid`.

**Règle n°2 : on identifie les personnes par leur `uid`, pas par leur nom.**
Aujourd'hui les modèles écrivent `auteur: 'Sami Ben Ali'`. Deux voisins
peuvent avoir le même nom, et un nom peut changer. Dans Firestore on garde :

| Champ | Exemple | À quoi il sert |
|---|---|---|
| `auteurId` | `"Xk3...9a"` (uid Firebase Auth) | Les règles de sécurité (« est-ce bien moi ? ») |
| `auteurNom` | `"Sami Ben Ali"` | L'affichage, sans relire le profil à chaque ligne |

Le nom est **recopié** (on dit *dénormalisé*). Si quelqu'un change de nom,
ses anciens messages gardent l'ancien : c'est accepté.

**Règle n°3 : seul un membre ACTIF lit ou écrit.** Un compte `enAttente`,
`refuse` ou `bloque` peut lire **seulement son propre profil**, la liste des
quartiers et un code d'invitation. Tout le reste lui est refusé par Firebase,
même si l'application a un bug.

**Règle n°4 : les compteurs sont protégés.** Un nombre affiché sur chaque
carte d'une liste (confirmations d'un signalement, participants d'un
événement) est stocké dans le document. Les règles vérifient qu'il ne bouge
que de **+1 / −1**, et **en même temps** que la fiche de la personne
(`confirmations/{monUid}`). Cette fiche porte l'`uid` de la personne : on ne
peut donc confirmer qu'une seule fois.

## 2. Vue d'ensemble

```
utilisateurs/{uid}                              M1  profil + statut + rôle
codesQuartier/{code}                            M1  code d'invitation → quartier
quartiers/{quartierId}                          M1  nom, localisation
  ├── services/{serviceId}                      M2
  ├── demandes/{demandeId}                      M2
  │     └── messages/{messageId}                M2  chat de la demande
  ├── evaluations/{demandeId}                   M2  1 évaluation par demande
  ├── creneaux/{creneauId}                      M2  services communs
  ├── signalements/{signalementId}              M3
  │     └── confirmations/{uid}                 M3  « moi aussi »
  ├── evenements/{evenementId}                  M4
  │     └── participants/{uid}                  M4
  └── sondages/{sondageId}                      M4
        └── votes/{uid}                         M4  1 vote par membre
```

**Conventions pour tous les modules :**

| En Dart | Dans Firestore | Remarque |
|---|---|---|
| `String`, `int`, `double`, `bool` | pareil | |
| `DateTime` | `timestamp` | On écrit un `DateTime`, Firestore le range en `Timestamp`. À la lecture : `(valeur as Timestamp).toDate()` |
| `enum` | `string` | On écrit `statut.name` (`"enAttente"`). On relit en cherchant dans `Statut.values`, avec une valeur par défaut si inconnue |
| `List<String>` | `array` | |
| champ optionnel (`String?`) | absent ou `null` | Les champs testés par les règles (ex. `inscritId`) sont **toujours écrits**, même à `null` |
| `id` du modèle | **identifiant du document** | Pas recopié dans les champs |
| `IconData`, `Color` | jamais stockés | Restent dans le code (ex. catégories de signalement) |

Chaque modèle reçoit `toMap()` et `factory X.fromMap(String id, Map<String, dynamic> map)`.
Ce sont les mêmes fonctions pour Firestore et pour le cache Hive (phase 4) : pas de génération de code.

## 3. Module 1 · Utilisateurs et quartiers

### `utilisateurs/{uid}`

L'identifiant du document est l'`uid` Firebase Auth. Le mot de passe n'est
**jamais** ici : Firebase Auth s'en occupe.

| Champ Dart (`Utilisateur`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `id` | *(id du document)* | | = `uid` |
| `prenom`, `nom` | `prenom`, `nom` | string | |
| `email` | `email` | string | Doit être l'e-mail du compte Auth (vérifié par les règles) |
| `telephone` | `telephone` | string | Champ de profil, pas utilisé pour se connecter |
| *(nouveau)* `quartierId` | `quartierId` | string ou `null` | `null` tant que le voisin n'a pas choisi de quartier |
| `quartier` | `quartierNom` | string | Nom recopié pour l'affichage |
| `residence` | `residence` | string | **Inchangé** (utilisé par M2 et M3) |
| `logement` | `logement` | string | |
| `statut` | `statut` | string | `enAttente` · `actif` · `bloque` · `refuse` (nouveau, voir plus bas) |
| `role` | `role` | string | `resident` · `admin` |
| `competences` | `competences` | array de string | |
| `avatar` | `avatar` | string | Identifiant d'un des 6 avatars prédéfinis |
| `dateDemande` | `dateDemande` | timestamp | Date de la demande d'adhésion |
| `servicesRendus`, `noteMoyenne`, `nbSignalements` | **non stockés** | | Calculés (voir ci-dessous) |

**Pourquoi les statistiques du profil ne sont pas stockées.** Si
`noteMoyenne` était dans mon profil, il faudrait laisser les autres écrire
dans mon profil pour la mettre à jour. On les calcule donc avec les
*requêtes d'agrégation* de Firestore (`count()`, `average()`), qui coûtent
une seule lecture :

| Statistique | Calcul |
|---|---|
| `noteMoyenne` | `average('note')` sur `evaluations` où `evalueId == uid` |
| `servicesRendus` | `count()` sur `evaluations` où `evalueId == uid` (un service rendu est évalué) |
| `nbSignalements` | `count()` sur `signalements` où `auteurId == uid` |

Le modèle Dart garde ces 3 champs (valeur `0` par défaut). Le repository les
remplit après la lecture du profil.

**Décision : le statut `refuse`.** Quand l'admin refuse une demande, on
passe `statut` à `refuse` au lieu de supprimer le document. Pourquoi :
- l'admin ne peut changer **que** le statut d'un membre (règle simple) ;
- le voisin voit « demande refusée » au lieu d'un écran vide ;
- il peut ensuite choisir un autre quartier, et repasse alors `enAttente`.

À faire en phase 3 : ajouter `refuse` à `enum StatutUtilisateur`
(`lib/data/models/utilisateur.dart`, sans toucher à `residence`).

**Qui peut faire quoi :**

| Action | Qui |
|---|---|
| Lire | Soi-même (quel que soit son statut) ; un membre **actif** du même quartier |
| Créer | Soi-même, à l'inscription : `statut = enAttente`, `role = resident` (impossible de se déclarer admin) |
| Modifier son profil | Soi-même si `actif`, sans changer `statut`, `role`, ni `quartierId` |
| Rejoindre / changer de quartier | Soi-même si `enAttente` ou `refuse`, **e-mail vérifié**, vers un quartier qui existe ; le statut redevient `enAttente` |
| Valider / refuser / bloquer / débloquer | L'admin **actif** du quartier, **uniquement** le champ `statut`, jamais sur lui-même |
| Supprimer | Personne depuis l'app |

Cycle de vie du statut :

```
inscription ──► enAttente ──(admin valide)──► actif ◄──(admin débloque)── bloque
                   ▲   │                        │                          ▲
                   │   └──(admin refuse)──► refuse                         │
                   └──(choisit un autre quartier)┘     └──(admin bloque)───┘
```

Un compte `bloque` ne peut **plus rien lire** sauf son propre profil :
l'application affiche « compte bloqué » et le déconnecte.

### `quartiers/{quartierId}`

| Champ Dart (`Quartier`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `id` | *(id du document)* | | |
| `nom` | `nom` | string | ex. « Résidence El Yasmine » |
| `localisation` | `localisation` | string | ex. « Ennasr 2, Ariana » |
| `codeInvitation` | **déplacé** dans `codesQuartier` | | Sinon tout compte connecté pourrait le lire |
| `nbMembres` | **non stocké** | | `count()` sur `utilisateurs` où `quartierId == id` et `statut == actif` |

- **Lire** : tout compte connecté, même en attente (il faut chercher un
  quartier avant d'être validé). Seuls le nom et la localisation sont visibles.
- **Écrire** : personne depuis l'app (création à la main, section 8).

`nbMembres` n'est calculable que par un membre actif. L'écran « rejoindre
un quartier » affichera donc seulement la localisation (adaptation en phase 5).

### `codesQuartier/{code}`

L'identifiant du document **est** le code (ex. `YAS72B`).

| Champ | Type | Remarque |
|---|---|---|
| `quartierId` | string | Le quartier à rejoindre |
| `quartierNom` | string | Pour afficher « Vous rejoignez Résidence El Yasmine » |

- **Lire un code précis** (`get`) : tout compte connecté. On ne peut lire
  que le code que l'on a tapé.
- **Lister les codes** (`list`) : **interdit**. Personne ne peut obtenir
  tous les codes.
- **Écrire** : personne depuis l'app (console).

Le code sert de raccourci. La vraie sécurité reste la **validation par l'admin**.

## 4. Module 2 · Services

Proposition pour la branche `feature/module2-services` (yappa).

### `quartiers/{q}/services/{serviceId}`

| Champ Dart (`Service`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `titre`, `description` | `titre`, `description` | string | |
| `categorie` | `categorie` | string | |
| `auteur` (nom) | `auteurId` + `auteurNom` | string | |
| `bloc` | `auteurBloc` | string | Recopié de `residence` de l'auteur |
| `estOffre`, `estCommun` | `estOffre`, `estCommun` | bool | |
| `jour`, `prix`, `disponibilite`, `duree`, `recuperation` | pareil | string ou absent | |
| `datePublication` | `datePublication` | timestamp | |

Lire : membre actif. Créer : membre actif, `auteurId` = soi. Modifier :
l'auteur. Supprimer : l'auteur ou l'admin.

### `quartiers/{q}/demandes/{demandeId}`

| Champ Dart (`DemandeService`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `serviceId` | `serviceId` | string | |
| *(nouveau)* | `serviceTitre` | string | Recopié pour la liste |
| `demandeur` (nom) | `demandeurId` + `demandeurNom` | string | |
| `auteurService` (nom) | `auteurServiceId` + `auteurServiceNom` | string | Vérifié : doit être l'auteur du service |
| `statut` | `statut` | string | `enAttente` · `acceptee` · `refusee` · `realisee` |
| `dateDemande` | `dateDemande` | timestamp | |
| `evaluee` | `evaluee` | bool | |

Lire : **seulement les 2 personnes concernées**. Les requêtes doivent donc
filtrer : `where('demandeurId', isEqualTo: monUid)` (envoyées) ou
`where('auteurServiceId', isEqualTo: monUid)` (reçues).

Changements autorisés :
- l'auteur du service : `enAttente` → `acceptee` ou `refusee` ;
- l'un des deux : `acceptee` → `realisee` ;
- le demandeur : `evaluee` → `true` (en même temps que l'évaluation).

#### `.../demandes/{demandeId}/messages/{messageId}` (chat)

| Champ Dart (`MessageChat`) | Champ Firestore | Type |
|---|---|---|
| `demandeId` | *(dans le chemin)* | |
| `auteur` (nom) | `auteurId` + `auteurNom` | string |
| `texte` | `texte` | string |
| `date` | `date` | timestamp |
| `lu` | `lu` | bool |

Lire et écrire : seulement les 2 personnes de la demande. Le destinataire
peut passer `lu` à `true`, et rien d'autre. Pour un chat en direct, on
utilise `snapshots()` (un `Stream`) au lieu de l'écouteur manuel actuel de
`ChatRepository`.

### `quartiers/{q}/evaluations/{demandeId}`

L'identifiant du document est **l'id de la demande** : il ne peut donc y
avoir qu'une seule évaluation par demande.

| Champ Dart (`Evaluation`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `demandeId` | *(id du document)* | | |
| `serviceId` | `serviceId` | string | |
| *(nouveau)* | `auteurId` | string | Celui qui évalue (le demandeur) |
| `auteurEvalue` (nom) | `evalueId` + `evalueNom` | string | Celui qui a rendu le service |
| `note` | `note` | int | Entre 1 et 5 (vérifié) |
| `tags` | `tags` | array de string | |
| `message` | `message` | string ou absent | |
| `date` | `date` | timestamp | |

Lire : membre actif. Créer : le demandeur, seulement si la demande est
`realisee`. Modifier ou supprimer : personne.

### `quartiers/{q}/creneaux/{creneauId}` (services communs)

| Champ Dart (`CreneauCommun`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `serviceId`, `titre` | pareil | string | |
| `date` | `date` | timestamp | Le jour |
| `heureDebut`, `heureFin` | pareil | string `"20:00"` | |
| `inscrit` (nom) | `inscritId` + `inscritNom` | string ou `null` | **Toujours écrits**, `null` si libre |
| `rappelVeille` | `rappelVeille` | bool | |

Créer / supprimer : l'auteur du service. S'inscrire : un membre actif, si le
créneau est libre. Se désinscrire ou changer le rappel : l'inscrit.

## 5. Module 3 · Signalements

Proposition pour la branche `feature/module3-signalements` (malouka).

### `quartiers/{q}/signalements/{signalementId}`

| Champ Dart (`Signalement`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `titre`, `description`, `lieu` | pareil | string | |
| `categorieId` | `categorieId` | string | `electricite`, `eau`, `ordures`, `travaux`, `incident` |
| `statut` | `statut` | string | `enAttente` · `enCours` · `resolu` · `refuse` |
| `date` | `date` | timestamp | |
| `auteur` (nom) | `auteurId` + `auteurNom` | string | |
| `confirmations` | `nbConfirmations` | int | Compteur protégé (règle n°4) |

Les **catégories** (`CategorieSignalement`, avec icône et couleur) restent
dans le code : elles ne changent pas, et une icône ne se range pas dans
Firestore. Seul `categorieId` est stocké.

- Lire : membre actif.
- Créer : membre actif, `statut = enAttente`, `nbConfirmations = 0`.
- Modifier le contenu : l'auteur, tant que le statut est `enAttente`.
- Changer le statut : **l'admin uniquement**.
- Supprimer : l'auteur (si `enAttente`) ou l'admin.

#### `.../signalements/{id}/confirmations/{uid}` (« moi aussi »)

| Champ | Type |
|---|---|
| `date` | timestamp |

L'identifiant du document est l'`uid` de la personne : une seule
confirmation chacun. On ne peut pas confirmer son propre signalement. On
écrit **dans le même `WriteBatch`** la fiche `confirmations/{monUid}` et
`nbConfirmations + 1` : les règles refusent l'un sans l'autre.

## 6. Module 4 · Événements et sondages

Proposition pour la branche `feature/module4-evenements` (hamza).

### `quartiers/{q}/evenements/{evenementId}`

| Champ Dart (`Evenement`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `titre`, `description`, `lieu` | pareil | string | |
| `date` | `date` | timestamp | |
| `organisateur` (nom) | `organisateurId` + `organisateurNom` | string | |
| `participants` | `nbParticipants` | int | Compteur protégé (règle n°4) |

#### `.../evenements/{id}/participants/{uid}`

| Champ | Type |
|---|---|
| `nom` | string |
| `date` | timestamp |

Participer = créer sa fiche **et** `nbParticipants + 1` dans le même
`WriteBatch`. Se retirer = supprimer sa fiche **et** `nbParticipants − 1`.
Modifier ou supprimer l'événement : l'organisateur (ou l'admin pour supprimer).

### `quartiers/{q}/sondages/{sondageId}`

| Champ Dart (`Sondage`) | Champ Firestore | Type | Remarque |
|---|---|---|---|
| `question` | `question` | string | |
| `options` (`List<OptionSondage>`) | `options` | array de string | Seulement les textes |
| `OptionSondage.votes` | **non stocké** | | `count()` sur `votes` où `choix == i` |
| `dateFin` | `dateFin` | timestamp | Plus de vote après cette date (vérifié) |
| `proposePar` (nom) | `proposeParId` + `proposeParNom` | string | |
| `nombreMembres` | **non stocké** | | `count()` des membres actifs (comme `nbMembres`) |

#### `.../sondages/{id}/votes/{uid}`

| Champ | Type | Remarque |
|---|---|---|
| `choix` | int | Index de l'option (0, 1, 2...) |
| `date` | timestamp | |

Un seul vote par membre, définitif. Pourquoi pas de compteur ici ? Un
sondage s'affiche seul sur son écran : quelques `count()` suffisent, et les
règles restent très simples.

## 7. Index à créer

Firestore crée tout seul les index sur **un** champ. Il faut créer un index
*composite* quand une requête filtre sur un champ **et** trie sur un autre.
Si l'index manque, l'erreur affiche un lien qui le crée en un clic.

| Collection | Champs | Utilisé pour |
|---|---|---|
| `utilisateurs` | `quartierId` ↑, `statut` ↑, `dateDemande` ↓ | Admin : demandes en attente, les plus récentes d'abord |
| `demandes` | `demandeurId` ↑, `dateDemande` ↓ | M2 : mes demandes envoyées |
| `demandes` | `auteurServiceId` ↑, `dateDemande` ↓ | M2 : demandes reçues |
| `services` | `categorie` ↑, `datePublication` ↓ | M2 : filtre par catégorie |
| `services` | `estCommun` ↑, `datePublication` ↓ | M2 : services communs |
| `creneaux` | `serviceId` ↑, `date` ↑ | M2 : créneaux d'un service |
| `evaluations` | `evalueId` ↑, `date` ↓ | M2 : avis reçus par un voisin |
| `signalements` | `statut` ↑, `date` ↓ | M3 : filtre par statut |

Ces index seront écrits dans `firestore.indexes.json` à la phase 6.

## 8. Démarrage : créer le premier quartier et le premier admin

Les règles interdisent de créer un quartier ou de se nommer admin depuis
l'application (sinon n'importe qui pourrait le faire). La toute première
fois, on le fait **à la main dans la console Firebase**, qui n'est pas
soumise aux règles. À faire une seule fois.

**Étape 1 : créer le quartier et son code.**
Console Firebase → *Firestore Database* → *Démarrer une collection* :
- collection `quartiers`, ID automatique, champs
  `nom` (string) = `Résidence El Yasmine`,
  `localisation` (string) = `Ennasr 2, Ariana`.
  Noter l'ID généré.
- collection `codesQuartier`, ID du document = `YAS72B`, champs
  `quartierId` (string) = l'ID noté, `quartierNom` (string) = `Résidence El Yasmine`.

**Étape 2 : créer son compte dans l'application.**
S'inscrire, valider l'e-mail, puis entrer le code `YAS72B`. Le compte est
`enAttente`. (Possible à partir de la phase 5, quand les écrans utilisent Firebase.)

**Étape 3 : se nommer admin.**
Console → `utilisateurs` → le document de son compte → modifier
`statut` = `actif` et `role` = `admin`. Relancer l'application. Cet admin
valide ensuite tous les autres voisins depuis l'écran « Membres du quartier ».

## 9. Hors ligne

- **Firestore** garde déjà en cache les documents lus : une liste déjà
  ouverte s'affiche sans réseau.
- **Hive** (phase 4, demandé par le professeur) garde l'utilisateur
  connecté. Ainsi `getUtilisateurConnecte()` répond **tout de suite**, sans
  attendre le réseau, et ne lève jamais d'exception. Le cache s'affiche
  d'abord, puis Firestore le met à jour en arrière-plan.
- Les `count()` / `average()` demandent le réseau. Hors ligne, on affiche
  la dernière valeur connue.
