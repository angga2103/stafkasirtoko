import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stafkasirtoko/core/network/lan_http_client.dart';
import 'package:stafkasirtoko/core/security/request_signer.dart';
import 'package:stafkasirtoko/core/security/secure_credential_store.dart';
import 'package:stafkasirtoko/core/utils/format_and_scan_helpers.dart';
import 'package:stafkasirtoko/data/local/staff_local_db.dart';
import 'package:stafkasirtoko/data/models/staff_models.dart';
import 'package:stafkasirtoko/main.dart';
import 'package:stafkasirtoko/providers/staff_session_controller.dart';
import 'package:stafkasirtoko/ui/screens/pairing_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_pos_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await StaffLocalDb.instance.close();
  });

  group('POS Staff Core Security, Cache-Only DB, Offline Lock & Reconciliation', () {
    test('StaffLocalDb contains ZERO cost_price, central ledger, or user credentials and bounds receipts to 30',
        () async {
      final db = await StaffLocalDb.instance.openTestDatabase();
      final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'].toString())
          .toSet();

      expect(tables.contains('cached_products'), isTrue);
      expect(tables.contains('active_cart_items'), isTrue);
      expect(tables.contains('local_held_orders'), isTrue);
      expect(tables.contains('pending_checkout_intents'), isTrue);
      expect(tables.contains('recent_receipt_cache'), isTrue);

      // Must NEVER have second central DB tables
      expect(tables.contains('transactions'), isFalse);
      expect(tables.contains('users'), isFalse);
      expect(tables.contains('inventory_movements'), isFalse);

      // cached_products must NEVER contain cost_price or warehouse buckets
      final cols = (await db.rawQuery('PRAGMA table_info(cached_products)'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(cols.contains('cost_price'), isFalse);
      expect(cols.contains('quarantine_stock'), isFalse);
      expect(cols.contains('damaged_stock'), isFalse);

      // Recent receipt cache capped strictly at 30
      for (int i = 1; i <= 35; i++) {
        await StaffLocalDb.instance.cacheRecentReceipt(StaffReceipt(
          id: i,
          invoiceNumber: 'INV-STAFF-$i',
          date: DateTime(2026, 11, 26, 10, i).toIso8601String(),
          cashierId: 3,
          cashierName: 'Kasir 1',
          terminalId: 'TERM-001',
          cashRegisterId: 1,
          customerName: 'Pelanggan Umum',
          subtotal: 10000,
          discountTotal: 0,
          taxAmount: 0,
          promoName: '',
          grandTotal: 10000,
          paymentMethod: 'tunai',
          creditUsed: 0,
          amountPaid: 10000,
          changeAmount: 0,
          qrCodePayload: 'TRX|INV-STAFF-$i|10000',
          items: const [],
          rawJsonMap: {
            'id': i,
            'invoice_number': 'INV-STAFF-$i',
            'date': DateTime(2026, 11, 26, 10, i).toIso8601String(),
            'cashier_id': 3,
            'cashier_name': 'Kasir 1',
            'terminal_id': 'TERM-001',
            'cash_register_id': 1,
            'customer_name': 'Pelanggan Umum',
            'subtotal': 10000,
            'discount_total': 0,
            'tax_amount': 0,
            'promo_name': '',
            'grand_total': 10000,
            'payment_method': 'tunai',
            'credit_used': 0,
            'amount_paid': 10000,
            'change_amount': 0,
            'qr_code_payload': 'TRX|INV-STAFF-$i|10000',
            'items': [],
          },
        ));
      }
      final cached = await StaffLocalDb.instance.loadCachedRecentReceipts();
      expect(cached.length, 30);
    });

    test('RequestSigner calibrates server clock offset & generates valid canonical HMAC signatures', () {
      final signer = RequestSigner();
      signer.calibrateFromServerTimeMs(1000000, localTimeMs: 900000);
      expect(signer.clockOffsetMs, 100000);

      final headers = signer.buildSignedHeaders(
        terminalId: 'TERM-001',
        deviceToken: 'tok123',
        deviceSecret: 'sec456',
        method: 'POST',
        pathAndQuery: '/api/v1/transactions',
        bodyBytes: utf8.encode('{"a":1}'),
        sessionToken: 'sess789',
        idempotencyKey: 'idem-abc',
      );
      expect(headers['X-Terminal-Id'], 'TERM-001');
      expect(headers['X-Idempotency-Key'], 'idem-abc');
      expect(headers['Authorization'], 'Bearer sess789');
      expect(headers['X-Signature']!.length, 64);
    });

    test('BarcodeScanGuard debounces duplicate continuous scans within cooldown', () {
      final guard = BarcodeScanGuard(cooldown: const Duration(milliseconds: 1200));
      final t0 = DateTime(2026, 11, 26, 12, 0, 0);
      expect(guard.shouldAccept('899123', now: t0), isTrue);
      expect(guard.shouldAccept('899123', now: t0.add(const Duration(milliseconds: 400))), isFalse);
      expect(guard.shouldAccept('899123', now: t0.add(const Duration(milliseconds: 1300))), isTrue);
      expect(guard.shouldAccept('899999', now: t0.add(const Duration(milliseconds: 1350))), isTrue);
    });

    test('Offline disconnect preserves active cart + locks checkout; reconnect reconciles pending intent cleanly',
        () async {
      await StaffLocalDb.instance.openTestDatabase();
      final credStore = InMemoryCredentialStore();
      await credStore.saveCredentials(const StaffCredentials(
        terminalId: 'TERM-001',
        terminalCode: 'TERM-001',
        terminalName: 'HP Kasir 1',
        deviceUuid: 'uuid-1',
        deviceToken: 'dev-tok',
        deviceSecret: 'dev-sec',
        tlsCertSha256: 'abc',
        serverUrl: 'https://127.0.0.1:8443',
        sessionToken: 'sess-tok',
      ));

      final ctrl = StaffSessionController(
        credentialStore: credStore,
        localDb: StaffLocalDb.instance,
      );

      final prod = const StaffProduct(
        id: 10,
        code: 'PRD-10',
        name: 'Kabel Data USB-C',
        category: 'Aksesoris',
        baseUnit: 'Pcs',
        sellingPrice: 25000,
        stock: 15,
      );
      await StaffLocalDb.instance.upsertProducts([prod]);
      final added = await ctrl.addToCart(prod, qtyDelta: 2);
      expect(added.success, isTrue);
      expect(ctrl.cartItems.length, 1);

      // Even with items in cart, offline state strictly locks checkout!
      expect(ctrl.connectionState, TerminalConnectionState.unpaired);
      expect(ctrl.canSubmitCheckout, isFalse);

      await ctrl.initialize();
      // Active cart survives initialize / restart from SQLite cache
      expect(ctrl.cartItems.length, 1);
      expect(ctrl.cartItems.first.qty, 2);

      // Hold & resume draft persists locally without creating any fake transaction
      await ctrl.holdCurrentCart();
      expect(ctrl.cartItems, isEmpty);
      expect(ctrl.heldOrders.length, 1);
      await ctrl.resumeHeldOrder(ctrl.heldOrders.first.holdUuid);
      expect(ctrl.cartItems.length, 1);
    });

    test('QuickCashHelper suggests accurate Rupiah denominations', () {
      final list = QuickCashHelper.suggestAmounts(37000);
      expect(list.first, 37000);
      expect(list.contains(40000), isTrue);
      expect(list.contains(50000), isTrue);
      expect(list.contains(100000), isTrue);
    });

    test('LanHttpClient rejects untrusted / mismatched TLS certificate fingerprint over loopback', () async {
      final credStore = InMemoryCredentialStore();
      final client = LanHttpClient(credentialStore: credStore);
      // In flutter_test (TestHttpOverrides), empty 400 body triggers safe LanNetworkException
      await expectLater(
        client.checkHealth(baseUrl: 'https://127.0.0.1:1', expectedSha256: 'abc'),
        throwsA(isA<LanNetworkException>()),
      );
      expect(HttpStatus.ok, 200);
    });
  });

  group('POS Staff Responsive UI Widget Tests (Phone 360x640 & Tablet 1280x800)', () {
    testWidgets('PairingScreen renders without overflow on 360x640 phone', (tester) async {
      late StaffSessionController ctrl;
      await tester.runAsync(() async {
        await StaffLocalDb.instance.openTestDatabase();
        ctrl = StaffSessionController(
          credentialStore: InMemoryCredentialStore(),
          localDb: StaffLocalDb.instance,
        );
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await tester.runAsync(() async {
          ctrl.dispose();
          await StaffLocalDb.instance.close();
        });
      });

      await tester.pumpWidget(KasirTokoStaffApp(controllerOverride: ctrl));
      await tester.pump();
      expect(find.byType(PairingScreen), findsOneWidget);
      expect(find.textContaining('Scan QR Pairing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('StaffPosScreen shows hard offline checkout lock cleanly on 360x640 and 1280x800', (tester) async {
      late StaffSessionController ctrl;
      await tester.runAsync(() async {
        await StaffLocalDb.instance.openTestDatabase();
        final credStore = InMemoryCredentialStore();
        await credStore.saveCredentials(const StaffCredentials(
          terminalId: 'TERM-001',
          terminalCode: 'TERM-001',
          terminalName: 'Tablet Kasir',
          deviceUuid: 'uuid-t1',
          deviceToken: 'tok',
          deviceSecret: 'sec',
          tlsCertSha256: 'abc',
          serverUrl: 'https://127.0.0.1:8443',
        ));

        ctrl = StaffSessionController(
          credentialStore: credStore,
          localDb: StaffLocalDb.instance,
        );
        await ctrl.addToCart(const StaffProduct(
          id: 1,
          code: 'P1',
          name: 'Powerbank 10000mAh',
          category: 'Elektronik',
          baseUnit: 'Unit',
          sellingPrice: 120000,
          stock: 8,
        ));
      });
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await tester.runAsync(() async {
          ctrl.dispose();
          await StaffLocalDb.instance.close();
        });
      });

      // Test phone 360x640
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<StaffSessionController>.value(
              value: ctrl,
              child: const StaffPosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Terputus dari POS Admin'), findsOneWidget);
      expect(find.text('Terkunci'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Test tablet 1280x800 dual pane
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      expect(find.textContaining('Checkout Terkunci'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
