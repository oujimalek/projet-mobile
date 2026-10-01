import 'package:flutter/material.dart';

import '../../widgets/coming_soon.dart';

/// M2 - Services : liste des services entre voisins.
///
/// PLACEHOLDER : remplacer le contenu de ce fichier en phase 2
/// (garder le nom de la classe ServicesListScreen).
///
/// À utiliser pour le vrai écran :
///   - ListView.builder pour la liste, AppCard pour chaque service
///   - filtres : ServiceRepository().getCategories()
///   - données : ServiceRepository().getServicesParCategorie(categorie)
///   - services communs : ServiceRepository().getServicesCommuns()
class ServicesListScreen extends StatelessWidget {
  const ServicesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      body: const ComingSoon(module: 'Module 2 - Services\nListe des services'),
    );
  }
}
