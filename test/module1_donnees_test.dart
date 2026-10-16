import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';
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
      expect(q.position, isNull);
      expect(q.contour, isEmpty);
      expect(q.aUnePosition, false);
    });

    test('fromMap lit la position et le contour (GeoPoint)', () {
      final Quartier q = Quartier.fromMap('q1', {
        'nom': 'El Yasmine',
        'position': const GeoPoint(36.86, 10.17),
        'contour': [const GeoPoint(36.1, 10.1), const GeoPoint(36.2, 10.2)],
      });
      expect(q.position!.latitude, 36.86);
      expect(q.position!.longitude, 10.17);
      expect(q.contour.length, 2);
      expect(q.contour[1].latitude, 36.2);
      expect(q.aUnePosition, true);
    });

    test('fromMap accepte des points {lat, lng} et ignore le reste', () {
      final Quartier q = Quartier.fromMap('q1', {
        'position': {'lat': 36, 'lng': 10.5},
        'contour': [
          {'lat': 36.1, 'lng': 10.1},
          'pas un point',
        ],
      });
      expect(q.position!.latitude, 36.0);
      expect(q.position!.longitude, 10.5);
      expect(q.contour.length, 1);
    });

    // Un carré : latitude 36.0 à 36.2, longitude 10.0 à 10.2
    const Quartier carre = Quartier(
      id: 'c1',
      nom: 'Charguia 1',
      localisation: 'Ariana',
      contour: [
        PointGps(36.0, 10.0),
        PointGps(36.2, 10.0),
        PointGps(36.2, 10.2),
        PointGps(36.0, 10.2),
      ],
    );

    test('contient : un point au milieu est dedans', () {
      expect(carre.contient(const PointGps(36.1, 10.1)), true);
    });

    test('contient : des points à côté sont dehors', () {
      expect(carre.contient(const PointGps(36.3, 10.1)), false); // au nord
      expect(carre.contient(const PointGps(36.1, 10.3)), false); // à l'est
      expect(carre.contient(const PointGps(35.9, 9.9)), false);
    });

    test('contient : forme en L (pas seulement des carrés)', () {
      const Quartier enL = Quartier(
        id: 'l',
        nom: 'L',
        localisation: '',
        contour: [
          PointGps(0, 0),
          PointGps(2, 0),
          PointGps(2, 1),
          PointGps(1, 1),
          PointGps(1, 2),
          PointGps(0, 2),
        ],
      );
      expect(enL.contient(const PointGps(0.5, 0.5)), true);
      expect(enL.contient(const PointGps(1.5, 0.5)), true);
      expect(enL.contient(const PointGps(1.5, 1.5)), false); // le "creux"
    });

    test('contient : faux sans contour (moins de 3 points)', () {
      const Quartier sans = Quartier(id: 'x', nom: '', localisation: '');
      expect(sans.contient(const PointGps(0, 0)), false);
    });

    test('centre : la position, sinon le milieu du contour', () {
      expect(carre.centre!.latitude, closeTo(36.1, 1e-9));
      expect(carre.centre!.longitude, closeTo(10.1, 1e-9));
      const Quartier avecPosition = Quartier(
        id: 'p',
        nom: '',
        localisation: '',
        position: PointGps(1, 2),
      );
      expect(avecPosition.centre!.latitude, 1);
      const Quartier rien = Quartier(id: 'r', nom: '', localisation: '');
      expect(rien.centre, isNull);
    });

    test('un contour seul suffit pour être sur la carte', () {
      const Quartier q = Quartier(
        id: 'q1',
        nom: 'A',
        localisation: 'B',
        contour: [PointGps(36.1, 10.1)],
      );
      expect(q.aUnePosition, true);
    });

    test('toMap ajoute position et contour en GeoPoint quand ils existent', () {
      const Quartier q = Quartier(
        id: 'q1',
        nom: 'A',
        localisation: 'B',
        position: PointGps(36.86, 10.17),
        contour: [PointGps(36.1, 10.1)],
      );
      final Map<String, dynamic> map = q.toMap();
      expect(map['position'], const GeoPoint(36.86, 10.17));
      expect(map['contour'], [const GeoPoint(36.1, 10.1)]);
    });
  });

  // -------------------------------------------------------------------
  group('Changement de quartier (refusChangement)', () {
    const Quartier q1 = Quartier(id: 'q1', nom: 'El Yasmine', localisation: 'A');
    const Quartier q2 = Quartier(id: 'q2', nom: 'El Wafa', localisation: 'B');
    const Utilisateur resident = Utilisateur(
      id: 'r1',
      prenom: 'Rim',
      nom: 'Saidi',
      email: '',
      telephone: '',
      quartierId: 'q1',
      quartier: 'El Yasmine',
      residence: 'El Yasmine',
    );

    test('un résident actif peut changer de quartier', () {
      expect(UtilisateurRepository.refusChangement(resident, q2), isNull);
    });

    test('un résident actif ne peut pas redemander son quartier', () {
      expect(
        UtilisateurRepository.refusChangement(resident, q1),
        'Tu fais déjà partie de ce quartier',
      );
    });

    test('un admin ne peut pas quitter son quartier', () {
      const Utilisateur admin = Utilisateur(
        id: 'a1',
        prenom: 'Amira',
        nom: 'Ben Salah',
        email: '',
        telephone: '',
        quartierId: 'q1',
        quartier: 'El Yasmine',
        residence: 'El Yasmine',
        role: RoleUtilisateur.admin,
      );
      expect(
        UtilisateurRepository.refusChangement(admin, q2),
        'Un administrateur ne peut pas quitter son quartier',
      );
    });

    test('pas de restriction pour un compte en attente ou refusé', () {
      expect(
        UtilisateurRepository.refusChangement(
          resident.copier(statut: StatutUtilisateur.refuse),
          q1,
        ),
        isNull,
      );
      expect(
        UtilisateurRepository.refusChangement(
          resident.copier(statut: StatutUtilisateur.enAttente),
          q1,
        ),
        isNull,
      );
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

    group('connexion par téléphone', () {
      test('réussit avec le numéro seul (8 chiffres)', () async {
        final Resultat<dynamic> r = await repo.connexion(
          '22345678',
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, true);
        expect(r.donnee.id, 'u1');
      });

      test('réussit avec +216 et des espaces', () async {
        final Resultat<dynamic> r = await repo.connexion(
          '+216 22 345 678',
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, true);
      });

      test('échoue pour un numéro inconnu', () async {
        final Resultat<dynamic> r = await repo.connexion(
          '29999999',
          MockUtilisateurRepository.motDePasseDemo,
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Numéro ou mot de passe incorrect');
      });

      test('échoue avec un mauvais mot de passe', () async {
        final Resultat<dynamic> r = await repo.connexion('22345678', 'faux');
        expect(r.estSucces, false);
        expect(r.erreur, 'Numéro ou mot de passe incorrect');
      });

      test('l\'inscription refuse un numéro déjà pris', () async {
        final Resultat<dynamic> r = await repo.inscription(
          nomComplet: 'Autre Personne',
          telephone: '22 345 678',
          email: 'autre@houmani.tn',
          motDePasse: 'abc12345',
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Ce numéro est déjà utilisé par un autre compte');
      });

      test('l\'inscription refuse un numéro invalide', () async {
        final Resultat<dynamic> r = await repo.inscription(
          nomComplet: 'Autre Personne',
          telephone: '1234',
          email: 'autre@houmani.tn',
          motDePasse: 'abc12345',
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Numéro de téléphone invalide (8 chiffres)');
      });

      test('modifierProfil refuse le numéro d\'un autre membre', () async {
        await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          MockUtilisateurRepository.motDePasseDemo,
        );
        final Resultat<void> r = await repo.modifierProfil(
          nomComplet: 'Amira Ben Salah',
          telephone: '+216 98 765 432',
          logement: 'Bloc B - Appt 12',
          competences: const [],
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Ce numéro est déjà utilisé par un autre compte');
      });

      test('modifierProfil garde son propre numéro sans erreur', () async {
        await repo.connexion(
          MockUtilisateurRepository.emailDemo,
          MockUtilisateurRepository.motDePasseDemo,
        );
        final Resultat<void> r = await repo.modifierProfil(
          nomComplet: 'Amira Ben Salah',
          telephone: '22 345 678',
          logement: 'Bloc B - Appt 12',
          competences: const [],
        );
        expect(r.estSucces, true);
      });
    });

    group('normaliserTelephone', () {
      test('accepte 8 chiffres, +216 et 00216', () {
        expect(UtilisateurRepository.normaliserTelephone('22 345 678'),
            '22345678');
        expect(UtilisateurRepository.normaliserTelephone('+216 22345678'),
            '22345678');
        expect(UtilisateurRepository.normaliserTelephone('0021622345678'),
            '22345678');
      });

      test('refuse les autres longueurs', () {
        expect(UtilisateurRepository.normaliserTelephone('1234'), null);
        expect(UtilisateurRepository.normaliserTelephone('223456789'), null);
        expect(UtilisateurRepository.normaliserTelephone(''), null);
      });
    });

    group('code SMS', () {
      test('connexion par SMS avec un numéro vérifié et le bon code', () async {
        expect((await repo.envoyerCodeSms('+216 22 345 678')).estSucces, true);
        final Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.estSucces, true);
        expect(r.donnee!.id, 'u1');
      });

      test('mauvais code : refusé', () async {
        await repo.envoyerCodeSms('22345678');
        final Resultat<Utilisateur> r = await repo.connexionParSms('000000');
        expect(r.estSucces, false);
        expect(r.erreur, 'Code incorrect');
      });

      test('sans avoir demandé de code : refusé', () async {
        final Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.erreur, 'Demande d\'abord un code');
      });

      test('numéro invalide : le SMS ne part pas', () async {
        final Resultat<void> r = await repo.envoyerCodeSms('1234');
        expect(r.erreur, 'Numéro de téléphone invalide (8 chiffres)');
      });

      test('numéro jamais vérifié (ou inconnu) : "pas encore vérifié"',
          () async {
        await repo.envoyerCodeSms('98 765 432'); // Sarra : pas vérifié
        Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.erreur, UtilisateurRepository.numeroNonVerifie);

        await repo.envoyerCodeSms('29 999 999'); // personne
        r = await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.erreur, UtilisateurRepository.numeroNonVerifie);
      });

      test('vérifier son numéro, puis se connecter par SMS', () async {
        await creerCompte(); // Nour, +216 20 000 000
        expect(repo.telephoneEstVerifie(), false);

        await repo.envoyerCodeSms('+216 20 000 000');
        final Resultat<void> v =
            await repo.verifierTelephone(MockUtilisateurRepository.codeSmsDemo);
        expect(v.estSucces, true);
        expect(repo.telephoneEstVerifie(), true);

        await repo.envoyerCodeSms('20000000');
        final Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.donnee!.prenom, 'Nour');
      });

      test('vérifier : le code doit aller au numéro du profil', () async {
        await creerCompte();
        await repo.envoyerCodeSms('22 345 678'); // pas son numéro
        final Resultat<void> r =
            await repo.verifierTelephone(MockUtilisateurRepository.codeSmsDemo);
        expect(r.erreur, 'Le code doit être envoyé au numéro de ton profil');
        expect(repo.telephoneEstVerifie(), false);
      });

      test('changer de numéro : il n\'est plus vérifié', () async {
        expect(repo.telephoneEstVerifie(), true); // démo : déjà vérifié
        await repo.modifierProfil(
          nomComplet: 'Amira Ben Salah',
          telephone: '+216 21 000 111',
          logement: 'Bloc B - Appt 12',
          competences: const [],
        );
        expect(repo.telephoneEstVerifie(), false);

        await repo.envoyerCodeSms('21000111');
        final Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
        expect(r.erreur, UtilisateurRepository.numeroNonVerifie);
      });

      test('compte bloqué : pas de connexion par SMS', () async {
        await repo.bloquerMembre('u1');
        await repo.envoyerCodeSms('22345678');
        final Resultat<Utilisateur> r =
            await repo.connexionParSms(MockUtilisateurRepository.codeSmsDemo);
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

      test('l\'admin de démo ne peut pas changer de quartier', () async {
        final Resultat<void> r = await repo.rejoindreQuartier(
          const Quartier(id: 'q2', nom: 'Cité El Wafa', localisation: 'Ennasr 1'),
        );
        expect(r.estSucces, false);
        expect(r.erreur, 'Un administrateur ne peut pas quitter son quartier');
        expect(repo.getUtilisateurConnecte().quartierId, 'q1');
      });

      test('un résident actif change de quartier et repasse en attente',
          () async {
        // Un résident actif de q1 (e-mail vérifié par ajouterCompte)
        repo.ajouterCompte(
          const Utilisateur(
            id: 'r1',
            prenom: 'Rim',
            nom: 'Saidi',
            email: 'rim@houmani.tn',
            telephone: '',
            quartierId: 'q1',
            quartier: 'Résidence El Yasmine',
            residence: 'Résidence El Yasmine',
          ),
          'secret123',
        );
        await repo.connexion('rim@houmani.tn', 'secret123');
        expect(repo.getUtilisateurConnecte().statut, StatutUtilisateur.actif);

        // Redemander q1 : refusé
        final Resultat<void> meme = await repo.rejoindreQuartier(
          const Quartier(id: 'q1', nom: 'Résidence El Yasmine', localisation: 'A'),
        );
        expect(meme.erreur, 'Tu fais déjà partie de ce quartier');

        final Resultat<void> r = await repo.rejoindreQuartier(
          const Quartier(id: 'q2', nom: 'Cité El Wafa', localisation: 'Ennasr 1'),
        );
        expect(r.estSucces, true);
        expect(repo.getUtilisateurConnecte().quartierId, 'q2');
        expect(repo.getUtilisateurConnecte().statut, StatutUtilisateur.enAttente);
      });

      test('getCodeInvitation renvoie le code du quartier de l\'admin',
          () async {
        final Resultat<String?> r = await repo.getCodeInvitation();
        expect(r.donnee, 'YAS72B');
      });

      test('getCodeInvitation est refusé à un résident', () async {
        await creerCompte();
        final Resultat<String?> r = await repo.getCodeInvitation();
        expect(r.estSucces, false);
        expect(r.erreur, 'Action non autorisée');
      });

      const List<PointGps> triangle = [
        PointGps(36.0, 10.0),
        PointGps(36.3, 10.0),
        PointGps(36.0, 10.3),
      ];

      test('enregistrerContour : l\'admin change les limites et le centre',
          () async {
        final Resultat<void> r = await repo.enregistrerContour(triangle);
        expect(r.estSucces, true);
        final Quartier q = (await repo.getQuartierConnecte()).donnee!;
        expect(q.contour.length, 3);
        expect(q.position!.latitude, closeTo(36.1, 1e-9));
        expect(q.position!.longitude, closeTo(10.1, 1e-9));
      });

      test('enregistrerContour : au moins 3 points', () async {
        final Resultat<void> r =
            await repo.enregistrerContour(triangle.sublist(0, 2));
        expect(r.estSucces, false);
        expect(r.erreur, 'Place au moins 3 points sur la carte');
      });

      test('enregistrerContour est refusé à un résident', () async {
        await creerCompte();
        final Resultat<void> r = await repo.enregistrerContour(triangle);
        expect(r.erreur, 'Action non autorisée');
      });

      test('getQuartierConnecte donne la position du quartier de démo',
          () async {
        final Resultat<Quartier?> r = await repo.getQuartierConnecte();
        expect(r.donnee!.aUnePosition, true);
        expect(r.donnee!.contour.length, 4);
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

    group('sécurité du compte', () {
      test('changer le mot de passe : l\'ancien est vérifié', () async {
        final Resultat<void> faux =
            await repo.changerMotDePasse('mauvais', 'nouveau123');
        expect(faux.estSucces, false);
        expect(faux.erreur, 'Mot de passe actuel incorrect');

        final Resultat<void> bon = await repo.changerMotDePasse(
          MockUtilisateurRepository.motDePasseDemo,
          'nouveau123',
        );
        expect(bon.estSucces, true);
        // L'ancien ne marche plus, le nouveau oui
        expect(
          (await repo.connexion(MockUtilisateurRepository.emailDemo,
                  MockUtilisateurRepository.motDePasseDemo))
              .estSucces,
          false,
        );
        expect(
          (await repo.connexion(MockUtilisateurRepository.emailDemo, 'nouveau123'))
              .estSucces,
          true,
        );
      });

      test('changer l\'e-mail : mot de passe vérifié, adresse libre', () async {
        const String motDePasse = MockUtilisateurRepository.motDePasseDemo;
        expect(
          (await repo.changerEmail('nouvelle@houmani.tn', 'mauvais')).erreur,
          'Mot de passe actuel incorrect',
        );
        expect(
          (await repo.changerEmail('youssef@houmani.tn', motDePasse)).erreur,
          'Un compte existe déjà avec cet e-mail',
        );
        final Resultat<void> r =
            await repo.changerEmail(' nouvelle@houmani.tn ', motDePasse);
        expect(r.estSucces, true);
        expect(repo.emailEnAttente, 'nouvelle@houmani.tn');
        // L'e-mail ne change qu'après le clic sur le lien
        expect(repo.getUtilisateurConnecte().email,
            MockUtilisateurRepository.emailDemo);
      });

      test('supprimer son compte : refusé pour l\'admin', () async {
        final Resultat<void> r =
            await repo.supprimerCompte(MockUtilisateurRepository.motDePasseDemo);
        expect(r.estSucces, false);
        expect(r.erreur, contains('administrateur'));
        expect(repo.getUtilisateurConnecte().id, 'u1');
      });

      test('supprimer son compte : le compte disparaît', () async {
        await creerCompte();
        expect(
          (await repo.supprimerCompte('mauvais')).erreur,
          'Mot de passe actuel incorrect',
        );
        final Resultat<void> r = await repo.supprimerCompte('secret123');
        expect(r.estSucces, true);
        expect(repo.getUtilisateurConnecte().id, isEmpty);
        // Plus de connexion possible, et l'e-mail est de nouveau libre
        expect(
          (await repo.connexion('nour@houmani.tn', 'secret123')).estSucces,
          false,
        );
        await creerCompte();
        expect(repo.getUtilisateurConnecte().email, 'nour@houmani.tn');
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
