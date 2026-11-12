import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models/evenement.dart';
import '../../data/resultat.dart';
import '../../data/services/evenement_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/preference_langue.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_header.dart';
import 'module4_widgets.dart';

/// M4 - (A21) Le QR code de présence, montré par l'organisateur (ou
/// l'admin) le jour de l'événement. Les participants le scannent avec
/// "Je suis là" : leur présence est enregistrée.
///
/// Le QR contient un code secret que seuls l'organisateur et l'admin
/// peuvent lire : impossible de se pointer sans être sur place.
class QrPresenceScreen extends StatefulWidget {
  final Evenement evenement;

  const QrPresenceScreen({super.key, required this.evenement});

  @override
  State<QrPresenceScreen> createState() => _QrPresenceScreenState();
}

class _QrPresenceScreenState extends State<QrPresenceScreen> {
  final EvenementRepository _depot = EvenementRepository();

  String? _code;
  int _nbPresents = 0;
  bool _enChargement = true;
  String? _erreur;

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
    final Resultat<String> code =
        await _depot.getCodePresence(widget.evenement);
    final Resultat<List<String>> presents =
        await _depot.getPresents(widget.evenement.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _enChargement = false;
      _code = code.donnee;
      _erreur = code.erreur;
      _nbPresents = presents.donnee?.length ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Evenement evenement = widget.evenement;
    Widget corps;
    if (_enChargement) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_code == null) {
      corps = MessageM4(
        texte: _erreur ?? 'Impossible de créer le QR code',
        icone: Icons.qr_code_2,
        reessayer: _charger,
      );
    } else {
      corps = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            evenement.titre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Les participants scannent ce QR avec « Je suis là »',
                'El jeyin yscaniw el QR hedha b « Ena houni »'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              // Fond blanc même en mode sombre : sinon le QR ne se lit pas
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: EvenementRepository.texteQrPresence(evenement.id, _code!),
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Row(
              children: [
                Icon(Icons.how_to_reg_outlined, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$_nbPresents présent${_nbPresents > 1 ? 's' : ''} sur '
                    '${evenement.participants} inscrit${evenement.participants > 1 ? 's' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  icon: Icon(Icons.refresh, color: AppColors.primary),
                  onPressed: _charger,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le pointage est ouvert de 2 h avant le début à 12 h après.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      );
    }
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('QR de présence', 'QR mta3 el 7odhour')),
          Expanded(child: corps),
        ],
      ),
    );
  }
}

/// M4 - (A21) La caméra qui lit le QR de présence. Renvoie le texte du
/// premier QR lu (Navigator.pop), ou null si on revient en arrière.
class ScannerPresenceScreen extends StatefulWidget {
  const ScannerPresenceScreen({super.key});

  @override
  State<ScannerPresenceScreen> createState() => _ScannerPresenceScreenState();
}

class _ScannerPresenceScreenState extends State<ScannerPresenceScreen> {
  bool _dejaLu = false; // la caméra peut lire le même QR plusieurs fois

  void _surDetection(BarcodeCapture capture) {
    if (_dejaLu) {
      return;
    }
    for (final Barcode code in capture.barcodes) {
      final String? texte = code.rawValue;
      if (texte != null && texte.isNotEmpty) {
        _dejaLu = true;
        Navigator.of(context).pop(texte);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(titre: tr('Scanner le QR', 'Scanni el QR')),
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: _surDetection,
                  errorBuilder: (context, erreur) {
                    return MessageM4(
                      texte: 'La caméra n\'est pas disponible. '
                          'Autorise l\'accès à la caméra dans les réglages.',
                      icone: Icons.no_photography_outlined,
                    );
                  },
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 30,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tr('Vise le QR code affiché par l\'organisateur',
                          'Wajjeh el caméra 3al QR mta3 l\'organisateur'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
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
