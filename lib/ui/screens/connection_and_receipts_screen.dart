import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../providers/staff_session_controller.dart';
import '../dialogs/staff_receipt_dialog.dart';

class ConnectionAndReceiptsScreen extends StatelessWidget {
  const ConnectionAndReceiptsScreen({super.key});

  Future<void> _showManualDrawerDialog(BuildContext context, StaffSessionController ctrl) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Buka Laci Kasir Manual'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Alasan (Wajib masuk log audit Admin)',
                hintText: 'Mis. Tukar uang kembalian pecahan kecil',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim Perintah')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final res = await ctrl.requestManualDrawerOpen(reasonCtrl.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.error ?? (res.triggered ? 'Perintah buka laci terkirim ke Admin.' : 'Laci tidak dapat dipicu.'),
        ),
        backgroundColor: res.error != null ? AppTheme.accentRed : AppTheme.success,
      ),
    );
  }

  Future<void> _showSwitchEndpointDialog(BuildContext context, StaffSessionController ctrl) async {
    final currentUri = Uri.tryParse(ctrl.credentials?.serverUrl ?? '');
    final hostCtrl = TextEditingController(text: currentUri?.host ?? '192.168.43.1');
    final portCtrl = TextEditingController(text: (currentUri?.hasPort == true ? currentUri!.port : 8443).toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: const Text('Pindah IP Server Admin Manual'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Gunakan saat beralih ke Hotspot HP Admin cadangan atau router baru tanpa perlu pairing ulang. Sistem tetap memverifikasi Server ID dan fingerprint TLS Admin.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP Server Admin Baru (cth. 192.168.43.1)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port HTTPS',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verifikasi & Pindah')),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;
    final success = await ctrl.updateServerEndpointManually(
      host: hostCtrl.text.trim(),
      port: int.tryParse(portCtrl.text.trim()) ?? 8443,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Berhasil berpindah dan terverifikasi ke ${ctrl.credentials?.serverUrl} (${ctrl.networkStatus.displayLabel}).'
              : (ctrl.lastError ?? 'Gagal menghubungkan ke IP baru dengan verifikasi TLS & Server ID.'),
        ),
        backgroundColor: success ? AppTheme.success : AppTheme.accentRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final creds = ctrl.credentials;
    final canManualDrawer =
        ctrl.allowManualOpenDrawer && (ctrl.cashier?.hasPermission('open_cash_drawer') == true);
    final certPinPreview = (creds != null && creds.tlsCertSha256.length >= 12)
        ? creds.tlsCertSha256.substring(0, 12).toUpperCase()
        : (creds?.tlsCertSha256.toUpperCase() ?? '-');

    return Scaffold(
      appBar: AppBar(title: const Text('Koneksi, Struk & Diagnostik')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status Terminal, Jaringan & Keamanan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text('Status Jaringan : ${ctrl.networkStatus.displayLabel}'),
                      Text('Server ID      : ${ctrl.serverId.isEmpty ? "-" : ctrl.serverId}'),
                      Text('Terminal ID    : ${creds?.terminalId ?? "-"} (${creds?.terminalName ?? ""})'),
                      Text('Alamat Aktif   : ${creds?.serverUrl ?? "-"}'),
                      if (creds != null && creds.primaryServerUrl.isNotEmpty)
                        Text('Router Utama   : ${creds.primaryServerUrl}'),
                      if (creds != null && creds.backupServerUrl.isNotEmpty)
                        Text('Hotspot Cadangan: ${creds.backupServerUrl}'),
                      Text('WebSocket      : ${ctrl.wsConnected ? "Terhubung Real-time" : "Terputus"}'),
                      Text('Sync Version   : v${ctrl.lastSyncVersion}'),
                      Text('Clock Offset   : ${ctrl.httpClient.signer.clockOffsetMs} ms'),
                      Text('TLS Pin SHA256 : $certPinPreview...'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => ctrl.checkConnectivityAndRestoreSession(),
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('Rekoneksi & Failover Otomatis'),
                          ),
                          OutlinedButton.icon(
                            onPressed: creds != null && creds.isPaired
                                ? () => _showSwitchEndpointDialog(context, ctrl)
                                : null,
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                            label: const Text('Ganti IP Manual (Router/Hotspot)'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => ctrl.syncCatalogFull(),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Sinkron Katalog Penuh'),
                          ),
                          if (canManualDrawer)
                            OutlinedButton.icon(
                              onPressed: () => _showManualDrawerDialog(context, ctrl),
                              icon: const Icon(Icons.point_of_sale_rounded, size: 18, color: Colors.orange),
                              label: const Text('Buka Laci Manual'),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              await ctrl.logoutCashier();
                              if (context.mounted) Navigator.pop(context);
                            },
                            icon: const Icon(Icons.logout_rounded, color: AppTheme.accentRed),
                            label: const Text('Logout Kasir', style: TextStyle(color: AppTheme.accentRed)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              '30 Struk Terbaru Terminal',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ctrl.syncRecentReceiptsFromServer(),
                            child: const Text('Muat Ulang'),
                          ),
                        ],
                      ),
                      if (ctrl.recentReceipts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Belum ada transaksi tersahkan di terminal ini.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      else
                        ...ctrl.recentReceipts.map((r) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(r.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${r.cashierName} • ${r.paymentMethod.toUpperCase()}'),
                              trailing: Text(
                                CurrencyHelper.format(r.grandTotal),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              onTap: () => showDialog(
                                context: context,
                                builder: (_) => StaffReceiptDialog(receipt: r),
                              ),
                            )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
