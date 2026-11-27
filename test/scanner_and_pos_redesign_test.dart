import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'package:stafkasirtoko/core/network/lan_http_client.dart';
import 'package:stafkasirtoko/core/network/lan_ws_client.dart';
import 'package:stafkasirtoko/core/security/secure_credential_store.dart';
import 'package:stafkasirtoko/core/theme/app_theme.dart';
import 'package:stafkasirtoko/data/local/staff_local_db.dart';
import 'package:stafkasirtoko/data/models/staff_models.dart';
import 'package:stafkasirtoko/providers/staff_session_controller.dart';
import 'package:stafkasirtoko/ui/dialogs/staff_payment_dialog.dart';
import 'package:stafkasirtoko/ui/dialogs/staff_receipt_dialog.dart';
import 'package:stafkasirtoko/ui/screens/pairing_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_barcode_scanner_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_pos_screen.dart';

const bool _exportScreenshots = bool.fromEnvironment('EXPORT_SCREENSHOTS');

class FakeScannerCameraAdapter extends ScannerCameraAdapter {
  ScannerViewState _state;
  final StreamController<List<String>> _stream = StreamController<List<String>>.broadcast();
  bool _disposed = false;

  int startCalls = 0;
  int stopCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  int torchToggleCalls = 0;
  int switchCameraCalls = 0;

  ScannerErrorReason? nextStartErrorReason;
  String? nextStartErrorMessage;

  FakeScannerCameraAdapter({ScannerViewState? initialState})
      : _state = initialState ?? const ScannerViewState();

  @override
  ScannerViewState get viewState => _state;

  @override
  Stream<List<String>> get detectedBarcodes => _stream.stream;

  @override
  bool get isDisposed => _disposed;

  void emitBarcodes(List<String> codes) {
    if (!_disposed && !_stream.isClosed) {
      _stream.add(codes);
    }
  }

  void triggerRuntimeError(ScannerErrorReason reason, String message) {
    _state = _state.copyWith(
      isInitialized: true,
      isRunning: false,
      isStarting: false,
      hasCameraPermission: reason != ScannerErrorReason.permissionDenied,
      errorReason: reason,
      errorMessage: message,
    );
    notifyListeners();
  }

  @override
  Future<void> start() async {
    if (_disposed) return;
    startCalls++;
    if (nextStartErrorReason != null) {
      _state = ScannerViewState(
        isInitialized: true,
        isRunning: false,
        isStarting: false,
        hasCameraPermission: nextStartErrorReason != ScannerErrorReason.permissionDenied,
        errorReason: nextStartErrorReason,
        errorMessage: nextStartErrorMessage ?? 'Simulasi gagal kamera',
      );
      notifyListeners();
      return;
    }
    _state = ScannerViewState(
      isInitialized: true,
      isRunning: true,
      isStarting: false,
      hasCameraPermission: true,
      torchAvailable: true,
      torchEnabled: _state.torchEnabled,
      availableCameras: 2,
    );
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (_disposed) return;
    _state = _state.copyWith(isRunning: false, isStarting: false);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (_disposed) return;
    _state = _state.copyWith(isRunning: false, isStarting: false);
    notifyListeners();
  }

  @override
  Future<void> toggleTorch() async {
    torchToggleCalls++;
    _state = _state.copyWith(torchEnabled: !_state.torchEnabled);
    notifyListeners();
  }

  @override
  Future<void> switchCamera() async {
    switchCameraCalls++;
    notifyListeners();
  }

