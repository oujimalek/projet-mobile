# Module 4 · Événements et sondages

Branche : `feature/module4-evenements` (hamza).
Format des données : [`schema_firestore.md`](schema_firestore.md) §6.
Règles de sécurité : [`firestore.rules`](../firestore.rules), parties « M4 ».

## 1. Ce que fait le module

Les voisins d'une même houma :
- **organisent des événements** (fête, réunion, nettoyage, sport, culture...),
  s'y **inscrivent**, posent des questions, disent qui apporte quoi, notent
  l'événement après coup et **pointent leur présence par QR code** ;
- **créent des sondages** et **votent** (vote secret, un vote par membre,
  définitif) ;
- **élisent leur leader** (un seul par houma, élection tous les 6 mois).

Le module écrit dans `quartiers/{q}/evenements`, `sondages`, `elections` et
`demandesElection`. Il lit l'utilisateur connecté du module 1
(`UtilisateurRepository().getUtilisateurConnecte()`).

## 2. Qui peut faire quoi

Seul un membre **actif** du quartier voit le module.

| Action | Membre | Leader | Admin |
|---|:-:|:-:|:-:|
| Voir les événements, les sondages et leurs résultats | ✅ | ✅ | ✅ |
| Voir le **nombre** de participants | ✅ | ✅ | ✅ |
| Voir les **noms** des participants, exporter la liste | ❌ | ✅ (ses événements) | ✅ |
| Créer un événement ou un sondage | ❌ | ✅ | ✅ |
| Créer un événement **officiel** (épinglé) | ❌ | ❌ | ✅ |
| Modifier / annuler un événement | ❌ | ✅ (les siens) | ✅ (tous) |
| Supprimer un événement ou un sondage | ❌ | ✅ (les siens) | ✅ (tous) |
| Afficher le QR de présence | ❌ | ✅ (ses événements) | ✅ |
| Participer, « Peut-être », liste d'attente | ✅ | ✅ | ✅ |
| Voter (1 fois, définitif, avant la fin, secret) | ✅ | ✅ | ✅ |
| Se porter candidat à l'élection | ✅ | ✅ | ❌ |
| Ouvrir une élection, publier les résultats, nommer / retirer un leader | ❌ | ❌ | ✅ |
| Statistiques du module | ❌ | ❌ | ✅ |

### Le rôle Leader

- Rôle du module 1 (`RoleUtilisateur.leader`), à côté de `resident` et `admin`.
- **Un admin pour toute l'application** (l'admin global) et **un leader par
  houma**, élu par les résidents. L'admin global visite les cités (son
  `quartierId` est la cité qu'il regarde) ; il n'habite nulle part et ne
  compte pas dans les membres.
- **Le premier leader** : le premier habitant d'une houma sans leader envoie
  son contrat d'habitation (photo Cloudinary) ; l'admin global le vérifie,
  le valide et le nomme leader (`aUnLeader` = `true` sur le quartier).
- **Élection normale** : au plus tôt 6 mois après la dernière élection
  publiée (avant, le bouton est grisé avec la date possible). 3 jours de
  candidatures puis 2 jours de vote, 1 voix par membre, vote secret. Une
  seule place. L'admin coche l'élu (égalité : il tranche) et publie :
  l'élu devient leader, l'ancien redevient résident. Si l'élu n'est plus
  membre actif, la publication est refusée (pas 6 mois sans leader).
- **Élection anticipée** (24 h : 12 h + 12 h) : les membres appuient sur
  « Demander une nouvelle élection ». Quand les demandes atteignent **le
  tiers des membres actifs** (`seuilAnticipee`, arrondi au-dessus), l'admin
  est alerté et peut l'ouvrir ; avant, c'est refusé. Seules comptent les
  demandes des membres encore actifs.
