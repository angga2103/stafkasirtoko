import 'dart:convert';

class StaffProductUnit {
  final int? id;
  final int productId;
  final String unitName;
  final double conversionFactor;
  final double sellingPrice;
  final String barcode;

  const StaffProductUnit({
    this.id,
    required this.productId,
    required this.unitName,
    required this.conversionFactor,
    required this.sellingPrice,
    this.barcode = '',
  });

  factory StaffProductUnit.fromMap(Map<String, dynamic> m) => StaffProductUnit(
        id: (m['id'] as num?)?.toInt(),
        productId: (m['product_id'] as num).toInt(),
        unitName: (m['unit_name'] ?? '').toString(),
        conversionFactor: (m['conversion_factor'] as num?)?.toDouble() ?? 1.0,
        sellingPrice: (m['selling_price'] as num?)?.toDouble() ?? 0.0,
        barcode: (m['barcode'] ?? '').toString(),
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'unit_name': unitName,
        'conversion_factor': conversionFactor,
        'selling_price': sellingPrice,
        'barcode': barcode,
      };
}

class StaffTieredPrice {
  final int? id;
  final int productId;
  final double minQty;
  final double price;

  const StaffTieredPrice({
    this.id,
    required this.productId,
    required this.minQty,
    required this.price,
  });

  factory StaffTieredPrice.fromMap(Map<String, dynamic> m) => StaffTieredPrice(
        id: (m['id'] as num?)?.toInt(),
        productId: (m['product_id'] as num).toInt(),
        minQty: (m['min_qty'] as num?)?.toDouble() ?? 1.0,
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'min_qty': minQty,
        'price': price,
      };
}

/// Public staff catalog model — NEVER includes cost_price or warehouse buckets.
class StaffProduct {
  final int id;
  final String code;
  final String name;
  final String category;
  final String barcode;
  final bool isService;
  final bool trackStock;
  final String baseUnit;
  final double sellingPrice;
  final double stock;
  final double minStockAlert;
  final bool isActive;
  final String updatedAt;
  final int syncVersion;
  final List<StaffProductUnit> units;
  final List<StaffTieredPrice> tieredPrices;

  const StaffProduct({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    this.barcode = '',
    this.isService = false,
    this.trackStock = true,
    this.baseUnit = 'Pcs',
    required this.sellingPrice,
    required this.stock,
    this.minStockAlert = 5.0,
    this.isActive = true,
    this.updatedAt = '',
    this.syncVersion = 1,
    this.units = const [],
    this.tieredPrices = const [],
  });

  bool get managesStock => !isService && trackStock;
  bool get isOutOfStock => managesStock && stock <= 0.0001;

  double getPriceForQty(double qty) {
    if (tieredPrices.isEmpty) return sellingPrice;
    final sorted = List<StaffTieredPrice>.from(tieredPrices)
      ..sort((a, b) => b.minQty.compareTo(a.minQty));
    for (final t in sorted) {
      if (qty >= t.minQty) return t.price;
    }
    return sellingPrice;
  }

