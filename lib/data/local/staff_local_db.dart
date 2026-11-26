import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/staff_models.dart';

/// Cache-only terminal database (`staff_terminal.db`).
///
/// Architectural guarantees:
/// - Contains NO central transaction ledger, NO user PINs/passwords, and NO `cost_price`.
/// - Stores ONLY read-only product/promo/customer cache, persistent active cart,
///   local held drafts, in-flight idempotency intents, and <= 30 confirmed receipt previews.
class StaffLocalDb {
  static const int dbVersion = 1;
  static final StaffLocalDb instance = StaffLocalDb._init();

  Database? _db;
  String? _testDbPath;

  StaffLocalDb._init();

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbPath = _testDbPath ?? await _defaultPath();
    _db = await openDatabase(
      dbPath,
      version: dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'staff_terminal.db');
  }

  @visibleForTesting
  Future<Database> openTestDatabase({
    String path = inMemoryDatabasePath,
    bool deleteIfExists = true,
  }) async {
    await close();
    _testDbPath = path;
    if (deleteIfExists && path != inMemoryDatabasePath) {
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      }
    }
    _db = await openDatabase(
      path,
      version: dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _testDbPath = null;
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    if (_testDbPath != inMemoryDatabasePath) {
      try {
        await db.rawQuery('PRAGMA journal_mode = WAL');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pairing_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        server_host TEXT NOT NULL DEFAULT '',
        server_port INTEGER NOT NULL DEFAULT 8443,
        store_name TEXT NOT NULL DEFAULT 'KasirToko',
        store_address TEXT NOT NULL DEFAULT '',
        store_phone TEXT NOT NULL DEFAULT '',
        currency_symbol TEXT NOT NULL DEFAULT 'Rp ',
        drawer_mode TEXT NOT NULL DEFAULT 'SHARED_DRAWER',
        tax_enabled INTEGER NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0.0,
        assigned_register_id INTEGER,
        allow_auto_open_drawer INTEGER NOT NULL DEFAULT 0,
        allow_manual_open_drawer INTEGER NOT NULL DEFAULT 0,
        last_sync_version INTEGER NOT NULL DEFAULT 0,
        last_sync_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_products (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        barcode TEXT NOT NULL DEFAULT '',
        is_service INTEGER NOT NULL DEFAULT 0,
        track_stock INTEGER NOT NULL DEFAULT 1,
        base_unit TEXT NOT NULL,
        selling_price REAL NOT NULL,
        stock REAL NOT NULL DEFAULT 0.0,
        min_stock_alert REAL NOT NULL DEFAULT 0.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL DEFAULT '',
        sync_version INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL,
        selling_price REAL NOT NULL,
        barcode TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (product_id) REFERENCES cached_products (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_tiered_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        min_qty REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES cached_products (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_promos (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        promo_type TEXT NOT NULL,
        min_purchase REAL NOT NULL DEFAULT 0.0,
        discount_value REAL NOT NULL DEFAULT 0.0,
        buy_qty INTEGER,
        get_qty INTEGER,
        target_product_id INTEGER,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_customers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        points INTEGER NOT NULL DEFAULT 0,
        credit_balance REAL NOT NULL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE active_cart (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        customer_id INTEGER,
        customer_name TEXT NOT NULL DEFAULT 'Pelanggan Umum',
        customer_phone TEXT NOT NULL DEFAULT '',
        selected_promo_id INTEGER,
        manual_discount REAL NOT NULL DEFAULT 0.0,
        note TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE active_cart_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        is_service INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE local_held_orders (
        hold_uuid TEXT PRIMARY KEY,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL DEFAULT '',
        manual_discount REAL NOT NULL DEFAULT 0.0,
        note TEXT NOT NULL DEFAULT '',
        held_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE local_held_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hold_uuid TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        product_code TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        is_service INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (hold_uuid) REFERENCES local_held_orders (hold_uuid) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_checkout_intents (
        idempotency_key TEXT PRIMARY KEY,
        request_json TEXT NOT NULL,
        expected_grand_total REAL NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE recent_receipt_cache (
        server_trx_id INTEGER PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        receipt_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_cached_products_barcode ON cached_products (barcode)');
    await db.execute('CREATE INDEX idx_cached_units_barcode ON cached_product_units (barcode)');
  }

  // ==================== PROFILE & SYNC METADATA ====================

  Future<void> savePairingProfile(Map<String, dynamic> profile) async {
    final db = await database;
    await db.insert(
      'pairing_profile',
      {'id': 1, ...profile},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPairingProfile() async {
    final db = await database;
    final rows = await db.query('pairing_profile', where: 'id = 1', limit: 1);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  Future<int> getLastSyncVersion() async {
    final prof = await getPairingProfile();
    return (prof?['last_sync_version'] as num?)?.toInt() ?? 0;
  }

  Future<void> setLastSyncVersion(int version) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pairing_profile SET last_sync_version = ?, last_sync_at = ? WHERE id = 1',
      [version, DateTime.now().toIso8601String()],
    );
  }

  Future<void> clearAllLocalData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recent_receipt_cache');
      await txn.delete('pending_checkout_intents');
      await txn.delete('local_held_orders');
      await txn.delete('active_cart_items');
      await txn.delete('active_cart');
      await txn.delete('cached_customers');
      await txn.delete('cached_promos');
      await txn.delete('cached_products');
      await txn.delete('pairing_profile');
    });
  }

  // ==================== CATALOG & CUSTOMERS CACHE ====================

  Future<void> upsertProducts(List<StaffProduct> products, {bool replaceAll = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('cached_product_units');
        await txn.delete('cached_tiered_prices');
        await txn.delete('cached_products');
      }
      for (final p in products) {
        await txn.insert(
          'cached_products',
          {
            'id': p.id,
            'code': p.code,
            'name': p.name,
            'category': p.category,
            'barcode': p.barcode,
            'is_service': p.isService ? 1 : 0,
            'track_stock': p.trackStock ? 1 : 0,
            'base_unit': p.baseUnit,
            'selling_price': p.sellingPrice,
            'stock': p.stock,
            'min_stock_alert': p.minStockAlert,
            'is_active': p.isActive ? 1 : 0,
            'updated_at': p.updatedAt,
            'sync_version': p.syncVersion,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete('cached_product_units', where: 'product_id = ?', whereArgs: [p.id]);
        await txn.delete('cached_tiered_prices', where: 'product_id = ?', whereArgs: [p.id]);
        for (final u in p.units) {
          await txn.insert('cached_product_units', {
            'product_id': p.id,
            'unit_name': u.unitName,
            'conversion_factor': u.conversionFactor,
            'selling_price': u.sellingPrice,
            'barcode': u.barcode,
          });
        }
        for (final t in p.tieredPrices) {
          await txn.insert('cached_tiered_prices', {
            'product_id': p.id,
            'min_qty': t.minQty,
            'price': t.price,
          });
        }
      }
    });
  }

  Future<List<StaffProduct>> getCachedProducts({String? query, String? category}) async {
    final db = await database;
    var where = 'is_active = 1';
    final args = <dynamic>[];
    if (category != null && category.isNotEmpty && category != 'Semua') {
      where += ' AND category = ?';
      args.add(category);
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      where += ' AND (name LIKE ? OR code LIKE ? OR barcode LIKE ?)';
      args.addAll([q, q, q]);
    }
    final rows = await db.query('cached_products', where: where, whereArgs: args, orderBy: 'name ASC');
    final out = <StaffProduct>[];
    for (final r in rows) {
      final pid = (r['id'] as num).toInt();
      final uRows = await db.query('cached_product_units', where: 'product_id = ?', whereArgs: [pid]);
      final tRows = await db.query('cached_tiered_prices', where: 'product_id = ?', whereArgs: [pid]);
      out.add(StaffProduct(
        id: pid,
        code: (r['code'] ?? '').toString(),
        name: (r['name'] ?? '').toString(),
        category: (r['category'] ?? 'Umum').toString(),
        barcode: (r['barcode'] ?? '').toString(),
        isService: (r['is_service'] ?? 0) == 1,
        trackStock: (r['track_stock'] ?? 1) == 1,
        baseUnit: (r['base_unit'] ?? 'Pcs').toString(),
        sellingPrice: (r['selling_price'] as num).toDouble(),
        stock: (r['stock'] as num).toDouble(),
        minStockAlert: (r['min_stock_alert'] as num?)?.toDouble() ?? 5.0,
        isActive: (r['is_active'] ?? 1) == 1,
        updatedAt: (r['updated_at'] ?? '').toString(),
        syncVersion: (r['sync_version'] as num?)?.toInt() ?? 0,
        units: uRows.map((u) => StaffProductUnit.fromMap(u)).toList(),
        tieredPrices: tRows.map((t) => StaffTieredPrice.fromMap(t)).toList(),
      ));
    }
    return out;
  }

  Future<({StaffProduct product, StaffProductUnit? unit})?> findCachedByBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'cached_products',
      where: '(barcode = ? OR code = ?) AND is_active = 1',
      whereArgs: [clean, clean],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final list = await getCachedProducts();
      final match = list.where((p) => p.id == rows.first['id']).firstOrNull;
      if (match != null) return (product: match, unit: null);
    }
    final unitRows = await db.query(
      'cached_product_units',
      where: 'barcode = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (unitRows.isNotEmpty) {
      final unit = StaffProductUnit.fromMap(unitRows.first);
      final list = await getCachedProducts();
      final match = list.where((p) => p.id == unit.productId).firstOrNull;
      if (match != null) return (product: match, unit: unit);
    }
    return null;
  }

  Future<void> replaceCachedPromos(List<StaffPromo> promos) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('cached_promos');
      for (final p in promos) {
        await txn.insert('cached_promos', p.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<StaffPromo>> getCachedPromos() async {
    final db = await database;
    final rows = await db.query('cached_promos', where: 'is_active = 1');
    return rows.map((e) => StaffPromo.fromMap(e)).where((p) => p.isRunning).toList();
  }

  Future<void> replaceCachedCustomers(List<StaffCustomer> customers) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('cached_customers');
      for (final c in customers) {
        await txn.insert('cached_customers', c.toDbMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<StaffCustomer>> getCachedCustomers({String? query}) async {
    final db = await database;
    final rows = (query == null || query.trim().isEmpty)
        ? await db.query('cached_customers', orderBy: 'name ASC')
        : await db.query(
            'cached_customers',
            where: 'name LIKE ? OR phone LIKE ?',
            whereArgs: ['%${query.trim()}%', '%${query.trim()}%'],
            orderBy: 'name ASC',
          );
    return rows.map((e) => StaffCustomer.fromMap(e)).toList();
  }

  // ==================== PERSISTENT ACTIVE CART & LOCAL HELD ORDERS ====================

  Future<void> saveActiveCart({
    required List<StaffCartItem> items,
    int? customerId,
    required String customerName,
    String customerPhone = '',
    int? selectedPromoId,
    double manualDiscount = 0.0,
    String note = '',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'active_cart',
        {
          'id': 1,
          'customer_id': customerId,
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'selected_promo_id': selectedPromoId,
          'manual_discount': manualDiscount,
          'note': note,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('active_cart_items');
      for (final it in items) {
        await txn.insert('active_cart_items', {
          'product_id': it.productId,
          'product_code': it.productCode,
          'product_name': it.productName,
          'unit_name': it.unitName,
          'conversion_factor': it.conversionFactor,
          'qty': it.qty,
          'unit_price': it.unitPrice,
          'discount': it.discount,
          'is_service': it.isService ? 1 : 0,
        });
      }
    });
  }

  Future<({
    List<StaffCartItem> items,
    int? customerId,
    String customerName,
    String customerPhone,
    int? selectedPromoId,
    double manualDiscount,
    String note,
  })?> loadActiveCart() async {
    final db = await database;
    final head = await db.query('active_cart', where: 'id = 1', limit: 1);
    final rows = await db.query('active_cart_items', orderBy: 'id ASC');
    if (head.isEmpty && rows.isEmpty) return null;
    final h = head.isNotEmpty ? head.first : <String, dynamic>{};
    return (
      items: rows
          .map((r) => StaffCartItem(
                productId: (r['product_id'] as num).toInt(),
                productCode: (r['product_code'] ?? '').toString(),
                productName: (r['product_name'] ?? '').toString(),
                unitName: (r['unit_name'] ?? 'Pcs').toString(),
                conversionFactor: (r['conversion_factor'] as num?)?.toDouble() ?? 1.0,
                qty: (r['qty'] as num).toDouble(),
                unitPrice: (r['unit_price'] as num).toDouble(),
                discount: (r['discount'] as num?)?.toDouble() ?? 0.0,
                isService: (r['is_service'] ?? 0) == 1,
              ))
          .toList(),
      customerId: (h['customer_id'] as num?)?.toInt(),
      customerName: (h['customer_name'] ?? 'Pelanggan Umum').toString(),
      customerPhone: (h['customer_phone'] ?? '').toString(),
      selectedPromoId: (h['selected_promo_id'] as num?)?.toInt(),
      manualDiscount: (h['manual_discount'] as num?)?.toDouble() ?? 0.0,
      note: (h['note'] ?? '').toString(),
    );
  }

  Future<void> saveHeldOrder(StaffHeldOrder order) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'local_held_orders',
        {
          'hold_uuid': order.holdUuid,
          'customer_id': order.customerId,
          'customer_name': order.customerName,
          'customer_phone': order.customerPhone,
          'manual_discount': order.manualDiscount,
          'note': order.note,
          'held_at': order.heldAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('local_held_order_items', where: 'hold_uuid = ?', whereArgs: [order.holdUuid]);
      for (final it in order.items) {
        await txn.insert('local_held_order_items', {
          'hold_uuid': order.holdUuid,
          'product_id': it.productId,
          'product_code': it.productCode,
          'product_name': it.productName,
          'unit_name': it.unitName,
          'conversion_factor': it.conversionFactor,
          'qty': it.qty,
          'unit_price': it.unitPrice,
          'discount': it.discount,
          'is_service': it.isService ? 1 : 0,
        });
      }
    });
  }

  Future<List<StaffHeldOrder>> loadHeldOrders() async {
    final db = await database;
    final heads = await db.query('local_held_orders', orderBy: 'held_at DESC');
    final out = <StaffHeldOrder>[];
    for (final h in heads) {
      final uuid = h['hold_uuid'].toString();
      final itemRows = await db.query('local_held_order_items', where: 'hold_uuid = ?', whereArgs: [uuid]);
      out.add(StaffHeldOrder(
        holdUuid: uuid,
        customerId: (h['customer_id'] as num?)?.toInt(),
        customerName: (h['customer_name'] ?? 'Pelanggan Umum').toString(),
        customerPhone: (h['customer_phone'] ?? '').toString(),
        manualDiscount: (h['manual_discount'] as num?)?.toDouble() ?? 0.0,
        note: (h['note'] ?? '').toString(),
        heldAt: (h['held_at'] ?? '').toString(),
        items: itemRows
            .map((r) => StaffCartItem(
                  productId: (r['product_id'] as num).toInt(),
                  productCode: (r['product_code'] ?? '').toString(),
                  productName: (r['product_name'] ?? '').toString(),
                  unitName: (r['unit_name'] ?? 'Pcs').toString(),
                  conversionFactor: (r['conversion_factor'] as num?)?.toDouble() ?? 1.0,
                  qty: (r['qty'] as num).toDouble(),
                  unitPrice: (r['unit_price'] as num).toDouble(),
                  discount: (r['discount'] as num?)?.toDouble() ?? 0.0,
                  isService: (r['is_service'] ?? 0) == 1,
                ))
            .toList(),
      ));
    }
    return out;
  }

  Future<void> deleteHeldOrder(String holdUuid) async {
    final db = await database;
    await db.delete('local_held_orders', where: 'hold_uuid = ?', whereArgs: [holdUuid]);
  }

  // ==================== IN-FLIGHT IDEMPOTENCY INTENTS ====================

  Future<void> upsertPendingIntent(PendingCheckoutIntent intent) async {
    final db = await database;
    await db.insert(
      'pending_checkout_intents',
      {
        'idempotency_key': intent.idempotencyKey,
        'request_json': intent.requestJson,
        'expected_grand_total': intent.expectedGrandTotal,
        'status': intent.status,
        'created_at': intent.createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingCheckoutIntent>> getPendingIntents() async {
    final db = await database;
    final rows = await db.query('pending_checkout_intents', orderBy: 'created_at ASC');
    return rows
        .map((r) => PendingCheckoutIntent(
              idempotencyKey: r['idempotency_key'].toString(),
              requestJson: r['request_json'].toString(),
              expectedGrandTotal: (r['expected_grand_total'] as num).toDouble(),
              status: r['status'].toString(),
              createdAt: r['created_at'].toString(),
            ))
        .toList();
  }

  Future<void> deletePendingIntent(String idempotencyKey) async {
    final db = await database;
    await db.delete(
      'pending_checkout_intents',
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  // ==================== BOUNDED 30 RECEIPT READ CACHE ====================

  Future<void> cacheRecentReceipt(StaffReceipt receipt) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'recent_receipt_cache',
        {
          'server_trx_id': receipt.id,
          'invoice_number': receipt.invoiceNumber,
          'receipt_json': jsonEncode(receipt.rawJsonMap ?? {'invoice_number': receipt.invoiceNumber}),
          'created_at': receipt.date,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete('''
        DELETE FROM recent_receipt_cache
        WHERE server_trx_id NOT IN (
          SELECT server_trx_id FROM recent_receipt_cache
          ORDER BY created_at DESC
          LIMIT 30
        )
      ''');
    });
  }

  Future<List<StaffReceipt>> loadCachedRecentReceipts() async {
    final db = await database;
    final rows = await db.query('recent_receipt_cache', orderBy: 'created_at DESC', limit: 30);
    return rows
        .map((r) => StaffReceipt.fromApiJson(
            jsonDecode(r['receipt_json'].toString()) as Map<String, dynamic>))
        .toList();
  }
}
