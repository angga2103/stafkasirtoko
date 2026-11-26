import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../data/models/staff_models.dart';
import '../../providers/staff_session_controller.dart';
import '../dialogs/staff_payment_dialog.dart';
import 'connection_and_receipts_screen.dart';
import 'staff_shift_screen.dart';

class StaffPosScreen extends StatefulWidget {
  const StaffPosScreen({super.key});

  @override
  State<StaffPosScreen> createState() => _StaffPosScreenState();
}

class _StaffPosScreenState extends State<StaffPosScreen> {
  final _searchCtrl = TextEditingController();
  final BarcodeScanGuard _scanGuard = BarcodeScanGuard();
  String _selectedCategory = 'Semua';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeScanned(String code) async {
    final clean = code.trim();
    if (!_scanGuard.shouldAccept(clean)) return;
    try {
      await const MethodChannel('com.kasirtoko.app.stafkasirtoko/hardware')
          .invokeMethod('playBeep', {'durationMs': 110});
    } catch (_) {}

    if (!mounted) return;
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    final match = await ctrl.lookupBarcodeLiveOrCache(clean);
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode "$clean" tidak ditemukan.'), backgroundColor: AppTheme.warning),
      );
      return;
    }
    final res = await ctrl.addToCart(match.product, unit: match.unit);
    if (!mounted) return;
    if (!res.success && res.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message!), backgroundColor: AppTheme.accentRed),
      );
    }
  }

  Future<void> _openCameraScanner() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Scan Barcode Produk')),
          body: MobileScanner(
            onDetect: (cap) {
              for (final b in cap.barcodes) {
                final raw = b.rawValue ?? '';
                if (raw.isNotEmpty) {
                  Navigator.pop(ctx);
                  _handleBarcodeScanned(raw);
                  return;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onProductTap(StaffSessionController ctrl, StaffProduct p) async {
    if (p.units.isEmpty) {
      final res = await ctrl.addToCart(p);
      if (!mounted) return;
      if (!res.success && res.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message!), backgroundColor: AppTheme.accentRed),
        );
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Pilih Satuan Penjualan'),
            ),
            ListTile(
              title: Text('${p.baseUnit} (Satuan Dasar)'),
              trailing: Text(CurrencyHelper.format(p.sellingPrice)),
              onTap: () async {
                Navigator.pop(ctx);
                final res = await ctrl.addToCart(p);
                if (mounted && !res.success && res.message != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.message!), backgroundColor: AppTheme.accentRed),
                  );
                }
              },
            ),
            ...p.units.map((u) => ListTile(
                  title: Text('${u.unitName} (${CurrencyHelper.formatNumber(u.conversionFactor)} ${p.baseUnit})'),
                  trailing: Text(CurrencyHelper.format(u.sellingPrice)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final res = await ctrl.addToCart(p, unit: u);
                    if (mounted && !res.success && res.message != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res.message!), backgroundColor: AppTheme.accentRed),
                      );
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomerPicker(StaffSessionController ctrl) async {
    final searchCtrl = TextEditingController();
    final canAddCust = ctrl.cashier?.hasPermission('manage_customers') == true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final q = searchCtrl.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? ctrl.customers
              : ctrl.customers
                  .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q))
                  .toList();
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Pilih Pelanggan')),
                if (canAddCust)
                  IconButton(
                    icon: const Icon(Icons.person_add_rounded, color: AppTheme.primaryGreen),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _showAddCustomerDialog(ctrl);
                    },
                  ),
              ],
            ),
            content: SizedBox(
              width: 360,
              height: 320,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Cari nama / HP...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          title: const Text('Pelanggan Umum (Walk-in)'),
                          onTap: () {
                            ctrl.setCustomer(null);
                            Navigator.pop(ctx);
                          },
                        ),
                        ...filtered.where((c) => !c.isWalkIn).map((c) => ListTile(
                              title: Text(c.name),
                              subtitle: Text(
                                '${c.phone.isEmpty ? "-" : c.phone} • Kredit: ${CurrencyHelper.format(c.creditBalance)}',
                              ),
                              onTap: () {
                                ctrl.setCustomer(c);
                                Navigator.pop(ctx);
                              },
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddCustomerDialog(StaffSessionController ctrl) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pelanggan Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama *', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'No HP', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await ctrl.createCustomerOnAdmin(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim());
    }
  }

  Future<void> _showPromoAndDiscountSheet(StaffSessionController ctrl) async {
    final canDiscount = ctrl.cashier?.hasPermission('apply_discount') == true;
    final discCtrl = TextEditingController(text: ctrl.manualDiscount.toStringAsFixed(0));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Promo & Diskon Transaksi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              if (ctrl.promos.isNotEmpty) ...[
                const Text('Promo Aktif:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Tanpa Promo'),
                      selected: ctrl.selectedPromo == null,
                      onSelected: (_) {
                        ctrl.setSelectedPromo(null);
                        Navigator.pop(ctx);
                      },
                    ),
                    ...ctrl.promos.map((p) => ChoiceChip(
                          label: Text(p.name),
                          selected: ctrl.selectedPromo?.id == p.id,
                          onSelected: (_) {
                            ctrl.setSelectedPromo(p);
                            Navigator.pop(ctx);
                          },
                        )),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (canDiscount) ...[
                TextField(
                  controller: discCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Diskon Manual Tambahan (Rp)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    ctrl.setManualDiscount(double.tryParse(discCtrl.text.trim()) ?? 0.0);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Terapkan Diskon'),
                ),
              ] else
                const Text(
                  'Akun Anda tidak memiliki izin memberikan diskon manual.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHeldOrdersDialog(StaffSessionController ctrl) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Draft Tertahan (${ctrl.heldOrders.length})'),
        content: SizedBox(
          width: 360,
          child: ctrl.heldOrders.isEmpty
              ? const Text('Tidak ada keranjang yang ditahan.')
              : ListView(
                  shrinkWrap: true,
                  children: ctrl.heldOrders
                      .map((h) => ListTile(
                            title: Text('${h.customerName} (${h.items.length} item)'),
                            subtitle: Text('Disimpan lokal ${h.heldAt.substring(11, 16)}'),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await ctrl.resumeHeldOrder(h.holdUuid);
                            },
                          ))
                      .toList(),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);

    final cats = <String>{'Semua', ...ctrl.products.map((p) => p.category)}.toList();
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = ctrl.products.where((p) {
      if (_selectedCategory != 'Semua' && p.category != _selectedCategory) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctrl.storeName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
            Text(
              '${ctrl.cashier?.name ?? ""} • ${ctrl.credentials?.terminalId ?? ""}',
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Shift & Laci Kas',
            icon: const Icon(Icons.lock_clock_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffShiftScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Status Koneksi & Struk',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConnectionAndReceiptsScreen()),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 680;
          return Column(
            children: [
              _buildStatusBanner(ctrl),
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          Expanded(flex: 6, child: _buildCatalogPane(ctrl, cats, filtered)),
                          const VerticalDivider(width: 1),
                          Expanded(flex: 4, child: _buildCartPane(ctrl)),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _buildCatalogPane(ctrl, cats, filtered)),
                          _buildPhoneCartFooter(ctrl),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner(StaffSessionController ctrl) {
    final state = ctrl.connectionState;
    late Color bg;
    late String text;
    Widget? trailing;

    switch (state) {
      case TerminalConnectionState.onlineReady:
        bg = AppTheme.success;
        text =
            'Online • Shift #${ctrl.currentShift?.id} (${ctrl.drawerMode}) • Sinkron v${ctrl.lastSyncVersion}';
        break;
      case TerminalConnectionState.shiftClosed:
        bg = AppTheme.warning;
        text = 'Shift belum dibuka — transaksi diblokir sampai shift dibuka';
        trailing = TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffShiftScreen()),
          ),
          child: const Text('Buka Shift', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        );
        break;
      default:
        bg = AppTheme.accentRed;
        text = 'Terputus dari POS Admin — Keranjang disimpan, checkout dikunci';
        trailing = TextButton(
          onPressed: () => ctrl.checkConnectivityAndRestoreSession(),
          child: const Text('Rekoneksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        );
        break;
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            state == TerminalConnectionState.onlineReady ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildCatalogPane(
    StaffSessionController ctrl,
    List<String> cats,
    List<StaffProduct> filtered,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari nama / scan barcode HID...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      _handleBarcodeScanned(val);
                      _searchCtrl.clear();
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _openCameraScanner,
                style: IconButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: cats.length,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (_, idx) {
              final c = cats[idx];
              return ChoiceChip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                selected: _selectedCategory == c,
                onSelected: (_) => setState(() => _selectedCategory = c),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    ctrl.isSyncing ? 'Mengunduh katalog dari POS Admin...' : 'Produk tidak ditemukan.',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 1.05,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final p = filtered[idx];
                    return InkWell(
                      onTap: p.isOutOfStock ? null : () => _onProductTap(ctrl, p),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: AppTheme.cardDecoration(
                          color: p.isOutOfStock ? Colors.grey.shade100 : Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  CurrencyHelper.format(p.sellingPrice),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryGreen,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  p.isService
                                      ? 'Jasa'
                                      : 'Stok: ${CurrencyHelper.formatNumber(p.stock)} ${p.baseUnit}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.isOutOfStock ? AppTheme.accentRed : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCartPane(StaffSessionController ctrl) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCustomerPicker(ctrl),
                    icon: const Icon(Icons.person_outline_rounded, size: 17),
                    label: Text(ctrl.customerName, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Promo & Diskon',
                  onPressed: () => _showPromoAndDiscountSheet(ctrl),
                  icon: const Icon(Icons.discount_outlined),
                ),
                IconButton(
                  tooltip: 'Tahan Keranjang',
                  onPressed: ctrl.cartItems.isEmpty ? null : () => ctrl.holdCurrentCart(),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                ),
                if (ctrl.heldOrders.isNotEmpty)
                  IconButton(
                    tooltip: 'Order Tertahan',
                    onPressed: () => _showHeldOrdersDialog(ctrl),
                    icon: Badge(
                      label: Text('${ctrl.heldOrders.length}'),
                      child: const Icon(Icons.restore_rounded),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ctrl.cartItems.isEmpty
                ? const Center(
                    child: Text('Keranjang kosong. Tap produk atau scan barcode.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: ctrl.cartItems.length,
                    separatorBuilder: (context, index) => const Divider(height: 10),
                    itemBuilder: (_, i) {
                      final it = ctrl.cartItems[i];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(
                                  '${CurrencyHelper.format(it.unitPrice)} / ${it.unitName}',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: () => ctrl.updateCartItemQty(i, it.qty - 1),
                          ),
                          Text(CurrencyHelper.formatNumber(it.qty), style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () => ctrl.updateCartItemQty(i, it.qty + 1),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ctrl.discountTotal > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(child: Text('Diskon/Promo', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                      Text('- ${CurrencyHelper.format(ctrl.discountTotal)}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.accentRed)),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Grand Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      CurrencyHelper.format(ctrl.grandTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: ctrl.canSubmitCheckout
                      ? () => showDialog(
                            context: context,
                            builder: (_) => const StaffPaymentDialog(),
                          )
                      : null,
                  icon: const Icon(Icons.payments_rounded),
                  label: Text(
                    ctrl.canSubmitCheckout
                        ? 'Bayar Sekarang'
                        : (ctrl.connectionState == TerminalConnectionState.onlineReady
                            ? 'Keranjang Kosong'
                            : 'Checkout Terkunci (Admin Offline / Shift Tutup)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneCartFooter(StaffSessionController ctrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.72,
                  child: _buildCartPane(ctrl),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${ctrl.cartItems.length} item • ${ctrl.customerName}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                  Text(
                    CurrencyHelper.format(ctrl.grandTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.primaryGreen),
                  ),
                ],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: ctrl.canSubmitCheckout
                ? () => showDialog(
                      context: context,
                      builder: (_) => const StaffPaymentDialog(),
                    )
                : null,
            child: Text(ctrl.canSubmitCheckout ? 'Bayar' : 'Terkunci'),
          ),
        ],
      ),
    );
  }
}