- **Un événement spécial** : la carte « Élection du leader »
  (`carte_election_m4.dart`) est en tête de la liste des événements
  (état de l'élection, date de la prochaine). Sur l'Accueil, l'admin voit
  une alerte quand il a quelque chose à faire : résultat à publier, tiers
  des demandes atteint, élection des 6 mois due.
- Candidats : tout membre pendant la première élection, ensuite les membres
  depuis au moins 30 jours. L'admin ne peut pas être leader.
- Sans Cloud Functions (offre gratuite Spark), la phase de l'élection est
  calculée à partir des dates enregistrées ; le délai de 6 mois et le seuil
  du tiers sont vérifiés par l'application (pas par les règles).

## 3. Les écrans (`lib/screens/module4/`)

| Écran | Fichier |
|---|---|
| Onglet Événements (sous-onglets Événements / Sondages, recherche, filtres, catégories) | `evenements_screen.dart` |
| Détail d'un événement | `evenement_detail_screen.dart` |
| Formulaire d'événement (photo, carte, places, service lié) | `evenement_form_screen.dart` |
| Questions, qui apporte quoi, avis, sondages de l'événement | `vie_evenement_widgets.dart` |
| Sondage (résultats en direct, camembert, compte à rebours) | `sondage_screen.dart`, `graphique_sondage.dart` |
| Nouveau sondage (dont sondage de date) | `sondage_form_screen.dart` |
| Élection du leader (+ la carte « événement spécial » et l'alerte admin) | `election_screen.dart`, `carte_election_m4.dart` |
| Calendrier | `calendrier_screen.dart` |
| Statistiques (admin) | `statistiques_screen.dart` |
| Carte du lieu | `carte_evenement.dart` |
| QR de présence et scanner | `presence_qr.dart` |
| Rappels sur le téléphone, notifications push | `notifications_m4.dart`, `push_m4.dart` |
| Badge « nouveau », bandeau de rappel, « Mes événements » | `nouveautes_m4.dart`, `bandeau_rappel_m4.dart`, `mes_evenements_m4.dart` |
| Outils communs | `module4_widgets.dart` |

## 4. Fonctionnalités réalisées

- **Événements** : catégories et illustrations, heure de fin, annuler /
  rétablir, événements officiels épinglés, partage, avatars des
  participants, places maximum + liste d'attente, « Peut-être », qui apporte
  quoi, questions, avis après l'événement, ajout à l'agenda du téléphone,
  export de la liste, lieu sur une carte, photo (Cloudinary, offre
  gratuite, preset non signé), vue calendrier, présence par QR code, lien
  vers un service commun du module 2, **événement organisé à la suite d'un
  signalement du module 3 (D3)** : champs `signalementId` /
  `signalementTitre` (comme `serviceId` / `serviceNom`), ligne « Suite au
  signalement » dans le détail, `getEvenementsDuSignalement` (un seul filtre
  d'égalité, pas d'index) ; le lien ne change plus après la création (les
  règles de modification ne l'acceptent pas).
- **Sondages** : résultats en direct, camembert, résultats cachés avant de
  voter, compte à rebours + participation, sondage de date → « Créer
  l'événement », sondages rattachés à un événement, votes secrets
  (compteurs `compteurs/{choix}`).
- **Partout** : bandeau de rappel à l'accueil, rappels sur le téléphone
  (veille et 1 h avant), badge « nouveau », **notifications push** des
  nouveaux événements, « Mes événements » et pastille Leader dans le profil,
  statistiques admin, derja, mode sombre, sélecteurs de
  date et d'heure en français (24 h).

**SQLite sur le téléphone** (`houmani_m4.db`, `base_locale_m4.dart`) : tables
`brouillons` et `historique` (« Mon historique » : `COUNT`, `AVG`, `GROUP BY`).
Version 2 : colonne `utilisateur_id` dans les deux tables, car un téléphone
peut servir à plusieurs comptes ; chaque requête filtre `WHERE utilisateur_id = ?`.
Les anciennes lignes sont données au premier compte connecté après la mise à jour.

## 5. Notifications push (gratuites)

- Le dossier [`push_worker/`](../push_worker) est un Worker **Cloudflare**
  (offre gratuite). Il garde la clé du compte de service Firebase en
  **secret Cloudflare** : elle n'est jamais dans le dépôt ni dans l'app.
- L'app envoie le jeton Firebase de l'utilisateur ; le Worker vérifie qu'il
  est **leader ou admin actif de ce quartier**, puis envoie la notification
  par Firebase Cloud Messaging au sujet `quartier_{id}`.
- Redéployer : `cd push_worker && npx wrangler deploy`. Changer la clé :
  `npx wrangler secret put SERVICE_ACCOUNT < cle.json` (depuis Git Bash :
  PowerShell ajoute un caractère invisible au début du fichier).

## 6. Assistant du leader (IA gratuite)

- Carte « Assistant du leader » en haut de l'onglet Événements (leaders et
  admin) : 3 à 5 idées d'événements, de sondages et un conseil, chacune
  avec sa raison ; « Créer » ouvre le formulaire déjà rempli.
- Les idées viennent du Worker (`push_worker/src/assistant.js`) : il calcule
  des statistiques **anonymes** de la houma (catégories, participation,
  meilleurs créneaux, sondages, services communs, saison et fêtes) et les
  donne à **Cloudflare Workers AI** (modèle Mistral Small, offre gratuite).
- Chaque lundi à 8 h (cron du Worker) : nouvelles idées pour chaque houma et
  notification aux leaders (sujet `leaders_{q}`). Bouton ↻ : tout de suite.
- Rangé dans `quartiers/{q}/suggestionsIA/courant` (lecture : leaders et
  admin ; écriture : seulement le serveur).

## 7. Tests

- `flutter test` : tests du module dans `test/module4_evenements_test.dart`
  et `test/module4_election_test.dart` (mocks dans `test/`).
- Règles Firestore : `test_regles/regles_m4.test.js` (voir
  [`test_regles/README.md`](../test_regles/README.md)).
- Vérifié sur l'émulateur avec le vrai Firestore (leader, résident, admin),
  dont l'élection complète et une vraie notification push.

## 8. Pour plus tard

- ~~Événement depuis un signalement (M3)~~ : fait (D3), voir la section 4.
