import 'package:flutter/material.dart';

import '../../data/models/creneau_commun.dart';
import '../../data/services/service_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import 'module2_outils.dart';
import 'module2_widgets.dart';

/// M2 - Inscription à un créneau d'un service commun (écran 07).
///
/// On voit les prochains créneaux du service (libres ou pris), on en
/// choisit un, et on s'inscrit. Si on est déjà inscrit, on peut se désister.
class InscriptionCreneauScreen extends StatefulWidget {
  final String creneauId; // le créneau touché dans le planning

  const InscriptionCreneauScreen({super.key, required this.creneauId});

  @override
  State<InscriptionCreneauScreen> createState() {
    return _InscriptionCreneauScreenState();
  }
}

class _InscriptionCreneauScreenState extends State<InscriptionCreneauScreen> {
  final ServiceRepository _repository = ServiceRepository();

  String? _creneauChoisi; // id du créneau sélectionné, null = aucun
  bool _rappelVeille = false;

  @override
  void initState() {
    super.initState();
    // Le créneau touché dans le planning est sélectionné au départ
    final CreneauCommun? depart = _repository.getCreneauParId(widget.creneauId);
    if (depart != null && _peutEtreChoisi(depart)) {
      _creneauChoisi = depart.id;
    }
  }

  /// On peut choisir un créneau libre ou le sien (pour se désister).
  bool _peutEtreChoisi(CreneauCommun creneau) {
    return creneau.estLibre || creneau.inscrit == _repository.getMonNom();
  }

  /// Les créneaux du service à partir d'aujourd'hui.
  List<CreneauCommun> _prochainsCreneaux(String serviceId) {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final List<CreneauCommun> resultat = [];
    for (final creneau in _repository.getCreneauxParService(serviceId)) {
      if (!creneau.date.isBefore(aujourdhui)) {
        resultat.add(creneau);
      }
    }
    return resultat;
  }

  /// Les jours où le service a lieu, ex : "lundi, mercredi, vendredi".
  String _jours(List<CreneauCommun> creneaux) {
    final List<int> numeros = [];
    for (final creneau in creneaux) {
      if (!numeros.contains(creneau.date.weekday)) {
        numeros.add(creneau.date.weekday);
      }
    }
    numeros.sort();
    final List<String> noms = [];
    for (final numero in numeros) {
      // Le 1er janvier 2024 était un lundi : on s'en sert pour avoir le nom du jour
      noms.add(jourLong(DateTime(2024, 1, numero)));
    }
    return noms.join(', ');
  }

  /// "Je m'inscris".
  void _inscrire() {
    final bool ok = _repository.inscrire(_creneauChoisi!, rappelVeille: _rappelVeille);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Inscription confirmée' : 'Ce créneau est déjà pris'),
      ),
    );
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _creneauChoisi = null;
      });
    }
  }

  /// "Se désister d'un créneau".
  void _desister() {
    final bool ok = _repository.desinscrire(_creneauChoisi!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Désinscription enregistrée' : 'Désinscription impossible'),
      ),
    );
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CreneauCommun? depart = _repository.getCreneauParId(widget.creneauId);

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: 'Inscription à un créneau'),
          Expanded(
            child: depart == null
                ? const Center(
                    child: Text(
                      'Ce créneau n\'existe plus',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : _contenu(depart),
          ),
        ],
      ),
    );
  }

  Widget _contenu(CreneauCommun depart) {
    final List<CreneauCommun> creneaux = _prochainsCreneaux(depart.serviceId);
    final String moi = _repository.getMonNom();

    // Le créneau sélectionné : libre (on s'inscrit) ou à moi (on se désiste)
    CreneauCommun? choisi;
    bool jeSuisInscrit = false;
    for (final creneau in creneaux) {
      if (creneau.id == _creneauChoisi) {
        choisi = creneau;
      }
      if (creneau.inscrit == moi) {
        jeSuisInscrit = true;
      }
    }
    final bool choisiLibre = choisi != null && choisi.estLibre;
    final bool choisiEstMoi = choisi != null && choisi.inscrit == moi;

    final List<Widget> lignes = [];
    for (final creneau in creneaux) {
      lignes.add(_ligneCreneau(creneau));
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ----- Le service commun -----
              Text(
                depart.titre,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    _ligneInfo(Icons.repeat, 'Fréquence', 'Chaque semaine · ${_jours(creneaux)}'),
                    _ligneInfo(
                      Icons.schedule,
                      'Horaire',
                      '${depart.heureDebut} – ${depart.heureFin}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ----- Les créneaux -----
              const Text(
                'Choisis ton créneau',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...lignes,
              const SizedBox(height: 8),

              // ----- Rappel -----
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Me rappeler la veille',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Le rappel est enregistré, sans notification pour l\'instant',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  value: _rappelVeille,
                  activeTrackColor: AppColors.secondary,
                  activeThumbColor: AppColors.card,
                  onChanged: (valeur) {
                    setState(() {
                      _rappelVeille = valeur;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // ----- Boutons fixes en bas -----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // null = bouton désactivé (aucun créneau libre sélectionné)
                PrimaryButton(
                  texte: 'Je m\'inscris',
                  onPressed: choisiLibre ? _inscrire : null,
                ),
                if (jeSuisInscrit) ...[
                  const SizedBox(height: 10),
                  SecondaryButton(
                    texte: 'Se désister d\'un créneau',
                    onPressed: choisiEstMoi ? _desister : null,
                  ),
                  if (!choisiEstMoi)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sélectionne ton créneau (« Toi ») pour te désister',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ligneInfo(IconData icone, String titre, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icone, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(titre, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Une ligne de la liste : rond de sélection, date et heure, état.
  Widget _ligneCreneau(CreneauCommun creneau) {
    final String moi = _repository.getMonNom();
    final bool estMoi = creneau.inscrit == moi;
    final bool choisi = creneau.id == _creneauChoisi;
    final bool selectionnable = _peutEtreChoisi(creneau);

    Widget etat;
    if (creneau.estLibre) {
      etat = const PastilleTexte(
        texte: 'Libre',
        couleur: AppColors.badgeResolu,
        fond: AppColors.badgeResoluFond,
      );
    } else if (estMoi) {
      etat = const PastilleTexte(
        texte: 'Toi',
        couleur: AppColors.primary,
        fond: AppColors.primaryLight,
      );
    } else {
      etat = Text(
        'Pris par ${creneau.inscrit}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        // Un créneau pris par quelqu'un d'autre ne peut pas être choisi
        onTap: selectionnable
            ? () {
                setState(() {
                  _creneauChoisi = creneau.id;
                });
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selectionnable ? AppColors.card : AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: choisi ? AppColors.secondary : AppColors.border,
              width: choisi ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Rond de sélection (anneau doré épais quand choisi)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: choisi ? AppColors.secondary : AppColors.border,
                    width: choisi ? 6 : 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${dateCourte(creneau.date)} · ${creneau.heureDebut} – ${creneau.heureFin}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selectionnable
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              etat,
            ],
          ),
        ),
      ),
    );
  }
}
