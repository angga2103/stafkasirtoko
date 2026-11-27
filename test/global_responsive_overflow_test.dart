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
import 'package:stafkasirtoko/ui/screens/connection_and_receipts_screen.dart';
import 'package:stafkasirtoko/ui/screens/pairing_screen.dart';
import 'package:stafkasirtoko/ui/screens/pin_login_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_pos_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_shift_screen.dart';

const bool _exportScreenshots = bool.fromEnvironment('EXPORT_SCREENSHOTS');

class _ViewportCase {
  final String label;
  final Size size;
  final double textScale;
  final double bottomInset;

  const _ViewportCase(
    this.label,
    this.size, {
    this.textScale = 1.0,
    this.bottomInset = 0.0,
  });
}

const List<_ViewportCase> _eightViewportMatrix = [
  _ViewportCase('320x640_s10', Size(320, 640), textScale: 1.0),
  _ViewportCase('360x640_s10', Size(360, 640), textScale: 1.0),
  _ViewportCase('360x800_s10', Size(360, 800), textScale: 1.0),
  _ViewportCase('390x844_s10', Size(390, 844), textScale: 1.0),
  _ViewportCase('412x915_s10', Size(412, 915), textScale: 1.0),
  _ViewportCase('480x960_s10', Size(480, 960), textScale: 1.0),
  _ViewportCase('800x1280_s10', Size(800, 1280), textScale: 1.0),
  _ViewportCase('1280x800_s10', Size(1280, 800), textScale: 1.0),
];

const List<_ViewportCase> _stressMatrix = [
  _ViewportCase('320x640_s12', Size(320, 640), textScale: 1.2),
  _ViewportCase('320x640_s15', Size(320, 640), textScale: 1.5),
  _ViewportCase('360x640_s15', Size(360, 640), textScale: 1.5),
  _ViewportCase('320x640_kb260', Size(320, 640), textScale: 1.2, bottomInset: 260),
  _ViewportCase('360x640_kb260', Size(360, 640), textScale: 1.5, bottomInset: 260),
  _ViewportCase('800x1280_s15', Size(800, 1280), textScale: 1.5),
];

class _MemoryStaffDb implements StaffLocalDb {
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
  Future<List<StaffProduct>> getCachedProducts({String? query, String? category}) async =>
      _products.values.toList();

  @override
  Future<({StaffProduct product, StaffProductUnit? unit})?> findCachedByBarcode(String barcode) async => null;

  @override
  Future<void> replaceCachedPromos(List<StaffPromo> promos) async {
    _promos = List<StaffPromo>.from(promos);
  }

  @override
  Future<List<StaffPromo>> getCachedPromos() async => _promos.where((p) => p.isRunning).toList();

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
  }

  @override
  Future<List<StaffReceipt>> loadCachedRecentReceipts() async => List<StaffReceipt>.from(_receipts);
}

class _OverflowHttpClient extends LanHttpClient {
  bool shiftOpen;
  int? lastOpenedRegisterId;
  final List<StaffProduct> catalog;

