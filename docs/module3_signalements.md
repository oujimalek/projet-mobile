# Module 3 · Signalements

Branche : `feature/module3-signalements` (malouka).
Format des données : [`schema_firestore.md`](schema_firestore.md) §5.
Règles de sécurité : [`firestore.rules`](../firestore.rules), partie « M3 »,
et [`module3_regles_a_deployer.md`](module3_regles_a_deployer.md).

## 1. Ce que fait le module

Les voisins d'une même houma **signalent les problèmes du quotidien**
(coupure d'électricité, fuite d'eau, ordures, travaux, incident) :

- **signaler** : catégorie, titre, description, lieu, case « Danger pour
  les personnes », **photo** (appareil photo ou galerie) et **position GPS**
  avec l'adresse trouvée automatiquement ;
- **confirmer** le signalement d'un voisin : « **Sa7, ena zeda** » (moi
  aussi), une fois par personne ;
- **suivre** : liste filtrée par statut et catégorie, triée par date ou par
  **urgence**, onglet « Mes signalements » ;
- **marcher hors ligne** : brouillon automatique, signalements envoyés au
  retour du réseau, liste et détail lisibles sans Internet ;
- **voir sur une carte** tous les signalements du quartier (repères par
  catégorie, urgents mis en avant) ;
- **éviter les doublons** : avant de publier, l'app propose de confirmer un
  signalement identique tout proche ;
- **agir** : « Partager » (WhatsApp, SMS...), « Appeler » le numéro utile
  (STEG, SONEDE, Protection civile), ouvrir le point dans l'application de
  cartes du téléphone ;
- l'**admin** du quartier fait avancer le statut : en attente → en cours →
  résolu (ou refusé), avec une **note** ; chaque étape reste dans
  l'**historique** du signalement ;
- un **leader ou l'admin** **organise un événement** (nettoyage, réunion)
  à partir d'un signalement d'ordures ou de travaux (D3, avec le module 4).

Le module écrit dans `quartiers/{q}/signalements` et ses sous-collections
`confirmations` et `historique`. Il lit l'utilisateur connecté du module 1
(`UtilisateurRepository().getUtilisateurConnecte()`).

## 2. Qui peut faire quoi

Seul un membre **actif** du quartier voit le module.

| Action | Membre | Auteur | Admin |
|---|:-:|:-:|:-:|
| Voir les signalements du quartier, filtrer, trier | ✅ | ✅ | ✅ |
| Créer un signalement | ✅ | — | ✅ |
| Modifier (texte, danger, position, photo) | ❌ | ✅ tant qu'il est **en attente** | ❌ (sauf les siens) |
| Supprimer | ❌ | ✅ tant qu'il est **en attente** | ✅ (tous) |
| « Sa7, ena zeda » (une fois) | ✅ | ❌ (pas le sien) | ✅ |
| … sur un signalement **résolu ou refusé** | ❌ | ❌ | ❌ |
| Changer le statut (avec une note ; obligatoire pour refuser) | ❌ | ❌ | ✅ |
| Voir l'historique, la carte, partager, appeler | ✅ | ✅ | ✅ |
| Organiser un événement (ordures, travaux ouverts) | ❌ (sauf leader) | ❌ (sauf leader) | ✅ |

Les mêmes règles sont vérifiées **deux fois** : dans l'app (méthodes
`static refus...` de `SignalementRepository`, messages en français) et par
le serveur (`firestore.rules`).

## 3. Les écrans (`lib/screens/module3/`)

