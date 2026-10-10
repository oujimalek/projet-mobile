/// M2 - Un créneau d'un service commun (ex : "Sortie des poubelles", lundi 20:00).
class CreneauCommun {
  final String id;
  final String serviceId; // id du service commun auquel il appartient
  final String titre; // ex : "Sortie des poubelles"
  final DateTime date; // le jour du créneau (l'heure est dans heureDebut)
  final String heureDebut; // ex : "20:00"
  final String heureFin; // ex : "20:30"
  final String? inscrit; // nom du voisin inscrit, null = créneau libre
  final bool rappelVeille; // true = "me rappeler la veille" (sans vraie notification)

  const CreneauCommun({
    required this.id,
    required this.serviceId,
    required this.titre,
    required this.date,
    required this.heureDebut,
    required this.heureFin,
    this.inscrit,
    this.rappelVeille = false,
  });

  /// true si personne n'est inscrit.
  bool get estLibre {
    return inscrit == null;
  }

  /// Copie du créneau avec un autre inscrit.
  /// Pour rendre le créneau libre, mettre libere à true.
  CreneauCommun copyWith({
    String? inscrit,
    bool libere = false,
    bool? rappelVeille,
  }) {
    return CreneauCommun(
      id: id,
      serviceId: serviceId,
      titre: titre,
      date: date,
      heureDebut: heureDebut,
      heureFin: heureFin,
      inscrit: libere ? null : (inscrit ?? this.inscrit),
      rappelVeille: rappelVeille ?? this.rappelVeille,
    );
  }
}
