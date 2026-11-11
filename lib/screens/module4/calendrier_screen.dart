import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/models/evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import 'evenement_detail_screen.dart';
import 'module4_widgets.dart';

/// M4 - Les événements dans un calendrier du mois (package table_calendar) :
/// un point sous chaque jour qui a un événement ; toucher un jour affiche
/// ses événements en dessous.
class CalendrierScreen extends StatefulWidget {
  const CalendrierScreen({super.key});

  @override
  State<CalendrierScreen> createState() {
    return _CalendrierScreenState();
  }
}

class _CalendrierScreenState extends State<CalendrierScreen> {
  final EvenementRepository _depot = EvenementRepository();

  List<Evenement> _evenements = [];
  bool _enChargement = true;
  String? _erreur;
  DateTime _moisAffiche = DateTime.now();
  DateTime _jourChoisi = DateTime.now();

  static const List<String> _mois = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet',
    'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];
  static const List<String> _joursCourts = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _enChargement = true;
      _erreur = null;
    });
    final Resultat<List<Evenement>> resultat = await _depot.chargerEvenements();
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      if (resultat.estSucces) {
        _evenements = resultat.donnee!;
      } else {
        _erreur = resultat.erreur;
      }
    });
  }

  /// Les événements d'un jour (pour les points et la liste du bas).
  List<Evenement> _evenementsDu(DateTime jour) {
    final List<Evenement> liste = [];
    for (final Evenement evenement in _evenements) {
      if (isSameDay(evenement.date, jour)) {
        liste.add(evenement);
      }
    }
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    Widget corps;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_erreur != null) {
      corps = MessageM4(
        texte: _erreur!,
        icone: Icons.error_outline,
        reessayer: _charger,
      );
    } else {
      final List<Evenement> duJour = _evenementsDu(_jourChoisi);
      corps = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(8),
            child: TableCalendar<Evenement>(
              firstDay: DateTime(DateTime.now().year - 1),
              lastDay: DateTime(DateTime.now().year + 2),
              focusedDay: _moisAffiche,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
              selectedDayPredicate: (jour) => isSameDay(jour, _jourChoisi),
              eventLoader: _evenementsDu,
              onDaySelected: (choisi, mois) {
                setState(() {
                  _jourChoisi = choisi;
                  _moisAffiche = mois;
                });
              },
              onPageChanged: (mois) {
                _moisAffiche = mois;
              },
              headerStyle: const HeaderStyle(titleCentered: true),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(color: AppColors.primary),
                selectedDecoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              // Textes en français, sans le package intl
              calendarBuilders: CalendarBuilders(
                headerTitleBuilder: (context, jour) {
                  return Text(
                    '${_mois[jour.month - 1]} ${jour.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  );
                },
                dowBuilder: (context, jour) {
                  return Center(
                    child: Text(
                      _joursCourts[jour.weekday - 1],
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            texteDate(_jourChoisi),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (duJour.isEmpty)
            Text('Aucun événement ce jour-là',
                style: TextStyle(color: AppColors.textSecondary)),
          for (final Evenement evenement in duJour) _carte(evenement),
        ],
      );
    }
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Calendrier'),
          Expanded(child: corps),
        ],
      ),
    );
  }

  Widget _carte(Evenement evenement) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () async {
          await ouvrirEcranM4<void>(
            context,
            EvenementDetailScreen(evenementId: evenement.id),
          );
          if (mounted) {
            _charger();
          }
        },
        child: Row(
          children: [
            Icon(iconeCategorie(evenement.categorie),
                color: couleurCategorie(evenement.categorie)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(evenement.titre,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${texteHoraire(evenement)} · ${evenement.lieu}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (evenement.annule)
              BadgeM4(
                texte: 'Annulé',
                couleur: AppColors.error,
                fond: AppColors.badgeRefuseFond,
              ),
          ],
        ),
      ),
    );
  }
}