| Écran | Fichier | Contenu |
|---|---|---|
| Liste (onglet Signalements) | `signalements_screen.dart` | Tous / Mes signalements, filtres statut et catégorie, tri « Plus récents / Plus urgents », badges statut et urgence, chargement / vide / erreur, tirer pour actualiser, bandeau « Hors ligne — dernière mise à jour à HH:mm », cartes « En attente d'envoi » (Réessayer / Annuler), icône carte, bouton « + Signaler » |
| Création / modification | `create_signalement_screen.dart` | Grille des catégories, titre, description, case danger, photo (aperçu, Changer, Retirer), lieu + « Utiliser ma position », brouillon proposé à la réouverture, question anti-doublon avant de publier |
| Détail | `signalement_detail_screen.dart` | Toutes les infos, score d'urgence, photo (miniature, plein écran), « Voir sur la carte » (carte de l'app) + « Application de cartes », « Partager », numéro utile + « Appeler », « Sa7, ena zeda », Modifier / Supprimer (auteur), statut avec note (admin), frise de l'historique |
| Carte | `carte_signalements_screen.dart` | Repères par catégorie (urgents plus grands, bord rouge), contour du quartier, mêmes filtres que la liste, fiche au toucher puis détail, cache hors ligne |
| Petits widgets | `widgets_module3.dart` | Filtres statut / catégorie (liste et carte), badge d'urgence, pastille de catégorie, étiquette Danger, bandeau, photo plein écran, texte partagé, messages |

Depuis les autres modules : Profil → « Mes signalements »
(`/signalements?onglet=mes`), menu latéral → « Nouveau signalement »
(`/signalements?action=nouveau`), raccourci « Signaler » de l'Accueil.

## 4. Architecture

```
Écrans (lib/screens/module3/)
   │
   ▼
SyncSignalementsM3                 en ligne ou hors ligne ? (le « chef d'orchestre »)
   ├── ConnexionM3                 réseau présent ? (connectivity_plus)
   ├── SignalementRepository       le CONTRAT (classe abstraite, Resultat<T>)
   │      ├── FirebaseSignalementRepository → Cloud Firestore
   │      └── MockSignalementRepository     → test/ (données fictives)
   ├── BaseLocaleM3                SQLite : brouillons, file d'envoi, cache
   ├── PhotosM3                    image_picker + Cloudinary
   └── (AdresseM3, LiensM3)        Nominatim ; cartes et téléphone
```

| Fichier (`lib/data/`) | Rôle |
|---|---|
| `models/signalement.dart` | `Signalement` (`toMap` / `fromMap` écrits à la main), `StatutSignalement`, `NiveauUrgence`, `CategorieSignalement` |
| `models/historique_signalement.dart` | `EntreeHistorique` : une étape (statut, note, date, qui) |
| `services/signalement_repository.dart` | Contrat + règles métier pures (catégories, validation, droits, urgence, numéros utiles, note de l'admin, distance et anti-doublon) |
| `services/firebase_signalement_repository.dart` | Firestore, conforme aux règles : confirmer = `WriteBatch` fiche + `FieldValue.increment(1)` ; créer et changer le statut = `WriteBatch` avec l'étape d'historique ; nombre de mes signalements = `count()` |
| `services/sync_signalements_m3.dart` | Publier, file d'envoi, lecture avec cache, brouillon, anti-doublon, nombre de mes signalements |
| `services/base_locale_m3.dart` | SQLite (SQL écrit à la main) |
| `services/connexion_m3.dart` | Réseau présent ? |
| `services/adresse_m3.dart` | Adresse à partir du GPS (Nominatim) |
| `services/photos_m3.dart` | Photo : choix, copie locale, envoi Cloudinary, miniatures |
| `services/liens_m3.dart` | Ouvrir l'application de cartes, appeler un numéro, partager (`share_plus`) |

Style du cours : `StatefulWidget` + `setState`, booléen `_enChargement`,
`if (!mounted) return;` après chaque `await`, `SnackBar` pour les erreurs,
pas de Provider ni de génération de code. Chaque service externe est
**remplaçable dans les tests** (même modèle que
`Localisation.positionActuelle` du module 1).

## 5. Fonctionnalités réalisées

### Urgence (calculée, jamais stockée)

`SignalementRepository.scoreUrgence` :

| Élément | Points |
|---|---|
| Catégorie incident, électricité, eau | 2 |
| Catégorie travaux, ordures | 1 |
| Danger pour les personnes | + 2 |
| 10 confirmations ou plus / 3 ou plus | + 2 / + 1 |

Score 0-1 : **faible** (vert), 2-3 : **normal** (orange), 4 et plus :
**urgent** (rouge). Tri « Plus urgents » : score, puis date.

### Hors ligne avec SQFlite

Détails et justification face au cache de Firestore :
[`module3_sqflite.md`](module3_sqflite.md).

- **Brouillon** enregistré 1 s après la dernière frappe et en quittant
  l'écran, proposé à la réouverture.
- **File d'envoi visible** : on vérifie le réseau AVANT d'écrire (hors
  ligne, `await add()` ne se termine jamais) ; le signalement part tout
  seul au retour du réseau, au démarrage et à l'Accueil ; Réessayer /
  Annuler ; arrêt automatique après 3 échecs. L'id du document est choisi
  sur le téléphone : un renvoi ne crée **jamais de doublon**.
- **Cache** des signalements du quartier, relu avec les mêmes filtres en
  **SQL**.
- **3 versions de la base, avec migrations** (`onUpgrade`, sans perte de
  données) : 1 (brouillons, file, cache) → 2 (GPS + cache des adresses)
  → 3 (adresse de la photo déjà envoyée).

### GPS et adresse (service web Nominatim)

« Utiliser ma position » : GPS du module 1, puis l'adresse via l'API
gratuite **Nominatim** d'OpenStreetMap (`http`, User-Agent
`tn.esprit.houmani`, 1 requête par seconde, 10 s maximum). Les réponses
sont gardées en **cache SQLite** (point arrondi à ~11 m). Hors ligne : le
point est gardé, l'utilisateur écrit le lieu.

