import '../models/evenement.dart';
import '../models/sondage.dart';

/// M4 - Accès aux événements et aux sondages du quartier.
///
/// Données en dur pour l'instant. Plus tard, seul l'intérieur de ces
/// méthodes changera (appel à une API), pas les écrans.
class EvenementRepository {
  /// Les prochains événements.
  List<Evenement> getEvenements() {
    return [
      Evenement(
        id: 'e1',
        titre: 'Fête des voisins',
        description: 'On se retrouve dans le jardin, chacun apporte un plat !',
        date: DateTime(2026, 10, 17, 18, 0),
        lieu: 'Jardin de la résidence',
        organisateur: 'Salma G.',
        participants: 24,
      ),
      Evenement(
        id: 'e2',
        titre: 'Grand nettoyage du quartier',
        description: 'Nlemmou le quartier ensemble : gants et sacs fournis.',
        date: DateTime(2026, 10, 25, 9, 0),
        lieu: 'Parking du bloc A',
        organisateur: 'Youssef T.',
        participants: 15,
      ),
      Evenement(
        id: 'e3',
        titre: 'Réunion du syndic',
        description: 'Budget de l\'année et travaux de l\'ascenseur.',
        date: DateTime(2026, 11, 3, 19, 30),
        lieu: 'Salle commune',
        organisateur: 'Syndic',
        participants: 9,
      ),
    ];
  }

  /// Le sondage en cours (utilisé par SondageScreen).
  Sondage getSondageActif() {
    // Le sondage se termine dans 2 jours (calculé à partir d'aujourd'hui)
    final DateTime aujourdhui = DateTime.now();

    return Sondage(
      id: 'p1',
      question: 'Quelle date pour la réunion de résidence ?',
      dateFin: DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + 2),
      proposePar: 'l\'admin',
      nombreMembres: 46,
      options: const [
        OptionSondage(texte: 'Mardi 6 oct. · 19:00', votes: 12),
        OptionSondage(texte: 'Jeudi 8 oct. · 19:00', votes: 7),
        OptionSondage(texte: 'Samedi 10 oct. · 10:00', votes: 3),
      ],
    );
  }
}
