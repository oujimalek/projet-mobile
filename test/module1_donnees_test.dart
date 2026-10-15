import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/screens/module1/widgets_module1.dart';
import 'mock_utilisateur_repository.dart';

// Tests de la couche données du Module 1 (sans Firebase).
void main() {
  // -------------------------------------------------------------------
  group('Resultat', () {
    test('succes contient la donnée et pas d\'erreur', () {
      const Resultat<int> r = Resultat.succes(5);
      expect(r.estSucces, true);
      expect(r.donnee, 5);
      expect(r.erreur, isNull);
    });

    test('echec contient le message et pas de donnée', () {
      const Resultat<int> r = Resultat.echec('Oups');
      expect(r.estSucces, false);
      expect(r.erreur, 'Oups');
      expect(r.donnee, isNull);
    });

    test('Resultat<void> avec succes(null) est un succès', () {
      const Resultat<void> r = Resultat.succes(null);
      expect(r.estSucces, true);
    });
  });

  // -------------------------------------------------------------------
  group('Utilisateur', () {
    const Utilisateur amira = Utilisateur(
      id: 'u1',
      prenom: 'Amira',
      nom: 'Ben Salah',
      email: 'amira@houmani.tn',
      telephone: '+216 22 345 678',
      quartierId: 'q1',
      quartier: 'Résidence El Yasmine',
      residence: 'Résidence El Yasmine, Bloc B',
      statut: StatutUtilisateur.enAttente,
      role: RoleUtilisateur.admin,
    );

    test('toMap enregistre statut et role avec leur nom', () {
      final Map<String, dynamic> map = amira.toMap();
      expect(map['statut'], 'enAttente');
      expect(map['role'], 'admin');
    });

    test('toMap enregistre le quartier sous la clé quartierNom', () {
      final Map<String, dynamic> map = amira.toMap();
      expect(map['quartierNom'], 'Résidence El Yasmine');
      expect(map.containsKey('quartier'), false);
    });

    test('toMap contient la résidence et le quartierId', () {
      final Map<String, dynamic> map = amira.toMap();
      expect(map['residence'], 'Résidence El Yasmine, Bloc B');
      expect(map['quartierId'], 'q1');
    });

    test('fromMap lit une dateDemande de type Timestamp', () {
      final DateTime date = DateTime(2025, 3, 10, 14, 30);
      final Utilisateur u = Utilisateur.fromMap('u9', {
        'dateDemande': Timestamp.fromDate(date),
      });
      expect(u.dateDemande, date);
    });

    test('fromMap met des valeurs par défaut quand les champs manquent', () {
      final Utilisateur u = Utilisateur.fromMap('u9', {});
      expect(u.id, 'u9');
      expect(u.prenom, '');
      expect(u.quartier, '');
      expect(u.residence, '');
      expect(u.quartierId, isNull);
      expect(u.competences, isEmpty);
      expect(u.dateDemande, isNull);
      expect(u.role, RoleUtilisateur.resident);
    });

    test('fromMap met enAttente quand le statut est inconnu', () {
      final Utilisateur u = Utilisateur.fromMap('u9', {'statut': 'nimporte'});
      expect(u.statut, StatutUtilisateur.enAttente);
    });

    test('fromMap lit le statut refuse', () {
      final Utilisateur u = Utilisateur.fromMap('u9', {'statut': 'refuse'});
      expect(u.statut, StatutUtilisateur.refuse);
    });

    test('fromMap lit le rôle admin', () {
      final Utilisateur u = Utilisateur.fromMap('u9', {'role': 'admin'});
      expect(u.role, RoleUtilisateur.admin);
      expect(u.estAdmin, true);
    });

    test('fromMap convertit une List<dynamic> en compétences', () {
      final List<dynamic> liste = <dynamic>['Bricolage', 'Cuisine'];
      final Utilisateur u = Utilisateur.fromMap('u9', {'competences': liste});
      expect(u.competences, ['Bricolage', 'Cuisine']);
    });

    test('toMap puis fromMap redonne le même utilisateur', () {
      final Utilisateur original = amira.copier(
        dateDemande: DateTime(2025, 1, 5, 9, 0),
        competences: ['Informatique'],
        avatar: 'chat',
      );
      // Firestore transforme le DateTime en Timestamp : on le fait à la main
      final Map<String, dynamic> map = original.toMap();
      map['dateDemande'] = Timestamp.fromDate(map['dateDemande']);

      final Utilisateur copie = Utilisateur.fromMap('u1', map);
      expect(copie.prenom, original.prenom);
      expect(copie.nom, original.nom);
      expect(copie.quartierId, original.quartierId);
      expect(copie.quartier, original.quartier);
      expect(copie.residence, original.residence);
      expect(copie.statut, original.statut);
      expect(copie.role, original.role);
      expect(copie.competences, original.competences);
      expect(copie.avatar, 'chat');
      expect(copie.dateDemande, original.dateDemande);
    });

    test('copier garde la résidence et le quartierId par défaut', () {
      final Utilisateur copie = amira.copier(prenom: 'Sonia');
      expect(copie.prenom, 'Sonia');
      expect(copie.residence, amira.residence);
      expect(copie.quartierId, 'q1');
    });

    test('copier change le quartierId quand on le donne', () {
      final Utilisateur copie = amira.copier(quartierId: 'q2');
      expect(copie.quartierId, 'q2');
    });
  });

  // -------------------------------------------------------------------
  group('Quartier', () {
    test('toMap contient seulement nom et localisation', () {
      const Quartier q = Quartier(
        id: 'q1',
        nom: 'Cité El Wafa',
        localisation: 'Ennasr 1, Ariana',
        codeInvitation: 'WAF18C',
        nbMembres: 18,
      );
      expect(q.toMap(), {'nom': 'Cité El Wafa', 'localisation': 'Ennasr 1, Ariana'});
    });

    test('fromMap met des valeurs par défaut quand les champs manquent', () {
      final Quartier q = Quartier.fromMap('q9', {});
      expect(q.id, 'q9');
      expect(q.nom, '');
      expect(q.localisation, '');
      expect(q.codeInvitation, '');
      expect(q.nbMembres, 0);
    });
  });

  // -------------------------------------------------------------------
  group('MockUtilisateurRepository', () {
    late MockUtilisateurRepository repo;

    // Crée un compte et reste connecté dessus
    Future<void> creerCompte() async {
      await repo.inscription(
        nomComplet: 'Nour Hamdi',
        telephone: '+216 20 000 000',
        email: 'nour@houmani.tn',
        motDePasse: 'secret123',
      );
    }

    setUp(() {
      repo = MockUtilisateurRepository();
    });

    group('connexion', () {
      test('réussit avec le compte de démo', () async {
        final Resultat<dynamic> r = await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, true);
        expect(r.donnee.id, 'u1');
      });

      test('accepte l\'e-mail en majuscules et avec des espaces', () async {
        final Resultat<dynamic> r = await repo.connexion(
          '  DEMO@Houmani.TN ',
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, true);
      });

      test('échoue avec un mauvais mot de passe', () async {
        final Resultat<dynamic> r = await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          'faux',
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'E-mail ou mot de passe incorrect');
      });

      test('échoue pour un compte bloqué', () async {
        await repo.bloquerMembre('u1');
        final Resultat<dynamic> r = await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Ton compte a été bloqué par l\'administrateur');
      });
    });

    group('inscription et vérification de l\'e-mail', () {
      test('refuse un e-mail déjà utilisé', () async {
        final Resultat<dynamic> r = await repo.inscription(
          nomComplet: 'Autre Personne',
          telephone: '+216 20 000 000',
          email: MockUtilisateurRepository.emailDemo,
          motDePasse: 'abc12345',
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Un compte existe déjà avec cet e-mail');
      });

      test('découpe le nom complet et met le compte en attente', () async {
        await creerCompte();
        final Utilisateur u = repo.getUtilisateurConnecte();
        expect(u.prenom, 'Nour');
        expect(u.nom, 'Hamdi');
        expect(u.statut, StatutUtilisateur.enAttente);
      });

      test('refuse une 2e inscription avec le même e-mail (majuscules)',
          () async {
        await creerCompte();
        final Resultat<dynamic> r = await repo.inscription(
          nomComplet: 'Autre Nour',
          telephone: '+216 21 111 111',
          email: 'NOUR@Houmani.TN',
          motDePasse: 'autre1234',
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Un compte existe déjà avec cet e-mail');
      });

      test('on peut se connecter avec le compte qu\'on vient de créer',
          () async {
        await creerCompte();
        final Resultat<dynamic> r =
            await repo.connexion('nour@houmani.tn', 'secret123');
        expect(r.estSucces, true);
        expect(r.donnee.id, repo.getUtilisateurConnecte().id);
        expect(r.donnee.prenom, 'Nour');
      });

      test('un compte sans quartier n\'apparaît pas chez l\'admin', () async {
        await creerCompte();
        // On se reconnecte en admin de démo pour lire sa liste
        await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          MockUtilisateurRepository.motDePasseDemo,
        );
        final Resultat<List<Utilisateur>> r =
            await repo.getMembres(StatutUtilisateur.enAttente);
        expect(r.donnee!.any((m) => m.email == 'nour@houmani.tn'), false);
        expect(r.donnee!.length, 3);
      });

      test('un nouveau compte n\'a pas son e-mail vérifié', () async {
        await creerCompte();
        final Resultat<bool> r = await repo.emailEstVerifie();
        expect(r.donnee, false);
      });

      test('simulerVerificationEmail vérifie l\'e-mail', () async {
        await creerCompte();
        await repo.simulerVerificationEmail();
        final Resultat<bool> r = await repo.emailEstVerifie();
        expect(r.donnee, true);
      });
    });

    group('quartiers', () {
      test('rejoindreQuartier est refusé avant la vérification', () async {
        await creerCompte();
        final Resultat<void> r = await repo.rejoindreQuartier(
          const Quartier(id: 'q2', nom: 'Cité El Wafa', localisation: 'Ennasr 1'),
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Action non autorisée');
      });

      test('rejoindreQuartier remplit le quartier après la vérification',
          () async {
        await creerCompte();
        await repo.simulerVerificationEmail();
        final Resultat<void> r = await repo.rejoindreQuartier(
          const Quartier(id: 'q2', nom: 'Cité El Wafa', localisation: 'Ennasr 1'),
        );
        expect(r.estSucces, true);

        final Utilisateur u = repo.getUtilisateurConnecte();
        expect(u.quartierId, 'q2');
        expect(u.quartier, 'Cité El Wafa');
        expect(u.residence, 'Cité El Wafa');
        expect(u.statut, StatutUtilisateur.enAttente);
      });

      test('trouverParCode accepte un code en minuscules', () async {
        final Resultat<Quartier?> r = await repo.trouverParCode('yas72b');
        expect(r.donnee, isNotNull);
        expect(r.donnee!.id, 'q1');
      });

      test('trouverParCode renvoie null pour un code inconnu', () async {
        final Resultat<Quartier?> r = await repo.trouverParCode('ZZZZZZ');
        expect(r.estSucces, true);
        expect(r.donnee, isNull);
      });
    });

    group('administration des membres', () {
      test('compterMembres compte les demandes en attente de la démo', () async {
        final Resultat<int> r =
            await repo.compterMembres(StatutUtilisateur.enAttente);
        expect(r.donnee, 3);
      });

      test('validerMembre passe un membre en attente à actif', () async {
        await repo.validerMembre('u4');
        final Resultat<int> r =
            await repo.compterMembres(StatutUtilisateur.enAttente);
        expect(r.donnee, 2);
      });

      test('refuserMembre met le statut refuse', () async {
        await repo.refuserMembre('u4');
        final Resultat<List<Utilisateur>> refuses =
            await repo.getMembres(StatutUtilisateur.refuse);
        expect(refuses.donnee!.map((m) => m.id), ['u4']);
      });

      test('bloquerMembre puis debloquerMembre change le statut', () async {
        await repo.bloquerMembre('u2');
        final Resultat<int> bloques =
            await repo.compterMembres(StatutUtilisateur.bloque);
        expect(bloques.donnee, 2);

        await repo.debloquerMembre('u2');
        final Resultat<int> bloquesApres =
            await repo.compterMembres(StatutUtilisateur.bloque);
        expect(bloquesApres.donnee, 1);
      });

      test('validerMembre échoue pour un id inconnu', () async {
        final Resultat<void> r = await repo.validerMembre('inconnu');
        expect(r.estSucces, false);
        expect(r.erreur, 'Donnée introuvable');
      });
    });

    test('getUtilisateurConnecte est synchrone', () {
      // Pas de await : le résultat est directement un Utilisateur
      final Utilisateur u = repo.getUtilisateurConnecte();
      expect(u.id, 'u1');
    });

    group('session et rafraîchissement du profil', () {
      test('restaurerSession renvoie null sans session gardée', () async {
        expect(await repo.restaurerSession(), isNull);
      });

      test('restaurerSession redonne le profil gardé', () async {
        repo.sessionGardee = const Utilisateur(
          id: 'u9',
          prenom: 'Lina',
          nom: 'Saidi',
          email: 'lina@houmani.tn',
          telephone: '',
          quartier: 'Cité El Wafa',
          residence: 'Cité El Wafa',
        );
        final Utilisateur? u = await repo.restaurerSession();
        expect(u?.id, 'u9');
        // getUtilisateurConnecte répond tout de suite avec ce profil
        expect(repo.getUtilisateurConnecte().prenom, 'Lina');
      });

      test('restaurerSession ne restaure pas un compte bloqué', () async {
        repo.sessionGardee = const Utilisateur(
          id: 'u8',
          prenom: 'Walid',
          nom: 'Ferchichi',
          email: '',
          telephone: '',
          quartier: 'Résidence El Yasmine',
          residence: 'Résidence El Yasmine',
          statut: StatutUtilisateur.bloque,
        );
        expect(await repo.restaurerSession(), isNull);
      });

      test('rafraichirProfil renvoie le nouveau statut', () async {
        await repo.simulerStatut(StatutUtilisateur.refuse);
        final Resultat<Utilisateur> r = await repo.rafraichirProfil();
        expect(r.estSucces, true);
        expect(r.donnee!.statut, StatutUtilisateur.refuse);
      });

      test('rafraichirProfil déconnecte un compte bloqué', () async {
        await repo.simulerStatut(StatutUtilisateur.bloque);
        final Resultat<Utilisateur> r = await repo.rafraichirProfil();
        expect(r.estSucces, false);
        expect(r.erreur, 'Ton compte a été bloqué par l\'administrateur');
        expect(repo.getUtilisateurConnecte().id, isEmpty);
      });
    });

    group('erreurs réseau', () {
      test('getMembres et compterMembres renvoient le message d\'erreur',
          () async {
        repo.erreurMembres = 'Serveur injoignable';
        final Resultat<List<Utilisateur>> membres =
            await repo.getMembres(StatutUtilisateur.actif);
        expect(membres.estSucces, false);
        expect(membres.donnee, isNull);
        expect(membres.erreur, 'Serveur injoignable');

        final Resultat<int> nombre =
            await repo.compterMembres(StatutUtilisateur.enAttente);
        expect(nombre.estSucces, false);
        expect(nombre.erreur, 'Serveur injoignable');
      });
    });
  });

  // -------------------------------------------------------------------
  // L'écran ouvert après la connexion, le splash et "Vérifier ma demande"
  group('cheminSelonStatut', () {
    Utilisateur avec(StatutUtilisateur statut, {String quartier = 'Cité El Wafa'}) {
      return Utilisateur(
        id: 'u1',
        prenom: 'Amira',
        nom: 'Ben Salah',
        email: '',
        telephone: '',
        quartier: quartier,
        residence: quartier,
        statut: statut,
      );
    }

    test('actif → accueil', () {
      expect(cheminSelonStatut(avec(StatutUtilisateur.actif)), '/accueil');
    });

    test('en attente avec un quartier → attente', () {
      expect(cheminSelonStatut(avec(StatutUtilisateur.enAttente)), '/attente');
    });

    test('en attente sans quartier → vérification de l\'e-mail', () {
      expect(
        cheminSelonStatut(avec(StatutUtilisateur.enAttente, quartier: '')),
        '/verification',
      );
    });

    test('refusé → choisir un autre quartier', () {
      expect(
        cheminSelonStatut(avec(StatutUtilisateur.refuse)),
        '/code-quartier',
      );
    });

    test('bloqué → null (reste sur la connexion)', () {
      expect(cheminSelonStatut(avec(StatutUtilisateur.bloque)), isNull);
    });
  });
}
