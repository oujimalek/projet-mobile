import 'dart:async';

import 'package:houmani/data/models/evenement.dart';
import 'package:houmani/data/models/quartier.dart';
import 'package:houmani/data/models/sondage.dart';
import 'package:houmani/data/models/utilisateur.dart';
import 'package:houmani/data/models/vie_evenement.dart';
import 'package:houmani/data/resultat.dart';
import 'package:houmani/data/services/evenement_repository.dart';
import 'package:houmani/data/services/utilisateur_repository.dart';

/// M4 - Implémentation "en mémoire" de EvenementRepository, pour les TESTS.
///
/// Aucune donnée au départ : chaque test ajoute ce dont il a besoin avec
/// [ajouterEvenementDe] et [ajouterSondageDe]. Mêmes règles que
/// FirebaseEvenementRepository (EvenementRepository.refus...). Sans Internet.
class MockEvenementRepository implements EvenementRepository {
  final List<Evenement> _evenements = [];
  final List<Sondage> _sondages = [];

  // evenementId → (uid → nom) des participants
  final Map<String, Map<String, String>> _participants = {};
  // sondageId → (uid → choix) des votes
  final Map<String, Map<String, int>> _votes = {};

  int _compteur = 0;

  /// Si ce n'est pas null : toutes les opérations réseau échouent avec ce message.
  String? erreur;

  /// Nombre de membres renvoyé dans les sondages chargés.
  int nombreMembres = 0;

  /// Les événements enregistrés (pour vérifier les tests).
  List<Evenement> get evenements => List.of(_evenements);

  /// Les sondages enregistrés, SANS les votes (pour vérifier les tests).
  List<Sondage> get sondages => List.of(_sondages);

  String _nouvelId(String prefixe) {
    _compteur++;
    return '$prefixe$_compteur';
  }

  Utilisateur _moi() {
    return UtilisateurRepository().getUtilisateurConnecte();
  }

  /// Ajoute directement un événement organisé par [organisateur].
  Evenement ajouterEvenementDe(
    Utilisateur organisateur, {
    String titre = 'Fête des voisins',
    String description = '',
    String lieu = 'Jardin de la résidence',
    DateTime? date,
    DateTime? dateFin,
    CategorieEvenement categorie = CategorieEvenement.fete,
    bool annule = false,
    bool? officiel, // par défaut : officiel si l'organisateur est admin
    int placesMax = 0,
    PointGps? position,
  }) {
    final Evenement evenement = Evenement(
      id: _nouvelId('e'),
      titre: titre,
      description: description,
      date: date ?? DateTime.now().add(const Duration(days: 7)),
      dateFin: dateFin,
      lieu: lieu,
      categorie: categorie,
      organisateurId: organisateur.id,
      organisateur: EvenementRepository.nomCourt(organisateur),
      annule: annule,
      officiel: officiel ?? organisateur.estAdmin,
      placesMax: placesMax,
      position: position,
    );
    _evenements.add(evenement);
    _participants[evenement.id] = {};
    _interesses[evenement.id] = {};
    return evenement;
  }

  /// Ajoute directement un sondage proposé par [auteur].
  Sondage ajouterSondageDe(
    Utilisateur auteur, {
    String question = 'Quelle date pour la réunion ?',
    List<String> options = const ['Mardi', 'Jeudi'],
    DateTime? dateFin,
    List<DateTime> dates = const [],
    String? evenementId,
    DateTime? dateCreation,
  }) {
    final List<OptionSondage> choix = [];
    final List<String> textes =
        dates.isNotEmpty ? EvenementRepository.textesDates(dates) : options;
    for (final String texte in textes) {
      choix.add(OptionSondage(texte: texte));
    }
    final Sondage sondage = Sondage(
      id: _nouvelId('p'),
      question: question,
      options: choix,
      dateFin: dateFin ?? DateTime.now().add(const Duration(days: 2)),
      proposeParId: auteur.id,
      proposePar: EvenementRepository.nomCourt(auteur),
      dates: dates,
      evenementId: evenementId,
      dateCreation: dateCreation ?? DateTime.now(),
    );
    _sondages.add(sondage);
    _votes[sondage.id] = {};
    return sondage;
  }

