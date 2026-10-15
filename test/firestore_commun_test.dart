import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/services/firestore_commun.dart';

// Outils partagés par les 4 modules : pas besoin de Firebase pour ces tests
void main() {
  test('lireDate : Timestamp → DateTime, sinon null', () {
    final DateTime date = DateTime(2026, 10, 15, 9, 30);
    expect(FirestoreCommun.lireDate(Timestamp.fromDate(date)), date);
    expect(FirestoreCommun.lireDate(null), isNull);
    expect(FirestoreCommun.lireDate('2026-10-15'), isNull);
  });

  test('lireEnum : texte connu → enum, inconnu → valeur par défaut', () {
    expect(
      FirestoreCommun.lireEnum(
        StatutUtilisateur.values,
        'bloque',
        StatutUtilisateur.enAttente,
      ),
      StatutUtilisateur.bloque,
    );
    expect(
      FirestoreCommun.lireEnum(
        StatutUtilisateur.values,
        'inconnu',
        StatutUtilisateur.enAttente,
      ),
      StatutUtilisateur.enAttente,
    );
    expect(
      FirestoreCommun.lireEnum(
        StatutUtilisateur.values,
        null,
        StatutUtilisateur.enAttente,
      ),
      StatutUtilisateur.enAttente,
    );
  });

  test('executer : succès → Resultat.succes, FirebaseException → échec', () async {
    final succes = await FirestoreCommun.executer(() async => 42);
    expect(succes.estSucces, isTrue);
    expect(succes.donnee, 42);

    final echec = await FirestoreCommun.executer<int>(() async {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    });
    expect(echec.estSucces, isFalse);
    expect(echec.erreur, 'Action non autorisée');
  });

  test('messageErreur : code inconnu → message générique avec le code', () {
    expect(
      FirestoreCommun.messageErreur('unavailable'),
      'Serveur injoignable, vérifie ta connexion Internet',
    );
    expect(
      FirestoreCommun.messageErreur('bizarre'),
      'Une erreur est survenue (bizarre)',
    );
  });
}
