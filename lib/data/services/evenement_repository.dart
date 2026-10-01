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
    return Sondage(
      id: 'p1',
      question: 'Quel jour pour la fête des voisins ?',
      dateFin: DateTime(2026, 10, 10),
      options: const [
        OptionSondage(texte: 'Vendredi soir', votes: 8),
        OptionSondage(texte: 'Samedi après-midi', votes: 14),
        OptionSondage(texte: 'Dimanche midi', votes: 5),
      ],
    );
  }
}