  @override
  Widget buildPreview({
    required BuildContext context,
    required Widget Function(BuildContext context) placeholderBuilder,
    required Widget Function(BuildContext context, ScannerErrorReason reason, String message) errorBuilder,
  }) {
    if (_state.errorReason != null) {
      return errorBuilder(
        context,
        _state.errorReason!,
        _state.errorMessage ?? 'Error kamera',
      );
    }
    if (!_state.isInitialized) {
      return placeholderBuilder(context);
    }
    return Container(
      key: const ValueKey('fake_camera_preview'),
      color: const Color(0xFF134E4A),
      alignment: Alignment.center,
      child: const Text(
        'CAMERA PREVIEW ACTIVE',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    disposeCalls++;
    if (!_stream.isClosed) {
      await _stream.close();
    }
    super.dispose();
  }
}

/// Fast synchronous-safe in-memory cache DB so FakeAsync widget tests never deadlock sqflite isolates.
class InMemoryStaffLocalDb implements StaffLocalDb {
  Map<String, dynamic>? _profile;
  final Map<int, StaffProduct> _products = {};
  List<StaffPromo> _promos = [];
  List<StaffCustomer> _customers = [];
  ({
    List<StaffCartItem> items,
    int? customerId,
    String customerName,
    String customerPhone,
    int? selectedPromoId,
    double manualDiscount,
    String note,
  })? _cart;
  final List<StaffHeldOrder> _held = [];
  final Map<String, PendingCheckoutIntent> _intents = {};
  final List<StaffReceipt> _receipts = [];

  @override
  Future<Database> get database => throw UnimplementedError();

  @override
  Future<Database> openTestDatabase({String path = '', bool deleteIfExists = true}) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<void> savePairingProfile(Map<String, dynamic> profile) async {
    _profile = Map<String, dynamic>.from(profile);
  }

  @override
  Future<Map<String, dynamic>?> getPairingProfile() async =>
      _profile == null ? null : Map<String, dynamic>.from(_profile!);

  @override
  Future<int> getLastSyncVersion() async => (_profile?['last_sync_version'] as num?)?.toInt() ?? 0;

  @override
  Future<void> setLastSyncVersion(int version) async {
    _profile = {...?_profile, 'last_sync_version': version};
  }

  @override
  Future<void> clearAllLocalData() async {
    _profile = null;
    _products.clear();
    _promos.clear();
    _customers.clear();
    _cart = null;
    _held.clear();
    _intents.clear();
    _receipts.clear();
  }

  @override
  Future<void> upsertProducts(List<StaffProduct> products, {bool replaceAll = false}) async {
    if (replaceAll) _products.clear();
    for (final p in products) {
      _products[p.id] = p;
    }
  }

  @override
  Future<List<StaffProduct>> getCachedProducts({String? query, String? category}) async {
    final list = _products.values.where((p) {
      if (!p.isActive) return false;
      if (category != null && category.isNotEmpty && category != 'Semua' && p.category != category) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.code.toLowerCase().contains(q) ||
            p.barcode.toLowerCase().contains(q);
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<({StaffProduct product, StaffProductUnit? unit})?> findCachedByBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    for (final p in _products.values) {
      if (!p.isActive) continue;
      if (p.barcode == clean || p.code == clean) {
        return (product: p, unit: null);
      }
      for (final u in p.units) {
        if (u.barcode == clean) {
          return (product: p, unit: u);
        }
      }
    }
    return null;
  }

  @override
  Future<void> replaceCachedPromos(List<StaffPromo> promos) async {
    _promos = List<StaffPromo>.from(promos);
  }

  @override
  Future<List<StaffPromo>> getCachedPromos() async =>
      _promos.where((p) => p.isRunning).toList();

  @override
  Future<void> replaceCachedCustomers(List<StaffCustomer> customers) async {
    _customers = List<StaffCustomer>.from(customers);
  }

  @override
  Future<List<StaffCustomer>> getCachedCustomers({String? query}) async =>
      List<StaffCustomer>.from(_customers);

  @override
  Future<void> saveActiveCart({
    required List<StaffCartItem> items,
    int? customerId,
    required String customerName,
    String customerPhone = '',
    int? selectedPromoId,
    double manualDiscount = 0.0,
    String note = '',
  }) async {
    _cart = (
      items: List<StaffCartItem>.from(items),
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      selectedPromoId: selectedPromoId,
      manualDiscount: manualDiscount,
      note: note,
    );
  }

  @override
  Future<({
    List<StaffCartItem> items,
    int? customerId,
    String customerName,
    String customerPhone,
    int? selectedPromoId,
    double manualDiscount,
    String note,
  })?> loadActiveCart() async => _cart;

  @override
  Future<void> saveHeldOrder(StaffHeldOrder order) async {
    _held.removeWhere((h) => h.holdUuid == order.holdUuid);
    _held.insert(0, order);
  }

  @override
  Future<List<StaffHeldOrder>> loadHeldOrders() async => List<StaffHeldOrder>.from(_held);

  @override
  Future<void> deleteHeldOrder(String holdUuid) async {
    _held.removeWhere((h) => h.holdUuid == holdUuid);
  }

  @override
  Future<void> upsertPendingIntent(PendingCheckoutIntent intent) async {
    _intents[intent.idempotencyKey] = intent;
  }

  @override
  Future<List<PendingCheckoutIntent>> getPendingIntents() async => _intents.values.toList();

  @override
  Future<void> deletePendingIntent(String idempotencyKey) async {
    _intents.remove(idempotencyKey);
  }

  @override
  Future<void> cacheRecentReceipt(StaffReceipt receipt) async {
    _receipts.removeWhere((r) => r.id == receipt.id);
    _receipts.insert(0, receipt);
    if (_receipts.length > 30) {
      _receipts.removeRange(30, _receipts.length);
    }
  }

  @override
  Future<List<StaffReceipt>> loadCachedRecentReceipts() async => List<StaffReceipt>.from(_receipts);
}

class FakeLanHttpClient extends LanHttpClient {
  bool online = true;
  final List<StaffProduct> serverCatalog;
  int checkoutPosts = 0;

  FakeLanHttpClient({
    required super.credentialStore,
    required this.serverCatalog,
  });

  Map<String, dynamic> _productJson(StaffProduct p) => {
        'id': p.id,
        'code': p.code,
        'name': p.name,
        'category': p.category,
        'barcode': p.barcode,
        'is_service': p.isService,
        'track_stock': p.trackStock,
        'base_unit': p.baseUnit,
        'selling_price': p.sellingPrice,
        'stock': p.stock,
        'min_stock_alert': p.minStockAlert,
        'is_active': p.isActive,
        'sync_version': p.syncVersion,
        'units': p.units.map((u) => u.toDbMap()).toList(),
        'tiered_prices': p.tieredPrices.map((t) => t.toDbMap()).toList(),
      };

  @override
  Future<Map<String, dynamic>> checkHealth({
    required String baseUrl,
    String? expectedSha256,
    String? expectedShortPin,
  }) async {
    if (!online) throw const LanNetworkException('Simulated offline');
    return {
      'server_time_ms': DateTime.now().millisecondsSinceEpoch,
      'store_name': 'KasirToko Maju',
    };
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool requireSession = true,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    if (!online) throw const LanNetworkException('Simulated offline');
    final path = Uri.parse('https://localhost$pathAndQuery').path;

    if (path == '/api/v1/security/cert-info') {
      return {
        'success': true,
        'data': {'next_cert_sha256': null, 'rotation_pending': false},
      };
    }
    if (path == '/api/v1/auth/me' || path == '/api/v1/store/bootstrap') {
      return {
        'success': true,
        'data': {
          'store_name': 'KasirToko Maju',
          'drawer_mode': 'SHARED_DRAWER',
          'auto_print_staff_transactions': true,
          'cashier': {'id': 3, 'name': 'Rina Kasir', 'role': 'cashier', 'permissions': {'access_pos': true}},
          'current_shift': {
            'id': 7,
            'cashier_id': 3,
            'cashier_name': 'Rina Kasir',
            'terminal_id': 'TERM-01',
            'cash_register_id': 1,
            'drawer_mode': 'SHARED_DRAWER',
            'start_time': DateTime.now().toIso8601String(),
            'starting_cash': 150000,
            'status': 'open',
          },
        },
      };
    }
    if (path == '/api/v1/cash-registers') {
      return {
        'success': true,
        'data': {'authorized_register_id': 1, 'cash_registers': []},
      };
    }
    if (path == '/api/v1/shifts/current') {
      return {
        'success': true,
        'data': {
          'drawer_mode': 'SHARED_DRAWER',
          'shift': {
            'id': 7,
            'cashier_id': 3,
            'cashier_name': 'Rina Kasir',
            'terminal_id': 'TERM-01',
            'cash_register_id': 1,
            'drawer_mode': 'SHARED_DRAWER',
            'start_time': DateTime.now().toIso8601String(),
            'starting_cash': 150000,
            'status': 'open',
          },
        },
      };
    }
    if (path == '/api/v1/catalog/products' || path == '/api/v1/catalog/changes') {
      return {
        'success': true,
        'data': {
          'items': serverCatalog.map(_productJson).toList(),
          'has_more': false,
          'sync_version': 5,
        },
      };
    }
    if (path.startsWith('/api/v1/catalog/barcode/')) {
      final code = Uri.decodeComponent(path.split('/').last);
      for (final p in serverCatalog) {
        if (p.barcode == code || p.code == code) {
          return {
            'success': true,
            'data': {'product': _productJson(p), 'matched_unit': null},
          };
        }
        for (final u in p.units) {
          if (u.barcode == code) {
            return {
              'success': true,
              'data': {'product': _productJson(p), 'matched_unit': u.toDbMap()},
            };
          }
        }
      }
      throw const LanApiException(
        statusCode: 404,
        errorCode: 'NOT_FOUND',
        message: 'Barcode tidak ditemukan',
      );
    }
    if (path == '/api/v1/promos/active') {
      return {
        'success': true,
        'data': {'promos': []},
      };
    }
    if (path == '/api/v1/customers') {
      return {
        'success': true,
        'data': {
          'customers': [
            {'id': 9, 'name': 'Budi Santoso', 'phone': '08123456789', 'credit_balance': 10000},
          ],
        },
      };
    }
    if (path == '/api/v1/transactions' && method == 'POST') {
      checkoutPosts++;
      final paid = (body?['amount_paid'] as num?)?.toDouble() ?? 0.0;
      final total = (body?['expected_grand_total'] as num?)?.toDouble() ?? 0.0;
      return {
        'success': true,
        'data': {
          'transaction': {
            'id': 99,
            'invoice_number': 'INV-STAFF-0099',
            'date': DateTime.now().toIso8601String(),
            'cashier_id': 3,
            'cashier_name': 'Rina Kasir',
            'terminal_id': 'TERM-01',
            'cash_register_id': 1,
            'shift_id': 7,
            'customer_name': body?['customer_name'] ?? 'Pelanggan Umum',
            'subtotal': total,
            'discount_total': 0,
            'tax_amount': 0,
            'promo_name': '',
            'grand_total': total,
            'payment_method': body?['payment_method'] ?? 'tunai',
            'credit_used': body?['credit_used'] ?? 0,
            'amount_paid': paid,
            'change_amount': paid >= total ? paid - total : 0,
            'qr_code_payload': 'TRX|INV-STAFF-0099|${total.toInt()}',
            'items': const [],
          },
          'print_job': {
            'job_uuid': 'pj-0099',
            'status': 'submitted',
            'drawer_pulse_sent': true,
            'error_message': '',
          },
        },
      };
    }
    if (path == '/api/v1/transactions' && method == 'GET') {
      return {
        'success': true,
        'data': {'transactions': []},
      };
    }
    throw const LanApiException(statusCode: 404, errorCode: 'NOT_FOUND', message: 'Not found');
  }
}

class NoOpLanWsClient extends LanWsClient {
  NoOpLanWsClient({
    required super.credentialStore,
    required super.httpClient,
  });

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

class _PopCountingObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

List<StaffProduct> _sampleCatalog() => const [
      StaffProduct(
        id: 1,
        code: 'BRG-001',
        name: 'Kopi Susu Gula Aren',
        category: 'Minuman',
        barcode: '8991001001',
        baseUnit: 'Cup',
        sellingPrice: 18000,
        stock: 2,
        minStockAlert: 3,
      ),
      StaffProduct(
        id: 2,
        code: 'BRG-002',
        name: 'Roti Bakar Coklat Keju',
        category: 'Makanan',
        barcode: '8991002002',
        baseUnit: 'Porsi',
        sellingPrice: 15000,
        stock: 15,
        minStockAlert: 5,
      ),
      StaffProduct(
        id: 3,
        code: 'JASA-001',
        name: 'Jasa Packing Bubble Wrap',
        category: 'Layanan',
        barcode: '8991003003',
        isService: true,
        trackStock: false,
        baseUnit: 'Paket',
        sellingPrice: 5000,
        stock: 0,
      ),
      StaffProduct(
        id: 4,
        code: 'BRG-004',
        name: 'Air Mineral 600ml',
        category: 'Minuman',
        barcode: '8991004004',
        baseUnit: 'Botol',
        sellingPrice: 4000,
        stock: 30,
        units: [
          StaffProductUnit(
            id: 40,
            productId: 4,
            unitName: 'Dus (24 Btl)',
            conversionFactor: 24,
            sellingPrice: 84000,
            barcode: '8991004024',
          ),
        ],
      ),
    ];

Future<({FakeLanHttpClient http, StaffSessionController controller})>
    _createOnlineControllerWithSampleData() async {
  final db = InMemoryStaffLocalDb();
  final catalog = _sampleCatalog();
  await db.upsertProducts(catalog, replaceAll: true);
  await db.replaceCachedCustomers(const [
    StaffCustomer(id: 9, name: 'Budi Santoso', phone: '08123456789', creditBalance: 10000),
  ]);

  final credStore = InMemoryCredentialStore();
  await credStore.saveCredentials(const StaffCredentials(
    terminalId: 'TERM-01',
    terminalCode: 'TERM-01',
    terminalName: 'HP Kasir 1',
    deviceUuid: 'dev-uuid-1',
    deviceToken: 'tok-1',
    deviceSecret: 'sec-1',
    sessionToken: 'sess-1',
    tlsCertSha256: 'abc123',
    serverUrl: 'https://127.0.0.1:8443',
  ));

  final fakeHttp = FakeLanHttpClient(credentialStore: credStore, serverCatalog: catalog);
  final fakeWs = NoOpLanWsClient(credentialStore: credStore, httpClient: fakeHttp);
  final ctrl = StaffSessionController(
    credentialStore: credStore,
    localDb: db,
    httpClient: fakeHttp,
    wsClient: fakeWs,
  );
  await ctrl.initialize();
  await ctrl.checkConnectivityAndRestoreSession();
  return (http: fakeHttp, controller: ctrl);
}

void main() {
  group('BUG 1 Regression — Scanner Lifecycle, Double-Pop & Error Recovery', () {
    testWidgets('1. Open scanner -> back without scan stops camera & keeps StaffPosScreen intact',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter();
      final observer = _PopCountingObserver();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.byType(StaffBarcodeScannerScreen), findsOneWidget);
      expect(fakeAdapter.startCalls, 1);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(observer.popCount, 1);
      expect(find.byType(StaffBarcodeScannerScreen), findsNothing);
      expect(find.byType(StaffPosScreen), findsOneWidget);
      expect(fakeAdapter.stopCalls, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. Burst duplicate frames in 1x mode pop ONCE & never underflow root StaffPosScreen',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      final observer = _PopCountingObserver();
      final fakeAdapter = FakeScannerCameraAdapter();

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1x & Tutup'));
      await tester.pump();

      fakeAdapter.emitBarcodes(['8991002002', '8991002002']);
      fakeAdapter.emitBarcodes(['8991002002']);
      fakeAdapter.emitBarcodes(['8991002002']);
      await tester.pumpAndSettle();

      expect(observer.popCount, 1);
      expect(find.byType(StaffPosScreen), findsOneWidget);
      expect(ctrl.cartItems.length, 1);
      expect(ctrl.cartItems.first.productName, 'Roti Bakar Coklat Keju');
      expect(ctrl.cartItems.first.qty, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Continuous multi-scan: cooldown blocks immediate duplicate, scans different items & closes cleanly',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      fakeAdapter.emitBarcodes(['8991001001']);
      await tester.pump();
      // Duplicate barcode immediately within cooldown -> ignored
      fakeAdapter.emitBarcodes(['8991001001']);
      await tester.pump();
      // Different barcode -> added
      fakeAdapter.emitBarcodes(['8991002002']);
      await tester.pumpAndSettle();

      expect(ctrl.cartItems.length, 2);
      expect(ctrl.cartItems[0].qty, 1);
      expect(ctrl.cartItems[1].qty, 1);
      expect(find.text('Selesai Scan'), findsOneWidget);

      await tester.tap(find.text('Selesai Scan'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPosScreen), findsOneWidget);
      expect(find.textContaining('2 baris'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Rapid close -> reopen scanner 4x sequentially & lifecycle paused -> resumed recovers camera',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      final createdAdapters = <FakeScannerCameraAdapter>[];
      addTearDown(() async {
        ctrl.dispose();
        for (final a in createdAdapters) {
          await a.dispose();
        }
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(
              scannerAdapterFactory: () {
                final a = FakeScannerCameraAdapter();
                createdAdapters.add(a);
                return a;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('Scan'));
        await tester.pumpAndSettle();
        expect(find.byType(StaffBarcodeScannerScreen), findsOneWidget);
        expect(createdAdapters.last.viewState.isRunning, isTrue);

        if (i == 2) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          expect(createdAdapters.last.viewState.isRunning, isFalse);

          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pumpAndSettle();
          expect(createdAdapters.last.viewState.isRunning, isTrue);
        }

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(StaffPosScreen), findsOneWidget);
      }

      expect(createdAdapters.length, 4);
      for (final a in createdAdapters) {
        expect(a.stopCalls, greaterThanOrEqualTo(1));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Permission denied & runtime error render recovery UI (never black) and retry recovers',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter()
        ..nextStartErrorReason = ScannerErrorReason.permissionDenied
        ..nextStartErrorMessage = 'Izin kamera ditolak oleh pengguna.';

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.text('Izin Kamera Diperlukan'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);
      expect(find.text('Input Barcode Manual'), findsOneWidget);
      expect(find.text('Kembali ke Kasir'), findsOneWidget);

      fakeAdapter.nextStartErrorReason = null;
      await tester.tap(find.text('Coba Lagi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake_camera_preview')), findsOneWidget);

      fakeAdapter.triggerRuntimeError(ScannerErrorReason.genericError, 'Kamera terputus.');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kembali ke Kasir'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPosScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Offline barcode lookup falls back to cached DB & PairingScreen QR uses safe scanner',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      setup.http.online = false;
      final ctrl = setup.controller;
      await ctrl.checkConnectivityAndRestoreSession();
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      fakeAdapter.emitBarcodes(['8991004024']);
      await tester.pumpAndSettle();

      expect(ctrl.cartItems.length, 1);
      expect(ctrl.cartItems.first.unitName, 'Dus (24 Btl)');
      expect(ctrl.grandTotal, 84000);

      await tester.tap(find.text('Selesai Scan'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: const PairingScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Scan QR Pairing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MASALAH 2 Regression — Inline Stepper, Stock & Service Guards, Responsive Grid & Payment UI', () {
    testWidgets('7. Inline quantity stepper syncs cart, obeys stock limit, allows Service items, and removes at 0',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: const StaffPosScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Online'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add_btn_1')));
      await tester.pumpAndSettle();
      expect(ctrl.cartItems.length, 1);
      expect(ctrl.getProductCartDisplayQty(1), 1);

      await tester.tap(find.byKey(const ValueKey('inc_btn_1')));
      await tester.pumpAndSettle();
      expect(ctrl.getProductCartDisplayQty(1), 2);
      expect(ctrl.grandTotal, 36000);

      // Stock limit enforced at stock=2
      await tester.tap(find.byKey(const ValueKey('inc_btn_1')));
      await tester.pumpAndSettle();
      expect(ctrl.getProductCartDisplayQty(1), 2);
      expect(find.textContaining('tidak mencukupi'), findsOneWidget);

      // Service item allowed past stock 0
      await tester.ensureVisible(find.byKey(const ValueKey('add_btn_3')));
      await tester.tap(find.byKey(const ValueKey('add_btn_3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inc_btn_3')));
      await tester.pumpAndSettle();
      expect(ctrl.getProductCartDisplayQty(3), 2);
      expect(ctrl.grandTotal, 36000 + 10000);

      // Decrement back to 0 removes item cleanly
      ScaffoldMessenger.of(tester.element(find.byType(StaffPosScreen))).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('dec_btn_1')));
      await tester.tap(find.byKey(const ValueKey('dec_btn_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dec_btn_1')));
      await tester.pumpAndSettle();
      expect(ctrl.getProductCartDisplayQty(1), 0);
      expect(find.byKey(const ValueKey('add_btn_1')), findsOneWidget);
      expect(ctrl.grandTotal, 10000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Keyboard open on 360x640, Payment Dialog & Receipt flow complete without overflow',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      await ctrl.addToCart(_sampleCatalog()[1], qtyDelta: 2); // 30.000
      addTearDown(ctrl.dispose);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: const StaffPosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPaymentDialog), findsOneWidget);

      expect(find.text('Tunai'), findsOneWidget);
      expect(find.text('QRIS'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Kasbon'), findsOneWidget);

      // Test quick cash selection + open software keyboard without overflow
      await tester.ensureVisible(find.text('Rp 50.000'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rp 50.000'));
      await tester.pumpAndSettle();
      expect(ctrl.amountPaid, 50000);
      expect(ctrl.changeAmount, 20000);

      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(find.text('Sahkan & Bayar'), findsOneWidget);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.text('Sahkan & Bayar'));
      await tester.pumpAndSettle();

      expect(setup.http.checkoutPosts, 1);
      expect(find.byType(StaffReceiptDialog), findsOneWidget);
      expect(ctrl.cartItems, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Multi-unit picker & Tablet 1280x800 dual-pane + cart pane render cleanly',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: const StaffPosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add_btn_4')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dus (24 Btl)'), findsOneWidget);

      await tester.tap(find.textContaining('Dus (24 Btl)'));
      await tester.pumpAndSettle();

      expect(ctrl.cartItems.length, 1);
      expect(ctrl.cartItems.first.unitName, 'Dus (24 Btl)');
      expect(ctrl.grandTotal, 84000);
      expect(find.text('Proses Pembayaran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('10. Search + Category filter + Clear reset & Manual barcode input when camera denied',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter()
        ..nextStartErrorReason = ScannerErrorReason.permissionDenied;

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Category chip filter: Makanan shows Roti Bakar only
      await tester.ensureVisible(find.text('Makanan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Makanan'));
      await tester.pumpAndSettle();
      expect(find.text('Roti Bakar Coklat Keju'), findsOneWidget);
      expect(find.text('Kopi Susu Gula Aren'), findsNothing);

      await tester.ensureVisible(find.text('Semua'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semua'));
      await tester.pumpAndSettle();

      // Search box + clear button
      await tester.enterText(find.byType(TextField).first, 'Packing');
      await tester.pumpAndSettle();
      expect(find.text('Jasa Packing Bubble Wrap'), findsOneWidget);
      expect(find.text('Roti Bakar Coklat Keju'), findsNothing);

      await tester.tap(find.byTooltip('Hapus pencarian'));
      await tester.pumpAndSettle();
      expect(find.text('Roti Bakar Coklat Keju'), findsOneWidget);

      // Open scanner under permission denied -> enter manual barcode fallback
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Input Barcode Manual'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '8991002002');
      await tester.tap(find.text('Proses'));
      await tester.pumpAndSettle();

      expect(ctrl.cartItems.length, 1);
      expect(ctrl.cartItems.first.productName, 'Roti Bakar Coklat Keju');
      await tester.tap(find.text('Kembali ke Kasir'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPosScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11. Mobile Cart BottomSheet syncs grid stepper, customer selection & Kasbon eligibility',
        (tester) async {
      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      await ctrl.addToCart(_sampleCatalog()[1], qtyDelta: 2);
      addTearDown(ctrl.dispose);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ChangeNotifierProvider<StaffSessionController>.value(
            value: ctrl,
            child: const StaffPosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap cart footer summary bar to open Cart BottomSheet
      await tester.tap(find.textContaining('2 qty'));
      await tester.pumpAndSettle();
      expect(find.text('Keranjang (1)'), findsOneWidget);

      // Pick registered customer inside Payment Dialog -> Kasbon becomes usable
      await tester.tap(find.text('Proses Pembayaran'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPaymentDialog), findsOneWidget);

      await tester.tap(find.text('Pelanggan Umum (Walk-in)'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Budi Santoso').last);
      await tester.pumpAndSettle();

      // Credit balance checkbox & Kasbon method now active
      expect(find.text('Gunakan Saldo Kredit Retur'), findsOneWidget);
      await tester.tap(find.text('Kasbon'));
      await tester.pumpAndSettle();
      expect(ctrl.paymentMethod, 'kasbon');
      expect(ctrl.customerId, 9);
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. Visual UI Render Export (Phone POS, Cart Sheet, Payment, Scanner & Tablet)',
        (tester) async {
      if (!_exportScreenshots) return;

      await tester.runAsync(() async {
        final flutterExe = File(Platform.resolvedExecutable);
        final cacheRoot = Directory(
          '${flutterExe.parent.parent.parent.path}${Platform.pathSeparator}material_fonts',
        );
        if (cacheRoot.existsSync()) {
          for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
            final f = File('${cacheRoot.path}${Platform.pathSeparator}$name');
            if (f.existsSync()) {
              await ui.loadFontFromList(f.readAsBytesSync(), fontFamily: 'Roboto');
            }
          }
          final iconsFile = File('${cacheRoot.path}${Platform.pathSeparator}materialicons-regular.otf');
          if (iconsFile.existsSync()) {
            await ui.loadFontFromList(iconsFile.readAsBytesSync(), fontFamily: 'MaterialIcons');
          }
        }
      });

      final outDir = Directory('docs/screenshots');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      Future<void> captureBoundary(GlobalKey key, String filename) async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2.0);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (data != null) {
            File('${outDir.path}/$filename').writeAsBytesSync(data.buffer.asUint8List());
          }
        });
      }

      final setup = await _createOnlineControllerWithSampleData();
      final ctrl = setup.controller;
      await ctrl.addToCart(_sampleCatalog()[0], qtyDelta: 2);
      await ctrl.addToCart(_sampleCatalog()[2], qtyDelta: 1);
      addTearDown(ctrl.dispose);

      final fakeAdapter = FakeScannerCameraAdapter();

      // 1. Phone POS Catalog + Inline Stepper + Bottom Bar
      final rootKey = GlobalKey();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final baseTheme = AppTheme.lightTheme;
      final screenshotTheme = baseTheme.copyWith(
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Roboto'),
        primaryTextTheme: ThemeData.light().primaryTextTheme.apply(fontFamily: 'Roboto'),
        appBarTheme: baseTheme.appBarTheme.copyWith(
          titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: baseTheme.elevatedButtonTheme.style?.copyWith(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: rootKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: screenshotTheme,
            home: ChangeNotifierProvider<StaffSessionController>.value(
              value: ctrl,
              child: StaffPosScreen(scannerAdapterFactory: () => fakeAdapter),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '01_staff_pos_phone_catalog_stepper.png');

      // 2. Cart BottomSheet
      await tester.tap(find.textContaining('3 qty'));
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '02_staff_pos_cart_bottom_sheet.png');

      // 3. Payment Dialog
      await tester.tap(find.text('Proses Pembayaran'));
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '03_staff_payment_dialog_phone.png');

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // 4. Active Continuous Scanner + Scan Result Banner
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      fakeAdapter.emitBarcodes(['8991002002']);
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '04_staff_scanner_active.png');

      // 5. Camera Error Recovery UI (zero black freeze)
      fakeAdapter.triggerRuntimeError(
        ScannerErrorReason.permissionDenied,
        'Izin kamera ditolak. Aktifkan izin kamera pada pengaturan perangkat lalu tekan Coba Lagi.',
      );
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '05_staff_scanner_error_recovery.png');

      await tester.tap(find.text('Kembali ke Kasir'));
      await tester.pumpAndSettle();

      // 6. Tablet Dual-Pane Landscape
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      await captureBoundary(rootKey, '06_staff_pos_tablet_dual_pane.png');
    });
  });
}
