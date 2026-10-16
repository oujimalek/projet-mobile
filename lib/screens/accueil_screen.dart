import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/evenement.dart';
import '../data/models/service.dart';
import '../data/models/sondage.dart';
import '../data/models/utilisateur.dart';
import '../data/resultat.dart';
import '../data/services/evenement_repository.dart';
import '../data/services/service_repository.dart';
import '../data/services/utilisateur_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_drawer.dart';
import '../widgets/houmani_logo.dart';
import 'module1/widgets_module1.dart';

/// Onglet "Accueil" : le tableau de bord du quartier.
///
/// - En-tête bleu : bouton du menu, salutation, nom du quartier, avatar.
/// - Admin : carte des demandes d'adhésion en attente.
/// - Raccourcis vers les 4 modules.
/// - Aperçu : prochain événement, sondage en cours, derniers services.
///
/// Les données viennent des repositories des modules (lecture seule).
class AccueilScreen extends StatefulWidget {
  const AccueilScreen({super.key});

  @override
  State<AccueilScreen> createState() {
    return _AccueilScreenState();
  }
}

class _AccueilScreenState extends State<AccueilScreen> {
  final UtilisateurRepository _utilisateurs = UtilisateurRepository();
  final ServiceRepository _services = ServiceRepository();
  final EvenementRepository _evenements = EvenementRepository();

  // Nombre de demandes d'adhésion en attente (affiché à l'admin)
  int _enAttente = 0;

  @override
  void initState() {
    super.initState();
    _chargerDemandesEnAttente();
  }

  Future<void> _chargerDemandesEnAttente() async {
    if (!_utilisateurs.getUtilisateurConnecte().estAdmin) {
      return;
    }
    final Resultat<int> resultat =
        await _utilisateurs.compterMembres(StatutUtilisateur.enAttente);
    if (!mounted) {
      return;
    }
    setState(() {
      _enAttente = resultat.donnee ?? 0;
    });
  }

  /// Le prochain événement (le plus proche dans le futur), ou null.
  Evenement? _prochainEvenement() {
    final DateTime maintenant = DateTime.now();
    Evenement? prochain;
    for (final Evenement evenement in _evenements.getEvenements()) {
      if (evenement.date.isAfter(maintenant) &&
          (prochain == null || evenement.date.isBefore(prochain.date))) {
        prochain = evenement;
      }
    }
    return prochain;
  }

