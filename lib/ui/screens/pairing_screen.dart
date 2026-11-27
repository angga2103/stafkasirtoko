import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/staff_session_controller.dart';
import 'staff_barcode_scanner_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.');
  final _portCtrl = TextEditingController(text: '8443');
  final _codeCtrl = TextEditingController();
  final _certPinCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(text: 'Kasir Staff 1');
  bool _isSubmitting = false;
  bool _isScannerOpen = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    _certPinCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitManualPairing() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8443;
    final code = _codeCtrl.text.trim();
    final pin = _certPinCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (host.isEmpty || code.isEmpty || pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi IP Admin, Kode Pairing, dan minimal 6 karakter Checksum Sertifikat.'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    final ok = await ctrl.pairUsingQrOrManual(
      host: host,
      port: port,
      pairingCode: code,
      deviceName: name.isEmpty ? 'Terminal Kasir' : name,
      shortPin: pin,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (!ok && ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.lastError!), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  Future<void> _openQrScanner() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'Terminal Kasir' : _nameCtrl.text.trim();
    if (_isScannerOpen || _isSubmitting) return;
    _isScannerOpen = true;
    String? scannedRaw;
    try {
      scannedRaw = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => StaffBarcodeScannerScreen(
            title: 'Scan QR Pairing Admin',
            subtitle: 'Arahkan kamera ke QR Pairing di aplikasi POS Admin',
            initialMode: StaffScannerMode.single,
            allowModeToggle: false,
            formats: const [BarcodeFormat.qrCode],
            barcodeValidator: (raw) => raw.contains('pairing_code'),
            invalidCodeMessage: 'Bukan QR Pairing Admin (pairing_code tidak ditemukan).',
            manualInputHint: 'Tempel payload JSON QR Pairing (berisi pairing_code)',
          ),
        ),
      );
    } finally {
      _isScannerOpen = false;
    }
    if (scannedRaw == null || !mounted) return;
    setState(() => _isSubmitting = true);
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    final ok = await ctrl.pairFromQrPayload(scannedRaw, deviceName: name);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (!ok && ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.lastError!), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Hubungkan Terminal POS Staff')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/branding/kasirtoko_staff_logo.png',
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.point_of_sale_rounded, size: 52, color: AppTheme.primaryGreen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'KasirToko Staff Terminal',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sambungkan ke Server POS Admin melalui Wi-Fi router atau Hotspot Android Admin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                  if (ctrl.connectionState == TerminalConnectionState.revoked) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Text(
                        'Akses terminal sebelumnya telah dicabut Admin. Lakukan pairing ulang.',
                        style: TextStyle(color: AppTheme.accentRed, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Perangkat Kasir Ini',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.devices_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _openQrScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan QR Pairing dari POS Admin'),
                  ),
                  const Row(
                    children: [
                      Expanded(child: Divider(height: 28)),
                      Flexible(
                        flex: 3,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'atau input manual',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ),
                      ),
                      Expanded(child: Divider(height: 28)),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                      final stackVert = constraints.maxWidth < 310 || (constraints.maxWidth < 360 && textScale > 1.3);
                      final ipField = TextField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(
                          labelText: 'IP Server Admin',
                          hintText: '192.168.43.1',
                          border: OutlineInputBorder(),
                        ),
                      );
                      final portField = TextField(
                        controller: _portCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                      );
                      if (stackVert) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [ipField, const SizedBox(height: 10), portField],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 3, child: ipField),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: portField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Kode Pairing (8 karakter)',
                      hintText: 'Contoh: A7K9-M2P4',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _certPinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'PIN Checksum Sertifikat TLS (8 karakter)',
                      hintText: 'Lihat di layar Server POS Admin',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : _submitManualPairing,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verifikasi Sertifikat & Pasangkan'),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

