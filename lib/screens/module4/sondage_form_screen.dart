import 'package:flutter/material.dart';

import '../../data/models/evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/primary_button.dart';
import 'module4_widgets.dart';

/// M4 - Formulaire d'un nouveau sondage : une question, 2 à 6 choix et
/// une date de fin. Un sondage ne se modifie plus ensuite (règles).
/// « Sondage de date » : les choix sont des dates (on pourra créer
/// l'événement à la date gagnante). [evenement] : sondage rattaché à cet
/// événement (affiché dans son détail).
/// Renvoie `true` (Navigator.pop) une fois créé.
class SondageFormScreen extends StatefulWidget {
  final Evenement? evenement;

  const SondageFormScreen({super.key, this.evenement});

  @override
  State<SondageFormScreen> createState() {
    return _SondageFormScreenState();
  }
}

class _SondageFormScreenState extends State<SondageFormScreen> {
  final EvenementRepository _depot = EvenementRepository();
  final GlobalKey<FormState> _formulaire = GlobalKey<FormState>();
  final TextEditingController _question = TextEditingController();

  // Un champ par choix : 2 au départ
  final List<TextEditingController> _choix = [
    TextEditingController(),
    TextEditingController(),
  ];

  // Sondage de date : les dates proposées (au lieu des champs texte)
  bool _deDate = false;
  final List<DateTime> _dates = [];

  // Fin par défaut : dans 3 jours, à 23:59
  late DateTime _fin = _finDuJour(DateTime.now().add(const Duration(days: 3)));
  bool _enChargement = false;
  String? _message;

  /// Ajoute une date proposée : le jour, puis l'heure.
  Future<void> _ajouterDate() async {
    // Sans ça, le clavier se rouvre sur le dernier champ quand la fenêtre se ferme
    FocusManager.instance.primaryFocus?.unfocus();
    final DateTime maintenant = DateTime.now();
    final DateTime? jour = await showDatePicker(
      context: context,
      initialDate: maintenant.add(const Duration(days: 7)),
      firstDate: maintenant,
      lastDate: maintenant.add(const Duration(days: 365)),
    );
    if (jour == null || !mounted) {
      return;
    }
    final TimeOfDay? heure = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (heure == null) {
      return;
    }
    setState(() {
      _dates.add(DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute));
      _dates.sort();
    });
  }

  @override
  void dispose() {
    _question.dispose();
    for (final TextEditingController champ in _choix) {
      champ.dispose();
    }
    super.dispose();
  }

  DateTime _finDuJour(DateTime jour) {
    return DateTime(jour.year, jour.month, jour.day, 23, 59);
  }

  void _ajouterChoix() {
    setState(() {
      _choix.add(TextEditingController());
    });
  }

  void _retirerChoix(int index) {
    setState(() {
      _choix.removeAt(index).dispose();
    });
  }

  Future<void> _choisirFin() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final DateTime maintenant = DateTime.now();
    final DateTime? choisi = await showDatePicker(
      context: context,
      initialDate: _fin,
      firstDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      lastDate: maintenant.add(const Duration(days: 90)),
    );
    if (choisi != null) {
      setState(() {
        _fin = _finDuJour(choisi);
      });
    }
  }

  Future<void> _creer() async {
    if (!_formulaire.currentState!.validate()) {
      return;
    }
    final List<String> textes = [];
    if (_deDate) {
      textes.addAll(EvenementRepository.textesDates(_dates));
    } else {
      for (final TextEditingController champ in _choix) {
        textes.add(champ.text);
      }
    }
    final String? refus = EvenementRepository.refusSondage(
      question: _question.text,
      options: textes,
      dateFin: _fin,
    );
    if (refus != null) {
      setState(() {
        _message = refus;
      });
      return;
    }

    setState(() {
      _enChargement = true;
      _message = null;
    });
    final Resultat<void> resultat = await _depot.creerSondage(
      question: _question.text,
      options: textes,
      dateFin: _fin,
      dates: _deDate ? List.of(_dates) : const [],
      evenementId: widget.evenement?.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
    });
    if (!resultat.estSucces) {
      setState(() {
        _message = resultat.erreur;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> champsChoix = [];
    for (int i = 0; i < _choix.length; i++) {
      champsChoix.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _choix[i],
                  decoration: InputDecoration(
                    hintText: 'Choix ${i + 1}',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                ),
              ),
              // On garde toujours au moins 2 champs
              if (_choix.length > EvenementRepository.optionsMin)
                IconButton(
                  tooltip: 'Retirer ce choix',
                  icon: Icon(Icons.remove_circle_outline, color: AppColors.error),
                  onPressed: () => _retirerChoix(i),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            titre: widget.evenement == null
                ? 'Nouveau sondage'
                : 'Sondage · ${widget.evenement!.titre}',
          ),
          Expanded(
            child: Form(
              key: _formulaire,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  AppTextField(
                    label: 'Question',
                    hint: 'Ex : Quelle date pour la réunion de résidence ?',
                    controller: _question,
                    lignes: 2,
                    validator: (valeur) {
                      if (valeur == null || valeur.trim().isEmpty) {
                        return 'Écris la question du sondage';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  // Sondage de date : les choix sont des dates
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Sondage de date', 'Sondage mta3 date')),
                    subtitle: const Text(
                        'Les voisins choisissent une date ; ensuite tu crées l\'événement à la date gagnante'),
                    value: _deDate,
                    onChanged: (valeur) {
                      setState(() {
                        _deDate = valeur;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les choix (${EvenementRepository.optionsMin} à ${EvenementRepository.optionsMax})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (_deDate) ...[
                    for (int i = 0; i < _dates.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.event, color: AppColors.primary),
                        title: Text(EvenementRepository.texteChoixDate(_dates[i])),
                        trailing: IconButton(
                          tooltip: 'Retirer cette date',
                          icon: Icon(Icons.remove_circle_outline,
                              color: AppColors.error),
                          onPressed: () {
                            setState(() {
                              _dates.removeAt(i);
                            });
                          },
                        ),
                      ),
                    if (_dates.length < EvenementRepository.optionsMax)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _ajouterDate,
                          icon: const Icon(Icons.add),
                          label: Text(tr('Ajouter une date', 'Zid date')),
                        ),
                      ),
                  ],
                  if (!_deDate) ...champsChoix,
                  if (!_deDate && _choix.length < EvenementRepository.optionsMax)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _ajouterChoix,
                        icon: const Icon(Icons.add),
                        label: Text(tr('Ajouter un choix', 'Zid ekhtiyar')),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fin du sondage',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    onTap: _choisirFin,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_outlined, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Text('${texteDate(_fin)} à ${texteHeure(_fin)}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Une fois publié, le sondage ne peut plus être modifié, '
                    'et chaque voisin vote une seule fois.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  PrimaryButton(
                    texte: tr('Publier le sondage', 'Onchor el sondage'),
                    onPressed: _enChargement ? null : _creer,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
