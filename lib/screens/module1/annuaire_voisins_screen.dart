import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/utilisateur.dart';
import '../../data/resultat.dart';
import '../../data/services/trouver_voisin_m1.dart';
import '../../data/services/utilisateur_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
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
  // Date de la copie SQLite affichée quand Firebase n'a pas répondu
  // (null : la liste vient du serveur)
  DateTime? _copieHorsLigne;

  // (IA) "Qui peut m'aider ?"
  bool _iaEnCours = false;
  String _besoin = ''; // le dernier besoin décrit
  ReponseBesoin? _reponse; // null = rien demandé (ou fermé)

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
    final DateTime debut = DateTime.now();
    final Resultat<List<Utilisateur>> resultat = await _repository.getVoisins();
    // Copie plus ancienne que la demande : Firebase n'a pas répondu,
    // la liste vient de la base SQLite du téléphone
    final DateTime? copie = await _repository.dateCopieVoisins();
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
      _copieHorsLigne =
          resultat.estSucces && copie != null && copie.isBefore(debut)
              ? copie
              : null;
    });
  }

  /// "12/11 à 18:05"
  static String _dateCourte(DateTime date) {
    String deux(int n) {
      return n.toString().padLeft(2, '0');
    }

    return '${deux(date.day)}/${deux(date.month)} à '
        '${deux(date.hour)}:${deux(date.minute)}';
  }

  /// Bandeau "hors ligne" : la liste affichée est la copie du téléphone.
  Widget _bandeauHorsLigne(DateTime date) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: AppColors.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Hors ligne : liste enregistrée le ${_dateCourte(date)}',
                'Ma famma ch connexion : el liste mte3 ${_dateCourte(date)}',
              ),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// (IA) Demande le besoin, puis cherche les compétences utiles.
  Future<void> _demanderAide() async {
    final TextEditingController champ = TextEditingController(text: _besoin);
    final String? besoin = await showDialog<String>(
      context: context,
      builder: (contexteDialogue) {
        return AlertDialog(
          title: Text(tr('Qui peut m\'aider ?', 'Chkoun ynajem y3aweni ?')),
          content: TextField(
            controller: champ,
            autofocus: true,
            maxLength: TrouverVoisinM1.besoinMax,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              hintText: tr(
                'Ex : ma machine à laver fuit',
                'Mithel : el machine mte3i tsayyeb',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(),
              child: Text(tr('Annuler', 'Batel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(champ.text),
              child: Text(
                tr('Chercher', 'Lawej'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    champ.dispose();
    if (besoin == null || !mounted) {
      return;
    }
    if (!TrouverVoisinM1.besoinValide(besoin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            'Décris ton besoin en quelques mots',
            'Ochre7 chnowa te7tej fi kelmtin',
          )),
        ),
      );
      return;
    }
    setState(() {
      _iaEnCours = true;
      _besoin = besoin.trim();
    });
    final Resultat<ReponseBesoin> resultat = await TrouverVoisinM1.trouver(
      quartierId: _repository.getUtilisateurConnecte().quartierId ?? '',
      besoin: besoin,
      voisins: _voisins,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _iaEnCours = false;
      _reponse = resultat.donnee;
    });
  }

  /// Carte "Besoin d'un coup de main ?" avec le bouton de l'IA.
  Widget _carteAide() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Un souci ? Décris-le, l\'IA trouve le voisin qui peut aider.',
                'Famma mochkla ? Ochre7ha, el IA tal9alek el jar elli ynajem y3awnek.',
              ),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          _iaEnCours
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  // Pas de voisin chargé : rien à chercher
                  onPressed: _voisins.isEmpty ? null : _demanderAide,
                  child: Text(tr('Demander', 'Is2el')),
                ),
        ],
      ),
    );
  }

  /// Les compétences utiles et les voisins qui les ont.
  Widget _resultatsAide(ReponseBesoin reponse) {
    final List<Widget> lignes = [];
    for (final Correspondance c in reponse.correspondances) {
      lignes.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pastille(
                texte: c.competence,
                couleur: AppColors.secondary,
                fond: AppColors.secondaryLight,
              ),
              if (c.raison.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  c.raison,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final Utilisateur voisin in c.voisins)
                    ActionChip(
                      avatar: Icon(Icons.phone_outlined,
                          size: 16, color: AppColors.primary),
                      label: Text(voisin.nomComplet),
                      onPressed: () => _afficherContact(voisin),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (lignes.isEmpty) {
      lignes.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            tr(
              'Personne dans la houma n\'a déclaré une compétence pour ça.',
              'Ma famma 7atta jar fel houma 3andou 5edma kif hethi.',
            ),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Pour « $_besoin »', 'Bech « $_besoin »'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: tr('Fermer', 'Sakker'),
                  onPressed: () {
                    setState(() {
                      _reponse = null;
                    });
                  },
                  icon: Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            Text(
              reponse.parIA
                  ? tr('Suggestions de l\'IA', 'Ra2y el IA')
                  : tr(
                      'IA indisponible : recherche simple par mots-clés',
                      'El IA mech mawjouda : lawajna bel kelmet',
                    ),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            ...lignes,
          ],
        ),
      ),
    );
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
          _voisins.isEmpty
              ? tr('Pas encore de voisins ici', 'Mazel ma famma 7atta jar lahne')
              : tr('Aucun voisin trouvé', 'Ma l9ina 7atta jar'),
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
                if (!_enChargement && _erreur.isEmpty) _carteAide(),
                if (_reponse != null) _resultatsAide(_reponse!),
                TextField(
                  controller: _rechercheController,
                  decoration: InputDecoration(
                    hintText: tr('Nom ou compétence...', 'Esm wala 5edma...'),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 14),
                if (_copieHorsLigne != null)
                  _bandeauHorsLigne(_copieHorsLigne!),
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
                  tr('Voisins', 'Jirani'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  tr(
                    '${moi.quartier} · ${_voisins.length} voisins',
                    '${moi.quartier} · ${_voisins.length} jirane',
                  ),
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
            numero.isEmpty
                ? tr(
                    'Pas de numéro dans son profil',
                    'Ma 7attech nouméro fel profil mte3ou',
                  )
                : numero,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(contexteDialogue).pop();
              },
              child: Text(tr('Fermer', 'Sakker')),
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
                    SnackBar(
                      content: Text(tr('Numéro copié', 'El nouméro tnasakh')),
                    ),
                  );
                },
                child: Text(
                  tr('Copier le numéro', 'Ansa5 el nouméro'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        );
      },
    );
  }
}