  /// Ajoute directement le vote de [votant].
  void ajouterVoteDe(Utilisateur votant, Sondage sondage, int choix) {
    _votes[sondage.id]![votant.id] = choix;
  }

  int _index(String evenementId) {
    return _evenements.indexWhere((e) => e.id == evenementId);
  }

  /// Le sondage avec ses votes comptés (comme count() côté Firebase).
  Sondage _avecVotes(Sondage sondage) {
    final List<OptionSondage> options = [];
    for (int i = 0; i < sondage.options.length; i++) {
      int votes = 0;
      for (final int choix in _votes[sondage.id]!.values) {
        if (choix == i) {
          votes++;
        }
      }
      options.add(OptionSondage(texte: sondage.options[i].texte, votes: votes));
    }
    return Sondage(
      id: sondage.id,
      question: sondage.question,
      options: options,
      dateFin: sondage.dateFin,
      proposeParId: sondage.proposeParId,
      proposePar: sondage.proposePar,
      nombreMembres: nombreMembres,
      dates: sondage.dates,
      evenementId: sondage.evenementId,
      dateCreation: sondage.dateCreation,
    );
  }

  // =====================================================================
  // Événements
  // =====================================================================

  @override
  List<Evenement> getEvenements() {
    final List<Evenement> aVenir = [];
    for (final Evenement evenement in _evenements) {
      if (!evenement.estPasse && !evenement.annule) {
        aVenir.add(evenement);
      }
    }
    aVenir.sort((a, b) => a.date.compareTo(b.date));
    return aVenir;
  }

