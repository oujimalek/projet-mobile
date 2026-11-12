import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/signalement.dart';
import '../models/utilisateur.dart';
import '../resultat.dart';
import 'firebase_signalement_repository.dart';
import 'photos_m3.dart';

/// M3 - Accès aux signalements du quartier : le CONTRAT.
///
/// Implémentations :
/// - FirebaseSignalementRepository : Cloud Firestore (celle de l'application) ;
/// - MockSignalementRepository (dans test/) : données en mémoire, que les
///   tests installent avec `SignalementRepository.instance = ...`.
///
/// Les méthodes réseau renvoient `Future<Resultat<...>>` (voir
/// lib/data/resultat.dart) : en cas d'échec, `resultat.erreur` contient un
/// message en français, prêt à afficher.
///
/// Les règles métier (méthodes `static refus...`) sont ici, communes à
/// Firebase et au mock. firestore.rules vérifie la même chose côté serveur.
abstract class SignalementRepository {
  /// L'implémentation utilisée par toute l'application.
  static SignalementRepository instance = FirebaseSignalementRepository();

  /// `SignalementRepository()` renvoie l'instance ci-dessus (pas de nouvel objet).
  factory SignalementRepository() {
    return instance;
  }

  // =====================================================================
  // Catégories (dans le code, pas dans Firestore : une icône ne s'y range pas)
  // =====================================================================

  /// Les catégories affichées dans la GridView de création de signalement.
  /// Getter (pas une constante) : les couleurs d'AppColors changent avec le
  /// thème clair / sombre, la liste est donc refaite à chaque appel.
  static List<CategorieSignalement> get categories => [
    CategorieSignalement(
      id: 'electricite',
      nom: 'Électricité',
      icone: Icons.bolt,
      couleur: AppColors.electricite,
      couleurClaire: AppColors.electriciteLight,
    ),
    CategorieSignalement(
      id: 'eau',
      nom: 'Eau',
      icone: Icons.water_drop,
      couleur: AppColors.eau,
      couleurClaire: AppColors.eauLight,
    ),
    CategorieSignalement(
      id: 'ordures',
      nom: 'Ordures',
      icone: Icons.delete_outline,
      couleur: AppColors.ordures,
      couleurClaire: AppColors.orduresLight,
    ),
    CategorieSignalement(
      id: 'travaux',
      nom: 'Travaux',
      icone: Icons.construction,
      couleur: AppColors.travaux,
      couleurClaire: AppColors.travauxLight,
    ),
    CategorieSignalement(
      id: 'incident',
      nom: 'Incident',
      icone: Icons.warning_amber_rounded,
      couleur: AppColors.incident,
      couleurClaire: AppColors.incidentLight,
    ),
  ];

  /// Les ids des catégories, dans l'ordre (pour les filtres).
  static const List<String> idsCategories = [
    'electricite',
    'eau',
    'ordures',
    'travaux',
    'incident',
  ];

  /// Retrouve une catégorie à partir de son id.
  /// Si l'id n'existe pas, on renvoie la catégorie "Incident".
  static CategorieSignalement getCategorieParId(String id) {
    for (final CategorieSignalement categorie in categories) {
      if (categorie.id == id) {
        return categorie;
      }
    }
    return categories.last;
  }

  /// La catégorie existe-t-elle ?
  static bool categorieExiste(String? id) {
    return idsCategories.contains(id);
  }

  // =====================================================================
  // Règles métier (communes à Firebase et au mock)
  // =====================================================================

  /// Nom court affiché sur un signalement (ex : "Amira B.").
  static String nomCourt(Utilisateur utilisateur) {
    String initialeNom = '';
    if (utilisateur.nom.isNotEmpty) {
      initialeNom = ' ${utilisateur.nom[0]}.';
    }
    return '${utilisateur.prenom}$initialeNom';
  }

  /// Pourquoi ce formulaire est refusé (null : il est valable).
  static String? refusSignalement({
    required String titre,
    required String description,
    required String lieu,
    required String? categorieId,
  }) {
    if (!categorieExiste(categorieId)) {
      return 'Choisis une catégorie';
    }
    return refusTitre(titre) ?? refusDescription(description) ?? refusLieu(lieu);
  }