  /// Les 3 services publiés le plus récemment.
  List<Service> _derniersServices() {
    final List<Service> services = List.of(_services.getServices());
    services.sort((a, b) {
      final DateTime dateA = a.datePublication ?? DateTime(2000);
      final DateTime dateB = b.datePublication ?? DateTime(2000);
      return dateB.compareTo(dateA); // du plus récent au plus ancien
    });
    return services.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final Utilisateur utilisateur = _utilisateurs.getUtilisateurConnecte();
    final Evenement? evenement = _prochainEvenement();
    final Sondage sondage = _evenements.getSondageActif();

    final List<Widget> contenu = [];

    // ----- Admin : demandes en attente -----
    if (utilisateur.estAdmin && _enAttente > 0) {
      contenu.add(_carteDemandesEnAttente());
      contenu.add(const SizedBox(height: 20));
    }

    // ----- Profil incomplet : invitation à le compléter -----
    final int pourcentage = _pourcentageProfil(utilisateur);
    if (pourcentage < 100) {
      contenu.add(_carteProfilIncomplet(pourcentage));
      contenu.add(const SizedBox(height: 20));
    }

    // ----- Raccourcis vers les modules -----
    contenu.add(_titre('Ta houma'));
    contenu.add(
      Row(
        children: [
          _raccourci(Icons.handshake_outlined, 'Services', '/services',
              AppColors.primary, AppColors.primaryLight),
          const SizedBox(width: 10),
          _raccourci(Icons.campaign_outlined, 'Signaler', '/signalements',
              AppColors.incident, AppColors.incidentLight),
        ],
      ),
    );
    contenu.add(const SizedBox(height: 10));
    contenu.add(
      Row(
        children: [
          _raccourci(Icons.event_outlined, 'Événements', '/evenements',
              AppColors.secondary, AppColors.secondaryLight),
          const SizedBox(width: 10),
          _raccourci(Icons.person_outline, 'Mon profil', '/profil',
              AppColors.badgeResolu, AppColors.backgroundSecondary),
        ],
      ),
    );
    contenu.add(const SizedBox(height: 24));

    // ----- À ne pas manquer : événement + sondage -----
    contenu.add(_titre('À ne pas manquer'));
    if (evenement != null) {
      contenu.add(_carteEvenement(evenement));
      contenu.add(const SizedBox(height: 10));
    }
    contenu.add(_carteSondage(sondage));
    contenu.add(const SizedBox(height: 24));

    // ----- Derniers services -----
    contenu.add(
      _titre('Derniers services', lien: 'Tout voir', cheminLien: '/services'),
    );
    for (final Service service in _derniersServices()) {
      contenu.add(_carteService(service));
      contenu.add(const SizedBox(height: 10));
    }
    contenu.add(const SizedBox(height: 14));

    // ----- Astuce du jour -----
    contenu.add(_carteAstuce());

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _enTete(utilisateur),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contenu,
            ),
          ),
        ],
      ),
    );
  }

  /// Le profil est-il complet ? 5 points : téléphone, e-mail, logement,
  /// photo et compétences. Renvoie un pourcentage (0 à 100).
  int _pourcentageProfil(Utilisateur utilisateur) {
    int remplis = 0;
    if (utilisateur.telephone.isNotEmpty) remplis++;
    if (utilisateur.email.isNotEmpty) remplis++;
    if (utilisateur.logement.isNotEmpty) remplis++;
    if (utilisateur.avatar.isNotEmpty) remplis++;
    if (utilisateur.competences.isNotEmpty) remplis++;
    return remplis * 100 ~/ 5;
  }

  /// "Bonjour" en derja selon l'heure : matin, après-midi ou soir.
  String _salutationDuMoment() {
    final int heure = DateTime.now().hour;
    if (heure >= 5 && heure < 12) {
      return 'Sbah el khir';
    }
    if (heure >= 12 && heure < 18) {
      return 'Nharek zin';
    }
    return 'Msa el khir';
  }

  /// La date du jour en toutes lettres : "vendredi 16 octobre".
  String _dateDuJour() {
    const List<String> jours = [
      'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
    ];
    const List<String> mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    final DateTime aujourdhui = DateTime.now();
    return '${jours[aujourdhui.weekday - 1]} ${aujourdhui.day} '
        '${mois[aujourdhui.month - 1]}';
  }

  /// En-tête bleu cobalt : menu, salutation, quartier et avatar,
  /// avec le logo en filigrane à droite (Stack).
  Widget _enTete(Utilisateur utilisateur) {
    return Stack(
      children: [
        _fondEnTete(utilisateur),
        const Positioned(
          right: -24,
          bottom: -18,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.12,
              child: HoumaniLogo(taille: 130, avecNom: false, blanc: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fondEnTete(Utilisateur utilisateur) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        20,
        24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Menu',
                onPressed: ouvrirMenu,
                icon: const Icon(Icons.menu, color: Colors.white),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/profil'),
                child: AvatarUtilisateur(
                  avatar: utilisateur.avatar,
                  initiales: utilisateur.initiales,
                  taille: 40,
                  couleur: AppColors.primary,
                  fond: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_salutationDuMoment()} · ${_dateDuJour()}',
                  style: const TextStyle(color: AppColors.primaryLight),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ahla ${utilisateur.prenom} !',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: AppColors.primaryLight, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        utilisateur.quartier,
                        style: const TextStyle(color: AppColors.primaryLight),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Titre d'une section, avec un lien optionnel à droite ("Tout voir").
  Widget _titre(String texte, {String? lien, String? cheminLien}) {
    final List<Widget> ligne = [
      Expanded(
        child: Text(
          texte,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    ];
    if (lien != null && cheminLien != null) {
      ligne.add(
        TextButton(
          onPressed: () => context.go(cheminLien),
          child: Text(lien, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(height: 32, child: Row(children: ligne)),
    );
  }

  /// Carte orange pour l'admin : "N demandes en attente".
  Widget _carteDemandesEnAttente() {
    final String texte = _enAttente == 1
        ? '1 demande d\'adhésion en attente'
        : '$_enAttente demandes d\'adhésion en attente';
    return AppCard(
      onTap: () async {
        await context.push('/profil/membres');
        _chargerDemandesEnAttente(); // le nombre a pu changer
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.badgeEnAttenteFond,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.how_to_reg_outlined,
                color: AppColors.badgeEnAttente),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texte, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                const Text(
                  'Touche pour les valider',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  /// Carte dorée : "Ton profil est complet à N %" + barre de progression.
  Widget _carteProfilIncomplet(int pourcentage) {
    return AppCard(
      onTap: () async {
        await context.push('/modifier-profil');
        if (mounted) {
          setState(() {}); // le profil a pu changer
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ton profil est complet à $pourcentage %',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Text(
                'Compléter',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pourcentage / 100,
              minHeight: 8,
              color: AppColors.secondary,
              backgroundColor: AppColors.secondaryLight,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ajoute ta photo et tes compétences : tes voisins sauront '
            'qui tu es et comment tu peux les aider.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Une astuce différente chaque jour (choisie selon la date).
  Widget _carteAstuce() {
    const List<String> astuces = [
      'Un voisin a besoin d\'aide ? Réponds à sa demande depuis Services.',
      'Tu vois un lampadaire en panne ? Un signalement prend 30 secondes.',
      'Vote au sondage du quartier : ton avis compte !',
      'Ajoute tes compétences à ton profil pour qu\'on pense à toi.',
      'Confirme les signalements de tes voisins pour qu\'ils soient traités plus vite.',
      'Prête tes outils : c\'est le meilleur moyen de faire connaissance.',
      'Note les services reçus pour aider tout le monde à bien choisir.',
    ];
    final DateTime aujourdhui = DateTime.now();
    final int numero =
        aujourdhui.difference(DateTime(aujourdhui.year)).inDays % astuces.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Astuce du jour',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(astuces[numero], style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Une tuile de raccourci vers un module (icône colorée + nom).
  Widget _raccourci(
    IconData icone,
    String texte,
    String chemin,
    Color couleur,
    Color fond,
  ) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.go(chemin),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
              child: Icon(icone, color: couleur, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texte,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Le prochain événement : date dans un bloc doré, titre et lieu.
  Widget _carteEvenement(Evenement evenement) {
    const List<String> mois = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
    ];
    final String heure =
        '${evenement.date.hour}:${evenement.date.minute.toString().padLeft(2, '0')}';

    return AppCard(
      onTap: () => context.go('/evenements'),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '${evenement.date.day}',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  mois[evenement.date.month - 1],
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evenement.titre,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '$heure · ${evenement.lieu}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${evenement.participants} participants',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Le sondage en cours : question et nombre de votes.
  Widget _carteSondage(Sondage sondage) {
    return AppCard(
      onTap: () => context.go('/evenements'),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.poll_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sondage en cours',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sondage.question,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sondage.totalVotes} votes · donne ton avis',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  /// Un service récent : offre (bleu) ou demande (doré), titre et auteur.
  Widget _carteService(Service service) {
    final Color couleur = service.estOffre ? AppColors.primary : AppColors.secondary;
    final Color fond =
        service.estOffre ? AppColors.primaryLight : AppColors.secondaryLight;

    return AppCard(
      onTap: () => context.go('/services'),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: fond,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              service.estOffre ? 'Offre' : 'Demande',
              style: TextStyle(
                color: couleur,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.titre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.categorie} · ${service.auteur}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