  @override
  Future<Resultat<List<Evenement>>> chargerEvenements() async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final List<Evenement> liste = List.of(_evenements);
    liste.sort((a, b) => a.date.compareTo(b.date));
    return Resultat.succes(liste);
  }

  @override
  Future<Resultat<Evenement>> getEvenement(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Cet événement n\'existe plus');
    }
    return Resultat.succes(_evenements[index]);
  }

  @override
  Future<Resultat<void>> creerEvenement({
    required String titre,
    required String description,
    required DateTime date,
    DateTime? dateFin,
    required String lieu,
    required CategorieEvenement categorie,
    int placesMax = 0,
    PointGps? position,
  }) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final String? refus = EvenementRepository.refusEvenement(
          titre: titre,
          description: description,
          lieu: lieu,
          date: date,
          dateFin: dateFin,
        ) ??
        EvenementRepository.refusPlaces(placesMax);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    if (!EvenementRepository.peutOrganiser(_moi())) {
      return const Resultat.echec(EvenementRepository.refusOrganiser);
    }
    ajouterEvenementDe(
      _moi(),
      titre: titre.trim(),
      description: description.trim(),
      lieu: lieu.trim(),
      date: date,
      dateFin: dateFin,
      categorie: categorie,
      placesMax: placesMax,
      position: position,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> modifierEvenement(Evenement evenement) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenement.id);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutModifier(_moi(), _evenements[index])) {
      return const Resultat.echec(
          'Seul l\'organisateur ou l\'admin peut modifier l\'événement');
    }
    final String? refus = EvenementRepository.refusEvenement(
          titre: evenement.titre,
          description: evenement.description,
          lieu: evenement.lieu,
          date: evenement.date,
          dateFin: evenement.dateFin,
        ) ??
        EvenementRepository.refusPlaces(evenement.placesMax,
            inscrits: _evenements[index].participants);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    // Le compteur ne change pas (comme dans les règles)
    _evenements[index] = _evenements[index].copyWith(
      titre: evenement.titre.trim(),
      description: evenement.description.trim(),
      lieu: evenement.lieu.trim(),
      date: evenement.date,
      dateFin: evenement.dateFin,
      sansFin: evenement.dateFin == null,
      categorie: evenement.categorie,
      placesMax: evenement.placesMax,
      position: evenement.position,
      sansPosition: evenement.position == null,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerEvenement(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutSupprimer(
        _moi(), _evenements[index].organisateurId)) {
      return const Resultat.echec('Action non autorisée');
    }
    _evenements.removeAt(index);
    _participants.remove(evenementId);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<bool>> estInscrit(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, String>? fiches = _participants[evenementId];
    return Resultat.succes(fiches != null && fiches.containsKey(_moi().id));
  }

  @override
  Future<Resultat<List<Participant>>> getParticipants(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, String> fiches = _participants[evenementId] ?? {};
    final List<Participant> liste = [];
    fiches.forEach((uid, nom) {
      liste.add(Participant(id: uid, nom: nom, avatar: _avatars[uid] ?? ''));
    });
    return Resultat.succes(liste);
  }

  final Map<String, String> _avatars = {}; // uid → avatar (module 1)

  @override
  Future<Resultat<void>> annulerEvenement(Evenement evenement, bool annule) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenement.id);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutModifier(_moi(), _evenements[index])) {
      return const Resultat.echec(
          'Seul l\'organisateur ou l\'admin peut annuler l\'événement');
    }
    _evenements[index] = _evenements[index].copyWith(annule: annule);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> participer(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    final Utilisateur moi = _moi();
    if (_participants[evenementId]!.containsKey(moi.id)) {
      return const Resultat.echec('Tu participes déjà à cet événement');
    }
    final List<String> attente = _attente[evenementId] ?? [];
    final String? refus = EvenementRepository.refusParticipation(
      _evenements[index],
      attente: attente,
      moiId: moi.id,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    attente.remove(moi.id); // j'étais en attente : j'en sors
    _participants[evenementId]![moi.id] = EvenementRepository.nomCourt(moi);
    _avatars[moi.id] = moi.avatar;
    final Evenement evenement = _evenements[index];
    _evenements[index] =
        evenement.copyWith(participants: evenement.participants + 1);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> seRetirer(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (_participants[evenementId]!.remove(_moi().id) == null) {
      return const Resultat.echec('Tu ne participes pas à cet événement');
    }
    final Evenement evenement = _evenements[index];
    _evenements[index] =
        evenement.copyWith(participants: evenement.participants - 1);
    return const Resultat.succes(null);
  }

  final Map<String, Set<String>> _interesses = {}; // evenementId → uids

  @override
  Future<Resultat<bool>> estInteresse(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_interesses[evenementId]?.contains(_moi().id) ?? false);
  }

  @override
  Future<Resultat<void>> changerInteret(String evenementId, bool interesse) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _index(evenementId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    final Set<String> uids = _interesses[evenementId]!;
    final bool deja = uids.contains(_moi().id);
    if (deja == interesse) {
      return const Resultat.succes(null);
    }
    if (interesse) {
      uids.add(_moi().id);
    } else {
      uids.remove(_moi().id);
    }
    final Evenement evenement = _evenements[index];
    _evenements[index] = evenement.copyWith(
        interesses: evenement.interesses + (interesse ? 1 : -1));
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Sondages
  // =====================================================================

  /// Les ouverts (fin la plus proche d'abord), puis les terminés (récents d'abord).
  List<Sondage> _tries() {
    final List<Sondage> ouverts = [];
    final List<Sondage> termines = [];
    for (final Sondage sondage in _sondages) {
      if (sondage.estOuvert) {
        ouverts.add(_avecVotes(sondage));
      } else {
        termines.add(_avecVotes(sondage));
      }
    }
    ouverts.sort((a, b) => a.dateFin.compareTo(b.dateFin));
    termines.sort((a, b) => b.dateFin.compareTo(a.dateFin));
    return [...ouverts, ...termines];
  }

  @override
  Sondage? getSondageActif() {
    for (final Sondage sondage in _tries()) {
      if (sondage.estOuvert) {
        return sondage;
      }
    }
    return null;
  }

  @override
  Future<Resultat<List<Sondage>>> chargerSondages() async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_tries());
  }

  @override
  Future<Resultat<void>> creerSondage({
    required String question,
    required List<String> options,
    required DateTime dateFin,
    List<DateTime> dates = const [],
    String? evenementId,
  }) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    if (dates.isNotEmpty) {
      options = EvenementRepository.textesDates(dates);
    }
    final String? refus = EvenementRepository.refusSondage(
      question: question,
      options: options,
      dateFin: dateFin,
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final List<String> remplies = [];
    for (final String texte in options) {
      if (texte.trim().isNotEmpty) {
        remplies.add(texte.trim());
      }
    }
    if (!EvenementRepository.peutOrganiser(_moi())) {
      return const Resultat.echec(EvenementRepository.refusOrganiser);
    }
    ajouterSondageDe(
      _moi(),
      question: question.trim(),
      options: remplies,
      dateFin: dateFin,
      dates: dates,
      evenementId: evenementId,
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<List<Sondage>>> chargerSondagesDe(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final List<Sondage> liste = [];
    for (final Sondage sondage in _sondages) {
      if (sondage.evenementId == evenementId) {
        liste.add(_avecVotes(sondage));
      }
    }
    return Resultat.succes(liste);
  }

  @override
  Future<Resultat<void>> supprimerSondage(String sondageId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final int index = _sondages.indexWhere((s) => s.id == sondageId);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutSupprimer(
        _moi(), _sondages[index].proposeParId)) {
      return const Resultat.echec('Action non autorisée');
    }
    _sondages.removeAt(index);
    _votes.remove(sondageId);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<int?>> getMonVote(String sondageId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(_votes[sondageId]?[_moi().id]);
  }

  @override
  Future<Resultat<void>> voter(Sondage sondage, int choix) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final Map<String, int>? votes = _votes[sondage.id];
    if (votes == null) {
      return const Resultat.echec('Donnée introuvable');
    }
    final String moi = _moi().id;
    final String? refus =
        EvenementRepository.refusVote(sondage, choix, votes[moi]);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    votes[moi] = choix;
    _changementVotes.add(null); // les écrans en direct se mettent à jour
    return const Resultat.succes(null);
  }

  // Prévient les écrans qui écoutent les votes (comme snapshots())
  final StreamController<void> _changementVotes = StreamController<void>.broadcast();

  List<int> _compter(String sondageId, int nbOptions) {
    final List<int> compteurs = List.filled(nbOptions, 0);
    for (final int choix in (_votes[sondageId] ?? {}).values) {
      if (choix >= 0 && choix < nbOptions) {
        compteurs[choix]++;
      }
    }
    return compteurs;
  }

  @override
  Stream<List<int>> ecouterVotes(String sondageId, int nbOptions) async* {
    yield _compter(sondageId, nbOptions);
    await for (final _ in _changementVotes.stream) {
      yield _compter(sondageId, nbOptions);
    }
  }

  /// Un voisin vote pendant que l'écran est ouvert (test du « en direct »).
  void voteEnDirect(Utilisateur votant, Sondage sondage, int choix) {
    ajouterVoteDe(votant, sondage, choix);
    _changementVotes.add(null);
  }

  // =====================================================================
  // Questions, objets à apporter, avis
  // =====================================================================

  final Map<String, List<Commentaire>> _commentaires = {};
  final Map<String, List<ObjetAApporter>> _objets = {};
  final Map<String, List<AvisEvenement>> _avis = {};

  Evenement? _parId(String evenementId) {
    final int index = _index(evenementId);
    return index < 0 ? null : _evenements[index];
  }

  @override
  Future<Resultat<List<Commentaire>>> getCommentaires(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(List.of(_commentaires[evenementId] ?? []));
  }

  @override
  Future<Resultat<void>> ajouterCommentaire(String evenementId, String texte) async {
    final String? refus = EvenementRepository.refusCommentaire(texte);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    final Utilisateur moi = _moi();
    _commentaires.putIfAbsent(evenementId, () => []).add(Commentaire(
          id: _nouvelId('c'),
          auteurId: moi.id,
          auteurNom: EvenementRepository.nomCourt(moi),
          texte: texte.trim(),
          date: DateTime.now(),
        ));
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerCommentaire(
      String evenementId, String commentaireId) async {
    final List<Commentaire> liste = _commentaires[evenementId] ?? [];
    final int index = liste.indexWhere((c) => c.id == commentaireId);
    final Evenement? evenement = _parId(evenementId);
    if (index < 0 || evenement == null) {
      return const Resultat.echec('Donnée introuvable');
    }
    if (!EvenementRepository.peutSupprimerCommentaire(
        _moi(), liste[index], evenement)) {
      return const Resultat.echec('Action non autorisée');
    }
    liste.removeAt(index);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<List<ObjetAApporter>>> getObjets(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(List.of(_objets[evenementId] ?? []));
  }

  @override
  Future<Resultat<void>> ajouterObjet(Evenement evenement, String objet) async {
    if (!EvenementRepository.peutModifier(_moi(), evenement)) {
      return const Resultat.echec('Seul l\'organisateur ou l\'admin gère la liste');
    }
    final String? refus = EvenementRepository.refusObjet(objet);
    if (refus != null) {
      return Resultat.echec(refus);
    }
    _objets
        .putIfAbsent(evenement.id, () => [])
        .add(ObjetAApporter(id: _nouvelId('o'), objet: objet.trim()));
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> supprimerObjet(Evenement evenement, String objetId) async {
    if (!EvenementRepository.peutModifier(_moi(), evenement)) {
      return const Resultat.echec('Seul l\'organisateur ou l\'admin gère la liste');
    }
    _objets[evenement.id]?.removeWhere((o) => o.id == objetId);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> prendreObjet(
      String evenementId, ObjetAApporter objet, bool prendre) async {
    final Utilisateur moi = _moi();
    final List<ObjetAApporter> liste = _objets[evenementId] ?? [];
    final int index = liste.indexWhere((o) => o.id == objet.id);
    if (index < 0) {
      return const Resultat.echec('Donnée introuvable');
    }
    final ObjetAApporter actuel = liste[index];
    if (actuel.estPris && actuel.prisParId != moi.id) {
      return Resultat.echec('${actuel.prisParNom} s\'en charge déjà');
    }
    liste[index] = ObjetAApporter(
      id: actuel.id,
      objet: actuel.objet,
      prisParId: prendre ? moi.id : null,
      prisParNom: prendre ? EvenementRepository.nomCourt(moi) : '',
    );
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<List<AvisEvenement>>> getAvis(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    return Resultat.succes(List.of(_avis[evenementId] ?? []));
  }

  @override
  Future<Resultat<void>> donnerAvis(
      Evenement evenement, int note, String commentaire) async {
    final Utilisateur moi = _moi();
    final List<AvisEvenement> liste = _avis.putIfAbsent(evenement.id, () => []);
    final String? refus = EvenementRepository.refusAvis(
      _parId(evenement.id) ?? evenement,
      note,
      participe: _participants[evenement.id]?.containsKey(moi.id) ?? false,
      dejaDonne: liste.any((a) => a.id == moi.id),
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    liste.add(AvisEvenement(
      id: moi.id,
      nom: EvenementRepository.nomCourt(moi),
      note: note,
      commentaire: commentaire.trim(),
    ));
    return const Resultat.succes(null);
  }

  // =====================================================================
  // Liste d'attente
  // =====================================================================

  final Map<String, List<String>> _attente = {}; // evenementId → uids, dans l'ordre
  final Map<String, String> _nomsAttente = {}; // uid → nom

  @override
  Future<Resultat<List<Participant>>> getAttente(String evenementId) async {
    if (erreur != null) {
      return Resultat.echec(erreur!);
    }
    final List<Participant> liste = [];
    for (final String uid in _attente[evenementId] ?? []) {
      liste.add(Participant(id: uid, nom: _nomsAttente[uid] ?? ''));
    }
    return Resultat.succes(liste);
  }

  @override
  Future<Resultat<void>> rejoindreAttente(Evenement evenement) async {
    final Utilisateur moi = _moi();
    final List<String> liste = _attente.putIfAbsent(evenement.id, () => []);
    final String? refus = EvenementRepository.refusAttente(
      _parId(evenement.id) ?? evenement,
      inscrit: _participants[evenement.id]?.containsKey(moi.id) ?? false,
      dejaEnAttente: liste.contains(moi.id),
    );
    if (refus != null) {
      return Resultat.echec(refus);
    }
    liste.add(moi.id);
    _nomsAttente[moi.id] = EvenementRepository.nomCourt(moi);
    return const Resultat.succes(null);
  }

  @override
  Future<Resultat<void>> quitterAttente(String evenementId) async {
    _attente[evenementId]?.remove(_moi().id);
    return const Resultat.succes(null);
  }

  /// Simule l'absence d'Internet (les données viennent de la copie locale).
  @override
  bool horsLigne = false;
}