### Photo (Cloudinary)

Envoi non signé (preset `houmani_signalements`, dossier
`houmani/signalements`), 5 Mo maximum, jamais de `public_id` ; miniatures
recadrées par Cloudinary ; la photo attend dans le dossier de
l'application si le signalement part plus tard, et n'est jamais envoyée
deux fois. Détails : [`module3_photos.md`](module3_photos.md).

### Carte des signalements

`carte_signalements_screen.dart` (`flutter_map`). Le fond OpenStreetMap,
l'attribution et le contour rouge du quartier viennent du module 1
(`carte_quartier.dart`, **import seulement**).

- Un repère par signalement qui a un point GPS, de la couleur de sa
  catégorie ; les **urgents** sont plus grands, avec un bord rouge, et
  dessinés au-dessus.
- Les **mêmes filtres** que la liste (le même widget) ; ouverte depuis la
  liste, elle reprend ses filtres.
- Toucher un repère : une petite fiche (statut, urgence), puis le détail.
- Caméra : le contour du quartier et tous les repères visibles ; depuis le
  détail (« Voir sur la carte »), centrée sur CE signalement, fiche ouverte.
- Hors ligne : repères lus dans le cache SQLite, avec un message (les
  images du fond ont besoin d'Internet).
- Dans le détail, « Application de cartes » ouvre aussi le point dans
  Google Maps / OsmAnd (lien `geo:`), sinon OpenStreetMap dans le
  navigateur (`url_launcher`).

### Anti-doublon

Avant de publier un **nouveau** signalement avec un point GPS, l'app
cherche un signalement **ouvert** (en attente ou en cours) de la **même
catégorie**, créé dans les **24 dernières heures**, à **100 m** au plus
(distance de **haversine**, fonction pure testée). Les candidats viennent du
**cache SQLite** rempli par la liste : aucune requête Firestore, aucun
nouvel index, et ça marche hors ligne.

« Un signalement similaire existe à 33 m : « … ». C'est le même problème ? »

- **Oui, Sa7 ena zeda** : le signalement existant est confirmé (ou
  simplement ouvert si c'est le mien), et son détail remplace le
  formulaire ; rien n'est publié, le brouillon est supprimé.
- **Non, publier quand même** : publication normale.
- Sans point GPS : pas de vérification.

### Historique des statuts et note de l'admin

Sous-collection `historique` : une étape `{ statut, note, date, parId,
parNom }` par changement.

- La **1re étape** (« en attente », par l'auteur) est écrite dans le
  **même `WriteBatch`** que la création (aussi depuis la file d'envoi).
- L'admin change le statut dans une fenêtre avec une **note** (optionnelle,
  **obligatoire pour refuser**, 3 à 200 caractères) : statut et étape dans
  le même `WriteBatch`.
- Le détail affiche une **frise verticale** (statut, date, qui, note). Un
  signalement créé avant l'historique commence par sa création, refaite à
  partir du signalement.
- Hors ligne : message (l'historique est lu en ligne).
- Les règles n'acceptent une étape que pendant une création ou un vrai
  changement de statut par l'admin ; une étape n'est jamais modifiée.

### Organiser un événement depuis un signalement (D3, avec le module 4)

Proposé par le module 4, sur le modèle du lien événement → service commun
(D4). Pour les problèmes qu'on règle **ensemble** :

| Catégorie du signalement | Événement proposé | Titre |
|---|---|---|
| Ordures | Nettoyage | « Nettoyage : titre du signalement » |
| Travaux | Réunion | « Réunion : titre du signalement » |

- Bouton « **Organiser un événement** » du détail : seulement pour un
  **leader ou l'admin** (comme la règle `organisateurDe` du module 4), un
  signalement **ouvert** (en attente ou en cours), catégorie ordures ou
  travaux ; caché hors ligne. Les règles sont des fonctions pures testées
  (`SignalementRepository.peutOrganiserEvenement`,
  `categorieEvenementPour`, `titreEvenementPour` : titre raccourci à 80
  caractères, la limite du module 4).
- Il ouvre le **formulaire du module 4** pré-rempli : type, titre, lieu,
  point GPS, et le lien (`signalementId` / `signalementTitre` dans
  l'événement). Après la publication, la section ci-dessous se met à jour.
- Section « **Événement organisé** » : date, titre, nombre de participants
  (et « Annulé ») ; toucher ouvre l'événement. Elle est lue avec
  `EvenementRepository.getEvenementsDuSignalement` (un seul filtre
  d'égalité, pas d'index) ; hors ligne ou en erreur, elle est simplement
  cachée.
- **Conseil à l'admin** : si un événement lié a eu lieu (et n'est pas
  annulé) et que le signalement est encore ouvert : « L'événement a eu
  lieu — marquer comme résolu ? » → la même fenêtre de statut (avec note).
- Côté module 4 : ligne « **Suite au signalement** » dans le détail de
  l'événement, qui ouvre le signalement. Le lien ne change plus après la
  création (la règle de modification d'un événement ne l'accepte pas) ;
  aucune règle Firestore n'a été modifiée pour D3.

### Partager

Icône « Partager » du détail (`share_plus`, même version que le module 4) :
titre, catégorie, statut, lieu, et le lien OpenStreetMap s'il y a un point
GPS. Marche aussi hors ligne.

### Numéros utiles

Une seule constante, `SignalementRepository.numerosUtiles` :

| Catégorie | Numéro |
|---|---|
| Électricité | STEG – urgences, 80 100 444 |
| Eau | SONEDE – numéro vert, 80 100 319 |
| Incident | Protection civile, 198 |
| Travaux, ordures | pas de bouton (pas de numéro national unique) |

« Appeler » ouvre le clavier du téléphone (`tel:`), aussi hors ligne.

## 6. Points de contact avec les autres modules

| Module | Ce que M3 utilise / change |
|---|---|
| M1 | Utilisateur connecté (quartier, rôle admin), `Localisation.positionActuelle()`, `PointGps`, le quartier et son contour, `fondOpenStreetMap` / `contourRouge` / `attributionOpenStreetMap` (import seulement) ; dans le Profil : lien « Mes signalements » et statistique « Signalements » (comptée par M3) |
| M4 | (D3) Le détail d'un signalement ouvre le formulaire d'événement pré-rempli et liste les événements liés ; le détail d'un événement ouvre le signalement (« Suite au signalement ») ; `EvenementRepository.peutOrganiser` réutilisé. Même compte Cloudinary (preset différent), mêmes versions de paquets (`http`, `image_picker`, `sqflite`, `share_plus`) ; bases SQLite séparées (`houmani_m3.db` / `houmani_m4.db`) |
| Commun | Onglet `/signalements` du routeur (paramètres `onglet` et `action`), « Nouveau signalement » du menu, envoi de la file depuis l'Accueil et `main.dart` |

## 7. Tests

| Fichier | Tests | Contenu |
|---|---:|---|
| `test/module3_signalements_test.dart` | 41 | Modèle, règles métier, urgence, repository (mock), écrans liste / création / détail |
| `test/module3_sqflite_test.dart` | 33 | SQL des tables, file d'envoi, cache, écrans hors ligne, nombre de mes signalements |
| `test/module3_adresse_test.dart` | 23 | Nominatim (faux client HTTP), migration 1 → 3, GPS dans les écrans, application de cartes |
| `test/module3_photos_test.dart` | 33 | Cloudinary (faux client), fichiers locaux, envoi sans doublon, appels simultanés, écrans photo |
| `test/module3_numeros_test.dart` | 10 | Numéros utiles, « Appeler » |
| `test/module3_partage_test.dart` | 9 | Texte partagé (français / derja, lien carte), bouton, hors ligne, mode sombre |
| `test/module3_carte_test.dart` | 13 | Repères, urgents, filtres, fiche, centrage, hors ligne, erreur, mode sombre |
| `test/module3_doublon_test.dart` | 18 | Haversine, règle des 100 m / 24 h, cache, toutes les réponses de la fenêtre |
| `test/module3_historique_test.dart` | 15 | Étapes, note obligatoire pour refuser, frise, ancien signalement, hors ligne |
| `test/module3_d3_test.dart` | 20 | (D3) Modèle et dépôt M4, formulaire pré-rempli, ligne « Suite au signalement », visibilité du bouton (rôle, catégorie, statut), correspondances, section, conseil à l'admin |
| `test/widget_test.dart` | 3 (M3) | Profil → Mes signalements et statistique, menu → Nouveau signalement |
| `test_regles/regles_m3.test.js` | 38 | Règles Firestore sur l'émulateur (dont l'historique) |

Aucun test ne touche Firebase, Internet ni le GPS : mocks et faux services
(SQLite en mémoire avec `sqflite_common_ffi`, faux réseau, faux GPS, fond
de carte remplacé). Les fichiers M3 n'importent pas `main.dart` : ils
compilent même sans `lib/firebase_options.dart`.

```
flutter test test/module3_signalements_test.dart test/module3_sqflite_test.dart test/module3_adresse_test.dart test/module3_photos_test.dart test/module3_numeros_test.dart test/module3_partage_test.dart test/module3_carte_test.dart test/module3_doublon_test.dart test/module3_historique_test.dart test/module3_d3_test.dart
```

## 8. Limites connues

- Règles et index : prêts dans le dépôt, à déployer **avant** d'utiliser une
  version de l'app qui contient l'historique (sinon la création est
  refusée) ; voir [`module3_regles_a_deployer.md`](module3_regles_a_deployer.md).
  Sans l'index, « Mes signalements » montre le cache du téléphone (ou un
  message d'erreur s'il est vide).
- L'anti-doublon ne voit que les signalements déjà chargés sur le téléphone
  (cache) : un signalement publié par un voisin depuis le dernier
  chargement n'est pas vu.
- L'historique et la carte (images) demandent Internet.
- `connectivity_plus` sait si une interface réseau est active, pas si
  Internet répond : d'où un délai maximum sur chaque appel.
- Un signalement envoyé plus tard prend la date de l'envoi.
- Supprimer un signalement ne supprime ni ses confirmations ni son
  historique (règles) ni sa photo sur Cloudinary (clé secrète interdite
  dans l'app).
- Un preset Cloudinary non signé est public : limité par le preset
  (format, taille, pas d'écrasement).

## 9. Pour plus tard

- **Notifications** à l'auteur quand le statut change.
- Photo « après » à la résolution.
- **Statistiques** pour l'admin (par catégorie, délai moyen de résolution).
