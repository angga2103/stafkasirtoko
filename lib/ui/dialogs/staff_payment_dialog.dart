import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../providers/staff_session_controller.dart';
import 'staff_receipt_dialog.dart';

class StaffPaymentDialog extends StatefulWidget {
  const StaffPaymentDialog({super.key});

  @override
  State<StaffPaymentDialog> createState() => _StaffPaymentDialogState();
}

class _StaffPaymentDialogState extends State<StaffPaymentDialog> {
  final _paidCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _requestPrint = true;
  bool _useCreditBalance = false;
  double _creditBal = 0.0;

  @override
  void initState() {
    super.initState();
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    _requestPrint = ctrl.autoPrintStaffTransactions;
    ctrl.setCreditUsed(0.0);
    ctrl.setAmountPaid(ctrl.grandTotal);
    _paidCtrl.text = ctrl.grandTotal.toStringAsFixed(0);

    if (ctrl.customerId != null) {
      final match = ctrl.customers.where((c) => c.id == ctrl.customerId).firstOrNull;
      _creditBal = match?.creditBalance ?? 0.0;
    }
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(StaffSessionController ctrl) async {
    final res = await ctrl.submitCheckout(
      note: _noteCtrl.text.trim(),
      requestPrint: _requestPrint,
    );
    if (!mounted) return;
    if (res.receipt != null) {
      Navigator.pop(context);
      await showDialog(
        context: context,
        builder: (_) => StaffReceiptDialog(
          receipt: res.receipt!,
          initialPrintJob: res.printJob,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.error ?? 'Transaksi gagal disahkan server Admin.'),
        backgroundColor: AppTheme.accentRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final hasRegisteredCust = ctrl.customerId != null;
    final suggestions = QuickCashHelper.suggestAmounts(ctrl.netPayable);

    return AlertDialog(
      title: const Text('Pembayaran Transaksi'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreenSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Tagihan', style: TextStyle(fontSize: 13)),
                        Text(
                          CurrencyHelper.format(ctrl.grandTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryGreen),
                        ),
                      ],
                    ),
                    if (ctrl.creditUsed > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Potong Saldo Kredit', style: TextStyle(fontSize: 12)),
                          Text('- ${CurrencyHelper.format(ctrl.creditUsed)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sisa Harus Dibayar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          Text(CurrencyHelper.format(ctrl.netPayable),
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text('Pelanggan: ${ctrl.customerName}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (hasRegisteredCust && _creditBal > 0)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Gunakan Saldo Kredit (${CurrencyHelper.format(_creditBal)})'),
                  value: _useCreditBalance,
                  onChanged: (v) {
                    setState(() {
                      _useCreditBalance = v;
                      final used = v ? (_creditBal > ctrl.grandTotal ? ctrl.grandTotal : _creditBal) : 0.0;
                      ctrl.setCreditUsed(used);
                      _paidCtrl.text = ctrl.netPayable.toStringAsFixed(0);
                      ctrl.setAmountPaid(ctrl.netPayable);
                    });
                  },
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _methodChip(ctrl, 'tunai', 'Tunai'),
                  _methodChip(ctrl, 'qris', 'QRIS'),
                  _methodChip(ctrl, 'transfer', 'Transfer'),
                  if (hasRegisteredCust) _methodChip(ctrl, 'kasbon', 'Kasbon'),
                ],
              ),
              if (!hasRegisteredCust)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Kasbon & Saldo Kredit hanya aktif untuk pelanggan terdaftar.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
              if (ctrl.paymentMethod == 'tunai' || ctrl.paymentMethod == 'kasbon') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _paidCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ctrl.paymentMethod == 'kasbon' ? 'Uang Muka / DP (Rp)' : 'Uang Diterima (Rp)',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    ctrl.setAmountPaid(double.tryParse(v.trim()) ?? 0.0);
                  },
                ),
                if (ctrl.paymentMethod == 'tunai' && suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: suggestions.map((amt) {
                      return ActionChip(
                        label: Text(CurrencyHelper.format(amt)),
                        onPressed: () {
                          _paidCtrl.text = amt.toStringAsFixed(0);
                          ctrl.setAmountPaid(amt);
                        },
                      );
                    }).toList(),
                  ),
                ],
                if (ctrl.paymentMethod == 'tunai') ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembalian', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        CurrencyHelper.format(ctrl.changeAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.accentIndigo),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan Transaksi (opsional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Kirim Permintaan Cetak Struk ke POS Admin', style: TextStyle(fontSize: 12.5)),
                value: _requestPrint,
                onChanged: (v) => setState(() => _requestPrint = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: ctrl.isCheckingOut ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton.icon(
          onPressed: ctrl.canSubmitCheckout ? () => _submit(ctrl) : null,
          icon: ctrl.isCheckingOut
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Sahkan & Bayar'),
        ),
      ],
    );
  }

  Widget _methodChip(StaffSessionController ctrl, String value, String label) {
    final selected = ctrl.paymentMethod == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        ctrl.setPaymentMethod(value);
        if (value == 'kasbon') {
          _paidCtrl.text = '0';
          ctrl.setAmountPaid(0.0);
        } else {
          _paidCtrl.text = ctrl.netPayable.toStringAsFixed(0);
          ctrl.setAmountPaid(ctrl.netPayable);
        }
      },
    );
  }
}
