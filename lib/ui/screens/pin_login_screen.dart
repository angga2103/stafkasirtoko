import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/staff_models.dart';
import '../../providers/staff_session_controller.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  List<StaffCashier> _cashiers = [];
  StaffCashier? _selected;
  String _pin = '';
  bool _loadingCashiers = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCashiers());
  }

  Future<void> _loadCashiers() async {
    setState(() {
      _loadingCashiers = true;
      _loadError = null;
    });
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    try {
      final list = await ctrl.fetchAvailableCashiers();
      if (!mounted) return;
      setState(() {
        _cashiers = list;
        _selected = list.isNotEmpty ? list.first : null;
        _loadingCashiers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Gagal mengambil daftar kasir dari Admin: $e';
        _loadingCashiers = false;
      });
    }
  }

  void _appendDigit(String d) {
    if (_pin.length >= 6 || _submitting) return;
    setState(() => _pin += d);
  }

  void _backspace() {
    if (_pin.isEmpty || _submitting) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submitPin() async {
    if (_selected == null || _pin.isEmpty) return;
    setState(() => _submitting = true);
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    final ok = await ctrl.loginWithPin(userId: _selected!.id, pin: _pin);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (!ok) _pin = '';
    });
    if (!ok && ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.lastError!), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final compact = MediaQuery.sizeOf(context).width < 360;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${ctrl.storeName} • Login Kasir',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadCashiers,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Putuskan Pairing Terminal?'),
                  content: const Text(
                    'Perangkat ini akan dihapus dari daftar terminal berwenang Admin dan kembali ke layar pairing.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                      child: const Text('Putuskan'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ctrl.unpairTerminalCleanly();
              }
            },
            icon: const Icon(Icons.link_off_rounded, color: Colors.white),
            label: const Text('Unpair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/branding/kasirtoko_staff_logo.png',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.point_of_sale_rounded, size: 44, color: AppTheme.primaryGreen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Terminal: ${ctrl.credentials?.terminalName ?? ""} (${ctrl.credentials?.terminalId ?? ""})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 10),
                  if (_loadingCashiers)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else if (_loadError != null) ...[
                    Text(_loadError!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12.5)),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _loadCashiers, child: const Text('Coba Hubungkan Ulang')),
                  ] else if (_cashiers.isEmpty)
                    const Text('Tidak ada akun kasir aktif dengan izin POS di Admin.')
                  else ...[
                    DropdownButtonFormField<int>(
                      initialValue: _selected?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Pilih Akun Kasir',
                        border: OutlineInputBorder(),
                      ),
                      items: _cashiers
                          .map((c) => DropdownMenuItem<int>(
                                value: c.id,
                                child: Text(
                                  '${c.name} (${c.roleLabel.isNotEmpty ? c.roleLabel : c.role})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (id) {
                        setState(() {
                          _selected = _cashiers.where((c) => c.id == id).firstOrNull;
                          _pin = '';
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (i) {
                        final filled = i < _pin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? AppTheme.primaryGreen : Colors.transparent,
                            border: Border.all(
                              color: filled ? AppTheme.primaryGreen : Colors.grey.shade400,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildKeypad(),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _submitting || _pin.length < 4 ? null : _submitPin,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Masuk Kasir'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '<'],
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          children: rows
              .map((r) => Row(
                    children: r.map((k) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 50),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                              ),
                              onPressed: () {
                                if (k == 'C') {
                                  setState(() => _pin = '');
                                } else if (k == '<') {
                                  _backspace();
                                } else {
                                  _appendDigit(k);
                                }
                              },
                              child: Text(
                                k,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
