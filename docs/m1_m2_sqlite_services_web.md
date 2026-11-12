# M1 et M2 — SQLite et services web externes

Firestore reste la source de vérité partagée. SQLite (`sqflite`) garde sur
le téléphone ce qui est **personnel** ou doit marcher **hors ligne**.
Aucune erreur locale ne bloque l'application : chaque méthode attrape les
exceptions et renvoie une valeur vide.

## M1 — Utilisateurs (`houmani_m1.db`, `lib/data/services/cache_local.dart`)

| Table | Contenu | Utilisé par |
|---|---|---|
| `profil` | Le dernier profil connu | Démarrage hors ligne |
| `quartier`, `quartier_points` | Le quartier et son contour GPS | Carte, centre du quartier |
| `voisins`, `voisin_competences` | L'annuaire (une ligne par compétence) | Annuaire hors ligne ; compétences du quartier (`JOIN` + `COUNT` + `GROUP BY`) |
| `preferences` (clé, valeur) | Langue, thème, dernière météo | Paramètres, Accueil |
| `historique_connexions` | Les dernières connexions | Paramètres → « Dernières connexions » |

### Service web : Open-Meteo (`meteo_m1.dart`)

`GET https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto`

Gratuit, sans clé. Carte « météo » sur l'Accueil, au centre du quartier,
avec un conseil de voisinage (pluie → penser aux voisins âgés, forte
chaleur → prendre des nouvelles des voisins seuls…).

1. Cache SQLite de moins de 30 min au même endroit → aucune requête.
2. Sinon requête HTTP (8 s max) → mise en cache.
3. Échec réseau → la dernière météo gardée, marquée « Hors ligne · relevé à … ».

### Service web : Nominatim / OpenStreetMap (`verification_adresse_m1.dart`)

`GET https://nominatim.openstreetmap.org/search?q=…&format=jsonv2&countrycodes=tn&limit=1&viewbox=…`

Gratuit, sans clé. À l'inscription (« Rejoindre un quartier »), le résident
peut donner son adresse (facultatif, 5 à 150 caractères, champ `adresse`
de Firestore). Dans « Membres » → « En attente », l'admin voit un badge :
**dans la houma**, **hors de la houma · 2,3 km**, **introuvable**, ou
« trace les limites du quartier » (pas de contour). Le point trouvé est
testé avec le contour du quartier ; la distance est mesurée au centre
(formule de haversine).

Politique Nominatim respectée : `User-Agent` de l'application, **1 requête
par seconde au plus**, résultats gardés 30 jours dans la table SQLite
`geocodage` (version 2 de `houmani_m1.db`, ajoutée par `onUpgrade`).
« Introuvable » est aussi gardé ; une erreur réseau n'est jamais gardée.

### IA : « Qui peut m'aider ? » (`trouver_voisin_m1.dart`)

Dans l'annuaire, le résident décrit son besoin (« ma machine à laver
fuit »). L'application envoie au serveur Cloudflare (`push_worker/`, route
`POST /correspondances`) le besoin et la **liste des compétences** de la
houma — **aucun nom ni identifiant**. L'IA (Workers AI, gratuite) choisit au
plus 3 compétences de cette liste avec une phrase d'explication ; le
serveur rejette toute compétence inventée, et l'application retrouve
elle-même les voisins (bouton → numéro à copier).

Sans réseau (ou si l'IA ne répond pas), recherche locale : mots proches
(« plombier » → Plomberie) et petit dictionnaire (« fuite » → plomberie,
« ordinateur » → informatique…). L'écran indique laquelle des deux a répondu.

## M2 — Services (`houmani_m2.db`, `lib/data/services/base_locale_m2.dart`)

| Table | Contenu | Utilisé par |
|---|---|---|
| `favoris` | Services mis de côté (étoile) | Détail (étoile), liste (filtre « Favoris ») |
| `consultations` | Services ouverts (100 dernières) | « Vus récemment » (`GROUP BY` + `MAX`), catégories préférées (`COUNT`) |
| `brouillon_service` | La publication commencée (une ligne par utilisateur) | Formulaire : « Brouillon restauré » |
| `jours_feries` | Cache des jours fériés, par année | Planning des services communs |

Version 2 : `onUpgrade` ajoute `jours_feries`. Version 3 : colonne
`utilisateur_id` dans `favoris`, `consultations` et `brouillon_service`.
Pourquoi : un téléphone peut servir à plusieurs comptes ; chacun ne voit que
ses lignes (`WHERE utilisateur_id = ?`) et les retrouve après reconnexion.
Les anciennes lignes sont données au premier compte connecté après la mise
à jour. `jours_feries` (public) reste partagé.

### Service web : Nager.Date (`jours_feries_m2.dart`)

`GET https://date.nager.at/api/v3/PublicHolidays/{année}/TN`

Gratuit, sans clé. Dans le planning, un jour férié a son numéro en rouge ;
le choisir affiche « Jour férié : Fête de la République » et, s'il y a des
créneaux, « Vérifie que le créneau est bien maintenu ». Une seule requête
par année (cache SQLite), noms traduits de l'anglais au français.

**Limite :** l'API ne donne que les fêtes civiles (dates fixes). Les fêtes
religieuses (Aïd, Mouled…) suivent le calendrier lunaire et n'y figurent pas.

### IA : « Améliorer avec l'IA » (`aide_redaction_m2.dart`)

Sur le formulaire d'un service, un bouton envoie le titre, la description
et la catégorie au serveur Cloudflare (route `POST /ameliorer`). L'IA
réécrit l'annonce en français clair et poli sans rien inventer (titre
≤ 60, description ≤ 400 caractères). La proposition s'affiche dans une
fenêtre : **« Utiliser »** ou **« Garder mon texte »** — rien n'est remplacé
sans accord.

Sans réseau, mise en forme locale : espaces, majuscules en début de
phrase, ponctuation (« Mise en forme proposée »).

## Serveur (`push_worker/`)

Les routes `/ameliorer` et `/correspondances` sont ouvertes à **tout membre
actif du quartier** (jeton Firebase vérifié, profil lu dans Firestore) ;
`/notifier` et `/suggestions` restent réservées aux leaders et à l'admin.
Code IA : `push_worker/src/aide_ia.js`.

## Tests

Réseau remplacé par un `MockClient`, SQLite en mémoire (`sqflite_common_ffi`).

```
flutter test test/cache_local_test.dart test/preference_langue_test.dart test/module2_sqlite_test.dart test/meteo_m1_test.dart test/jours_feries_m2_test.dart test/verification_adresse_m1_test.dart test/trouver_voisin_m1_test.dart test/aide_redaction_m2_test.dart
```
