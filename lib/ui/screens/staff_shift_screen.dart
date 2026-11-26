import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../providers/staff_session_controller.dart';

class StaffShiftScreen extends StatefulWidget {
  final VoidCallback? onShiftReady;
  const StaffShiftScreen({super.key, this.onShiftReady});

  @override
  State<StaffShiftScreen> createState() => _StaffShiftScreenState();
}

class _StaffShiftScreenState extends State<StaffShiftScreen> {
  final _startingCashCtrl = TextEditingController(text: '0');
  final _actualCashCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int? _selectedRegId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = Provider.of<StaffSessionController>(context, listen: false);
      await ctrl.refreshShiftAndRegisters();
      if (mounted) {
        setState(() {
          _selectedRegId = ctrl.assignedRegister?.id ??
              ctrl.registers.where((r) => r.isAuthorized).firstOrNull?.id;
        });
      }
    });
  }

  @override
  void dispose() {
    _startingCashCtrl.dispose();
    _actualCashCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final shift = ctrl.currentShift;
    final canOpen = ctrl.registers.any((r) => r.isAuthorized);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift & Laci Kas Terminal'),
        actions: [
          IconButton(
            onPressed: () => ctrl.refreshShiftAndRegisters(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Operasional: ${ctrl.drawerMode}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ctrl.drawerMode == 'SHARED_DRAWER'
                            ? 'Laci Kas Bersama: beberapa terminal kasir menggunakan satu shift aktif bersama.'
                            : 'Laci Kas Individual: setiap kasir/laci wajib memiliki shift aktif sendiri.',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (shift != null && shift.isOpen)
                  _buildActiveShiftCard(ctrl, shift)
                else
                  _buildOpenShiftCard(ctrl, canOpen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveShiftCard(StaffSessionController ctrl, dynamic shift) {
    final isMine = shift.cashierId == ctrl.cashier?.id;
    final isIndividual = ctrl.drawerMode == 'INDIVIDUAL_DRAWER';
    final canCloseHere = !isIndividual || isMine;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open_rounded, color: AppTheme.success),
              const SizedBox(width: 8),
              Text(
                'Shift Aktif #${shift.id} Terbuka',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Kasir Pembuka : ${shift.cashierName}'),
          Text('Laci Kas       : #${shift.cashRegisterId} (${ctrl.assignedRegister?.name ?? ""})'),
          Text('Modal Awal     : ${CurrencyHelper.format(shift.startingCash)}'),
          const SizedBox(height: 14),
          if (widget.onShiftReady != null)
            ElevatedButton.icon(
              onPressed: widget.onShiftReady,
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('Lanjut ke Layar Kasir'),
            ),
          if (canCloseHere) ...[
            const Divider(height: 28),
            const Text(
              'Tutup Shift (Blind Cash Count)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _actualCashCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total Uang Fisik di Laci (Rp)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan Penutupan (wajib jika ada selisih)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final actual = double.tryParse(_actualCashCtrl.text.trim());
                      if (actual == null || actual < 0) return;
                      setState(() => _busy = true);
                      final res = await ctrl.closeShift(
                        actualCash: actual,
                        note: _noteCtrl.text,
                      );
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (res == null && ctrl.lastError != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ctrl.lastError!), backgroundColor: AppTheme.accentRed),
                        );
                      } else if (res != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Shift ditutup. Selisih: ${CurrencyHelper.format((res['difference'] as num).toDouble())}',
                            ),
                          ),
                        );
                      }
                    },
              child: const Text('Tutup Shift Ini'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOpenShiftCard(StaffSessionController ctrl, bool canOpen) {
    final authorizedRegs = ctrl.registers.where((r) => r.isAuthorized).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_clock_rounded, color: AppTheme.warning),
              SizedBox(width: 8),
              Text(
                'Belum Ada Shift Terbuka',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!canOpen)
            const Text(
              'Terminal/kasir Anda belum ditugaskan laci kas yang sah di Admin. Hubungi Admin untuk assignment laci.',
              style: TextStyle(color: AppTheme.accentRed, fontSize: 12.5),
            )
          else ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedRegId ?? authorizedRegs.first.id,
              decoration: const InputDecoration(
                labelText: 'Laci Kas yang Ditugaskan',
                border: OutlineInputBorder(),
              ),
              items: authorizedRegs
                  .map((r) => DropdownMenuItem<int>(
                        value: r.id,
                        child: Text('${r.registerCode} — ${r.name}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRegId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _startingCashCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Modal Awal Laci (Rp)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final regId = _selectedRegId ?? authorizedRegs.first.id;
                      final cash = double.tryParse(_startingCashCtrl.text.trim()) ?? -1;
                      if (cash < 0) return;
                      setState(() => _busy = true);
                      final ok = await ctrl.openShift(
                        cashRegisterId: regId,
                        startingCash: cash,
                      );
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (!ok && ctrl.lastError != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ctrl.lastError!), backgroundColor: AppTheme.accentRed),
                        );
                      } else if (ok && widget.onShiftReady != null) {
                        widget.onShiftReady!();
                      }
                    },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Buka Shift Kasir'),
            ),
          ],
        ],
      ),
    );
  }
}
