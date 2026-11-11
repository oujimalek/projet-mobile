# Module 4 · Événements et sondages

Branche : `feature/module4-evenements` (hamza).
Format des données : [`schema_firestore.md`](schema_firestore.md) §6.
Règles de sécurité : [`firestore.rules`](../firestore.rules), partie « M4 ».

## 1. Ce que fait le module

Les voisins d'une même houma :
- **organisent des événements** (fête, réunion, nettoyage, sport, culture...) ;
- **s'inscrivent** à un événement ;
- **créent des sondages** et **votent** (un vote par membre, définitif).

Le module écrit dans `quartiers/{q}/evenements` (+ `participants`) et
`quartiers/{q}/sondages` (+ `votes`). Il lit l'utilisateur connecté du
module 1 (`UtilisateurRepository().getUtilisateurConnecte()`).

## 2. Qui peut faire quoi

Seul un membre **actif** du quartier voit le module (règle n°3).

| Action | Membre | Leader (organisateur) | Admin |
|---|:-:|:-:|:-:|
| Voir les événements, les sondages et leurs résultats | ✅ | ✅ | ✅ |
| Voir le **nombre** de participants | ✅ | ✅ | ✅ |
| Voir les **noms** des participants | ❌ | ✅ (ses événements) | ✅ |
| Créer un événement ou un sondage | ❌ (*) | ✅ | ✅ |
| Modifier un événement | ❌ | ✅ (les siens) | ✅ (tous) |
| Supprimer un événement ou un sondage | ❌ | ✅ (les siens) | ✅ (tous) |
| Participer / se retirer (pas après l'événement) | ✅ | ✅ | ✅ |
| Voter (1 fois, définitif, avant la fin) | ✅ | ✅ | ✅ |
| Modifier un sondage ou changer son vote | ❌ | ❌ | ❌ |

(*) **Aujourd'hui** tout membre peut encore créer : le rôle Leader arrive à
l'étape 3 (ci-dessous). Un leader ne touche pas aux événements d'un autre
leader.

### Le rôle Leader (étape 3, à venir)

- Nouveau rôle dans le module 1, à côté de `resident` et `admin`.
- Plusieurs leaders par quartier ; l'admin choisit le nombre de places.
- Élection tous les 6 mois : 3 jours de candidatures puis 2 jours de vote,
  1 voix par membre, les N premiers sont élus ; égalité : l'admin tranche.
- Élection anticipée : les membres appuient sur « Demander une nouvelle
  élection », l'admin voit le nombre de demandes et peut ouvrir une
  élection de 24 h (12 h de candidatures + 12 h de vote).
- Mandat : jusqu'à la prochaine élection, ou jusqu'au retrait par l'admin.
- Candidats : tout membre pendant la première élection du quartier, ensuite
  les membres depuis au moins 1 mois. L'admin ne peut pas être leader.
- Avant la première élection, l'admin nomme des leaders provisoires.

## 3. Les écrans (`lib/screens/module4/`)

| Écran | Fichier | Contenu |
|---|---|---|
| Onglet Événements | `evenements_screen.dart` | Sous-onglets **Événements** (recherche, filtres Tous / Cette semaine / J'organise / Je participe, catégories, À venir · Passés) et **Sondages** (En cours · Terminés). Bouton + : nouvel événement / nouveau sondage. |
| Détail d'un événement | `evenement_detail_screen.dart` | Illustration de la catégorie, date et horaire, lieu, organisateur, participants, bouton **Je participe / Me retirer**, menu Modifier / Supprimer. |
| Formulaire d'événement | `evenement_form_screen.dart` | Titre, catégorie, date, heure de début et de fin (optionnelle), lieu, description. Création et modification. |
| Sondage | `sondage_screen.dart` | Question, choix avec barres de %, vote, suppression (auteur / admin). |
| Nouveau sondage | `sondage_form_screen.dart` | Question, 2 à 6 choix, date de fin. |
| Outils communs | `module4_widgets.dart` | Icônes et couleurs des catégories, dates en français, messages vide / erreur. |

L'accueil ouvre directement l'événement ou le sondage de ses cartes.

## 4. Étapes

- [x] **1. Données** : modèles, `EvenementRepository` (contrat),
  `FirebaseEvenementRepository`, mock et tests.
- [x] **2. Écrans** : liste, détail, formulaires, sondages, accueil.
  Catégories + illustrations, recherche et filtres, heure de fin.
  Essayé sur l'émulateur avec le vrai Firestore.
- [ ] **3. Rôle Leader** : rôle dans le module 1, seuls leaders et admin
  créent, l'admin nomme les leaders, règles.
- [ ] **4. Si le temps le permet** : élection, bandeau de rappel, résultats
  en direct, partage.

Avant chaque commit : `flutter analyze` puis `flutter test`.

## 5. Règles : changements à déployer

- `evenements` (update) : l'organisateur **ou l'admin** modifie ; champs
  autorisés : `titre`, `description`, `date`, `dateFin`, `lieu`,
  `categorie`. **Pas encore déployé** : avant le déploiement, modifier un
  événement peut être refusé.
- Supprimer un événement laisse ses fiches `participants` (l'application ne
  peut pas supprimer celles des autres). Sans gêne pour l'affichage.

## 6. Pour plus tard

Choisis pendant la revue, hors du temps disponible : photo d'événement
(Cloudinary, gratuit), annulation au lieu de suppression, places maximum et
liste d'attente, « Peut-être », qui apporte quoi, commentaires, événements
officiels, lieu sur une carte, vue calendrier, ajout à l'agenda du
téléphone, partage, avatars, note après l'événement, export de la liste,
QR code ; résultats en direct, graphique, sondage de date → événement,
sondage dans un événement, votes secrets, résultats cachés avant de voter,
rappel de participation ; bandeau de rappel, notification locale, badge
« nouveau », notifications push (gratuites via un service externe) ;
« Mes événements » dans le profil, événement depuis un signalement (M3),
lien avec un service commun (M2), statistiques admin ; derja, mode hors
ligne, tests des règles.
