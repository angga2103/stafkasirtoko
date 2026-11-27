import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../data/models/staff_models.dart';
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
  final _paidFocusNode = FocusNode();

  bool _requestPrint = true;
  bool _useCreditBalance = false;
  double _creditBal = 0.0;

  @override
  void initState() {
    super.initState();
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    _requestPrint = ctrl.autoPrintStaffTransactions;
    _creditBal = _lookupCustomerCredit(ctrl, ctrl.customerId);
    _paidCtrl.text = ctrl.grandTotal.toStringAsFixed(0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ctrl.setCreditUsed(0.0);
      ctrl.setAmountPaid(ctrl.grandTotal);
    });
  }

  double _lookupCustomerCredit(StaffSessionController ctrl, int? customerId) {
    if (customerId == null) return 0.0;
    final match = ctrl.customers.where((c) => c.id == customerId).firstOrNull;
    return match?.creditBalance ?? 0.0;
  }

  @override
  void dispose() {
    _paidFocusNode.dispose();
    _paidCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _applyPaymentMethod(StaffSessionController ctrl, String method) {
    if (method == 'kasbon' && ctrl.customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih pelanggan terdaftar terlebih dahulu untuk pembayaran Kasbon.'),
          backgroundColor: AppTheme.accentOrange,
        ),
      );
      return;
    }
    ctrl.setPaymentMethod(method);
    if (method == 'kasbon') {
      _paidCtrl.text = '0';
      ctrl.setAmountPaid(0.0);
    } else {
      final due = ctrl.netPayable;
      _paidCtrl.text = due.toStringAsFixed(0);
      ctrl.setAmountPaid(due);
    }
  }

  Future<void> _submit(StaffSessionController ctrl) async {
    final nav = Navigator.of(context);
    final res = await ctrl.submitCheckout(
      note: _noteCtrl.text.trim(),
      requestPrint: _requestPrint,
    );
    if (!mounted) return;
    if (res.receipt != null) {
      nav.pop();
      await showDialog(
        context: nav.context,
        builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
          value: ctrl,
          child: StaffReceiptDialog(
            receipt: res.receipt!,
            initialPrintJob: res.printJob,
          ),
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
    final registeredCustomers = ctrl.customers.where((c) => !c.isWalkIn).toList();
    final netDue = ctrl.netPayable;
    final suggestions = QuickCashHelper.suggestAmounts(netDue);
    final isTunai = ctrl.paymentMethod == 'tunai';
    final isKasbon = ctrl.paymentMethod == 'kasbon';
    final tunaiInsufficient = isTunai && netDue > 0 && ctrl.amountPaid + 0.01 < netDue;
    final canSubmit = ctrl.canSubmitCheckout && !tunaiInsufficient && (!isKasbon || hasRegisteredCust);
    final shortfall = (netDue - ctrl.amountPaid).clamp(0.0, double.infinity);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact Brand Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.primaryGreen,
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pembayaran Transaksi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Pengesahan langsung ke POS Admin',
                          style: TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: ctrl.isCheckingOut ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Scrollable Body (keyboard-safe)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Total Summary Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreenSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'TOTAL TAGIHAN',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryGreenDark,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            CurrencyHelper.format(ctrl.grandTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                          if (ctrl.creditUsed > 0) ...[
                            const Divider(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Potong Saldo Kredit Retur',
                                  style: TextStyle(fontSize: 12, color: AppTheme.accentBlue),
                                ),
                                Text(
                                  '-${CurrencyHelper.format(ctrl.creditUsed)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accentBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Sisa Harus Dibayar',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  CurrencyHelper.format(netDue),
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Customer Selector synced with StaffSessionController
                    DropdownButtonFormField<int?>(
                      initialValue: registeredCustomers.any((c) => c.id == ctrl.customerId)
                          ? ctrl.customerId
                          : null,
                      isExpanded: true,
                      decoration: AppTheme.denseInputDecoration(
                        hintText: 'Pelanggan Umum',
                        prefixIcon: Icons.person_outline_rounded,
                      ).copyWith(labelText: 'Pelanggan'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Pelanggan Umum (Walk-in)'),
                        ),
                        ...registeredCustomers.map((StaffCustomer c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(
                                c.phone.isNotEmpty ? '${c.name} (${c.phone})' : c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (custId) async {
                        final picked = custId == null
                            ? null
                            : registeredCustomers.where((c) => c.id == custId).firstOrNull;
                        await ctrl.setCustomer(picked);
                        if (!mounted) return;
                        setState(() {
                          _creditBal = _lookupCustomerCredit(ctrl, picked?.id);
                          _useCreditBalance = false;
                          ctrl.setCreditUsed(0.0);
                          final due = ctrl.netPayable;
                          if (ctrl.paymentMethod != 'kasbon') {
                            _paidCtrl.text = due.toStringAsFixed(0);
                            ctrl.setAmountPaid(due);
                          }
                        });
                      },
                    ),

                    if (hasRegisteredCust && _creditBal > 0) ...[
                      const SizedBox(height: 10),
                      Material(
                        color: AppTheme.accentBlue.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AppTheme.accentBlue.withValues(alpha: 0.35)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          value: _useCreditBalance,
                          title: const Text(
                            'Gunakan Saldo Kredit Retur',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Tersedia: ${CurrencyHelper.format(_creditBal)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.accentBlue),
                          ),
                          onChanged: (v) {
                            final enable = v ?? false;
                            setState(() {
                              _useCreditBalance = enable;
                              final used =
                                  enable ? (_creditBal > ctrl.grandTotal ? ctrl.grandTotal : _creditBal) : 0.0;
                              ctrl.setCreditUsed(used);
                              final due = ctrl.netPayable;
                              _paidCtrl.text = due.toStringAsFixed(0);
                              ctrl.setAmountPaid(due);
                            });
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    const Text(
                      'Metode Pembayaran',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    ),
                    const SizedBox(height: 8),

                    // Compact 4-Method Row matching Admin POS style
                    Row(
                      children: [
                        Expanded(
                          child: _methodTile(
                            ctrl: ctrl,
                            value: 'tunai',
                            label: 'Tunai',
                            icon: Icons.payments_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _methodTile(
                            ctrl: ctrl,
                            value: 'qris',
                            label: 'QRIS',
                            icon: Icons.qr_code_2_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _methodTile(
                            ctrl: ctrl,
                            value: 'transfer',
                            label: 'Transfer',
                            icon: Icons.account_balance_rounded,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _methodTile(
                            ctrl: ctrl,
                            value: 'kasbon',
                            label: 'Kasbon',
                            icon: Icons.hourglass_top_rounded,
                            mutedDisabled: !hasRegisteredCust,
                          ),
                        ),
                      ],
                    ),
                    if (!hasRegisteredCust)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          'Kasbon hanya aktif jika pelanggan terdaftar dipilih.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Method-specific sections
                    if (isTunai) ...[
                      TextField(
                        controller: _paidCtrl,
                        focusNode: _paidFocusNode,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: AppTheme.denseInputDecoration(
                          hintText: '0',
                          prefixIcon: Icons.money_rounded,
                        ).copyWith(
                          labelText: 'Uang Diterima',
                          prefixText: 'Rp ',
                          suffixIcon: _paidCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _paidCtrl.clear();
                                    ctrl.setAmountPaid(0);
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) {
                          final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                          ctrl.setAmountPaid(double.tryParse(cleaned) ?? 0.0);
                        },
                      ),
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: suggestions.map((amt) {
                            final isExact = (amt - netDue).abs() < 1;
                            final isSelected = (ctrl.amountPaid - amt).abs() < 1;
                            return ChoiceChip(
                              selected: isSelected,
                              selectedColor: AppTheme.primaryGreenSoft,
                              side: BorderSide(
                                color: isSelected ? AppTheme.primaryGreen : AppTheme.borderLight,
                              ),
                              label: Text(
                                isExact
                                    ? '${CurrencyHelper.format(amt)} (Pas)'
                                    : CurrencyHelper.format(amt),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? AppTheme.primaryGreen : AppTheme.textDark,
                                ),
                              ),
                              onSelected: (_) {
                                _paidCtrl.text = amt.toStringAsFixed(0);
                                ctrl.setAmountPaid(amt);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: tunaiInsufficient ? AppTheme.accentRedSoft : AppTheme.lightGreyBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: tunaiInsufficient
                                ? AppTheme.accentRed.withValues(alpha: 0.35)
                                : AppTheme.borderLight,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tunaiInsufficient ? 'Kurang Bayar' : 'Kembalian',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: tunaiInsufficient ? AppTheme.accentRed : AppTheme.textDark,
                              ),
                            ),
                            Text(
                              CurrencyHelper.format(
                                tunaiInsufficient ? shortfall : ctrl.changeAmount,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: tunaiInsufficient ? AppTheme.accentRed : AppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (ctrl.paymentMethod == 'qris') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: QrImageView(
                                data: 'KASIRTOKO-QRIS|${netDue.toInt()}',
                                size: 58,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pembayaran QRIS',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pastikan pembayaran ${CurrencyHelper.format(netDue)} sudah masuk sebelum menyelesaikan.',
                                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (ctrl.paymentMethod == 'transfer') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.lightGreyBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderLight),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_rounded, color: AppTheme.primaryGreen),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Transfer sebesar ${CurrencyHelper.format(netDue)}. Verifikasi mutasi masuk sebelum mengesahkan.',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (isKasbon) ...[
                      TextField(
                        controller: _paidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: AppTheme.denseInputDecoration(
                          hintText: '0',
                          prefixIcon: Icons.hourglass_bottom_rounded,
                        ).copyWith(
                          labelText: 'Uang Muka / DP (Isi 0 jika tempo penuh)',
                          prefixText: 'Rp ',
                        ),
                        onChanged: (v) {
                          final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                          ctrl.setAmountPaid(double.tryParse(cleaned) ?? 0.0);
                        },
                      ),
                    ],

                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteCtrl,
                      decoration: AppTheme.denseInputDecoration(
                        hintText: 'Mis. Tanpa kantong plastik / meja 4',
                        prefixIcon: Icons.note_alt_outlined,
                      ).copyWith(labelText: 'Catatan Nota (Opsional)'),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppTheme.primaryGreen,
                      title: const Text(
                        'Cetak Struk di Printer Admin',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Kirim antrean cetak otomatis setelah disahkan',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      value: _requestPrint,
                      onChanged: (v) => setState(() => _requestPrint = v),
                    ),
                  ],
                ),
              ),
            ),

            // Sticky Bottom CTA Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: AppTheme.lightGreyBg,
                border: Border(top: BorderSide(color: AppTheme.borderLight)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: ctrl.isCheckingOut ? null : () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: canSubmit ? () => _submit(ctrl) : null,
                        icon: ctrl.isCheckingOut
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline_rounded, size: 19),
                        label: Text(
                          ctrl.isCheckingOut ? 'Memproses...' : 'Sahkan & Bayar',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodTile({
    required StaffSessionController ctrl,
    required String value,
    required String label,
    required IconData icon,
    bool mutedDisabled = false,
  }) {
    final selected = ctrl.paymentMethod == value;
    final fgColor = selected
        ? AppTheme.primaryGreen
        : (mutedDisabled ? AppTheme.textMuted.withValues(alpha: 0.55) : AppTheme.textSecondary);

    return Material(
      color: selected ? AppTheme.primaryGreenSoft : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _applyPaymentMethod(ctrl, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryGreen : AppTheme.borderLight,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: fgColor),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
