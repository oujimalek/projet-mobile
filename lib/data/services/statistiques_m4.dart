import '../models/evenement.dart';
import '../models/sondage.dart';

/// M4 - Les statistiques du module pour l'admin, calculées à partir des
/// listes déjà chargées (aucune lecture Firestore en plus).
class StatistiquesM4 {
  final int nbEvenements;
  final int nbAVenir;
  final int nbAnnules;
  final int totalParticipants; // somme des inscrits (événements non annulés)
  final double participationMoyenne; // inscrits par événement passé
  final int nbSondages;
  final int nbSondagesOuverts;
  final double tauxVoteMoyen; // 0 à 1 : votes / membres, en moyenne par sondage
  final List<int> evenementsParMois; // les 6 derniers mois, du plus ancien au mois en cours
  final List<Evenement> plusPopulaires; // 3 maximum

  const StatistiquesM4({
    required this.nbEvenements,
    required this.nbAVenir,
    required this.nbAnnules,
    required this.totalParticipants,
    required this.participationMoyenne,
    required this.nbSondages,
    required this.nbSondagesOuverts,
    required this.tauxVoteMoyen,
    required this.evenementsParMois,
    required this.plusPopulaires,
  });

  /// Le mois [decalage] mois avant celui de [maintenant] (0 = ce mois-ci).
  static DateTime moisAvant(DateTime maintenant, int decalage) {
    return DateTime(maintenant.year, maintenant.month - decalage);
  }

  static StatistiquesM4 calculer(
    List<Evenement> evenements,
    List<Sondage> sondages,
    DateTime maintenant,
  ) {
    int aVenir = 0;
    int annules = 0;
    int participants = 0;
    int passes = 0;
    int participantsPasses = 0;
    final List<int> parMois = List.filled(6, 0);

    for (final Evenement evenement in evenements) {
      if (evenement.annule) {
        annules++;
        continue;
      }
      participants += evenement.participants;
      if (evenement.estPasse) {
        passes++;
        participantsPasses += evenement.participants;
      } else {
        aVenir++;
      }
      // Événements par mois (date de l'événement), sur 6 mois
      for (int i = 0; i < 6; i++) {
        final DateTime mois = moisAvant(maintenant, 5 - i);
        if (evenement.date.year == mois.year && evenement.date.month == mois.month) {
          parMois[i]++;
        }
      }
    }

    int ouverts = 0;
    double sommeTaux = 0;
    int sondagesAvecMembres = 0;
    for (final Sondage sondage in sondages) {
      if (sondage.estOuvert) {
        ouverts++;
      }
      if (sondage.nombreMembres > 0) {
        sommeTaux += sondage.totalVotes / sondage.nombreMembres;
        sondagesAvecMembres++;
      }
    }

    final List<Evenement> tries = [];
    for (final Evenement evenement in evenements) {
      if (!evenement.annule) {
        tries.add(evenement);
      }
    }
    tries.sort((a, b) => b.participants.compareTo(a.participants));

    return StatistiquesM4(
      nbEvenements: evenements.length,
      nbAVenir: aVenir,
      nbAnnules: annules,
      totalParticipants: participants,
      participationMoyenne: passes == 0 ? 0 : participantsPasses / passes,
      nbSondages: sondages.length,
      nbSondagesOuverts: ouverts,
      tauxVoteMoyen: sondagesAvecMembres == 0 ? 0 : sommeTaux / sondagesAvecMembres,
      evenementsParMois: parMois,
      plusPopulaires: tries.take(3).toList(),
    );
  }
}
