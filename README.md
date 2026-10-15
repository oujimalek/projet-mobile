# projet-mobile

**Houmani** : application mobile communautaire de quartier (projet Flutter, ESPRIT).
Elle est réservée aux membres d'un même quartier ou d'une même résidence :
signalements du quotidien, services entre voisins, services communs et événements.

## Installer et lancer le projet

Prérequis : Flutter (canal stable), Android Studio avec le SDK Android, et Git.

1. Cloner le dépôt :
   ```bash
   git clone https://github.com/oujimalek/projet-mobile.git
   cd projet-mobile
   ```
2. Télécharger les packages du projet :
   ```bash
   flutter pub get
   ```
3. Ajouter les 2 fichiers de configuration Firebase (voir
   [Configuration Firebase](#configuration-firebase) juste en dessous).
   Sans eux, le projet ne compile pas
   (`Error when reading 'lib/firebase_options.dart'`).
4. Lancer un émulateur :
   - dans Android Studio : **Device Manager** → ▶ sur un appareil (ex : Pixel 7) ;
   - ou en ligne de commande : `flutter emulators` puis
     `flutter emulators --launch <id>`.
5. Lancer l'application :
   - dans Android Studio ou VS Code : bouton **Run** (▶) sur `lib/main.dart` ;
   - ou en ligne de commande : `flutter run`.

> La police Inter est téléchargée au premier lancement : il faut Internet
> la première fois.

## Configuration Firebase

L'application utilise **Firebase** (projet `houmani-235bb`) : comptes
(Firebase Auth, e-mail + mot de passe) et base de données (Cloud Firestore).
Il n'y a pas de serveur à lancer : Firebase est le backend.

Deux fichiers relient l'application à ce projet. Ils **ne sont pas sur GitHub**
(ils sont dans `.gitignore`, car le dépôt est public) :

| Fichier | Rôle |
|---|---|
| `android/app/google-services.json` | Configuration Firebase côté Android |
| `lib/firebase_options.dart` | Configuration Firebase côté Dart (utilisée dans `main.dart`) |

Pour les obtenir, au choix :

**Option A (la plus simple) : demander les fichiers à Mohamed.**
Il les envoie en privé (WhatsApp, Drive...). Les copier exactement à ces
deux emplacements, puis lancer l'application.

**Option B : les générer soi-même** (il faut avoir accès au projet dans la
console Firebase, et Node.js installé) :
```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=houmani-235bb --platforms=android --android-package-name=tn.esprit.houmani --yes
```
Grâce au fichier `firebase.json` (lui, sur GitHub), la commande réutilise
l'application Android déjà enregistrée : elle n'en crée pas une deuxième.
Si `flutterfire` n'est pas reconnu, ajouter
`%LOCALAPPDATA%\Pub\Cache\bin` au PATH, puis rouvrir le terminal.

Ne jamais ajouter ces deux fichiers dans un commit
(`git status` ne doit pas les montrer).

> Si la compilation Android échoue avec `AAPT: error: failed to open file`,
> lancer `flutter clean`, puis relancer.

Les règles de sécurité de la base sont dans `firestore.rules` et les index
dans `firestore.indexes.json`. Le schéma complet des 4 modules est dans
[`docs/schema_firestore.md`](docs/schema_firestore.md). Mohamed les déploie
(`firebase deploy --only firestore`) une fois chaque partie validée.

Avant chaque commit, vérifier que tout va bien :
```bash
flutter analyze
flutter test
```

Les règles se testent à part, sur l'émulateur Firebase : voir
[`test_regles/README.md`](test_regles/README.md).

## Organisation de l'équipe : les branches

- `main` contient uniquement du code validé. **Jamais de push directement sur `main`.**
- Chaque membre travaille sur la branche de son module :
  - `feature/module1-utilisateurs`
  - `feature/module2-services`
  - `feature/module3-signalements`
  - `feature/module4-evenements`
- Une nouvelle fonctionnalité = une nouvelle branche `feature/moduleX-...`,
  créée depuis `main` à jour :
  ```bash
  git checkout main
  git pull
  git checkout -b feature/module2-detail-service
  ```
- Pour intégrer son travail dans `main` : **Pull Request obligatoire**.
- Ne jamais utiliser `git push --force`.
- Chaque membre modifie seulement les fichiers de son module. Un changement
  dans un fichier commun (`theme/`, `widgets/`, `data/`) se fait dans sa
  propre branche et sa propre Pull Request, pour que tout le monde en profite.

## Les modules et leurs dossiers

| Module | Dossier | Écran (fichier · classe) |
|---|---|---|
| M1 · Utilisateurs | `lib/screens/module1/` | 9 écrans : inscription, vérification de l'e-mail, connexion, mot de passe oublié, code du quartier, attente de validation, profil, modification du profil, membres (admin) — voir ci-dessous |
| M2 · Services | `lib/screens/module2/` | `services_list_screen.dart` · `ServicesListScreen` (liste + filtres) |
| M3 · Signalements | `lib/screens/module3/` | `create_signalement_screen.dart` · `CreateSignalementScreen` (GridView des catégories) |
| M4 · Événements | `lib/screens/module4/` | `sondage_screen.dart` · `SondageScreen` (sondage avec vote) |

## Les fichiers communs (la fondation)

| Dossier | Contenu |
|---|---|
| `lib/theme/app_theme.dart` | Toutes les couleurs (`AppColors`) et le thème de l'app |
| `lib/widgets/` | Composants réutilisables : bouton principal (bleu cobalt) et secondaire (bordure dorée), champ de saisie, carte, badge de statut, séparateur en clous, date en arc, barre du bas, en-tête (avec une action optionnelle à droite), logo |
| `lib/data/models/` | Les modèles de données (Utilisateur, Quartier, Service, Signalement, Evenement, Sondage) |
| `lib/data/services/` | Les classes qui fournissent les données. M1 est sur Firebase. M2 à M4 sont encore en dur, à brancher en suivant [`docs/guide_modules_firebase.md`](docs/guide_modules_firebase.md). `firestore_commun.dart` regroupe les outils Firestore communs aux modules. |
| `lib/data/resultat.dart` | `Resultat<T>` : la réponse d'un repository, succès (avec la donnée) ou échec (avec un message à afficher) |
| `lib/router/app_router.dart` | La navigation (go_router) : les 5 onglets de la barre du bas (Accueil, Services, Signalements, Événements, Profil) et les écrans en plein écran (splash, connexion, inscription, démo...) |
| `lib/screens/splash_screen.dart` | Écran de lancement : logo blanc sur fond bleu cobalt, puis la connexion |
| `lib/screens/accueil_screen.dart` | Onglet Accueil |
| `lib/screens/demo_screen.dart` | Écran de démonstration qui ouvre les 4 modules (bouton sur l'onglet Accueil) |
| `assets/images/logo_couleur.png`, `logo_blanc.png` | Le logo officiel Houmani (version couleur, et version blanche pour les fonds bleus) |

## M1 · Utilisateurs : architecture et parcours

Les comptes sont de vrais comptes **Firebase Auth** (e-mail + mot de passe),
et les profils sont enregistrés dans **Cloud Firestore**.

```
Écrans (lib/screens/module1/)
   │  appellent seulement le contrat
   ▼
UtilisateurRepository            (classe abstraite, méthodes en Future,
   │                              réponses en Resultat<T>)
   ├── FirebaseUtilisateurRepository → Firebase Auth + Cloud Firestore
   │        └── CacheLocal (Hive)   → copie du profil sur le téléphone
   └── MockUtilisateurRepository    → test/ : données fictives des tests
```

- **Chargement, succès, erreur :** chaque écran garde un booléen
  `_enChargement` (avec `setState`). Pendant l'appel, il affiche un indicateur
  de chargement. Ensuite, il affiche soit le résultat, soit le message d'erreur
  du `Resultat` (« Pas de connexion Internet », « E-mail ou mot de passe incorrect »…).
- **Cache local (Hive) :** au redémarrage, le profil s'affiche tout de suite
  et l'app reste utilisable sans Internet. Firebase met ensuite le profil à
  jour.
- **Le statut décide de l'écran** : `actif` → accueil ; `enAttente` → attente
  de validation (ou vérification de l'e-mail s'il n'y a pas encore de
  quartier) ; `refuse` → choisir un autre quartier ; `bloque` → déconnexion
  avec un message.
- `UtilisateurRepository().getUtilisateurConnecte()` reste **synchrone** et ne
  lève jamais d'exception : les autres modules peuvent l'appeler directement.
- Les modules 2, 3 et 4 suivent la même structure : voir
  [`docs/guide_modules_firebase.md`](docs/guide_modules_firebase.md).

| Écran | Chemin | Fichier |
|---|---|---|
| Splash | `/splash` | `screens/splash_screen.dart` |
| Connexion | `/connexion` | `connexion_screen.dart` |
| Mot de passe oublié | `/mot-de-passe-oublie` | `mot_de_passe_oublie_screen.dart` |
| Inscription | `/inscription` | `inscription_screen.dart` |
| Vérification de l'e-mail (lien + renvoi) | `/verification` | `verification_otp_screen.dart` |
| Code du quartier / recherche | `/code-quartier` | `code_quartier_screen.dart` |
| Attente de validation | `/attente` | `attente_validation_screen.dart` |
| Profil (onglet) | `/profil` | `profil_screen.dart` |
| Modifier le profil | `/modifier-profil` | `profil_edition_screen.dart` |
| Membres du quartier (admin) | `/profil/membres` | `admin_membres_screen.dart` |

Parcours d'un nouveau voisin : splash → connexion → inscription →
vérification de l'e-mail → code du quartier → attente de validation → accueil.

### Avoir un compte pour tester

Il n'y a plus de compte de démo : chacun crée **son propre compte**.

1. Récupérer les 2 fichiers de configuration Firebase (voir
   [Configuration Firebase](#configuration-firebase)).
2. Dans l'app : **S'inscrire** avec une vraie adresse e-mail, puis cliquer sur
   le lien reçu par e-mail (regarder aussi les spams).
3. Entrer le code du quartier : `YAS72B` (Résidence El Yasmine). Le champ
   `residence` du profil reçoit le nom du quartier.
4. Faire valider la demande, au choix :
   - par un admin du quartier, dans Profil → **« Membres du quartier »** ;
   - ou par Mohamed, dans la console Firebase → Firestore → `utilisateurs` →
     ton document → `statut` = `actif`.
5. Pour tester l'écran admin : demander à Mohamed de passer ton `role` à
   `admin`.

Autres points :
- **« Mot de passe oublié ? »** envoie un vrai e-mail de réinitialisation
  (Firebase).
- **« Changer la photo »** (modifier le profil) propose 6 avatars prédéfinis.
  L'envoi d'une vraie photo n'est pas encore fait.
- **« Membres du quartier »** (admin) permet de valider, refuser, bloquer ou
  débloquer un membre de son quartier.

### Tests

- `flutter test` : 80 tests. Ils couvrent les modèles, les validateurs, le
  repository (avec le mock), le cache Hive, la couche Firestore commune et les
  parcours d'écrans selon le statut.
- `test_regles/` : 32 tests des règles de sécurité du module 1, lancés sur
  l'émulateur Firebase.

### Notions du cours utilisées

| Notion | Où dans le module 1 |
|---|---|
| `StatefulWidget` + `setState` | Tous les écrans (formulaires, `_enChargement`) |
| `Form`, `TextFormField`, validateurs | Connexion, inscription, profil, mot de passe oublié |
| Navigation (go_router, `context.go` / `push`) | `app_router.dart`, choix de l'écran selon le statut |
| `ListView`, widgets réutilisables | Membres du quartier, `widgets_module1.dart` |
| Classe abstraite, `factory`, `static` | `UtilisateurRepository` |
| `Future`, `async` / `await` | Toutes les méthodes du repository |
| Gestion succès / erreur / chargement | `Resultat<T>` + indicateur de chargement |
| Stockage local | `CacheLocal` (Hive) |
| Firebase Auth et Cloud Firestore | `FirebaseUtilisateurRepository` |
| Tests unitaires et tests de widgets | `test/` |