  factory StaffProduct.fromApiJson(Map<String, dynamic> m) {
    final pid = (m['id'] as num).toInt();
    final rawUnits = (m['units'] as List<dynamic>?) ?? const [];
    final rawTiers = (m['tiered_prices'] as List<dynamic>?) ?? const [];
    return StaffProduct(
      id: pid,
      code: (m['code'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      category: (m['category'] ?? 'Umum').toString(),
      barcode: (m['barcode'] ?? '').toString(),
      isService: m['is_service'] == true || m['is_service'] == 1,
      trackStock: m['track_stock'] == null || m['track_stock'] == true || m['track_stock'] == 1,
      baseUnit: (m['base_unit'] ?? 'Pcs').toString(),
      sellingPrice: (m['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (m['stock'] as num?)?.toDouble() ?? 0.0,
      minStockAlert: (m['min_stock_alert'] as num?)?.toDouble() ?? 5.0,
      isActive: m['is_active'] == null || m['is_active'] == true || m['is_active'] == 1,
      updatedAt: (m['updated_at'] ?? '').toString(),
      syncVersion: (m['sync_version'] as num?)?.toInt() ?? 1,
      units: rawUnits
          .map((e) => StaffProductUnit.fromMap({...Map<String, dynamic>.from(e as Map), 'product_id': pid}))
          .toList(),
      tieredPrices: rawTiers
          .map((e) => StaffTieredPrice.fromMap({...Map<String, dynamic>.from(e as Map), 'product_id': pid}))
          .toList(),
    );
  }
}

class StaffPromo {
  final int id;
  final String name;
  final String promoType;
  final double minPurchase;
  final double discountValue;
  final int? buyQty;
  final int? getQty;
  final int? targetProductId;
  final String startDate;
  final String endDate;
  final bool isActive;

  const StaffPromo({
    required this.id,
    required this.name,
    required this.promoType,
    this.minPurchase = 0.0,
    this.discountValue = 0.0,
    this.buyQty,
    this.getQty,
    this.targetProductId,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
  });

  bool get isRunning {
    if (!isActive) return false;
    final start = DateTime.tryParse(startDate);
    final end = DateTime.tryParse(endDate);
    if (start == null || end == null) return false;
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end.add(const Duration(days: 1)));
  }

  factory StaffPromo.fromMap(Map<String, dynamic> m) => StaffPromo(
        id: (m['id'] as num).toInt(),
        name: (m['name'] ?? '').toString(),
        promoType: (m['promo_type'] ?? '').toString(),
        minPurchase: (m['min_purchase'] as num?)?.toDouble() ?? 0.0,
        discountValue: (m['discount_value'] as num?)?.toDouble() ?? 0.0,
        buyQty: (m['buy_qty'] as num?)?.toInt(),
        getQty: (m['get_qty'] as num?)?.toInt(),
        targetProductId: (m['target_product_id'] as num?)?.toInt(),
        startDate: (m['start_date'] ?? '').toString(),
        endDate: (m['end_date'] ?? '').toString(),
        isActive: m['is_active'] == true || m['is_active'] == 1,
      );

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'promo_type': promoType,
        'min_purchase': minPurchase,
        'discount_value': discountValue,
        'buy_qty': buyQty,
        'get_qty': getQty,
        'target_product_id': targetProductId,
        'start_date': startDate,
        'end_date': endDate,
        'is_active': isActive ? 1 : 0,
      };
}

class StaffCustomer {
  final int id;
  final String name;
  final String phone;
  final String address;
  final int points;
  final double creditBalance;

  const StaffCustomer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.points = 0,
    this.creditBalance = 0.0,
  });

  bool get isWalkIn => name.trim().toLowerCase() == 'pelanggan umum';

