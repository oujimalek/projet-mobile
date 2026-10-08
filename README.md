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
| M1 · Utilisateurs | `lib/screens/module1/` | 8 écrans : inscription, code SMS, connexion, code du quartier, attente de validation, profil, modification du profil, membres (admin) — voir ci-dessous |
| M2 · Services | `lib/screens/module2/` | `services_list_screen.dart` · `ServicesListScreen` (liste + filtres) |
| M3 · Signalements | `lib/screens/module3/` | `create_signalement_screen.dart` · `CreateSignalementScreen` (GridView des catégories) |
| M4 · Événements | `lib/screens/module4/` | `sondage_screen.dart` · `SondageScreen` (sondage avec vote) |

## Les fichiers communs (la fondation)

| Dossier | Contenu |
|---|---|
| `lib/theme/app_theme.dart` | Toutes les couleurs (`AppColors`) et le thème de l'app |
| `lib/widgets/` | Composants réutilisables : bouton principal (bleu cobalt) et secondaire (bordure dorée), champ de saisie, carte, badge de statut, séparateur en clous, date en arc, barre du bas, en-tête (avec une action optionnelle à droite), logo |
| `lib/data/models/` | Les modèles de données (Utilisateur, Quartier, Service, Signalement, Evenement, Sondage) |
| `lib/data/services/` | Les classes qui fournissent les données (en dur pour l'instant, une API plus tard) |
| `lib/router/app_router.dart` | La navigation (go_router) : les 5 onglets de la barre du bas (Accueil, Services, Signalements, Événements, Profil) et les écrans en plein écran (splash, connexion, inscription, démo...) |
| `lib/screens/splash_screen.dart` | Écran de lancement : logo blanc sur fond bleu cobalt, puis la connexion |
| `lib/screens/accueil_screen.dart` | Onglet Accueil |
| `lib/screens/demo_screen.dart` | Écran de démonstration qui ouvre les 4 modules (bouton sur l'onglet Accueil) |
| `assets/images/logo_couleur.png`, `logo_blanc.png` | Le logo officiel Houmani (version couleur, et version blanche pour les fonds bleus) |

## M1 · Utilisateurs : parcours et données de démo

Les données sont fictives (`lib/data/services/mock_utilisateur_repository.dart`) :
rien n'est enregistré quand on relance l'application.

Accès aux données : les écrans n'appellent que le **contrat**
`UtilisateurRepository` (classe abstraite, méthodes en `Future`), jamais le mock
directement. Pour brancher Firebase Auth + Firestore plus tard : créer
`FirebaseUtilisateurRepository implements UtilisateurRepository`, puis changer
la ligne `instance = ...` dans `utilisateur_repository.dart`. Ni les écrans ni
les tests ne changent (les tests injectent le mock eux-mêmes). Les modules 2, 3
et 4 sont invités à suivre la même structure (voir le commentaire en tête de
`utilisateur_repository.dart`).

| Écran | Chemin | Fichier |
|---|---|---|
| Splash | `/splash` | `screens/splash_screen.dart` |
| Connexion | `/connexion` | `connexion_screen.dart` |
| Inscription | `/inscription` | `inscription_screen.dart` |
| Code SMS (6 chiffres + renvoi) | `/verification` | `verification_otp_screen.dart` |
| Code du quartier / recherche | `/code-quartier` | `code_quartier_screen.dart` |
| Attente de validation | `/attente` | `attente_validation_screen.dart` |
| Profil (onglet) | `/profil` | `profil_screen.dart` |
| Modifier le profil | `/modifier-profil` | `profil_edition_screen.dart` |
| Membres du quartier (admin) | `/profil/membres` | `admin_membres_screen.dart` |

Parcours d'un nouveau voisin : splash → connexion → inscription → code SMS →
code du quartier → attente de validation → accueil.

Pour tester :
- **Compte de démo** (administrateur) : `demo@houmani.tn` (ou `+216 22 345 678`)
  / mot de passe `houmani123` ;
- **Code SMS** : `123456` ;
- **Code du quartier** : `YAS72B` (Résidence El Yasmine) ;
- sur l'écran d'attente, le bouton **« Démo : simuler la validation »** fait
  comme si l'administrateur avait accepté la demande ;
- dans le profil du compte de démo, **« Membres du quartier »** ouvre la liste
  des membres (valider / refuser / bloquer).
