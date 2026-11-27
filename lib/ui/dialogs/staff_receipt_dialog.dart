import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../data/models/staff_models.dart';
import '../../providers/staff_session_controller.dart';

class StaffReceiptDialog extends StatefulWidget {
  final StaffReceipt receipt;
  final StaffPrintJob? initialPrintJob;

  const StaffReceiptDialog({
    super.key,
    required this.receipt,
    this.initialPrintJob,
  });

  @override
  State<StaffReceiptDialog> createState() => _StaffReceiptDialogState();
}

class _StaffReceiptDialogState extends State<StaffReceiptDialog> {
  StaffPrintJob? _job;
  Timer? _pollTimer;
  bool _reprinting = false;

  @override
  void initState() {
    super.initState();
    _job = widget.initialPrintJob;
    if (_job != null && (_job!.status == 'queued' || _job!.status == 'processing' || _job!.status == 'retrying')) {
      _startPolling(_job!.jobUuid);
    }
  }

  void _startPolling(String jobUuid) {
    _pollTimer?.cancel();
    var ticks = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      ticks++;
      if (!mounted || ticks > 15) {
        _pollTimer?.cancel();
        return;
      }
      final ctrl = Provider.of<StaffSessionController>(context, listen: false);
      final latest = await ctrl.getPrintJobStatus(jobUuid);
      if (!mounted) return;
      if (latest != null) {
        setState(() => _job = latest);
        if (latest.status == 'submitted' || latest.status == 'failed' || latest.status == 'cancelled') {
          _pollTimer?.cancel();
        }
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _describePrintStatus(StaffPrintJob j) {
    switch (j.status) {
      case 'queued':
        return 'Antrean cetak di POS Admin...';
      case 'processing':
        return 'Mengirim data ESC/POS ke printer...';
      case 'submitted':
        return 'Data struk terkirim ke printer${j.drawerPulseSent ? ' (laci dibuka)' : ''}';
      case 'retrying':
        return 'Mencoba mengirim ulang ke printer...';
      case 'failed':
        return 'Gagal kirim ke printer: ${j.errorMessage}';
      default:
        return j.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final r = widget.receipt;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: AppTheme.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Struk ${r.invoiceNumber}', style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80).clamp(200.0, 400.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ctrl.storeName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (ctrl.storeAddress.isNotEmpty)
                Text(ctrl.storeAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
              const Divider(height: 18),
              Text('Nota    : ${r.invoiceNumber}', style: const TextStyle(fontSize: 12)),
              Text('Kasir   : ${r.cashierName} (${r.terminalId})', style: const TextStyle(fontSize: 12)),
              Text('Pelanggan: ${r.customerName}', style: const TextStyle(fontSize: 12)),
              Text('Metode  : ${r.paymentMethod.toUpperCase()}', style: const TextStyle(fontSize: 12)),
              const Divider(height: 16),
              ...r.items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${it.productName} (${CurrencyHelper.formatNumber(it.qty)} ${it.unitName})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(CurrencyHelper.format(it.subtotal), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  )),
              const Divider(height: 16),
              _kv('Subtotal', CurrencyHelper.format(r.subtotal)),
              if (r.discountTotal > 0) _kv('Diskon', '- ${CurrencyHelper.format(r.discountTotal)}'),
              if (r.taxAmount > 0) _kv('Pajak', CurrencyHelper.format(r.taxAmount)),
              _kv('TOTAL', CurrencyHelper.format(r.grandTotal), bold: true),
              if (r.creditUsed > 0) _kv('Saldo Kredit', '- ${CurrencyHelper.format(r.creditUsed)}'),
              _kv('Dibayar', CurrencyHelper.format(r.amountPaid)),
              if (r.changeAmount > 0) _kv('Kembalian', CurrencyHelper.format(r.changeAmount)),
              const SizedBox(height: 12),
              Center(
                child: QrImageView(
                  data: r.qrCodePayload.isNotEmpty ? r.qrCodePayload : r.invoiceNumber,
                  size: 110,
                ),
              ),
              if (_job != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _job!.status == 'failed' ? Colors.red.shade50 : Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _describePrintStatus(_job!),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _job!.status == 'failed' ? AppTheme.accentRed : AppTheme.textDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _reprinting || !ctrl.adminReachable
              ? null
              : () async {
                  setState(() => _reprinting = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final res = await ctrl.requestReprint(r.invoiceNumber);
                  if (!mounted) return;
                  setState(() {
                    _reprinting = false;
                    if (res.job != null) _job = res.job;
                  });
                  if (res.job != null) {
                    _startPolling(res.job!.jobUuid);
                  } else if (res.error != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(res.error!), backgroundColor: AppTheme.accentRed),
                    );
                  }
                },
          icon: const Icon(Icons.print_rounded, size: 17),
          label: const Text('Cetak Ulang'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Selesai'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                k,
                style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.bold : FontWeight.w500),
              ),
            ),
          ],
        ),
      );
}