  factory StaffCustomer.fromMap(Map<String, dynamic> m) => StaffCustomer(
        id: (m['id'] as num).toInt(),
        name: (m['name'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        address: (m['address'] ?? '').toString(),
        points: (m['points'] as num?)?.toInt() ?? 0,
        creditBalance: (m['credit_balance'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'points': points,
        'credit_balance': creditBalance,
      };
}

class StaffCashier {
  final int id;
  final String name;
  final String username;
  final String role;
  final String roleLabel;
  final Map<String, bool> permissions;

  const StaffCashier({
    required this.id,
    required this.name,
    this.username = '',
    required this.role,
    this.roleLabel = '',
    this.permissions = const {},
  });

  bool hasPermission(String key) => permissions[key] == true || role == 'owner';

  factory StaffCashier.fromMap(Map<String, dynamic> m) {
    final rawPerms = m['permissions'];
    final parsed = <String, bool>{};
    if (rawPerms is Map) {
      rawPerms.forEach((k, v) => parsed[k.toString()] = v == true);
    }
    return StaffCashier(
      id: (m['id'] as num).toInt(),
      name: (m['name'] ?? '').toString(),
      username: (m['username'] ?? '').toString(),
      role: (m['role'] ?? 'cashier').toString(),
      roleLabel: (m['role_label'] ?? '').toString(),
      permissions: parsed,
    );
  }
}

class StaffShift {
  final int id;
  final int cashierId;
  final String cashierName;
  final String terminalId;
  final int cashRegisterId;
  final String drawerMode;
  final String startTime;
  final double startingCash;
  final String status;

  const StaffShift({
    required this.id,
    required this.cashierId,
    required this.cashierName,
    required this.terminalId,
    required this.cashRegisterId,
    required this.drawerMode,
    required this.startTime,
    required this.startingCash,
    required this.status,
  });

  bool get isOpen => status == 'open';

  factory StaffShift.fromMap(Map<String, dynamic> m) => StaffShift(
        id: (m['id'] as num).toInt(),
        cashierId: (m['cashier_id'] as num).toInt(),
        cashierName: (m['cashier_name'] ?? '').toString(),
        terminalId: (m['terminal_id'] ?? '').toString(),
        cashRegisterId: (m['cash_register_id'] as num?)?.toInt() ?? 1,
        drawerMode: (m['drawer_mode'] ?? 'SHARED_DRAWER').toString(),
        startTime: (m['start_time'] ?? '').toString(),
        startingCash: (m['starting_cash'] as num?)?.toDouble() ?? 0.0,
        status: (m['status'] ?? 'closed').toString(),
      );
}

class StaffCashRegister {
  final int id;
  final String registerCode;
  final String name;
  final bool isShared;
  final bool isAuthorized;
  final StaffShift? openShift;

  const StaffCashRegister({
    required this.id,
    required this.registerCode,
    required this.name,
    required this.isShared,
    required this.isAuthorized,
    this.openShift,
  });

  factory StaffCashRegister.fromMap(Map<String, dynamic> m) => StaffCashRegister(
        id: (m['id'] as num).toInt(),
        registerCode: (m['register_code'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        isShared: m['is_shared'] == true || m['is_shared'] == 1,
        isAuthorized: m['is_authorized'] == true,
        openShift: m['open_shift'] is Map
            ? StaffShift.fromMap(Map<String, dynamic>.from(m['open_shift'] as Map))
            : null,
      );
}

class StaffCartItem {
  final int productId;
  final String productCode;
  final String productName;
  final String unitName;
  final double conversionFactor;
  final double qty;
  final double unitPrice;
  final double discount;
  final bool isService;

  const StaffCartItem({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.unitName,
    this.conversionFactor = 1.0,
    required this.qty,
    required this.unitPrice,
    this.discount = 0.0,
    this.isService = false,
  });

  double get baseStockQty => isService ? 0.0 : qty * conversionFactor;
  double get subtotal => ((qty * unitPrice) - discount).clamp(0.0, double.infinity);

  StaffCartItem copyWith({
    double? qty,
    double? unitPrice,
    double? discount,
  }) =>
      StaffCartItem(
        productId: productId,
        productCode: productCode,
        productName: productName,
        unitName: unitName,
        conversionFactor: conversionFactor,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        isService: isService,
      );

  Map<String, dynamic> toCheckoutItemPayload() => {
        'product_id': productId,
        'unit_name': unitName,
        'conversion_factor': conversionFactor,
        'qty': qty,
        'item_discount': discount,
      };
}

class StaffHeldOrder {
  final String holdUuid;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final double manualDiscount;
  final String note;
  final String heldAt;
  final List<StaffCartItem> items;

  const StaffHeldOrder({
    required this.holdUuid,
    this.customerId,
    required this.customerName,
    this.customerPhone = '',
    this.manualDiscount = 0.0,
    this.note = '',
    required this.heldAt,
    required this.items,
  });
}

class StaffReceiptItem {
  final String productName;
  final String unitName;
  final double qty;
  final double unitPrice;
  final double discount;
  final double subtotal;

  const StaffReceiptItem({
    required this.productName,
    required this.unitName,
    required this.qty,
    required this.unitPrice,
    required this.discount,
    required this.subtotal,
  });

  factory StaffReceiptItem.fromMap(Map<String, dynamic> m) => StaffReceiptItem(
        productName: (m['product_name'] ?? '').toString(),
        unitName: (m['unit_name'] ?? 'Pcs').toString(),
        qty: (m['qty'] as num?)?.toDouble() ?? 1.0,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0.0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      );
}

class StaffReceipt {
  final int id;
  final String invoiceNumber;
  final String date;
  final int cashierId;
  final String cashierName;
  final String terminalId;
  final int cashRegisterId;
  final int? shiftId;
  final String customerName;
  final double subtotal;
  final double discountTotal;
  final double taxAmount;
  final String promoName;
  final double grandTotal;
  final String paymentMethod;
  final double creditUsed;
  final double amountPaid;
  final double changeAmount;
  final String qrCodePayload;
  final List<StaffReceiptItem> items;
  final Map<String, dynamic>? rawJsonMap;

  const StaffReceipt({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    required this.cashierId,
    required this.cashierName,
    required this.terminalId,
    required this.cashRegisterId,
    this.shiftId,
    required this.customerName,
    required this.subtotal,
    required this.discountTotal,
    required this.taxAmount,
    required this.promoName,
    required this.grandTotal,
    required this.paymentMethod,
    required this.creditUsed,
    required this.amountPaid,
    required this.changeAmount,
    required this.qrCodePayload,
    required this.items,
    this.rawJsonMap,
  });

  factory StaffReceipt.fromApiJson(Map<String, dynamic> m) {
    final rawItems = (m['items'] as List<dynamic>?) ?? const [];
    return StaffReceipt(
      id: (m['id'] as num?)?.toInt() ?? 0,
      invoiceNumber: (m['invoice_number'] ?? '').toString(),
      date: (m['date'] ?? '').toString(),
      cashierId: (m['cashier_id'] as num?)?.toInt() ?? 0,
      cashierName: (m['cashier_name'] ?? '').toString(),
      terminalId: (m['terminal_id'] ?? '').toString(),
      cashRegisterId: (m['cash_register_id'] as num?)?.toInt() ?? 1,
      shiftId: (m['shift_id'] as num?)?.toInt(),
      customerName: (m['customer_name'] ?? 'Pelanggan Umum').toString(),
      subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountTotal: (m['discount_total'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (m['tax_amount'] as num?)?.toDouble() ?? 0.0,
      promoName: (m['promo_name'] ?? '').toString(),
      grandTotal: (m['grand_total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: (m['payment_method'] ?? 'tunai').toString(),
      creditUsed: (m['credit_used'] as num?)?.toDouble() ?? 0.0,
      amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (m['change_amount'] as num?)?.toDouble() ?? 0.0,
      qrCodePayload: (m['qr_code_payload'] ?? '').toString(),
      items: rawItems
          .map((e) => StaffReceiptItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      rawJsonMap: m,
    );
  }
}

class StaffPrintJob {
  final String jobUuid;
  final String invoiceNumber;
  final String status;
  final bool drawerOpened;
  final bool drawerPulseSent;
  final String errorMessage;

  const StaffPrintJob({
    required this.jobUuid,
    required this.invoiceNumber,
    required this.status,
    required this.drawerOpened,
    required this.drawerPulseSent,
    this.errorMessage = '',
  });

  factory StaffPrintJob.fromMap(Map<String, dynamic> m) => StaffPrintJob(
        jobUuid: (m['job_uuid'] ?? m['job_id'] ?? '').toString(),
        invoiceNumber: (m['invoice_number'] ?? '').toString(),
        status: (m['status'] ?? 'queued').toString(),
        drawerOpened: m['drawer_opened'] == true || m['drawer_opened'] == 1,
        drawerPulseSent: m['drawer_pulse_sent'] == true || m['drawer_pulse_sent'] == 1,
        errorMessage: (m['error_message'] ?? '').toString(),
      );
}

class PendingCheckoutIntent {
  final String idempotencyKey;
  final String requestJson;
  final double expectedGrandTotal;
  final String status; // 'sending' | 'uncertain_reconciling' | 'failed'
  final String createdAt;

  const PendingCheckoutIntent({
    required this.idempotencyKey,
    required this.requestJson,
    required this.expectedGrandTotal,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> get parsedRequest =>
      jsonDecode(requestJson) as Map<String, dynamic>;
}
