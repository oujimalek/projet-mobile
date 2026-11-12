import 'package:houmani/data/models/signalement.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/signalement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M3 - Implémentation "fictive" de SignalementRepository, pour les TESTS.
///
/// Les données sont gardées en mémoire. Les tests l'installent avant chaque
/// test (`SignalementRepository.instance = ...`) : ils marchent sans
/// Internet et sans Firebase.
///
/// Mêmes règles que FirebaseSignalementRepository (et que firestore.rules) :
/// - l'auteur modifie son signalement tant qu'il est en attente ;
/// - l'admin seul change le statut ;
/// - une confirmation par voisin, jamais sur son propre signalement.
///
/// L'utilisateur connecté vient du module 1 (UtilisateurRepository), donc
/// du MockUtilisateurRepository dans les tests.
class MockSignalementRepository implements SignalementRepository {
  /// [avecDonneesDemo] : false = on part d'une liste vide.
  MockSignalementRepository({bool avecDonneesDemo = true}) {
    if (avecDonneesDemo) {
      _ajouterDonneesDemo();
    }
  }

  // Les signalements du quartier (tous dans le quartier q1 du mock M1)
  final List<Signalement> _signalements = [];

  // Qui a confirmé quoi : id du signalement -> uids des voisins
  final Map<String, Set<String>> _confirmations = {};

  // Numéro du prochain signalement créé (s100, s101, ...)
  int _prochainNumero = 100;

  /// Si ce n'est pas null : toutes les méthodes échouent avec ce message
  /// (comme Firebase sans réseau).
  String? erreurReseau;

  /// Nombre de signalements vraiment créés (pour vérifier les doublons).
  int nombreEnvois = 0;

  /// Tous les signalements, pour vérifier dans les tests.
  List<Signalement> get tous => List.unmodifiable(_signalements);

  Utilisateur get _moi => UtilisateurRepository().getUtilisateurConnecte();

  /// Les anciens signalements écrits en dur (avant Firebase).
  void _ajouterDonneesDemo() {
    _signalements.addAll([
      Signalement(
        id: 'r1',
        titre: 'Coupure d\'électricité',
        description: 'Plus de courant dans tout le bloc B depuis 14h.',
        categorieId: 'electricite',
        statut: StatutSignalement.enCours,
        date: DateTime(2026, 10, 1, 14, 0),
        lieu: 'Bloc B',
        auteurId: 'u1', // Amira, le compte connecté du mock M1
        auteurNom: 'Amira B.',
        nbConfirmations: 12,
        danger: true, // escaliers et ascenseur dans le noir
      ),
      Signalement(
        id: 'r2',
        titre: 'Le camion d\'ordures est passé',
        description: 'Passage du camion ce matin, pensez aux poubelles.',
        categorieId: 'ordures',
        statut: StatutSignalement.resolu,
        date: DateTime(2026, 10, 1, 7, 30),
        lieu: 'Rue principale',
        auteurId: 'u22',
        auteurNom: 'Youssef T.',
        nbConfirmations: 5,
      ),
      Signalement(
        id: 'r3',
        titre: 'Fuite d\'eau devant l\'entrée',
        description: 'Une canalisation fuit devant l\'entrée du bloc A.',
        categorieId: 'eau',
        statut: StatutSignalement.enAttente,
        date: DateTime(2026, 9, 30, 18, 15),
        lieu: 'Entrée bloc A',
        auteurId: 'u21',
        auteurNom: 'Salma G.',
        nbConfirmations: 3,
      ),
      Signalement(
        id: 'r4',
        titre: 'Travaux de voirie',
        description: 'La rue sera fermée toute la semaine.',
        categorieId: 'travaux',
        statut: StatutSignalement.refuse,
        date: DateTime(2026, 9, 29, 9, 0),
        lieu: 'Avenue Hédi Nouira',
        auteurId: 'u20',
        auteurNom: 'Karim M.',
      ),
    ]);
    // Des voisins fictifs ont déjà confirmé (autant que le compteur)
    for (final Signalement s in _signalements) {
      _confirmations[s.id] = {
        for (int i = 1; i <= s.nbConfirmations; i++) 'voisin$i',
      };
    }
  }

  /// Le refus commun à toutes les méthodes : réseau, puis utilisateur.
  String? _refusDeBase() {
    return erreurReseau ?? SignalementRepository.refusUtilisateur(_moi);
  }

  /// La position d'un signalement dans la liste (-1 : introuvable).
  int _position(String id) {
    return _signalements.indexWhere((s) => s.id == id);
  }

  /// Du plus récent au plus ancien (comme orderBy('date', descending: true)).
  List<Signalement> _trier(List<Signalement> liste) {
    return SignalementRepository.trierParDate(liste);
  }

  // =====================================================================
  // Lecture
  // =====================================================================

  @override
  Future<Resultat<List<Signalement>>> getSignalements({
    StatutSignalement? statut,
    String? categorieId,
  }) async {
    final String? refus = _refusDeBase();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    List<Signalement> liste = _signalements;
    if (statut != null) {
      liste = liste.where((s) => s.statut == statut).toList();
    }
    liste = SignalementRepository.filtrerParCategorie(liste, categorieId);
    return Resultat.succes(_trier(liste));
  }