  /// La photo : absente, ou une adresse de NOTRE compte Cloudinary (comme
  /// la règle firestore.rules).
  static String? refusPhoto(String? photoUrl) {
    if (photoUrl != null && !PhotosM3.estPhotoValide(photoUrl)) {
      return 'Photo invalide';
    }
    return null;
  }

  /// Le titre : 3 à 80 caractères (aussi le validator du formulaire).
  static String? refusTitre(String? titre) {
    final String texte = (titre ?? '').trim();
    if (texte.length < 3) {
      return 'Le titre doit avoir au moins 3 caractères';
    }
    if (texte.length > 80) {
      return 'Le titre doit avoir au plus 80 caractères';
    }
    return null;
  }

  /// La description : au moins 10 caractères.
  static String? refusDescription(String? description) {
    if ((description ?? '').trim().length < 10) {
      return 'La description doit avoir au moins 10 caractères';
    }
    return null;
  }

  /// Le lieu : au moins 2 caractères.
  static String? refusLieu(String? lieu) {
    if ((lieu ?? '').trim().length < 2) {
      return 'Indique le lieu du problème';
    }
    return null;
  }

  /// Pourquoi [moi] ne peut rien faire dans les signalements (null : il peut).
  /// Comme firestore.rules : connecté, avec un quartier, compte actif.
  static String? refusUtilisateur(Utilisateur moi) {
    if (moi.id.isEmpty) {
      return 'Tu n\'es pas connecté';
    }
    if ((moi.quartierId ?? '').isEmpty) {
      return 'Choisis d\'abord ton quartier';
    }
    if (moi.statut != StatutUtilisateur.actif) {
      return 'Ton compte doit être validé par l\'admin';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas modifier ce signalement (null : il peut).
  static String? refusModification(Signalement signalement, String moiId) {
    if (signalement.auteurId != moiId) {
      return 'Seul l\'auteur peut modifier ce signalement';
    }
    if (!signalement.estEnAttente) {
      return 'Ce signalement est déjà pris en charge, il ne peut plus être modifié';
    }
    return null;
  }

  /// Pourquoi [moi] ne peut pas supprimer ce signalement (null : il peut).
  /// L'auteur tant qu'il est en attente, ou l'admin.
  static String? refusSuppression(Signalement signalement, Utilisateur moi) {
    if (moi.estAdmin) {
      return null;
    }
    if (signalement.auteurId != moi.id) {
      return 'Seul l\'auteur peut supprimer ce signalement';
    }
    if (!signalement.estEnAttente) {
      return 'Ce signalement est déjà pris en charge, il ne peut plus être supprimé';
    }
    return null;
  }

  /// Pourquoi [moiId] ne peut pas confirmer ce signalement (null : il peut).
  static String? refusConfirmation(
    Signalement signalement,
    String moiId,
    bool dejaConfirme,
  ) {
    if (signalement.auteurId == moiId) {
      return 'Tu ne peux pas confirmer ton propre signalement';
    }
    if (signalement.estCloture) {
      return 'Ce signalement est déjà clôturé';
    }
    if (dejaConfirme) {
      return 'Tu as déjà confirmé ce signalement';
    }
    return null;
  }

  /// Pourquoi [moi] ne peut pas changer le statut (null : il peut).
  static String? refusChangementStatut(Utilisateur moi) {
    if (!moi.estAdmin) {
      return 'Seul l\'admin du quartier peut changer le statut';
    }
    return null;
  }

  // =====================================================================
  // Urgence : calculée dans l'application, jamais rangée dans Firestore
  // =====================================================================

  /// Les points d'une catégorie : 2 pour incident, électricité, eau
  /// (risque pour les personnes ou coupure), 1 pour travaux et ordures.
  static int pointsCategorie(String categorieId) {
    if (categorieId == 'incident' ||
        categorieId == 'electricite' ||
        categorieId == 'eau') {
      return 2;
    }
    return 1;
  }

  /// Le score d'urgence :
  ///   points de la catégorie (1 ou 2)
  /// + 2 si danger pour les personnes
  /// + 2 si au moins 10 confirmations, 1 si au moins 3.
  static int scoreUrgence(Signalement signalement) {
    int score = pointsCategorie(signalement.categorieId);
    if (signalement.danger) {
      score += 2;
    }
    if (signalement.nbConfirmations >= 10) {
      score += 2;
    } else if (signalement.nbConfirmations >= 3) {
      score += 1;
    }
    return score;
  }

  /// Le niveau d'urgence : score 0-1 faible, 2-3 normal, 4 et plus urgent.
  static NiveauUrgence niveauUrgence(Signalement signalement) {
    final int score = scoreUrgence(signalement);
    if (score >= 4) {
      return NiveauUrgence.urgent;
    }
    if (score >= 2) {
      return NiveauUrgence.normal;
    }
    return NiveauUrgence.faible;
  }

  /// Une copie triée du plus urgent au moins urgent ; à score égal, du plus
  /// récent au plus ancien.
  static List<Signalement> trierParUrgence(List<Signalement> liste) {
    final List<Signalement> triee = List.of(liste);
    triee.sort((a, b) {
      final int parScore = scoreUrgence(b).compareTo(scoreUrgence(a));
      if (parScore != 0) {
        return parScore;
      }
      return b.date.compareTo(a.date);
    });
    return triee;
  }

  /// Une copie triée du plus récent au plus ancien.
  static List<Signalement> trierParDate(List<Signalement> liste) {
    final List<Signalement> triee = List.of(liste);
    triee.sort((a, b) => b.date.compareTo(a.date));
    return triee;
  }

  /// Garde les signalements d'une catégorie (null : tous).
  static List<Signalement> filtrerParCategorie(
    List<Signalement> liste,
    String? categorieId,
  ) {
    if (categorieId == null) {
      return liste;
    }
    return liste.where((s) => s.categorieId == categorieId).toList();
  }

  // =====================================================================
  // Lecture
  // =====================================================================

  /// Les signalements du quartier, les plus récents en premier.
  /// [statut] et [categorieId] : filtres optionnels (null = tous).
  Future<Resultat<List<Signalement>>> getSignalements({
    StatutSignalement? statut,
    String? categorieId,
  });

  /// Les signalements de l'utilisateur connecté, les plus récents en premier.
  Future<Resultat<List<Signalement>>> getMesSignalements();

  /// Un signalement (échec s'il n'existe plus).
  Future<Resultat<Signalement>> getSignalement(String id);

  // =====================================================================
  // Écriture
  // =====================================================================

  /// Publie un signalement. L'auteur, le statut (enAttente), la date et le
  /// compteur (0) sont remplis par le repository : seuls titre,
  /// description, categorieId, lieu et danger viennent de [signalement].
  ///
  /// Si `signalement.id` n'est pas vide, il devient l'id du document : un
  /// envoi rejoué (file hors ligne, délai dépassé) retrouve le document déjà
  /// créé et ne fait pas de doublon. Id vide : Firestore en choisit un.
  Future<Resultat<void>> ajouterSignalement(Signalement signalement);

  /// L'auteur corrige titre, description, categorieId, lieu et danger, tant
  /// que le signalement est en attente (voir [refusModification]).
  /// Changer `danger` demande la règle mise à jour dans firestore.rules.
  Future<Resultat<void>> modifierSignalement(Signalement signalement);

  /// Supprime un signalement (voir [refusSuppression]).
  Future<Resultat<void>> supprimerSignalement(String id);

  /// "Sa7, ena zeda" (moi aussi) : une confirmation par voisin, jamais sur
  /// son propre signalement (voir [refusConfirmation]).
  Future<Resultat<void>> confirmer(String id);

  /// L'utilisateur connecté a-t-il déjà confirmé ce signalement ?
  Future<Resultat<bool>> aConfirme(String id);

  /// L'admin change le statut (voir [refusChangementStatut]).
  Future<Resultat<void>> changerStatut(String id, StatutSignalement statut);
}
