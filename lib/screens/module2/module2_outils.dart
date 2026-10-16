import 'package:flutter/material.dart';

/// M2 - Petites fonctions partagées par les écrans du module Services.

/// Ouvre un écran EN PLEIN ÉCRAN (sans la barre du bas), par-dessus tout.
/// À utiliser avec await : on reprend la main quand l'écran se ferme.
///
/// Exemple :
///   await ouvrirEcran(context, const ServiceFormScreen());
///   if (mounted) setState(() {});
Future<T?> ouvrirEcran<T>(BuildContext context, Widget ecran) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    MaterialPageRoute<T>(builder: (context) => ecran),
  );
}

/// Initiales d'un nom, par exemple "Karim M." donne "KM".
String initiales(String nom) {
  String resultat = '';
  for (final mot in nom.split(' ')) {
    if (mot.isNotEmpty && resultat.length < 2) {
      resultat = resultat + mot[0].toUpperCase();
    }
  }
  return resultat;
}

/// Premier mot d'un nom, par exemple "Karim M." donne "Karim".
String prenomDe(String nom) {
  return nom.split(' ').first;
}

/// Temps écoulé depuis une date, en texte court : "12 min", "3 h",
/// "hier", ou la date (ex : "28/9") si c'est plus ancien.
String depuisQuand(DateTime date) {
  final Duration ecart = DateTime.now().difference(date);
  if (ecart.inMinutes < 60) {
    return '${ecart.inMinutes < 1 ? 1 : ecart.inMinutes} min';
  }
  if (ecart.inHours < 24) {
    return '${ecart.inHours} h';
  }
  if (ecart.inHours < 48) {
    return 'hier';
  }
  return '${date.day}/${date.month}';
}

const List<String> _joursCourts = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const List<String> _joursLongs = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const List<String> _moisCourts = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Jour de la semaine abrégé : "Lun", "Mar"...
String jourCourt(DateTime date) {
  return _joursCourts[date.weekday - 1];
}

/// Jour de la semaine en toutes lettres : "lundi", "mardi"...
String jourLong(DateTime date) {
  return _joursLongs[date.weekday - 1];
}

/// Date courte : "Lun. 12 oct."
String dateCourte(DateTime date) {
  return '${jourCourt(date)}. ${date.day} ${_moisCourts[date.month - 1]}';
}

/// true si les deux dates tombent le même jour.
bool memeJour(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