  @override
  Future<Resultat<List<Signalement>>> getMesSignalements() async {
    final String? refus = _refusDeBase();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final String moiId = _moi.id;
    return Resultat.succes(
      _trier(_signalements.where((s) => s.auteurId == moiId).toList()),
    );
  }

  @override
  Future<Resultat<int>> compterMesSignalements() async {
    final String? refus = _refusDeBase();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final String moiId = _moi.id;
    return Resultat.succes(
      _signalements.where((s) => s.auteurId == moiId).length,
    );
  }

  @override
  Future<Resultat<Signalement>> getSignalement(String id) async {
    final String? refus = _refusDeBase();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final int position = _position(id);
    if (position == -1) {
      return const Resultat.echec('Ce signalement n\'existe plus');
    }
    return Resultat.succes(_signalements[position]);
  }

  @override
  Future<Resultat<bool>> aConfirme(String id) async {
    final String? refus = _refusDeBase();
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Set<String> qui = _confirmations[id] ?? {};
    return Resultat.succes(qui.contains(_moi.id));
  }

  // =====================================================================
  // Écriture
  // =====================================================================

  @override
  Future<Resultat<void>> ajouterSignalement(Signalement signalement) async {
    final Utilisateur moi = _moi;
    final String? refus = _refusDeBase() ??
        SignalementRepository.refusSignalement(
          titre: signalement.titre,
          description: signalement.description,
          lieu: signalement.lieu,
          categorieId: signalement.categorieId,
        ) ??
        SignalementRepository.refusPhoto(signalement.photoUrl);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Id choisi à l'avance (file d'envoi) : déjà créé = déjà envoyé
    if (signalement.id.isNotEmpty && _position(signalement.id) != -1) {
      return const Resultat.succes(null);
    }
    nombreEnvois++;
    final Signalement nouveau = signalement.copyWith(
      id: signalement.id.isNotEmpty ? signalement.id : 's$_prochainNumero',
      titre: signalement.titre.trim(),
      description: signalement.description.trim(),
      lieu: signalement.lieu.trim(),
      auteurId: moi.id,
      auteurNom: SignalementRepository.nomCourt(moi),
      statut: StatutSignalement.enAttente,
      nbConfirmations: 0,
      date: DateTime.now(),
    );
    _prochainNumero++;
    _signalements.add(nouveau);
    _confirmations[nouveau.id] = {};
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> modifierSignalement(Signalement signalement) async {
    final Resultat<Signalement> lecture = await getSignalement(signalement.id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final Signalement actuel = lecture.donnee!;
    final String? refus =
        SignalementRepository.refusModification(actuel, _moi.id) ??
            SignalementRepository.refusSignalement(
              titre: signalement.titre,
              description: signalement.description,
              lieu: signalement.lieu,
              categorieId: signalement.categorieId,
            ) ??
            SignalementRepository.refusPhoto(signalement.photoUrl);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Seulement les champs autorisés (firestore.rules) ; position et photo
    // peuvent redevenir null (retirées par l'auteur), d'où le constructeur
    // plutôt que copyWith
    _signalements[_position(actuel.id)] = Signalement(
      id: actuel.id,
      titre: signalement.titre.trim(),
      description: signalement.description.trim(),
      categorieId: signalement.categorieId,
      statut: actuel.statut,
      date: actuel.date,
      lieu: signalement.lieu.trim(),
      auteurId: actuel.auteurId,
      auteurNom: actuel.auteurNom,
      nbConfirmations: actuel.nbConfirmations,
      danger: signalement.danger,
      photoUrl: signalement.photoUrl,
      position: signalement.position,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerSignalement(String id) async {
    final Resultat<Signalement> lecture = await getSignalement(id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final String? refus =
        SignalementRepository.refusSuppression(lecture.donnee!, _moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    _signalements.removeAt(_position(id));
    _confirmations.remove(id);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> confirmer(String id) async {
    final Resultat<Signalement> lecture = await getSignalement(id);
    if (!lecture.estSucces) {
      return Resultat.echec(lecture.erreur!);
    }
    final Signalement signalement = lecture.donnee!;
    final String moiId = _moi.id;
    final Set<String> qui = _confirmations.putIfAbsent(id, () => {});
    final String? refus = SignalementRepository.refusConfirmation(
      signalement,
      moiId,
      qui.contains(moiId),
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Ma fiche + le compteur, ensemble (comme le WriteBatch de Firebase)
    qui.add(moiId);
    _signalements[_position(id)] = signalement.copyWith(
      nbConfirmations: signalement.nbConfirmations + 1,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> changerStatut(
    String id,
    StatutSignalement statut,
  ) async {
    final String? refus = _refusDeBase() ??
        SignalementRepository.refusChangementStatut(_moi);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final int position = _position(id);
    if (position == -1) {
      return const Resultat.echec('Ce signalement n\'existe plus');
    }
    _signalements[position] = _signalements[position].copyWith(statut: statut);
    return const Resultat.succes(null);
  }
}
