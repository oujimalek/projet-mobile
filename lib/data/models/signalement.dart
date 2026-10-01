import 'package:flutter/material.dart';

/// Les 4 statuts possibles d'un signalement (affichés avec StatusBadge).
enum StatutSignalement { enAttente, enCours, resolu, refuse }

/// M3 - Une catégorie de signalement (électricité, eau, ordures...).
/// Chaque catégorie a son icône et ses deux couleurs (normale + très claire).
class CategorieSignalement {
  final String id;
  final String nom;
  final IconData icone;
  final Color couleur;
  final Color couleurClaire;

  const CategorieSignalement({
    required this.id,
    required this.nom,
    required this.icone,
    required this.couleur,
    required this.couleurClaire,
  });
}

/// M3 - Un signalement d'un événement du quotidien (coupure, travaux...).
class Signalement {
  final String id;
  final String titre;
  final String description;
  final String categorieId; // id d'une CategorieSignalement
  final StatutSignalement statut;
  final DateTime date;
  final String lieu;
  final String auteur;
  final int confirmations; // nombre de voisins qui ont dit "Sa7, ena zeda"

  const Signalement({
    required this.id,
    required this.titre,
    required this.description,
    required this.categorieId,
    required this.statut,
    required this.date,
    required this.lieu,
    required this.auteur,
    this.confirmations = 0,
  });
}
