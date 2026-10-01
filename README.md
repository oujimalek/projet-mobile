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
3. Lancer un émulateur :
   - dans Android Studio : **Device Manager** → ▶ sur un appareil (ex : Pixel 7) ;
   - ou en ligne de commande : `flutter emulators` puis
     `flutter emulators --launch <id>`.
4. Lancer l'application :
   - dans Android Studio ou VS Code : bouton **Run** (▶) sur `lib/main.dart` ;
   - ou en ligne de commande : `flutter run`.

> La police Inter est téléchargée au premier lancement : il faut Internet
> la première fois.

Avant chaque commit, vérifier que tout va bien :
```bash
flutter analyze
flutter test
```

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
| M1 · Utilisateurs | `lib/screens/module1/` | `connexion_screen.dart` · `ConnexionScreen` (connexion avec Form) |
| M2 · Services | `lib/screens/module2/` | `services_list_screen.dart` · `ServicesListScreen` (liste + filtres) |
| M3 · Signalements | `lib/screens/module3/` | `create_signalement_screen.dart` · `CreateSignalementScreen` (GridView des catégories) |
| M4 · Événements | `lib/screens/module4/` | `sondage_screen.dart` · `SondageScreen` (sondage avec vote) |

## Les fichiers communs (la fondation)

| Dossier | Contenu |
|---|---|
| `lib/theme/app_theme.dart` | Toutes les couleurs (`AppColors`) et le thème de l'app |
| `lib/widgets/` | Composants réutilisables : bouton principal (orange) et secondaire (bordure teal), champ de saisie, carte, badge de statut, séparateur en clous, date en arc, barre du bas, logo |
| `lib/data/models/` | Les modèles de données (Utilisateur, Service, Signalement, Evenement, Sondage) |
| `lib/data/services/` | Les classes qui fournissent les données (en dur pour l'instant, une API plus tard) |
| `lib/router/app_router.dart` | La navigation (go_router) : les 5 onglets de la barre du bas (Accueil, Services, Signalements, Événements, Profil) et les écrans en plein écran (connexion, démo) |
| `lib/screens/accueil_screen.dart`, `profil_screen.dart` | Onglets Accueil et Profil (« À venir » pour l'instant) |
| `lib/screens/demo_screen.dart` | Écran de démonstration qui ouvre les 4 modules (bouton sur l'onglet Accueil) |
| `assets/images/logo.png` | Le logo officiel Houmani |
