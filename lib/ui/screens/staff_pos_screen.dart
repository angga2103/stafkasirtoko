import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/hardware_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../data/models/staff_models.dart';
import '../../providers/staff_session_controller.dart';
import '../dialogs/staff_payment_dialog.dart';
import 'connection_and_receipts_screen.dart';
import 'staff_barcode_scanner_screen.dart';
import 'staff_shift_screen.dart';

class StaffPosScreen extends StatefulWidget {
  final ScannerCameraAdapter Function()? scannerAdapterFactory;

  const StaffPosScreen({super.key, this.scannerAdapterFactory});

  @override
  State<StaffPosScreen> createState() => _StaffPosScreenState();
}

class _StaffPosScreenState extends State<StaffPosScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _gridScrollCtrl = ScrollController();

  String _selectedCategory = 'Semua';
  bool _isScannerOpen = false;
  final Set<int> _busyProductIds = <int>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _gridScrollCtrl.dispose();
    super.dispose();
  }

  void _showFeedbackSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          backgroundColor: isError ? AppTheme.accentRed : AppTheme.success,
          duration: Duration(seconds: isError ? 3 : 2),
        ),
      );
  }

  Future<void> _mutateProductWithGuard(
    int productId,
    Future<({bool success, String? message})> Function() action, {
    bool playBeepOnSuccess = false,
  }) async {
    if (_busyProductIds.contains(productId)) return;
    _busyProductIds.add(productId);
    try {
      final res = await action();
      if (!mounted) return;
      if (!res.success && res.message != null) {
        unawaited(HardwareFeedback.playErrorFeedback());
        _showFeedbackSnack(res.message!, isError: true);
      } else if (res.success && playBeepOnSuccess) {
        unawaited(HardwareFeedback.playSuccessBeep());
      }
    } finally {
      _busyProductIds.remove(productId);
    }
  }

  Future<ScannerScanFeedback> _processScannedBarcode(
    StaffSessionController ctrl,
    String code, {
    bool allowUnitPickerFallback = false,
  }) async {
    final clean = code.trim();
    if (clean.isEmpty) {
      return const ScannerScanFeedback(
        barcode: '',
        title: 'Kode kosong',
        subtitle: 'Arahkan kamera ke barcode produk',
        success: false,
      );
    }

    final match = await ctrl.lookupBarcodeLiveOrCache(clean);
    if (!mounted) {
      return ScannerScanFeedback(
        barcode: clean,
        title: 'Scanner ditutup',
        success: false,
      );
    }
    if (match == null) {
      return ScannerScanFeedback(
        barcode: clean,
        title: 'Kode "$clean" tidak ditemukan',
        subtitle: ctrl.adminReachable
            ? 'Barcode/SKU tidak terdaftar di katalog Admin'
            : 'Mode offline: produk tidak ada di cache lokal',
        success: false,
      );
    }

    if (allowUnitPickerFallback && match.unit == null && match.product.units.isNotEmpty) {
      await _showUnitPicker(match.product);
      return ScannerScanFeedback(
        barcode: clean,
        title: match.product.name,
        subtitle: 'Pilih satuan untuk menambahkan ke keranjang',
        success: true,
      );
    }

    final unit = match.unit;
    final res = await ctrl.addToCart(match.product, unit: unit);
    if (!res.success) {
      return ScannerScanFeedback(
        barcode: clean,
        title: match.product.name,
        subtitle: res.message ?? 'Gagal menambah ke keranjang',
        success: false,
      );
    }

    final unitName = unit?.unitName ?? match.product.baseUnit;
    final unitPrice = unit?.sellingPrice ?? match.product.sellingPrice;
    final inCart = ctrl.getProductCartDisplayQty(match.product.id);
    return ScannerScanFeedback(
      barcode: clean,
      title: match.product.name,
      subtitle:
          '${CurrencyHelper.format(unitPrice)}/$unitName • Di keranjang: ${CurrencyHelper.formatNumber(inCart)} ${match.product.baseUnit}',
      success: true,
    );
  }

  Future<void> _handleSearchSubmitBarcode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    final fb = await _processScannedBarcode(ctrl, clean, allowUnitPickerFallback: true);
    if (!mounted) return;
    if (fb.success) {
      unawaited(HardwareFeedback.playSuccessBeep());
      _searchCtrl.clear();
      setState(() {});
      _showFeedbackSnack('${fb.title} • ${fb.subtitle ?? 'Masuk keranjang'}');
    } else {
      unawaited(HardwareFeedback.playErrorFeedback());
      _showFeedbackSnack(fb.subtitle ?? fb.title, isError: true);
    }
  }

  Future<void> _openCameraScanner() async {
    if (_isScannerOpen || !mounted) return;
    _isScannerOpen = true;
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    _searchFocusNode.unfocus();

    String? singleCode;
    try {
      singleCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffBarcodeScannerScreen(
              title: 'Scan Barcode Produk',
              subtitle: 'Arahkan barcode produk ke bingkai kamera',
              initialMode: StaffScannerMode.continuous,
              allowModeToggle: true,
              showCartSummary: true,
              adapterOverride: widget.scannerAdapterFactory?.call(),
              onContinuousScan: (raw) => _processScannedBarcode(ctrl, raw),
            ),
          ),
        ),
      );
    } finally {
      _isScannerOpen = false;
    }

    // In "1x & Tutup" mode, await lookup strictly AFTER scanner route has stopped & popped once.
    if (singleCode != null && singleCode.isNotEmpty && mounted) {
      final fb = await _processScannedBarcode(ctrl, singleCode, allowUnitPickerFallback: true);
      if (!mounted) return;
      if (fb.success) {
        _showFeedbackSnack('${fb.title} masuk keranjang');
      } else {
        _showFeedbackSnack(fb.subtitle ?? fb.title, isError: true);
      }
    }
  }

  Future<void> _showUnitPicker(StaffProduct prod) async {
    final ctrl = Provider.of<StaffSessionController>(context, listen: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prod.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          prod.managesStock
                              ? 'Stok tersedia: ${CurrencyHelper.formatNumber(prod.stock)} ${prod.baseUnit}'
                              : (prod.isService ? 'Layanan / Jasa' : 'Tanpa batas stok'),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _unitTile(
                        ctx: ctx,
                        ctrl: ctrl,
                        product: prod,
                        unit: null,
                        label: '${prod.baseUnit} (Satuan Dasar)',
                        price: prod.sellingPrice,
                      ),
                      ...prod.units.map(
                        (u) => _unitTile(
                          ctx: ctx,
                          ctrl: ctrl,
                          product: prod,
                          unit: u,
                          label: '${u.unitName} (Isi ${CurrencyHelper.formatNumber(u.conversionFactor)} ${prod.baseUnit})',
                          price: u.sellingPrice,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unitTile({
    required BuildContext ctx,
    required StaffSessionController ctrl,
    required StaffProduct product,
    required StaffProductUnit? unit,
    required String label,
    required double price,
  }) {
    final unitName = unit?.unitName ?? product.baseUnit;
    final inCartQty = ctrl.getUnitCartQty(product.id, unitName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppTheme.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
        dense: true,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: Text(
          CurrencyHelper.format(price),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
        ),
        trailing: inCartQty > 0
            ? Chip(
                backgroundColor: AppTheme.primaryGreenSoft,
                side: const BorderSide(color: AppTheme.primaryGreen),
                label: Text(
                  '+1 (${CurrencyHelper.formatNumber(inCartQty)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                    fontSize: 12,
                  ),
                ),
              )
            : ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _mutateProductWithGuard(
                    product.id,
                    () => ctrl.addToCart(product, unit: unit),
                    playBeepOnSuccess: true,
                  );
                },
                child: const Text('+ Tambah'),
              ),
        onTap: () async {
          Navigator.pop(ctx);
          await _mutateProductWithGuard(
            product.id,
            () => ctrl.addToCart(product, unit: unit),
            playBeepOnSuccess: true,
          );
        },
        ),
      ),
    );
  }

  Future<void> _showQuickQtyInputDialog(
    StaffSessionController ctrl,
    StaffProduct prod,
    StaffProductUnit? unit,
  ) async {
    final unitName = unit?.unitName ?? prod.baseUnit;
    final currentQty = ctrl.getUnitCartQty(prod.id, unitName);
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _NumberInputDialog(
        title: 'Jumlah ${prod.name}',
        labelText: 'Qty ($unitName)',
        hintText: 'Masukkan 0 untuk hapus dari keranjang',
        initialValue: currentQty > 0 ? CurrencyHelper.formatNumber(currentQty) : '1',
        allowDecimal: true,
      ),
    );
    if (raw == null || !mounted) return;
    final submitted = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (submitted == null || submitted < 0) return;
    await _mutateProductWithGuard(
      prod.id,
      () => ctrl.setProductQtyDirect(prod, submitted, unit: unit),
    );
  }

  Future<void> _openCheckoutDialog(StaffSessionController ctrl) async {
    if (!ctrl.canSubmitCheckout) {
      String reason = 'Checkout belum siap.';
      if (!ctrl.adminReachable && !ctrl.wsConnected) {
        reason = 'Checkout Terkunci: perangkat tidak terhubung ke POS Admin.';
      } else if (ctrl.currentShift == null || !ctrl.currentShift!.isOpen) {
        reason = 'Shift kasir belum dibuka. Buka shift terlebih dahulu.';
      } else if (ctrl.cartItems.isEmpty) {
        reason = 'Keranjang masih kosong.';
      }
      _showFeedbackSnack(reason, isError: true);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
        value: ctrl,
        child: const StaffPaymentDialog(),
      ),
    );
  }

  void _openCartSheet(StaffSessionController ctrl) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => ChangeNotifierProvider<StaffSessionController>.value(
        value: ctrl,
        child: DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.50,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: _StaffCartPane(
              inBottomSheet: true,
              scrollController: scrollCtrl,
              onCloseSheet: () => Navigator.pop(sheetCtx),
              onCheckoutPressed: () {
                Navigator.pop(sheetCtx);
                _openCheckoutDialog(ctrl);
              },
              onMessage: _showFeedbackSnack,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    final isTablet = AppBreakpoints.isTablet(context);
    final compactPhone = AppBreakpoints.isCompactPhone(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final statusMsg = ctrl.statusMessage;

    final categories = <String>{'Semua', ...ctrl.products.map((p) => p.category)}.toList();
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'Semua';
    }

    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredProducts = ctrl.products.where((p) {
      if (_selectedCategory != 'Semua' && p.category != _selectedCategory) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.code.toLowerCase().contains(query) ||
          p.barcode.toLowerCase().contains(query) ||
          p.units.any((u) => u.barcode.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      appBar: _buildCompactAppBar(ctrl, compactPhone),
      body: Column(
        children: [
          if (!keyboardOpen) _buildStatusBanner(ctrl),
          if (!keyboardOpen && statusMsg != null && statusMsg.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              child: Text(
                statusMsg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: isTablet
                ? Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: _buildCatalogColumn(
                          ctrl: ctrl,
                          categories: categories,
                          filteredProducts: filteredProducts,
                          compactPhone: compactPhone,
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderLight),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 330, maxWidth: 420),
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width * 0.34,
                          child: _StaffCartPane(
                            inBottomSheet: false,
                            onCheckoutPressed: () => _openCheckoutDialog(ctrl),
                            onMessage: _showFeedbackSnack,
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildCatalogColumn(
                    ctrl: ctrl,
                    categories: categories,
                    filteredProducts: filteredProducts,
                    compactPhone: compactPhone,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: isTablet
          ? null
          : _buildMobileBottomCartBar(ctrl, keyboardOpen: keyboardOpen, compactPhone: compactPhone),
    );
  }

  PreferredSizeWidget _buildCompactAppBar(StaffSessionController ctrl, bool compactPhone) {
    final shift = ctrl.currentShift;
    final veryCompact = MediaQuery.sizeOf(context).width < 350;
    return AppBar(
      titleSpacing: veryCompact ? 8 : 12,
      title: Row(
        children: [
          if (!veryCompact) ...[
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/branding/kasirtoko_staff_logo.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.point_of_sale_rounded,
                    color: AppTheme.primaryGreen,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctrl.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.15),
                ),
                Text(
                  '${ctrl.cashier?.name ?? "Kasir"} • ${ctrl.credentials?.terminalId ?? "-"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.15),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _buildConnectionChip(ctrl, compact: compactPhone),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
                value: ctrl,
                child: const StaffShiftScreen(),
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: shift != null && shift.isOpen ? 0.16 : 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white30, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  shift != null && shift.isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  shift != null && shift.isOpen ? 'Shift' : 'Tutup',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Struk & Koneksi',
          padding: EdgeInsets.all(veryCompact ? 6 : 8),
          constraints: BoxConstraints(
            minWidth: veryCompact ? 34 : 44,
            minHeight: veryCompact ? 34 : 44,
          ),
          icon: const Icon(Icons.receipt_long_rounded, size: 21),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
                value: ctrl,
                child: const ConnectionAndReceiptsScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionChip(StaffSessionController ctrl, {required bool compact}) {
    late final Color bg;
    late final Color dot;
    late final String label;
    late final bool showSpinner;

    if (ctrl.connectionState == TerminalConnectionState.revoked) {
      bg = AppTheme.accentRed;
      dot = Colors.white;
      label = 'Dicabut';
      showSpinner = false;
    } else if (ctrl.isConnecting) {
      bg = const Color(0xFF0369A1);
      dot = Colors.lightBlueAccent;
      label = 'Connecting';
      showSpinner = true;
    } else if (ctrl.isReconnecting) {
      bg = AppTheme.accentOrange;
      dot = Colors.amberAccent;
      label = compact ? 'Reconn.' : 'Reconnecting';
      showSpinner = true;
    } else if (ctrl.adminReachable || ctrl.wsConnected) {
      bg = AppTheme.success;
      dot = const Color(0xFFBBF7D0);
      label = 'Online';
      showSpinner = false;
    } else {
      bg = AppTheme.accentRed;
      dot = const Color(0xFFFECACA);
      label = 'Offline';
      showSpinner = false;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => ctrl.checkConnectivityAndRestoreSession(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
              )
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(StaffSessionController ctrl) {
    final state = ctrl.connectionState;
    if (!ctrl.adminReachable && !ctrl.wsConnected) {
      final reconn = ctrl.isReconnecting;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: AppTheme.accentRedSoft,
        child: Row(
          children: [
            Icon(
              reconn ? Icons.sync_problem_rounded : Icons.wifi_off_rounded,
              size: 16,
              color: AppTheme.accentRed,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reconn
                    ? 'Menghubungkan ulang... Terputus dari POS Admin. Transaksi baru dikunci.'
                    : 'Terputus dari POS Admin. Katalog cache tetap tersedia; transaksi baru dikunci.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.accentRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: ctrl.isConnecting ? null : () => ctrl.checkConnectivityAndRestoreSession(),
              child: const Text('Sambungkan', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
    if (state == TerminalConnectionState.shiftClosed) {
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider<StaffSessionController>.value(
              value: ctrl,
              child: const StaffShiftScreen(),
            ),
          ),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: const Color(0xFFFEF3C7),
          child: const Row(
            children: [
              Icon(Icons.storefront_rounded, size: 16, color: AppTheme.accentOrange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Shift kasir masih tutup. Ketuk untuk membuka shift sebelum transaksi.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.accentOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.accentOrange),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCatalogColumn({
    required StaffSessionController ctrl,
    required List<String> categories,
    required List<StaffProduct> filteredProducts,
    required bool compactPhone,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.8);

    return Column(
      children: [
        // Search + SKU + Scan Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  decoration: AppTheme.denseInputDecoration(
                    hintText: 'Cari produk, SKU, atau barcode...',
                    prefixIcon: Icons.search_rounded,
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Hapus pencarian',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _handleSearchSubmitBarcode,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _openCameraScanner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: compactPhone ? 12 : 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text('Scan'),
                ),
              ),
            ],
          ),
        ),

        // Horizontal Category Chips
        SizedBox(
          height: 28.0 + 14.0 * textScale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, idx) {
              final cat = categories[idx];
              final selected = _selectedCategory == cat;
              return ChoiceChip(
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
                selected: selected,
                selectedColor: AppTheme.primaryGreen,
                backgroundColor: Colors.white,
                side: BorderSide(color: selected ? AppTheme.primaryGreen : AppTheme.borderLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onSelected: (_) => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // Responsive Product Grid
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          _searchCtrl.text.trim().isNotEmpty
                              ? 'Tidak ada produk cocok untuk "${_searchCtrl.text.trim()}".'
                              : 'Belum ada produk di katalog lokal.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (_searchCtrl.text.trim().isNotEmpty) {
                              _searchCtrl.clear();
                              setState(() => _selectedCategory = 'Semua');
                            } else {
                              ctrl.syncCatalogFull();
                            }
                          },
                          icon: Icon(
                            _searchCtrl.text.trim().isNotEmpty ? Icons.clear_all_rounded : Icons.sync_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _searchCtrl.text.trim().isNotEmpty ? 'Reset Filter' : 'Sinkronkan Katalog',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = AppBreakpoints.productGridCount(constraints.maxWidth);
                    final cardExtent = 74.0 + (compactPhone ? 94.0 : 98.0) * textScale;

                    return RefreshIndicator(
                      onRefresh: () => ctrl.syncCatalogIncremental(),
                      child: GridView.builder(
                        controller: _gridScrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: cardExtent,
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (_, idx) => _buildProductCard(ctrl, filteredProducts[idx]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard(StaffSessionController ctrl, StaffProduct prod) {
    final totalDisplayQty = ctrl.getProductCartDisplayQty(prod.id);
    final baseUnitQty = ctrl.getUnitCartQty(prod.id, prod.baseUnit);
    final hasMultiUnit = prod.units.isNotEmpty;
    final lineCount = ctrl.getProductCartLineCount(prod.id);
    final isInCart = totalDisplayQty > 0.0001;
    final lowStock = prod.managesStock && !prod.isOutOfStock && prod.stock <= prod.minStockAlert;

    // Resolve single-line unit if a multi-unit product currently has exactly 1 line in cart
    StaffProductUnit? singleSelectedUnit;
    double singleSelectedQty = baseUnitQty;
    String singleUnitLabel = prod.baseUnit;
    if (hasMultiUnit && lineCount == 1) {
      final line = ctrl.cartItems.where((i) => i.productId == prod.id).first;
      singleUnitLabel = line.unitName;
      singleSelectedQty = line.qty;
      singleSelectedUnit = prod.units.where((u) => u.unitName == line.unitName).firstOrNull;
    }

    // Status badge styling
    late final String stockText;
    late final Color stockColor;
    if (prod.isService) {
      stockText = 'JASA';
      stockColor = AppTheme.accentBlue;
    } else if (!prod.trackStock) {
      stockText = 'NON-STOK';
      stockColor = AppTheme.textMuted;
    } else if (prod.isOutOfStock) {
      stockText = 'Habis';
      stockColor = AppTheme.accentRed;
    } else {
      stockText = 'Stok ${CurrencyHelper.formatNumber(prod.stock)}';
      stockColor = lowStock ? AppTheme.accentOrange : AppTheme.success;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isInCart ? AppTheme.primaryGreen : AppTheme.borderLight,
          width: isInCart ? 1.5 : 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: isInCart
                ? AppTheme.primaryGreen.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: prod.isOutOfStock
              ? null
              : () {
                  if (hasMultiUnit) {
                    _showUnitPicker(prod);
                  } else {
                    _mutateProductWithGuard(
                      prod.id,
                      () => ctrl.addToCart(prod),
                      playBeepOnSuccess: true,
                    );
                  }
                },
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Compact Icon + Qty Badge + Stock Badge
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: prod.isService
                            ? AppTheme.accentBlue.withValues(alpha: 0.1)
                            : AppTheme.primaryGreenSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        prod.isService ? Icons.design_services_rounded : Icons.inventory_2_rounded,
                        size: 16,
                        color: prod.isService ? AppTheme.accentBlue : AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: AppTheme.softBadgeDecoration(stockColor),
                          child: Text(
                            stockText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: stockColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Product Name
                Text(
                  prod.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.18,
                    color: prod.isOutOfStock ? AppTheme.textMuted : AppTheme.textDark,
                  ),
                ),
                const Spacer(),

                // Price + Unit / Multi-Unit Tag
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            CurrencyHelper.format(prod.sellingPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: prod.isOutOfStock ? AppTheme.textMuted : AppTheme.primaryGreen,
                            ),
                          ),
                          Text(
                            'per ${prod.baseUnit}${prod.code.isNotEmpty ? ' • ${prod.code}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (hasMultiUnit)
                      InkWell(
                        onTap: prod.isOutOfStock ? null : () => _showUnitPicker(prod),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: AppTheme.softBadgeDecoration(AppTheme.accentIndigo),
                          child: Text(
                            '+${prod.units.length} Sat',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentIndigo,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),

                // Bottom Inline Quantity Stepper
                _buildInlineCardControl(
                  ctrl: ctrl,
                  prod: prod,
                  hasMultiUnit: hasMultiUnit,
                  lineCount: lineCount,
                  totalDisplayQty: totalDisplayQty,
                  activeQty: hasMultiUnit ? singleSelectedQty : baseUnitQty,
                  activeUnit: singleSelectedUnit,
                  activeUnitLabel: singleUnitLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCardControl({
    required StaffSessionController ctrl,
    required StaffProduct prod,
    required bool hasMultiUnit,
    required int lineCount,
    required double totalDisplayQty,
    required double activeQty,
    required StaffProductUnit? activeUnit,
    required String activeUnitLabel,
  }) {
    if (prod.isOutOfStock && totalDisplayQty <= 0) {
      return Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: const Text(
          'Stok Habis',
          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (hasMultiUnit && lineCount > 1) {
      return SizedBox(
        height: 32,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showUnitPicker(prod),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: AppTheme.primaryGreenSoft,
            foregroundColor: AppTheme.primaryGreen,
          ),
          icon: const Icon(Icons.layers_rounded, size: 15),
          label: Text(
            '${CurrencyHelper.formatNumber(totalDisplayQty)} ${prod.baseUnit} • Ubah',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    if (activeQty <= 0.0001) {
      return SizedBox(
        height: 32,
        width: double.infinity,
        child: Material(
          color: AppTheme.primaryGreenSoft,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey('add_btn_${prod.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (hasMultiUnit) {
                _showUnitPicker(prod);
              } else {
                _mutateProductWithGuard(
                  prod.id,
                  () => ctrl.addToCart(prod),
                  playBeepOnSuccess: true,
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 15, color: AppTheme.primaryGreen),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      hasMultiUnit ? 'Satuan' : 'Tambah',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Active inline stepper: [ - ]  qty  [ + ]
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          InkWell(
            key: ValueKey('dec_btn_${prod.id}'),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
            onTap: () => _mutateProductWithGuard(
              prod.id,
              () => ctrl.decrementProductQty(prod, unit: activeUnit, qtyDelta: 1.0),
            ),
            child: const SizedBox(
              width: 34,
              height: 32,
              child: Icon(Icons.remove_rounded, size: 17, color: AppTheme.primaryGreen),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _showQuickQtyInputDialog(ctrl, prod, activeUnit),
              child: Center(
                child: Text(
                  hasMultiUnit
                      ? '${CurrencyHelper.formatNumber(activeQty)} $activeUnitLabel'
                      : CurrencyHelper.formatNumber(activeQty),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryGreenDark,
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            key: ValueKey('inc_btn_${prod.id}'),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
            onTap: () => _mutateProductWithGuard(
              prod.id,
              () => ctrl.addToCart(prod, unit: activeUnit, qtyDelta: 1.0),
              playBeepOnSuccess: true,
            ),
            child: Container(
              width: 34,
              height: 32,
              decoration: const BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.horizontal(right: Radius.circular(7)),
              ),
              child: const Icon(Icons.add_rounded, size: 17, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomCartBar(
    StaffSessionController ctrl, {
    required bool keyboardOpen,
    required bool compactPhone,
  }) {
    final itemCount = ctrl.cartItems.length;
    final totalUnits = CurrencyHelper.formatNumber(ctrl.totalCartItemsQty);
    final isLocked = !ctrl.canSubmitCheckout && itemCount > 0;

    // Keep bar super compact while software keyboard is open so catalog search grid remains unobstructed
    return Material(
      elevation: 0,
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppTheme.borderLight, width: 1.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(12, keyboardOpen ? 6 : 9, 12, keyboardOpen ? 6 : 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openCartSheet(ctrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: EdgeInsets.all(keyboardOpen ? 7 : 9),
                              decoration: BoxDecoration(
                                color: itemCount > 0 ? AppTheme.primaryGreenSoft : AppTheme.lightGreyBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.shopping_cart_rounded,
                                size: keyboardOpen ? 18 : 21,
                                color: itemCount > 0 ? AppTheme.primaryGreen : AppTheme.textMuted,
                              ),
                            ),
                            if (itemCount > 0)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentOrange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$itemCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      itemCount > 0
                                          ? '$itemCount baris ($totalUnits qty)'
                                          : 'Keranjang kosong',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ),
                                  const Icon(Icons.keyboard_arrow_up_rounded, size: 15, color: AppTheme.textMuted),
                                ],
                              ),
                              Text(
                                CurrencyHelper.format(ctrl.grandTotal),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: itemCount == 0 ? null : () => _openCheckoutDialog(ctrl),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLocked ? Colors.grey.shade400 : AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: compactPhone ? 13 : 18,
                    vertical: keyboardOpen ? 10 : 12,
                  ),
                ),
                icon: Icon(
                  isLocked ? Icons.lock_rounded : Icons.payment_rounded,
                  size: 18,
                ),
                label: Text(
                  isLocked ? 'Terkunci' : 'Bayar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffCartPane extends StatelessWidget {
  final bool inBottomSheet;
  final ScrollController? scrollController;
  final VoidCallback? onCloseSheet;
  final VoidCallback onCheckoutPressed;
  final void Function(String message, {bool isError}) onMessage;

  const _StaffCartPane({
    required this.inBottomSheet,
    this.scrollController,
    this.onCloseSheet,
    required this.onCheckoutPressed,
    required this.onMessage,
  });

  Future<void> _showCustomerPicker(BuildContext context, StaffSessionController ctrl) async {
    await ctrl.syncCustomers();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pilih Pelanggan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Divider(),
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Pelanggan Umum (Walk-in)'),
                onTap: () async {
                  await ctrl.setCustomer(null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              if (ctrl.customers.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ctrl.customers.length,
                    itemBuilder: (_, idx) {
                      final c = ctrl.customers[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_rounded, color: AppTheme.primaryGreen),
                        title: Text(c.name),
                        subtitle: Text(
                          '${c.phone}${c.creditBalance > 0 ? ' • Kredit ${CurrencyHelper.format(c.creditBalance)}' : ''}',
                        ),
                        trailing: ctrl.customerId == c.id
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen)
                            : null,
                        onTap: () async {
                          await ctrl.setCustomer(c);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPromoPicker(BuildContext context, StaffSessionController ctrl) async {
    final activePromos = ctrl.promos.where((p) => p.isRunning).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Pilih Promo Aktif', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        dense: true,
                        title: const Text('Tanpa Promo'),
                        trailing: ctrl.selectedPromo == null
                            ? const Icon(Icons.check_rounded, color: AppTheme.primaryGreen)
                            : null,
                        onTap: () async {
                          await ctrl.setSelectedPromo(null);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                      if (activePromos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Belum ada promo aktif.', style: TextStyle(color: AppTheme.textMuted)),
                        )
                      else
                        ...activePromos.map(
                          (p) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.local_offer_rounded, color: AppTheme.accentOrange),
                            title: Text(p.name),
                            subtitle: Text(p.promoType),
                            trailing: ctrl.selectedPromo?.id == p.id
                                ? const Icon(Icons.check_rounded, color: AppTheme.primaryGreen)
                                : null,
                            onTap: () async {
                              await ctrl.setSelectedPromo(p);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDiscountDialog(BuildContext context, StaffSessionController ctrl) async {
    final rawVal = await showDialog<String>(
      context: context,
      builder: (_) => _NumberInputDialog(
        title: 'Diskon Manual (Rp)',
        prefixText: 'Rp ',
        hintText: '0',
        initialValue: ctrl.manualDiscount.toStringAsFixed(0),
        allowDecimal: false,
      ),
    );
    if (rawVal != null) {
      await ctrl.setManualDiscount(double.tryParse(rawVal.trim()) ?? 0.0);
    }
  }

  Future<void> _showHeldOrders(BuildContext context, StaffSessionController ctrl) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Pesanan Ditahan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              if (ctrl.heldOrders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada pesanan ditahan.', textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ctrl.heldOrders.length,
                    itemBuilder: (_, idx) {
                      final h = ctrl.heldOrders[idx];
                      return ListTile(
                        leading: const Icon(Icons.pause_circle_outline_rounded),
                        title: Text(h.customerName),
                        subtitle: Text('${h.items.length} baris • ${h.heldAt.split("T").first}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            await ctrl.resumeHeldOrder(h.holdUuid);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Lanjut'),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          if (inBottomSheet)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

          // Cart Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_rounded, size: 19, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keranjang (${ctrl.cartItems.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (ctrl.heldOrders.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showHeldOrders(context, ctrl),
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: Text('Tahan (${ctrl.heldOrders.length})'),
                  ),
                if (ctrl.cartItems.isNotEmpty)
                  IconButton(
                    tooltip: 'Tahan Pesanan',
                    onPressed: () async {
                      await ctrl.holdCurrentCart();
                      onMessage('Pesanan ditahan ke daftar Hold');
                    },
                    icon: const Icon(Icons.pause_circle_outline_rounded, color: AppTheme.accentOrange),
                  ),
                if (ctrl.cartItems.isNotEmpty)
                  IconButton(
                    tooltip: 'Kosongkan Keranjang',
                    onPressed: () => ctrl.clearCart(),
                    icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.accentRed),
                  ),
                if (inBottomSheet && onCloseSheet != null)
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: onCloseSheet,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),

          // Customer + Promo + Discount Quick Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppTheme.surfaceGray,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showCustomerPicker(context, ctrl),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.borderLight),
                    ),
                    icon: const Icon(Icons.person_outline_rounded, size: 16),
                    label: Text(
                      ctrl.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _showPromoPicker(context, ctrl),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    backgroundColor: ctrl.selectedPromo != null ? AppTheme.primaryGreenSoft : Colors.white,
                    side: BorderSide(
                      color: ctrl.selectedPromo != null ? AppTheme.primaryGreen : AppTheme.borderLight,
                    ),
                  ),
                  child: const Text('Promo', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _showDiscountDialog(context, ctrl),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    backgroundColor: ctrl.manualDiscount > 0 ? const Color(0xFFFEF3C7) : Colors.white,
                    side: BorderSide(
                      color: ctrl.manualDiscount > 0 ? AppTheme.accentOrange : AppTheme.borderLight,
                    ),
                  ),
                  child: const Text('Diskon', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          // Cart Line Items List
          Expanded(
            child: ctrl.cartItems.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Belum ada item di keranjang.\nKetuk "+ Tambah" pada produk atau gunakan Scan Barcode.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: ctrl.cartItems.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (_, idx) {
                      final item = ctrl.cartItems[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${CurrencyHelper.format(item.unitPrice)} / ${item.unitName}',
                                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus Item',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => ctrl.updateCartItemQty(idx, 0),
                                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppTheme.accentRed),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppTheme.lightGreyBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderLight),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                      onTap: () => ctrl.updateCartItemQty(idx, item.qty - 1),
                                      child: const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: Icon(Icons.remove_rounded, size: 16),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        CurrencyHelper.formatNumber(item.qty),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: AppTheme.primaryGreenDark,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                      onTap: () async {
                                        final prod = ctrl.products.where((p) => p.id == item.productId).firstOrNull;
                                        if (prod != null) {
                                          final unit = prod.units.where((u) => u.unitName == item.unitName).firstOrNull;
                                          final res = await ctrl.addToCart(prod, unit: unit, qtyDelta: 1);
                                          if (!res.success && res.message != null) {
                                            onMessage(res.message!, isError: true);
                                          }
                                        } else {
                                          await ctrl.updateCartItemQty(idx, item.qty + 1);
                                        }
                                      },
                                      child: const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: Icon(Icons.add_rounded, size: 16, color: AppTheme.primaryGreen),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyHelper.format(item.subtotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Totals Footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppTheme.lightGreyBg,
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _totalRow('Subtotal', CurrencyHelper.format(ctrl.subtotal)),
                  if (ctrl.discountTotal > 0)
                    _totalRow(
                      ctrl.selectedPromo != null ? 'Diskon (${ctrl.selectedPromo!.name})' : 'Diskon',
                      '-${CurrencyHelper.format(ctrl.discountTotal)}',
                      color: Colors.pink,
                    ),
                  if (ctrl.taxAmount > 0)
                    _totalRow(
                      'Pajak (${ctrl.taxRate.toStringAsFixed(0)}%)',
                      CurrencyHelper.format(ctrl.taxAmount),
                    ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            CurrencyHelper.format(ctrl.grandTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: ctrl.canSubmitCheckout ? onCheckoutPressed : null,
                      icon: Icon(
                        ctrl.canSubmitCheckout ? Icons.payment_rounded : Icons.lock_rounded,
                        size: 19,
                      ),
                      label: Text(
                        ctrl.canSubmitCheckout
                            ? 'Proses Pembayaran'
                            : (!ctrl.adminReachable
                                ? 'Checkout Terkunci (Offline)'
                                : (ctrl.currentShift == null ? 'Buka Shift Dahulu' : 'Keranjang Kosong')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String l, String r, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              l,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color ?? AppTheme.textMuted),
            ),
          ),
          Text(
            r,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? AppTheme.textDark),
          ),
        ],
      ),
    );
  }
}

class _NumberInputDialog extends StatefulWidget {
  final String title;
  final String? labelText;
  final String? prefixText;
  final String hintText;
  final String initialValue;
  final bool allowDecimal;

  const _NumberInputDialog({
    required this.title,
    this.labelText,
    this.prefixText,
    required this.hintText,
    required this.initialValue,
    required this.allowDecimal,
  });

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.allowDecimal),
        decoration: InputDecoration(
          labelText: widget.labelText,
          prefixText: widget.prefixText,
          hintText: widget.hintText,
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}
