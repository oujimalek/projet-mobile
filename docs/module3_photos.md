# M3 · Signalements : la photo

Un signalement peut avoir **une photo** (appareil photo ou galerie). Elle est
hébergée sur **Cloudinary** (offre gratuite, compte de l'équipe, comme les
photos du module 4) ; Firestore ne garde que son adresse `https`.

Pourquoi pas Firebase Storage : il demande le plan payant Blaze.

## 1. Réglage du preset Cloudinary (une seule fois, console Cloudinary)

Settings → Upload → Upload presets → **Add upload preset** :

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Upload preset name | `houmani_signalements` | Le nom utilisé par l'app (`PhotosM3.preset`) |
| Signing mode | **Unsigned** | L'app n'a aucune clé secrète (dépôt public) |
| Folder | `houmani/signalements` | Séparé des photos du module 4 (`houmani/evenements`) |
| Use filename / Unique filename | non / **oui** | Cloudinary choisit un nom unique |
| Overwrite | **non** | Impossible d'écraser une photo existante |
| Allowed formats | `jpg, png, webp, heic` | Seulement des images |
| Max file size | 5 Mo | Même limite que l'app (`PhotosM3.tailleMax`) |

L'app n'envoie **que** `upload_preset` et le fichier : **jamais** de
`public_id`, de clé (`api_key`) ni de signature (vérifié par les tests).

## 2. Le parcours d'une photo

```
image_picker (1600 px max, qualité 80)
   │  photo choisie (cache d'image_picker, peut être vidé par Android)
   ▼
PhotosM3.garderSurTelephone   → copie dans <dossier de l'app>/photos_m3/
   │  (refusée si plus de 5 Mo)
   ▼
Brouillon SQLite (photo_locale)  ← l'écran est quitté : la photo reste
   ▼
Publier (SyncSignalementsM3.publier)
   ├─ hors ligne → file d'envoi SQLite (photo_locale), rien n'est envoyé
   └─ en ligne   → 1. Cloudinary (adresse https)
                   2. Firestore (photoUrl = cette adresse)
                   3. la copie locale est supprimée
```

- **La photo d'abord, puis le signalement** : Firestore ne garde que
  l'adresse, il faut donc l'avoir.
- **Jamais envoyée deux fois** : si Cloudinary a répondu mais que
  Firestore échoue, l'adresse est notée dans la file
  (`envois_en_attente.photo_url`, version 3 de la base) ; le prochain essai
  ne renvoie que le signalement.
- **Réseau / refus** : Cloudinary injoignable → le signalement va dans la
  file ; photo refusée (preset, format) → message à l'écran.
- **Photo disparue du téléphone** avant l'envoi : le signalement part sans
  photo (le problème signalé compte plus que l'image).

## 3. Ménage des fichiers locaux

| Moment | Ce qui est supprimé |
|---|---|
| Signalement envoyé | La copie locale |
| « Annuler » un envoi en attente | Sa photo |
| « Retirer la photo » / « Changer » | L'ancienne copie |
| Brouillon jeté, ou remplacé par un autre avec une autre photo | Sa photo |
| Démarrage (`SyncSignalementsM3.demarrer`) | Les photos de `photos_m3/` que ni un brouillon ni la file n'utilisent (une requête SQL `UNION`) |

## 4. Affichage

- **Miniature** : l'app ne télécharge pas la photo originale pour la
  carte du détail ; elle demande à Cloudinary une version recadrée et
  légère, en ajoutant une transformation dans l'adresse :
  `.../image/upload/c_fill,w_800,h_450,q_auto,f_auto/v.../photo.jpg`
  (`q_auto,f_auto` : qualité et format WebP/AVIF choisis par Cloudinary).
- **Plein écran** (toucher la photo) : l'originale, avec zoom.
- Hors ligne ou photo introuvable : un cadre « Photo indisponible ».
- Liste : une petite icône 📷 sur les signalements avec photo.

## 5. Modifier ou retirer la photo

L'auteur (tant que le signalement est en attente) peut **changer** la photo
(la nouvelle est envoyée puis son adresse enregistrée) ou la **retirer**
(`photoUrl` est effacé du document avec `FieldValue.delete()`). La règle
Firestore correspondante est dans `docs/module3_regles_a_deployer.md`.

## 6. Sécurité et limites

- La règle Firestore n'accepte que des adresses qui commencent par
  `https://res.cloudinary.com/pu3lxdrf/` (notre compte) ; l'app vérifie la
  même chose (`SignalementRepository.refusPhoto`).
- Un preset « unsigned » est public : quelqu'un qui le connaît peut envoyer
  une image dans notre dossier. Les limites du preset (format, taille, pas
  d'écrasement) réduisent ce risque ; c'est le compromis accepté par
  l'équipe (même choix que le module 4).
- Supprimer un signalement **ne supprime pas** la photo sur Cloudinary :
  il faudrait la clé secrète, qui ne doit jamais être dans l'application.

## 7. Tests (`test/module3_photos_test.dart`)

- Adresses valides, miniature ;
- envoi (faux client HTTP) : requête non signée sans `public_id`, photo
  trop lourde refusée avant l'envoi, refus 400, adresse d'un autre compte,
  réponse illisible, pas de réseau, délai dépassé ;
- fichiers : copie, 5 Mo, fichier disparu, ménage des photos orphelines ;
- publication en ligne / hors ligne, Cloudinary ou Firestore injoignable,
  photo jamais envoyée deux fois, « Annuler », brouillons ;
- écrans : galerie → aperçu → publier, appareil photo refusé, photo trop
  lourde, annulation, carte d'attente avec 📷, brouillon repris, retirer
  ou changer la photo en modification, miniature et plein écran du détail.
