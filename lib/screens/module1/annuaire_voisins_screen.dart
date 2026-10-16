import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_card.dart';
import 'widgets_module1.dart';

/// M1 - Utilisateurs : annuaire des voisins.
///
/// Les membres actifs du quartier (getVoisins), sauf soi-même :
/// avatar, nom, logement et compétences. Une recherche filtre par nom
/// ou par compétence ("plomberie" trouve les plombiers du quartier).
/// Toucher une carte affiche le numéro, avec un bouton pour le copier.
class AnnuaireVoisinsScreen extends StatefulWidget {
  const AnnuaireVoisinsScreen({super.key});

  @override
  State<AnnuaireVoisinsScreen> createState() {
    return _AnnuaireVoisinsScreenState();
  }
}

class _AnnuaireVoisinsScreenState extends State<AnnuaireVoisinsScreen> {
  final UtilisateurRepository _repository = UtilisateurRepository();
  final TextEditingController _rechercheController = TextEditingController();

  List<Utilisateur> _voisins = [];
  bool _enChargement = true; // true jusqu'au premier chargement
  String _erreur = ''; // ex : pas de réseau

  @override
  void initState() {
    super.initState();
    _charger();
    _rechercheController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final Resultat<List<Utilisateur>> resultat = await _repository.getVoisins();
    if (!mounted) {
      return;
    }
    final String moi = _repository.getUtilisateurConnecte().id;
    final List<Utilisateur> voisins = [];
    for (final Utilisateur membre in resultat.donnee ?? []) {
      if (membre.id != moi) {
        voisins.add(membre);
      }
    }
    setState(() {
      _enChargement = false;
      _voisins = voisins;
      _erreur = resultat.estSucces ? '' : resultat.erreur!;
    });
  }

  /// Les voisins dont le nom ou une compétence contient la recherche.
  List<Utilisateur> _voisinsAffiches() {
    final String texte = _rechercheController.text.trim().toLowerCase();
    final List<Utilisateur> resultats = [];
    for (final Utilisateur voisin in _voisins) {
      bool trouve = voisin.nomComplet.toLowerCase().contains(texte);
      for (final String competence in voisin.competences) {
        if (competence.toLowerCase().contains(texte)) {
          trouve = true;
        }
      }
      if (trouve) {
        resultats.add(voisin);
      }
    }
    return resultats;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> cartes = [];
    for (final Utilisateur voisin in _voisinsAffiches()) {
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _carteVoisin(voisin),
        ),
      );
    }
    if (_enChargement) {
      cartes.add(const IndicateurChargement());
    } else if (_erreur.isNotEmpty) {
      cartes.add(_message(_erreur, AppColors.error));
    } else if (cartes.isEmpty) {
      cartes.add(
        _message(
          _voisins.isEmpty ? 'Pas encore de voisins ici' : 'Aucun voisin trouvé',
          AppColors.textSecondary,
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _enTete(context),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _rechercheController,
                  decoration: InputDecoration(
                    hintText: 'Nom ou compétence...',
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 14),
                ...cartes,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// En-tête blanc : flèche retour, "Voisins", quartier et nombre de voisins.
  Widget _enTete(BuildContext context) {
    final Utilisateur moi = _repository.getUtilisateurConnecte();

    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 12,
        20,
        20,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: Icon(Icons.arrow_back, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voisins',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${moi.quartier} · ${_voisins.length} voisins',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String texte, Color couleur) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Text(
        texte,
        textAlign: TextAlign.center,
        style: TextStyle(color: couleur),
      ),
    );
  }

  /// La carte d'un voisin : avatar, nom, logement, compétences.
  Widget _carteVoisin(Utilisateur voisin) {
    final List<Widget> pastilles = [];
    for (final String competence in voisin.competences) {
      pastilles.add(
        Pastille(
          texte: competence,
          couleur: AppColors.secondary,
          fond: AppColors.secondaryLight,
        ),
      );
    }

    return InkWell(
      onTap: () {
        _afficherContact(voisin);
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarUtilisateur(
                  avatar: voisin.avatar,
                  initiales: voisin.initiales,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voisin.nomComplet,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (voisin.logement.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          voisin.logement,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.phone_outlined, color: AppColors.textSecondary),
              ],
            ),
            if (pastilles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: pastilles),
            ],
          ],
        ),
      ),
    );
  }

  /// Fenêtre du contact : le numéro, et un bouton pour le copier
  /// (on le colle ensuite dans le téléphone ou WhatsApp).
  Future<void> _afficherContact(Utilisateur voisin) async {
    final String numero = voisin.telephone.trim();
    await showDialog<void>(
      context: context,
      builder: (contexteDialogue) {
        return AlertDialog(
          title: Text(voisin.nomComplet),
          content: Text(
            numero.isEmpty ? 'Pas de numéro dans son profil' : numero,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(contexteDialogue).pop();
              },
              child: const Text('Fermer'),
            ),
            if (numero.isNotEmpty)
              TextButton(
                onPressed: () async {
                  // On garde la fenêtre et le messager avant l'attente
                  final NavigatorState fenetre = Navigator.of(contexteDialogue);
                  final ScaffoldMessengerState messager =
                      ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: numero));
                  fenetre.pop();
                  messager.showSnackBar(
                    const SnackBar(content: Text('Numéro copié')),
                  );
                },
                child: const Text(
                  'Copier le numéro',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        );
      },
    );
  }
}
