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
- **agir** : « Voir sur la carte » (application de cartes du téléphone),
  « Appeler » le numéro utile (STEG, SONEDE, Protection civile) ;
- l'**admin** du quartier fait avancer le statut : en attente → en cours →
  résolu (ou refusé).

Le module écrit dans `quartiers/{q}/signalements` et sa sous-collection
`confirmations`. Il lit l'utilisateur connecté du module 1
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
| Changer le statut | ❌ | ❌ | ✅ |

Les mêmes règles sont vérifiées **deux fois** : dans l'app (méthodes
`static refus...` de `SignalementRepository`, messages en français) et par
le serveur (`firestore.rules`).

## 3. Les écrans (`lib/screens/module3/`)

| Écran | Fichier | Contenu |
|---|---|---|
| Liste (onglet Signalements) | `signalements_screen.dart` | Tous / Mes signalements, filtres statut et catégorie, tri « Plus récents / Plus urgents », badges statut et urgence, chargement / vide / erreur, tirer pour actualiser, bandeau « Hors ligne — dernière mise à jour à HH:mm », cartes « En attente d'envoi » (Réessayer / Annuler), bouton « + Signaler » |
| Création / modification | `create_signalement_screen.dart` | Grille des catégories, titre, description, case danger, photo (aperçu, Changer, Retirer), lieu + « Utiliser ma position », brouillon proposé à la réouverture |
| Détail | `signalement_detail_screen.dart` | Toutes les infos, score d'urgence, photo (miniature, plein écran), « Voir sur la carte », numéro utile + « Appeler », « Sa7, ena zeda », Modifier / Supprimer (auteur), statut (admin) |
| Petits widgets | `widgets_module3.dart` | Badge d'urgence, pastille de catégorie, étiquette Danger, bandeau, photo plein écran, messages |

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
| `services/signalement_repository.dart` | Contrat + règles métier pures (catégories, validation, droits, urgence, numéros utiles) |
| `services/firebase_signalement_repository.dart` | Firestore, conforme aux règles (confirmer = `WriteBatch` fiche + `FieldValue.increment(1)`) |
| `services/sync_signalements_m3.dart` | Publier, file d'envoi, lecture avec cache, brouillon |
| `services/base_locale_m3.dart` | SQLite (SQL écrit à la main) |
| `services/connexion_m3.dart` | Réseau présent ? |
| `services/adresse_m3.dart` | Adresse à partir du GPS (Nominatim) |
| `services/photos_m3.dart` | Photo : choix, copie locale, envoi Cloudinary, miniatures |
| `services/liens_m3.dart` | Ouvrir l'application de cartes, appeler un numéro |

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

### Voir sur la carte

Lien `geo:` (Google Maps, OsmAnd...) avec un repère nommé ; sinon
OpenStreetMap dans le navigateur (`url_launcher`).

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
| M1 | Utilisateur connecté (quartier, rôle admin), `Localisation.positionActuelle()` et `PointGps` (import seulement), lien « Mes signalements » du Profil |
| M4 | Même compte Cloudinary (preset différent), mêmes versions de paquets (`http`, `image_picker`, `sqflite`) ; bases SQLite séparées (`houmani_m3.db` / `houmani_m4.db`) |
| Commun | Onglet `/signalements` du routeur (paramètres `onglet` et `action`), « Nouveau signalement » du menu, envoi de la file depuis l'Accueil et `main.dart` |

## 7. Tests

| Fichier | Tests | Contenu |
|---|---:|---|
| `test/module3_signalements_test.dart` | 41 | Modèle, règles métier, urgence, repository (mock), écrans liste / création / détail |
| `test/module3_sqflite_test.dart` | 30 | SQL des tables, file d'envoi, cache, écrans hors ligne |
| `test/module3_adresse_test.dart` | 23 | Nominatim (faux client HTTP), migration 1 → 3, GPS dans les écrans, carte |
| `test/module3_photos_test.dart` | 33 | Cloudinary (faux client), fichiers locaux, envoi sans doublon, appels simultanés, écrans photo |
| `test/module3_numeros_test.dart` | 10 | Numéros utiles, « Appeler » |
| `test/widget_test.dart` | 2 (M3) | Profil → Mes signalements, menu → Nouveau signalement |
| `test_regles/regles_m3.test.js` | 27 | Règles Firestore sur l'émulateur |

Aucun test ne touche Firebase, Internet ni le GPS : mocks et faux services
(SQLite en mémoire avec `sqflite_common_ffi`). Les fichiers M3 n'importent
pas `main.dart` : ils compilent même sans `lib/firebase_options.dart`.

```
flutter test test/module3_signalements_test.dart test/module3_sqflite_test.dart test/module3_adresse_test.dart test/module3_photos_test.dart test/module3_numeros_test.dart
```

## 8. Limites connues

- Règles et index : prêts dans le dépôt, à déployer une fois (voir
  [`module3_regles_a_deployer.md`](module3_regles_a_deployer.md)) ; sans
  l'index, « Mes signalements » montre le cache du téléphone (ou un
  message d'erreur s'il est vide).
- `connectivity_plus` sait si une interface réseau est active, pas si
  Internet répond : d'où un délai maximum sur chaque appel.
- Un signalement envoyé plus tard prend la date de l'envoi.
- Supprimer un signalement ne supprime ni ses confirmations (règle) ni sa
  photo sur Cloudinary (clé secrète interdite dans l'app).
- Un preset Cloudinary non signé est public : limité par le preset
  (format, taille, pas d'écrasement).

## 9. Pour plus tard

- **Anti-doublon** : même catégorie, à moins de 100 m, dans les dernières
  24 h → proposer « Sa7, ena zeda » au lieu d'un nouveau signalement.
- **Carte des signalements** du quartier.
- **Historique des statuts** avec une note de l'admin, photo « après »
  à la résolution.
- **Notifications** à l'auteur quand le statut change.
- **Statistiques** pour l'admin (par catégorie, délai moyen de résolution).