  _OverflowHttpClient({
    required super.credentialStore,
    required this.catalog,
    this.shiftOpen = true,
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
        'tiered_prices': const [],
      };

  @override
  Future<Map<String, dynamic>> checkHealth({
    required String baseUrl,
    String? expectedSha256,
    String? expectedShortPin,
  }) async =>
      {
        'server_time_ms': DateTime.now().millisecondsSinceEpoch,
        'store_name': 'KasirToko Supermarket Cabang Utama Lantai 2',
      };

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool requireSession = true,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    final path = Uri.parse('https://localhost$pathAndQuery').path;
    if (path == '/api/v1/security/cert-info') {
      return {
        'success': true,
        'data': {'next_cert_sha256': null, 'rotation_pending': false},
      };
    }
    if (path == '/api/v1/auth/cashiers') {
      return {
        'success': true,
        'data': {
          'cashiers': [
            {
              'id': 3,
              'name': 'Muhammad Abdurrahman Assidiq Counter Utama Lantai 2',
              'username': 'abdurrahman',
              'role': 'cashier',
              'role_label': 'Kasir Senior Shift Pagi Cabang Mall Selatan',
              'permissions': {'access_pos': true, 'open_cash_drawer': true},
            },
            {
              'id': 4,
              'name': 'Siti Nurhaliza Kusumawardhani',
              'username': 'siti',
              'role': 'supervisor',
              'role_label': 'Supervisor Counter Depan',
              'permissions': {'access_pos': true, 'open_cash_drawer': true},
            },
          ],
        },
      };
    }
    if (path == '/api/v1/auth/me' || path == '/api/v1/store/bootstrap') {
      return {
        'success': true,
        'data': {
          'store_name': 'KasirToko Supermarket Cabang Utama Lantai 2',
          'drawer_mode': 'INDIVIDUAL_DRAWER',
          'auto_print_staff_transactions': true,
          'allow_manual_open_drawer': true,
          'cashier': {
            'id': 3,
            'name': 'Muhammad Abdurrahman Assidiq',
            'role': 'cashier',
            'permissions': {'access_pos': true, 'open_cash_drawer': true},
          },
          'current_shift': shiftOpen
              ? {
                  'id': 12,
                  'cashier_id': 3,
                  'cashier_name': 'Muhammad Abdurrahman Assidiq',
                  'terminal_id': 'TERM-COUNTER-UTAMA-01',
                  'cash_register_id': 1,
                  'drawer_mode': 'INDIVIDUAL_DRAWER',
                  'start_time': DateTime.now().toIso8601String(),
                  'starting_cash': 2500000,
                  'status': 'open',
                }
              : null,
        },
      };
    }
    if (path == '/api/v1/cash-registers') {
      return {
        'success': true,
        'data': {
          'authorized_register_id': 1,
          'cash_registers': [
            {
              'id': 1,
              'register_code': 'REG-UTAMA-01',
              'name': 'Laci Kasir Utama Counter Depan Cabang Mall Lantai Dasar',
              'is_shared': false,
              'is_authorized': true,
            },
            {
              'id': 2,
              'register_code': 'REG-EKSPRES-02',
              'name': 'Laci Kasir Layanan Cepat & Grosir Counter Pintu Timur Panjang',
              'is_shared': false,
              'is_authorized': true,
            },
          ],
        },
      };
    }
    if (path == '/api/v1/shifts/current') {
      return {
        'success': true,
        'data': {
          'drawer_mode': 'INDIVIDUAL_DRAWER',
          'shift': shiftOpen
              ? {
                  'id': 12,
                  'cashier_id': 3,
                  'cashier_name': 'Muhammad Abdurrahman Assidiq',
                  'terminal_id': 'TERM-COUNTER-UTAMA-01',
                  'cash_register_id': 1,
                  'drawer_mode': 'INDIVIDUAL_DRAWER',
                  'start_time': DateTime.now().toIso8601String(),
                  'starting_cash': 2500000,
                  'status': 'open',
                }
              : null,
        },
      };
    }
    if (path == '/api/v1/shifts/open' && method == 'POST') {
      lastOpenedRegisterId = (body?['cash_register_id'] as num?)?.toInt();
      shiftOpen = true;
      return {
        'success': true,
        'data': {
          'shift': {
            'id': 13,
            'cashier_id': 3,
            'cashier_name': 'Muhammad Abdurrahman Assidiq',
            'terminal_id': 'TERM-COUNTER-UTAMA-01',
            'cash_register_id': lastOpenedRegisterId ?? 1,
            'drawer_mode': 'INDIVIDUAL_DRAWER',
            'start_time': DateTime.now().toIso8601String(),
            'starting_cash': (body?['starting_cash'] as num?)?.toDouble() ?? 500000,
            'status': 'open',
          },
        },
      };
    }
    if (path == '/api/v1/catalog/products' || path == '/api/v1/catalog/changes') {
      return {
        'success': true,
        'data': {
          'items': catalog.map(_productJson).toList(),
          'has_more': false,
          'sync_version': 9,
        },
      };
    }
    if (path == '/api/v1/promos/active') {
      final now = DateTime.now();
      return {
        'success': true,
        'data': {
          'promos': [
            {
              'id': 1,
              'name': 'Promo Spesial Akhir Pekan Diskon Member VIP Counter Utama',
              'promo_type': 'diskon_persen',
              'min_purchase': 10000,
              'discount_value': 10,
              'start_date': now.subtract(const Duration(days: 1)).toIso8601String(),
              'end_date': now.add(const Duration(days: 5)).toIso8601String(),
              'is_active': true,
            },
          ],
        },
      };
    }
    if (path == '/api/v1/customers') {
      return {
        'success': true,
        'data': {
          'customers': [
            {
              'id': 9,
              'name': 'Ibu Hj. Siti Fatimah Zahra Counter Grosir Cabang Mall',
              'phone': '081234567890',
              'credit_balance': 500000,
            },
          ],
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

class _NoOpWsClient extends LanWsClient {
  _NoOpWsClient({required super.credentialStore, required super.httpClient});

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

List<StaffProduct> _longCatalog() => const [
      StaffProduct(
        id: 1,
        code: 'BRG-LONGCODE-001',
        name: 'Kopi Susu Gula Aren Premium Kemasan Botol 1000ml Edisi Khusus',
        category: 'Minuman Dingin',
        barcode: '8991001001',
        baseUnit: 'Botol',
        sellingPrice: 125000,
        stock: 25,
        units: [
          StaffProductUnit(
            id: 11,
            productId: 1,
            unitName: 'Karton Isi 24 Botol Besar',
            conversionFactor: 24,
            sellingPrice: 2800000,
            barcode: '8991001024',
          ),
        ],
      ),
      StaffProduct(
        id: 2,
        code: 'SRV-PANJANG-02',
        name: 'Jasa Packing Kayu & Bubble Wrap Berlapis Counter Ekspedisi',
        category: 'Jasa & Pengemasan',
        barcode: '8991003003',
        isService: true,
        trackStock: false,
        baseUnit: 'Paket',
        sellingPrice: 55000,
        stock: 0,
      ),
    ];

StaffReceipt _longReceipt() => const StaffReceipt(
      id: 99,
      invoiceNumber: 'INV-STAFF-20261127-0099-PANJANG',
      date: '2026-11-27T14:30:00',
      cashierId: 3,
      cashierName: 'Muhammad Abdurrahman Assidiq',
      terminalId: 'TERM-COUNTER-UTAMA-01',
      cashRegisterId: 1,
      shiftId: 12,
      customerName: 'Ibu Hj. Siti Fatimah Zahra Counter Grosir',
      subtotal: 125000000,
      discountTotal: 2500000,
      taxAmount: 13475000,
      promoName: 'Promo VIP Counter',
      grandTotal: 135975000,
      paymentMethod: 'tunai',
      creditUsed: 500000,
      amountPaid: 140000000,
      changeAmount: 4525000,
      qrCodePayload: 'TRX|INV-STAFF-20261127-0099|135975000',
      items: [
        StaffReceiptItem(
          productName: 'Kopi Susu Gula Aren Premium Botol 1000ml Edisi Khusus',
          unitName: 'Karton',
          qty: 50,
          unitPrice: 2500000,
          discount: 0,
          subtotal: 125000000,
        ),
      ],
    );

Future<({ _OverflowHttpClient http, StaffSessionController controller })> _setupController({
  bool shiftOpen = true,
  bool withCart = false,
}) async {
  final db = _MemoryStaffDb();
  final catalog = _longCatalog();
  await db.upsertProducts(catalog, replaceAll: true);
  await db.replaceCachedCustomers(const [
    StaffCustomer(
      id: 9,
      name: 'Ibu Hj. Siti Fatimah Zahra Counter Grosir Cabang Mall',
      phone: '081234567890',
      creditBalance: 500000,
    ),
  ]);
  await db.cacheRecentReceipt(_longReceipt());

  final credStore = InMemoryCredentialStore();
  await credStore.saveCredentials(const StaffCredentials(
    terminalId: 'TERM-COUNTER-UTAMA-01',
    terminalCode: 'TERM-01',
    terminalName: 'Terminal Kasir Utama Lantai Dasar Counter Depan',
    deviceUuid: 'dev-uuid-1',
    deviceToken: 'tok-1',
    deviceSecret: 'sec-1',
    tlsCertSha256: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
    serverUrl: 'https://192.168.43.100:8443',
    sessionToken: 'sess-1',
  ));

  final fakeHttp = _OverflowHttpClient(
    credentialStore: credStore,
    catalog: catalog,
    shiftOpen: shiftOpen,
  );
  final fakeWs = _NoOpWsClient(credentialStore: credStore, httpClient: fakeHttp);
  final ctrl = StaffSessionController(
    credentialStore: credStore,
    localDb: db,
    httpClient: fakeHttp,
    wsClient: fakeWs,
  );
  await ctrl.initialize();
  await ctrl.checkConnectivityAndRestoreSession();
  await ctrl.refreshShiftAndRegisters();
  await ctrl.syncCustomers();
  await ctrl.syncRecentReceiptsFromServer();
  if (withCart) {
    await ctrl.addToCart(catalog[0], qtyDelta: 3);
    await ctrl.addToCart(catalog[1], qtyDelta: 1);
  }
  return (http: fakeHttp, controller: ctrl);
}

Future<void> _pumpAndAssertZeroOverflow(
  WidgetTester tester, {
  required Widget child,
  required _ViewportCase vp,
  StaffSessionController? controller,
  ThemeData? themeOverride,
  GlobalKey? boundaryKey,
}) async {
  final recordedErrors = <FlutterErrorDetails>[];
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    recordedErrors.add(details);
  };

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = vp.size;
  tester.view.viewInsets = FakeViewPadding(bottom: vp.bottomInset);

  try {
    Widget body = MediaQuery(
      data: MediaQueryData(
        size: vp.size,
        textScaler: TextScaler.linear(vp.textScale),
        viewInsets: EdgeInsets.only(bottom: vp.bottomInset),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themeOverride ?? AppTheme.lightTheme,
        home: controller == null
            ? child
            : ChangeNotifierProvider<StaffSessionController>.value(
                value: controller,
                child: child,
              ),
      ),
    );
    if (boundaryKey != null) {
      body = RepaintBoundary(key: boundaryKey, child: body);
    }
    await tester.pumpWidget(body);
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'Uncaught exception at ${vp.label}: $exception');

    final overflowErrors = recordedErrors
        .where((e) => e.exceptionAsString().contains('overflowed') || e.exceptionAsString().contains('RenderFlex'))
        .toList();
    expect(
      overflowErrors,
      isEmpty,
      reason: 'Overflow detected at ${vp.label}: ${overflowErrors.map((e) => e.exceptionAsString()).join('\n')}',
    );
  } finally {
    FlutterError.onError = prevOnError;
    tester.view.reset();
  }
}

Future<ThemeData> _loadScreenshotTheme(WidgetTester tester) async {
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
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: ThemeData.light().textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: ThemeData.light().primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    ),
  );
}

void main() {
  group('Global Overflow Matrix — All 8 Viewports + Scales 1.0/1.2/1.5 + Keyboard', () {
    testWidgets('Reported #2 StaffShiftScreen (closed & open) renders zero overflow & selects long register',
        (tester) async {
      final setup = await _setupController(shiftOpen: false);
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      for (final vp in [..._eightViewportMatrix, ..._stressMatrix]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: StaffShiftScreen(key: ValueKey('shift_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }

      // Verify interactive dropdown selection on narrow 320x640 at 1.5x text scale
      await _pumpAndAssertZeroOverflow(
        tester,
        child: const StaffShiftScreen(key: ValueKey('shift_dropdown_pick')),
        vp: const _ViewportCase('320x640_s15_dd', Size(320, 640), textScale: 1.5),
        controller: ctrl,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('REG-EKSPRES-02').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('REG-EKSPRES-02'), findsWidgets);

      // Active shift card on 320x640 + keyboard open + 1.5x textScale
      setup.http.shiftOpen = true;
      await ctrl.refreshShiftAndRegisters();
      for (final vp in [_eightViewportMatrix.first, ..._stressMatrix.take(5)]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: StaffShiftScreen(key: ValueKey('shift_open_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }
    });

    testWidgets('PinLoginScreen renders zero overflow across viewports, 1.5x text scale & switches cashier',
        (tester) async {
      final setup = await _setupController(shiftOpen: false);
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      for (final vp in [..._eightViewportMatrix, ..._stressMatrix]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: PinLoginScreen(key: ValueKey('pin_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }

      // Open dropdown with long cashier name on 320x640 at 1.5x scale
      await _pumpAndAssertZeroOverflow(
        tester,
        child: const PinLoginScreen(key: ValueKey('pin_dd')),
        vp: const _ViewportCase('320x640_s15_pin_dd', Size(320, 640), textScale: 1.5),
        controller: ctrl,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Siti Nurhaliza').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('PairingScreen & ConnectionAndReceiptsScreen render zero overflow across viewports + keyboard',
        (tester) async {
      final setup = await _setupController(shiftOpen: true);
      final ctrl = setup.controller;
      addTearDown(ctrl.dispose);

      for (final vp in [_eightViewportMatrix.first, _eightViewportMatrix[1], ..._stressMatrix]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: PairingScreen(key: ValueKey('pair_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }

      for (final vp in [..._eightViewportMatrix, _stressMatrix[1], _stressMatrix[5]]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: ConnectionAndReceiptsScreen(key: ValueKey('conn_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }
    });

    testWidgets('StaffPosScreen, StaffPaymentDialog & StaffReceiptDialog render zero overflow at all scales',
        (tester) async {
      final setup = await _setupController(shiftOpen: true, withCart: true);
      final ctrl = setup.controller;
      await ctrl.setCustomer(const StaffCustomer(
        id: 9,
        name: 'Ibu Hj. Siti Fatimah Zahra Counter Grosir Cabang Mall',
        phone: '081234567890',
        creditBalance: 500000,
      ));
      addTearDown(ctrl.dispose);

      for (final vp in [..._eightViewportMatrix, _stressMatrix[1], _stressMatrix[3]]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: StaffPosScreen(key: ValueKey('pos_${vp.label}')),
          vp: vp,
          controller: ctrl,
        );
      }

      for (final vp in [
        _eightViewportMatrix[0],
        _eightViewportMatrix[1],
        _eightViewportMatrix[4],
        _eightViewportMatrix[7],
        _stressMatrix[1],
        _stressMatrix[4],
      ]) {
        await _pumpAndAssertZeroOverflow(
          tester,
          child: Scaffold(body: StaffPaymentDialog(key: ValueKey('pay_${vp.label}'))),
          vp: vp,
          controller: ctrl,
        );
        await _pumpAndAssertZeroOverflow(
          tester,
          child: Scaffold(body: StaffReceiptDialog(key: ValueKey('rec_${vp.label}'), receipt: _longReceipt())),
          vp: vp,
          controller: ctrl,
        );
      }
    });

    testWidgets('Export visual overflow verification screenshots for Staff App', (tester) async {
      if (!_exportScreenshots) return;

      final theme = await _loadScreenshotTheme(tester);
      final outDir = Directory('docs/screenshots/overflow_audit');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      Future<void> capture(GlobalKey key, String filename) async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          if (bytes != null) {
            File('${outDir.path}/$filename').writeAsBytesSync(bytes.buffer.asUint8List());
          }
        });
      }

      final setupClosed = await _setupController(shiftOpen: false);
      addTearDown(setupClosed.controller.dispose);
      final k1 = GlobalKey();
      await _pumpAndAssertZeroOverflow(
        tester,
        child: const StaffShiftScreen(),
        vp: const _ViewportCase('shot_shift', Size(320, 640), textScale: 1.5),
        controller: setupClosed.controller,
        themeOverride: theme,
        boundaryKey: k1,
      );
      await capture(k1, 'staff_shift_320x640_fs15.png');

      final k2 = GlobalKey();
      await _pumpAndAssertZeroOverflow(
        tester,
        child: const PinLoginScreen(),
        vp: const _ViewportCase('shot_pin', Size(320, 640), textScale: 1.5),
        controller: setupClosed.controller,
        themeOverride: theme,
        boundaryKey: k2,
      );
      await capture(k2, 'staff_pin_login_320x640_fs15.png');

      final setupPos = await _setupController(shiftOpen: true, withCart: true);
      addTearDown(setupPos.controller.dispose);
      final k3 = GlobalKey();
      await _pumpAndAssertZeroOverflow(
        tester,
        child: const Scaffold(body: StaffPaymentDialog()),
        vp: const _ViewportCase('shot_pay', Size(320, 640), textScale: 1.5),
        controller: setupPos.controller,
        themeOverride: theme,
        boundaryKey: k3,
      );
      await capture(k3, 'staff_payment_dialog_320x640_fs15.png');
    });
  });
}
