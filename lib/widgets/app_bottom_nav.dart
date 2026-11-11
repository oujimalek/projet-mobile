import 'package:flutter/material.dart';

import '../screens/module4/nouveautes_m4.dart';

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
          // M4 : un point s'il y a des nouveautés depuis la dernière visite
          icon: _IconeEvenements(Icons.event_outlined),
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

/// M4 - L'icône de l'onglet Événements, avec un point rouge et le nombre de
/// nouveautés (NouveautesM4.nombre) quand il y en a.
class _IconeEvenements extends StatelessWidget {
  final IconData icone;

  const _IconeEvenements(this.icone);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NouveautesM4.nombre,
      builder: (context, nombre, enfant) {
        return Badge(
          isLabelVisible: nombre > 0,
          label: Text('$nombre'),
          child: Icon(icone),
        );
      },
    );
  }
}
