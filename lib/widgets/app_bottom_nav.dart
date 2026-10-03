import 'package:flutter/material.dart';

/// Barre de navigation du bas, commune à toute l'application.
/// Les couleurs viennent du thème (onglet actif en doré).
///
/// Index des onglets :
///   0 = Accueil, 1 = Services, 2 = Signalements, 3 = Événements, 4 = Profil
class AppBottomNav extends StatelessWidget {
  final int indexActif;
  final Function(int) onTap; // fonction appelée avec l'index de l'onglet touché

  const AppBottomNav({
    super.key,
    required this.indexActif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: indexActif,
      onTap: onTap,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.handshake_outlined),
          activeIcon: Icon(Icons.handshake),
          label: 'Services',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.campaign_outlined),
          activeIcon: Icon(Icons.campaign),
          label: 'Signalements',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.event_outlined),
          activeIcon: Icon(Icons.event),
          label: 'Événements',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profil',
        ),
      ],
    );
  }
}
