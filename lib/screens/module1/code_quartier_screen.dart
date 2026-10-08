import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/quartier.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/houmani_logo.dart';
import '../../widgets/primary_button.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : écran 4, rejoindre sa houma.
///
/// Deux façons de choisir son quartier :
/// - taper le code d'invitation à 6 caractères donné par l'admin ;
/// - OU chercher le quartier par son nom et le sélectionner.
/// La demande part ensuite à l'administrateur (écran d'attente).
class CodeQuartierScreen extends StatefulWidget {
  const CodeQuartierScreen({super.key});

  @override
  State<CodeQuartierScreen> createState() {
    return _CodeQuartierScreenState();
  }
}

class _CodeQuartierScreenState extends State<CodeQuartierScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();

  final TextEditingController _rechercheController = TextEditingController();

  String _code = '';
  Quartier? _quartierDuCode; // trouvé grâce au code complet (6 caractères)
  bool _codeInconnu = false; // code complet mais qui ne correspond à rien
  Quartier? _quartierSelectionne; // choisi dans la liste de recherche
  List<Quartier> _quartiersTrouves = []; // résultat de la recherche

  @override
  void initState() {
    super.initState();
    _rechercher(); // au départ : tous les quartiers
    // On met la liste à jour à chaque lettre tapée dans la recherche
    _rechercheController.addListener(_rechercher);
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  /// Demande au repository les quartiers qui correspondent à la recherche.
  Future<void> _rechercher() async {
    final List<Quartier> trouves =
        await _repository.rechercherQuartiers(_rechercheController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _quartiersTrouves = trouves;
    });
  }

  /// Appelé à chaque caractère du code : dès qu'il est complet,
  /// on cherche le quartier correspondant.
  Future<void> _codeModifie(String code) async {
    setState(() {
      _code = code;
      _quartierDuCode = null;
      _codeInconnu = false;
    });
    if (code.length < 6) {
      return;
    }
    final Quartier? quartier = await _repository.trouverParCode(code);
    // Le code a pu changer pendant l'attente : on ignore l'ancienne réponse
    if (!mounted || code != _code) {
      return;
    }
    setState(() {
      _quartierDuCode = quartier;
      _codeInconnu = quartier == null;
    });
  }

  /// Le quartier qui sera rejoint : celui du code s'il est complet,
  /// sinon celui sélectionné dans la liste.
  Quartier? _quartierChoisi() {
    if (_code.length == 6) {
      return _quartierDuCode;
    }
    return _quartierSelectionne;
  }

  Future<void> _rejoindre() async {
    final Quartier? quartier = _quartierChoisi();
    if (quartier == null) {
      return;
    }
    await _repository.rejoindreQuartier(quartier);
    if (!mounted) {
      return;
    }
    // go : après l'envoi de la demande, pas de retour en arrière
    context.go('/attente');
  }

  @override
  Widget build(BuildContext context) {
    final String? aideDemo = _repository.aideDemoCodeQuartier;

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(titre: ''),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const TitreEcran(
                  titre: 'Rejoins ta houma',
                  sousTitre: 'Entre le code d\'invitation reçu de ton '
                      'administrateur, ou cherche ton quartier.',
                ),
                const SizedBox(height: 20),

                // ----- Code d'invitation -----
                const Text(
                  'Code d\'invitation',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SaisieCode(
                  chiffresSeulement: false,
                  onChanged: _codeModifie,
                ),
                if (_codeInconnu)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Ce code ne correspond à aucun quartier',
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                _separateurOu(),

                // ----- Recherche d'un quartier -----
                AppTextField(
                  label: 'Rechercher un quartier',
                  hint: 'Ex : Résidence El Yasmine, Ennasr...',
                  icone: Icons.search,
                  controller: _rechercheController,
                ),
                const SizedBox(height: 12),
                ..._listeQuartiers(),
                const SizedBox(height: 24),

                PrimaryButton(
                  texte: 'Rejoindre la houma',
                  onPressed: _quartierChoisi() != null ? _rejoindre : null,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ta demande sera validée par l\'administrateur du quartier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // Aide de démo (rien avec une vraie source de données)
                if (aideDemo != null)
                  Text(
                    'Démo : code $aideDemo',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ligne "——— ou ———" entre les deux façons de choisir.
  Widget _separateurOu() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('ou', style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }

  /// Les cartes des quartiers trouvés (avec un bouton radio).
  List<Widget> _listeQuartiers() {
    final List<Widget> cartes = [];
    for (final Quartier quartier in _quartiersTrouves) {
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _carteQuartier(quartier),
        ),
      );
    }
    if (cartes.isEmpty) {
      cartes.add(
        const Text(
          'Aucun quartier trouvé',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return cartes;
  }

  Widget _carteQuartier(Quartier quartier) {
    final bool selectionne = _quartierSelectionne?.id == quartier.id;

    return Material(
      color: selectionne ? AppColors.primaryLight : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(
          color: selectionne ? AppColors.primary : AppColors.border,
          width: selectionne ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _quartierSelectionne = quartier;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const HoumaniLogo(taille: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quartier.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${quartier.localisation} · ${quartier.nbMembres} membres',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selectionne ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selectionne ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
