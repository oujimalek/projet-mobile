import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/models/sondage.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../data/services/statistiques_m4.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import 'module4_widgets.dart';

/// M4 - Statistiques du module pour l'admin : événements, participation,
/// sondages, et un graphique des événements par mois (fl_chart).
class StatistiquesScreen extends StatefulWidget {
  const StatistiquesScreen({super.key});

  @override
  State<StatistiquesScreen> createState() {
    return _StatistiquesScreenState();
  }
}

class _StatistiquesScreenState extends State<StatistiquesScreen> {
  final EvenementRepository _depot = EvenementRepository();
  StatistiquesM4? _stats;
  bool _enChargement = true;
  String? _erreur;

  static const List<String> _mois = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

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
    final Resultat<List<Evenement>> evenements = await _depot.chargerEvenements();
    final Resultat<List<Sondage>> sondages = await _depot.chargerSondages();
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      if (!evenements.estSucces || !sondages.estSucces) {
        _erreur = evenements.erreur ?? sondages.erreur;
        return;
      }
      _stats = StatistiquesM4.calculer(
          evenements.donnee!, sondages.donnee!, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget corps;
    final StatistiquesM4? stats = _stats;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_erreur != null || stats == null) {
      corps = MessageM4(
        texte: _erreur ?? 'Statistiques indisponibles',
        icone: Icons.error_outline,
        reessayer: _charger,
      );
    } else {
      corps = RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _tuile('${stats.nbEvenements}', 'Événements', AppColors.primary),
              const SizedBox(width: 10),
              _tuile('${stats.nbAVenir}', 'À venir', AppColors.secondary),
              const SizedBox(width: 10),
              _tuile('${stats.nbAnnules}', 'Annulés', AppColors.error),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _tuile('${stats.totalParticipants}', 'Inscriptions', AppColors.success),
              const SizedBox(width: 10),
              _tuile(stats.participationMoyenne.toStringAsFixed(1),
                  'Inscrits par\névénement passé', AppColors.primary),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _tuile('${stats.nbSondages}', 'Sondages', AppColors.primary),
              const SizedBox(width: 10),
              _tuile('${stats.nbSondagesOuverts}', 'En cours', AppColors.secondary),
              const SizedBox(width: 10),
              _tuile('${(stats.tauxVoteMoyen * 100).round()} %',
                  'Participation\naux votes', AppColors.success),
            ]),
            const SizedBox(height: 20),
            const Text('Événements par mois',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            AppCard(child: SizedBox(height: 180, child: _graphique(stats))),
            const SizedBox(height: 20),
            const Text('Les plus suivis',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (stats.plusPopulaires.isEmpty)
              Text('Pas encore d\'événement',
                  style: TextStyle(color: AppColors.textSecondary)),
            for (int i = 0; i < stats.plusPopulaires.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Row(
                    children: [
                      Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(stats.plusPopulaires[i].titre,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text('${stats.plusPopulaires[i].participants} inscrits'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Statistiques'),
          Expanded(child: corps),
        ],
      ),
    );
  }

  Widget _tuile(String valeur, String libelle, Color couleur) {
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valeur,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: couleur)),
            const SizedBox(height: 4),
            Text(libelle,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Barres : nombre d'événements de chacun des 6 derniers mois.
  Widget _graphique(StatistiquesM4 stats) {
    final DateTime maintenant = DateTime.now();
    int maximum = 1;
    for (final int nombre in stats.evenementsParMois) {
      if (nombre > maximum) {
        maximum = nombre;
      }
    }
    return BarChart(
      BarChartData(
        maxY: maximum.toDouble() + 1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (valeur, meta) {
                final DateTime mois =
                    StatistiquesM4.moisAvant(maintenant, 5 - valeur.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_mois[mois.month - 1],
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < 6; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: stats.evenementsParMois[i].toDouble(),
                color: i == 5 ? AppColors.secondary : AppColors.primary,
                width: 18,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }
}
