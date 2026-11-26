import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/lan_http_client.dart';
import '../../core/network/lan_ws_client.dart';
import '../../core/security/request_signer.dart';
import '../../core/security/secure_credential_store.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../data/local/staff_local_db.dart';
import '../../data/models/staff_models.dart';

enum TerminalConnectionState {
  unpaired,
  pairedOffline,
  connectedNoSession,
  onlineReady,
  shiftClosed,
  revoked,
}

class StaffSessionController extends ChangeNotifier {
  final SecureCredentialStore _credStore;
  final StaffLocalDb _localDb;
  final LanHttpClient httpClient;
  late final LanWsClient wsClient;
  final Uuid _uuid = const Uuid();

  StaffCredentials? _credentials;
  StaffCashier? _cashier;
  StaffShift? _currentShift;
  StaffCashRegister? _assignedRegister;
  List<StaffCashRegister> _registers = [];

  List<StaffProduct> _products = [];
  List<StaffPromo> _promos = [];
  List<StaffCustomer> _customers = [];
  List<StaffCartItem> _cartItems = [];
  List<StaffHeldOrder> _heldOrders = [];
  List<StaffReceipt> _recentReceipts = [];

  String _storeName = 'KasirToko';
  String _storeAddress = '';
  String _storePhone = '';
  String _drawerMode = 'SHARED_DRAWER';
  bool _taxEnabled = false;
  double _taxRate = 0.0;
  bool _allowAutoOpenDrawer = false;
  bool _allowManualOpenDrawer = false;
  bool _autoPrintStaffTransactions = true;
  int _lastSyncVersion = 0;

  int? _customerId;
  String _customerName = 'Pelanggan Umum';
  String _customerPhone = '';
  StaffPromo? _selectedPromo;
  double _manualDiscount = 0.0;
  String _paymentMethod = 'tunai';
  double _creditUsed = 0.0;
  double _amountPaid = 0.0;

  bool _wsConnected = false;
  bool _adminReachable = false;
  bool _isCheckingOut = false;
  bool _isSyncing = false;
  bool _revokedFlag = false;
  String? _statusMessage;
  String? _lastError;

  StreamSubscription<WsServerEvent>? _wsEventSub;
  StreamSubscription<bool>? _wsStateSub;

  StaffSessionController({
    SecureCredentialStore? credentialStore,
    StaffLocalDb? localDb,
    LanHttpClient? httpClient,
    LanWsClient? wsClient,
  })  : _credStore = credentialStore ?? AndroidKeystoreCredentialStore(),
        _localDb = localDb ?? StaffLocalDb.instance,
        httpClient = httpClient ??
            LanHttpClient(
              credentialStore: credentialStore ?? AndroidKeystoreCredentialStore(),
            ) {
    this.wsClient = wsClient ??
        LanWsClient(
          credentialStore: _credStore,
          httpClient: this.httpClient,
        );
    _attachWsListeners();
  }

  // ==================== GETTERS ====================
  StaffCredentials? get credentials => _credentials;
  StaffCashier? get cashier => _cashier;
  StaffShift? get currentShift => _currentShift;
  StaffCashRegister? get assignedRegister => _assignedRegister;
  List<StaffCashRegister> get registers => _registers;

  List<StaffProduct> get products => _products;
  List<StaffPromo> get promos => _promos;
  List<StaffCustomer> get customers => _customers;
  List<StaffCartItem> get cartItems => _cartItems;
  List<StaffHeldOrder> get heldOrders => _heldOrders;
  List<StaffReceipt> get recentReceipts => _recentReceipts;

  String get storeName => _storeName;
  String get storeAddress => _storeAddress;
  String get storePhone => _storePhone;
  String get drawerMode => _drawerMode;
  bool get taxEnabled => _taxEnabled;
  double get taxRate => _taxRate;
  bool get allowAutoOpenDrawer => _allowAutoOpenDrawer;
  bool get allowManualOpenDrawer => _allowManualOpenDrawer;
  bool get autoPrintStaffTransactions => _autoPrintStaffTransactions;
  int get lastSyncVersion => _lastSyncVersion;

  int? get customerId => _customerId;
  String get customerName => _customerName;
  String get customerPhone => _customerPhone;
  StaffPromo? get selectedPromo => _selectedPromo;
  double get manualDiscount => _manualDiscount;
  String get paymentMethod => _paymentMethod;
  double get creditUsed => _creditUsed;
  double get amountPaid => _amountPaid;

  bool get wsConnected => _wsConnected;
  bool get adminReachable => _adminReachable;
  bool get isCheckingOut => _isCheckingOut;
  bool get isSyncing => _isSyncing;
  String? get statusMessage => _statusMessage;
  String? get lastError => _lastError;

  TerminalConnectionState get connectionState {
    if (_revokedFlag) return TerminalConnectionState.revoked;
    if (_credentials == null || !_credentials!.isPaired) {
      return TerminalConnectionState.unpaired;
    }
    if (!_adminReachable && !_wsConnected) {
      return TerminalConnectionState.pairedOffline;
    }
    if (_cashier == null ||
        _credentials!.sessionToken == null ||
        _credentials!.sessionToken!.isEmpty) {
      return TerminalConnectionState.connectedNoSession;
    }
    if (_currentShift == null || !_currentShift!.isOpen) {
      return TerminalConnectionState.shiftClosed;
    }
    return TerminalConnectionState.onlineReady;
  }

  /// HARD RULE: Checkout is STRICTLY allowed ONLY when Admin is reachable, session is valid,
  /// shift is open, and cart is not empty. Never create local offline finalized transactions!
  bool get canSubmitCheckout =>
      connectionState == TerminalConnectionState.onlineReady &&
      _cartItems.isNotEmpty &&
      !_isCheckingOut;

  double get subtotal => _cartItems.fold(0.0, (s, e) => s + e.subtotal);

  double get promoDiscount {
    final p = _selectedPromo;
    if (p == null || !p.isRunning) return 0.0;
    if (p.promoType == 'diskon_persen') {
      if (subtotal < p.minPurchase) return 0.0;
      return subtotal * (p.discountValue.clamp(0.0, 100.0) / 100.0);
    }
    if (p.promoType == 'potongan_nominal') {
      if (subtotal < p.minPurchase) return 0.0;
      return p.discountValue.clamp(0.0, subtotal);
    }
    if (p.promoType == 'beli_x_gratis_y') {
      final buy = p.buyQty ?? 0;
      final get = p.getQty ?? 0;
      if (buy <= 0 || get <= 0) return 0.0;
      double totalFree = 0.0;
      for (final item in _cartItems) {
        if (p.targetProductId != null && item.productId != p.targetProductId) continue;
        final group = buy + get;
        final sets = item.qty ~/ group;
        if (sets > 0) totalFree += sets * get * item.unitPrice;
      }
      return totalFree;
    }
    return 0.0;
  }

  double get discountTotal => (_manualDiscount + promoDiscount).clamp(0.0, subtotal);
  double get discountedSubtotal => (subtotal - discountTotal).clamp(0.0, subtotal);
  double get taxAmount =>
      (_taxEnabled && _taxRate > 0) ? discountedSubtotal * (_taxRate / 100.0) : 0.0;
  double get grandTotal => discountedSubtotal + taxAmount;
  double get netPayable => (grandTotal - _creditUsed).clamp(0.0, grandTotal);
  double get changeAmount =>
      _paymentMethod == 'tunai' && _amountPaid >= netPayable ? _amountPaid - netPayable : 0.0;

  // ==================== LIFECYCLE & INITIALIZATION ====================

  Future<void> initialize() async {
    _credentials = await _credStore.loadCredentials();
    await _loadLocalState();
    if (_credentials != null && _credentials!.isPaired) {
      await checkConnectivityAndRestoreSession();
    }
    notifyListeners();
  }

  Future<void> _loadLocalState() async {
    final prof = await _localDb.getPairingProfile();
    if (prof != null) {
      _storeName = (prof['store_name'] ?? _storeName).toString();
      _storeAddress = (prof['store_address'] ?? '').toString();
      _storePhone = (prof['store_phone'] ?? '').toString();
      _drawerMode = (prof['drawer_mode'] ?? 'SHARED_DRAWER').toString();
      _taxEnabled = (prof['tax_enabled'] ?? 0) == 1;
      _taxRate = (prof['tax_rate'] as num?)?.toDouble() ?? 0.0;
      _allowAutoOpenDrawer = (prof['allow_auto_open_drawer'] ?? 0) == 1;
      _allowManualOpenDrawer = (prof['allow_manual_open_drawer'] ?? 0) == 1;
      _lastSyncVersion = (prof['last_sync_version'] as num?)?.toInt() ?? 0;
      CurrencyHelper.setCurrencySymbol((prof['currency_symbol'] ?? 'Rp ').toString());
    }

    _products = await _localDb.getCachedProducts();
    _promos = await _localDb.getCachedPromos();
    _customers = await _localDb.getCachedCustomers();
    _heldOrders = await _localDb.loadHeldOrders();
    _recentReceipts = await _localDb.loadCachedRecentReceipts();

    final savedCart = await _localDb.loadActiveCart();
    if (savedCart != null) {
      _cartItems = savedCart.items;
      _customerId = savedCart.customerId;
      _customerName = savedCart.customerName;
      _customerPhone = savedCart.customerPhone;
      _manualDiscount = savedCart.manualDiscount;
      if (savedCart.selectedPromoId != null) {
        _selectedPromo = _promos.where((p) => p.id == savedCart.selectedPromoId).firstOrNull;
      }
    }
  }

  void _attachWsListeners() {
    _wsStateSub = wsClient.connectionStates.listen((connected) {
      _wsConnected = connected;
      if (connected) {
        _adminReachable = true;
      }
      notifyListeners();
    });

    _wsEventSub = wsClient.events.listen((evt) async {
      switch (evt.type) {
        case 'hello':
          _adminReachable = true;
          _wsConnected = true;
          final remoteVer = (evt.data['sync_version'] as num?)?.toInt() ?? 0;
          if (remoteVer > _lastSyncVersion) {
            unawaited(syncCatalogIncremental());
          }
          unawaited(refreshShiftAndRegisters());
          unawaited(reconcilePendingCheckoutIntents());
          break;
        case 'pong':
          _adminReachable = true;
          final remoteVer = (evt.data['sync_version'] as num?)?.toInt() ?? 0;
          if (remoteVer > _lastSyncVersion) {
            unawaited(syncCatalogIncremental());
          }
          break;
        case 'stock_updated':
        case 'catalog_changed':
          unawaited(syncCatalogIncremental());
          break;
        case 'promo_changed':
          unawaited(syncPromos());
          break;
        case 'customer_changed':
          unawaited(syncCustomers());
          break;
        case 'settings_changed':
          unawaited(syncBootstrapAndCert());
          break;
        case 'shift_changed':
          unawaited(refreshShiftAndRegisters());
          break;
        case 'terminal_policy_updated':
          unawaited(syncBootstrapAndCert());
          break;
        case 'session_revoked':
          await _handleLocalSessionClear(
            message: (evt.data['reason'] ?? 'Sesi berakhir. Silakan login ulang.').toString(),
          );
          break;
        case 'terminal_revoked':
          await _handleRevokedByServer();
          break;
        case 'server_stopping':
          _adminReachable = false;
          _wsConnected = false;
          _statusMessage = 'Server POS Admin dimatikan.';
          notifyListeners();
          break;
      }
    });
  }

  // ==================== PAIRING & CONNECTIVITY ====================

  Future<bool> pairUsingQrOrManual({
    required String host,
    required int port,
    required String pairingCode,
    required String deviceName,
    String? fullCertSha256,
    String? shortPin,
  }) async {
    _lastError = null;
    _revokedFlag = false;
    notifyListeners();
    final baseUrl = 'https://${host.trim()}:$port';

    try {
      final health = await httpClient.checkHealth(
        baseUrl: baseUrl,
        expectedSha256: fullCertSha256,
        expectedShortPin: shortPin,
      );
      final deviceUuid = _credentials?.deviceUuid.isNotEmpty == true
          ? _credentials!.deviceUuid
          : _uuid.v4();
      final model = await _credStore.getDeviceModel();

      final data = await httpClient.pairTerminal(
        baseUrl: baseUrl,
        pairingCode: pairingCode,
        deviceName: deviceName,
        deviceModel: model,
        deviceUuid: deviceUuid,
        expectedSha256: fullCertSha256,
        expectedShortPin: shortPin,
      );

      final certSha = (data['cert_sha256'] ?? fullCertSha256 ?? '').toString().toLowerCase();
      final nextCreds = StaffCredentials(
        terminalId: (data['terminal_id'] ?? '').toString(),
        terminalCode: (data['terminal_code'] ?? data['terminal_id'] ?? '').toString(),
        terminalName: (data['terminal_name'] ?? deviceName).toString(),
        deviceUuid: deviceUuid,
        deviceToken: (data['device_token'] ?? '').toString(),
        deviceSecret: (data['device_secret'] ?? '').toString(),
        tlsCertSha256: certSha,
        serverUrl: baseUrl,
      );
      await _credStore.saveCredentials(nextCreds);
      _credentials = nextCreds;
      _adminReachable = true;
      _storeName = (data['store_name'] ?? health['store_name'] ?? _storeName).toString();
      _drawerMode = (data['drawer_mode'] ?? 'SHARED_DRAWER').toString();
      _allowAutoOpenDrawer = data['allow_auto_open_drawer'] == true;
      _allowManualOpenDrawer = data['allow_manual_open_drawer'] == true;

      await _localDb.savePairingProfile({
        'server_host': host.trim(),
        'server_port': port,
        'store_name': _storeName,
        'drawer_mode': _drawerMode,
        'assigned_register_id': data['assigned_cash_register_id'],
        'allow_auto_open_drawer': _allowAutoOpenDrawer ? 1 : 0,
        'allow_manual_open_drawer': _allowManualOpenDrawer ? 1 : 0,
        'last_sync_version': 0,
      });

      notifyListeners();
      return true;
    } catch (e) {
      _lastError = _friendlyError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkConnectivityAndRestoreSession() async {
    if (_credentials == null || !_credentials!.isPaired) return false;
    try {
      await httpClient.checkHealth(
        baseUrl: _credentials!.serverUrl,
        expectedSha256: _credentials!.tlsCertSha256,
      );
      _adminReachable = true;

      // Refresh pinned cert rotation info before issuing device calls
      final certRes = await httpClient.get('/api/v1/security/cert-info', requireSession: false);
      final certData = Map<String, dynamic>.from(certRes['data'] as Map);
      final nextSha = certData['next_cert_sha256']?.toString();
      if (nextSha != null && nextSha.isNotEmpty) {
        _credentials = _credentials!.copyWith(nextCertSha256: nextSha);
        await _credStore.saveCredentials(_credentials!);
      }

      if (_credentials!.sessionToken != null && _credentials!.sessionToken!.isNotEmpty) {
        try {
          final meRes = await httpClient.get('/api/v1/auth/me');
          final meData = Map<String, dynamic>.from(meRes['data'] as Map);
          _cashier = StaffCashier.fromMap(Map<String, dynamic>.from(meData['cashier'] as Map));
          _drawerMode = (meData['drawer_mode'] ?? _drawerMode).toString();
          _currentShift = meData['current_shift'] is Map
              ? StaffShift.fromMap(Map<String, dynamic>.from(meData['current_shift'] as Map))
              : null;
          await _afterSessionAuthenticated();
        } on LanApiException catch (e) {
          if (e.isTerminalRevoked) {
            await _handleRevokedByServer();
            return false;
          }
          if (e.isSessionUnauthorized) {
            await _handleLocalSessionClear(message: e.message);
          }
        }
      }
      notifyListeners();
      return true;
    } on LanApiException catch (e) {
      if (e.isTerminalRevoked) {
        await _handleRevokedByServer();
      }
      return false;
    } catch (_) {
      _adminReachable = false;
      _wsConnected = false;
      notifyListeners();
      return false;
    }
  }

  // ==================== AUTHENTICATION & SHIFT ====================

  Future<List<StaffCashier>> fetchAvailableCashiers() async {
    try {
      final res = await httpClient.get('/api/v1/auth/cashiers', requireSession: false);
      final list = (res['data']['cashiers'] as List<dynamic>?) ?? const [];
      return list
          .map((e) => StaffCashier.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      await _inspectFatalAuthError(e);
      rethrow;
    }
  }

  Future<bool> loginWithPin({
    required int userId,
    required String pin,
  }) async {
    _lastError = null;
    notifyListeners();
    try {
      final res = await httpClient.post(
        '/api/v1/auth/pin-login',
        requireSession: false,
        body: {'user_id': userId, 'pin': pin},
      );
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final sessionToken = (data['session_token'] ?? '').toString();
      final expiresAt = (data['expires_at'] ?? '').toString();
      await _credStore.saveSession(sessionToken, expiresAt);
      _credentials = _credentials!.copyWith(
        sessionToken: sessionToken,
        sessionExpiresAt: expiresAt,
      );
      _cashier = StaffCashier.fromMap(Map<String, dynamic>.from(data['cashier'] as Map));
      _drawerMode = (data['drawer_mode'] ?? _drawerMode).toString();
      _currentShift = data['current_shift'] is Map
          ? StaffShift.fromMap(Map<String, dynamic>.from(data['current_shift'] as Map))
          : null;
      _adminReachable = true;

      await _afterSessionAuthenticated();
      notifyListeners();
      return true;
    } catch (e) {
      await _inspectFatalAuthError(e);
      _lastError = _friendlyError(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> logoutCashier() async {
    try {
      if (_credentials?.sessionToken != null) {
        await httpClient.post('/api/v1/auth/pin-logout', body: {});
      }
    } catch (_) {}
    await _handleLocalSessionClear();
  }

  Future<void> unpairTerminalCleanly() async {
    try {
      if (_credentials != null && _credentials!.isPaired) {
        await httpClient.post('/api/v1/pairing/unpair', body: {}, requireSession: false);
      }
    } catch (_) {}
    await wsClient.disconnect();
    await _credStore.clearAll();
    await _localDb.clearAllLocalData();
    _credentials = null;
    _cashier = null;
    _currentShift = null;
    _products = [];
    _promos = [];
    _customers = [];
    _cartItems = [];
    _heldOrders = [];
    _recentReceipts = [];
    _adminReachable = false;
    _wsConnected = false;
    _revokedFlag = false;
    notifyListeners();
  }

  Future<bool> createCustomerOnAdmin({
    required String name,
    String phone = '',
    String address = '',
  }) async {
    _lastError = null;
    try {
      final res = await httpClient.post('/api/v1/customers', body: {
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
      });
      final created = StaffCustomer.fromMap(
        Map<String, dynamic>.from(res['data']['customer'] as Map),
      );
      await syncCustomers();
      await setCustomer(created);
      return true;
    } catch (e) {
      await _inspectFatalAuthError(e);
      _lastError = _friendlyError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> pairFromQrPayload(String rawQrJson, {required String deviceName}) async {
    try {
      final map = jsonDecode(rawQrJson.trim()) as Map<String, dynamic>;
      final ips = ((map['ips'] as List<dynamic>?) ?? const ['127.0.0.1'])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final port = (map['port'] as num?)?.toInt() ?? 8443;
      final code = (map['pairing_code'] ?? '').toString();
      final certSha = (map['cert_sha256'] ?? '').toString();
      final shortPin = (map['short_pin'] ?? '').toString();
      for (final ip in ips) {
        final ok = await pairUsingQrOrManual(
          host: ip,
          port: port,
          pairingCode: code,
          deviceName: deviceName,
          fullCertSha256: certSha.isNotEmpty ? certSha : null,
          shortPin: shortPin.isNotEmpty ? shortPin : null,
        );
        if (ok) return true;
      }
      return false;
    } catch (e) {
      _lastError = 'Format QR Pairing tidak valid: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _afterSessionAuthenticated() async {
    await syncBootstrapAndCert();
    await syncCatalogFullOrIncremental();
    await syncPromos();
    await syncCustomers();
    await refreshShiftAndRegisters();
    await syncRecentReceiptsFromServer();
    await reconcilePendingCheckoutIntents();
    await wsClient.connect();
  }

  Future<void> syncBootstrapAndCert() async {
    try {
      final res = await httpClient.get('/api/v1/store/bootstrap');
      final d = Map<String, dynamic>.from(res['data'] as Map);
      _storeName = (d['store_name'] ?? _storeName).toString();
      _storeAddress = (d['store_address'] ?? '').toString();
      _storePhone = (d['store_phone'] ?? '').toString();
      _drawerMode = (d['drawer_mode'] ?? _drawerMode).toString();
      _taxEnabled = d['tax_enabled'] == true;
      _taxRate = (d['tax_rate'] as num?)?.toDouble() ?? 0.0;
      _allowAutoOpenDrawer = d['allow_auto_open_drawer'] == true;
      _allowManualOpenDrawer = d['allow_manual_open_drawer'] == true;
      _autoPrintStaffTransactions = d['auto_print_staff_transactions'] != false;
      CurrencyHelper.setCurrencySymbol((d['currency_symbol'] ?? 'Rp ').toString());

      final prof = await _localDb.getPairingProfile() ?? {};
      await _localDb.savePairingProfile({
        ...prof,
        'store_name': _storeName,
        'store_address': _storeAddress,
        'store_phone': _storePhone,
        'drawer_mode': _drawerMode,
        'tax_enabled': _taxEnabled ? 1 : 0,
        'tax_rate': _taxRate,
        'allow_auto_open_drawer': _allowAutoOpenDrawer ? 1 : 0,
        'allow_manual_open_drawer': _allowManualOpenDrawer ? 1 : 0,
      });

      final certRes = await httpClient.get('/api/v1/security/cert-info', requireSession: false);
      final nextSha = certRes['data']['next_cert_sha256']?.toString();
      if (nextSha != null && nextSha.isNotEmpty && _credentials != null) {
        _credentials = _credentials!.copyWith(nextCertSha256: nextSha);
        await _credStore.saveCredentials(_credentials!);
      }
      notifyListeners();
    } catch (e) {
      await _inspectFatalAuthError(e);
    }
  }

  Future<void> syncCatalogFullOrIncremental() async {
    if (_lastSyncVersion <= 0) {
      await syncCatalogFull();
    } else {
      await syncCatalogIncremental();
    }
  }

  Future<void> syncCatalogFull() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    try {
      var page = 1;
      var hasMore = true;
      final collected = <StaffProduct>[];
      var serverSyncVer = 1;

      while (hasMore) {
        final res = await httpClient.get('/api/v1/catalog/products?page=$page&limit=200&since_version=0');
        final data = Map<String, dynamic>.from(res['data'] as Map);
        serverSyncVer = (data['sync_version'] as num?)?.toInt() ?? serverSyncVer;
        final rawItems = (data['items'] as List<dynamic>?) ?? const [];
        for (final item in rawItems) {
          collected.add(StaffProduct.fromApiJson(Map<String, dynamic>.from(item as Map)));
        }
        final pag = Map<String, dynamic>.from(data['pagination'] as Map);
        hasMore = pag['has_more'] == true;
        page++;
      }

      await _localDb.upsertProducts(collected, replaceAll: true);
      _lastSyncVersion = serverSyncVer;
      await _localDb.setLastSyncVersion(serverSyncVer);
      _products = await _localDb.getCachedProducts();
      notifyListeners();
    } catch (e) {
      await _inspectFatalAuthError(e);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncCatalogIncremental() async {
    try {
      var page = 1;
      var hasMore = true;
      final delta = <StaffProduct>[];
      var nextVer = _lastSyncVersion;

      while (hasMore) {
        final res = await httpClient.get(
          '/api/v1/catalog/products?page=$page&limit=200&since_version=$_lastSyncVersion',
        );
        final data = Map<String, dynamic>.from(res['data'] as Map);
        nextVer = (data['sync_version'] as num?)?.toInt() ?? nextVer;
        final rawItems = (data['items'] as List<dynamic>?) ?? const [];
        for (final item in rawItems) {
          delta.add(StaffProduct.fromApiJson(Map<String, dynamic>.from(item as Map)));
        }
        final pag = Map<String, dynamic>.from(data['pagination'] as Map);
        hasMore = pag['has_more'] == true;
        page++;
      }

      if (delta.isNotEmpty) {
        await _localDb.upsertProducts(delta, replaceAll: false);
        _products = await _localDb.getCachedProducts();
      }
      _lastSyncVersion = nextVer;
      await _localDb.setLastSyncVersion(nextVer);
      notifyListeners();
    } catch (e) {
      await _inspectFatalAuthError(e);
    }
  }

  Future<void> syncPromos() async {
    try {
      final res = await httpClient.get('/api/v1/catalog/promos');
      final list = (res['data']['promos'] as List<dynamic>?) ?? const [];
      final promos = list
          .map((e) => StaffPromo.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      await _localDb.replaceCachedPromos(promos);
      _promos = promos.where((p) => p.isRunning).toList();
      if (_selectedPromo != null && !_promos.any((p) => p.id == _selectedPromo!.id)) {
        _selectedPromo = null;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> syncCustomers() async {
    try {
      final res = await httpClient.get('/api/v1/customers?page=1&limit=200');
      final list = (res['data']['customers'] as List<dynamic>?) ?? const [];
      final custs = list
          .map((e) => StaffCustomer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      await _localDb.replaceCachedCustomers(custs);
      _customers = custs;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshShiftAndRegisters() async {
    try {
      final regRes = await httpClient.get('/api/v1/cash-registers');
      final rawRegs = (regRes['data']['cash_registers'] as List<dynamic>?) ?? const [];
      _registers = rawRegs
          .map((e) => StaffCashRegister.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      final authRegId = (regRes['data']['authorized_register_id'] as num?)?.toInt();
      _assignedRegister = authRegId != null
          ? _registers.where((r) => r.id == authRegId).firstOrNull
          : _registers.where((r) => r.isAuthorized).firstOrNull;

      final shRes = await httpClient.get('/api/v1/shifts/current');
      final shData = Map<String, dynamic>.from(shRes['data'] as Map);
      _drawerMode = (shData['drawer_mode'] ?? _drawerMode).toString();
      _currentShift = shData['shift'] is Map
          ? StaffShift.fromMap(Map<String, dynamic>.from(shData['shift'] as Map))
          : null;
      notifyListeners();
    } catch (e) {
      await _inspectFatalAuthError(e);
    }
  }

  Future<bool> openShift({
    required int cashRegisterId,
    required double startingCash,
  }) async {
    _lastError = null;
    notifyListeners();
    try {
      final res = await httpClient.post(
        '/api/v1/shifts/open',
        idempotencyKey: RequestSigner.generateIdempotencyKey(),
        body: {
          'cash_register_id': cashRegisterId,
          'starting_cash': startingCash,
        },
      );
      _currentShift = StaffShift.fromMap(Map<String, dynamic>.from(res['data']['shift'] as Map));
      await refreshShiftAndRegisters();
      notifyListeners();
      return true;
    } catch (e) {
      await _inspectFatalAuthError(e);
      _lastError = _friendlyError(e);
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> closeShift({
    required double actualCash,
    required String note,
  }) async {
    if (_currentShift == null) return null;
    _lastError = null;
    notifyListeners();
    try {
      final res = await httpClient.post(
        '/api/v1/shifts/close',
        body: {
          'shift_id': _currentShift!.id,
          'actual_cash': actualCash,
          'note': note.trim(),
        },
      );
      _currentShift = null;
      await refreshShiftAndRegisters();
      notifyListeners();
      return Map<String, dynamic>.from(res['data'] as Map);
    } catch (e) {
      await _inspectFatalAuthError(e);
      _lastError = _friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  // ==================== BARCODE & CART MUTATIONS ====================

  Future<({StaffProduct product, StaffProductUnit? unit})?> lookupBarcodeLiveOrCache(
    String code,
  ) async {
    final clean = code.trim();
    if (clean.isEmpty) return null;
    if (_adminReachable) {
      try {
        final res = await httpClient.get('/api/v1/catalog/barcode/${Uri.encodeComponent(clean)}');
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final prod = StaffProduct.fromApiJson(Map<String, dynamic>.from(data['product'] as Map));
        final unit = data['matched_unit'] is Map
            ? StaffProductUnit.fromMap(Map<String, dynamic>.from(data['matched_unit'] as Map))
            : null;
        await _localDb.upsertProducts([prod], replaceAll: false);
        _products = await _localDb.getCachedProducts();
        notifyListeners();
        return (product: prod, unit: unit);
      } on LanApiException catch (e) {
        if (e.statusCode == 404) return null;
      } catch (_) {}
    }
    return _localDb.findCachedByBarcode(clean);
  }

  double getCartBaseQtyForProduct(int productId) {
    return _cartItems
        .where((i) => i.productId == productId)
        .fold(0.0, (s, e) => s + e.baseStockQty);
  }

  Future<({bool success, String? message})> addToCart(
    StaffProduct product, {
    StaffProductUnit? unit,
    double qtyDelta = 1.0,
  }) async {
    final unitName = unit?.unitName ?? product.baseUnit;
    final conv = unit?.conversionFactor ?? 1.0;

    if (product.managesStock) {
      final used = getCartBaseQtyForProduct(product.id);
      if (used + (qtyDelta * conv) > product.stock + 0.0001) {
        return (
          success: false,
          message:
              'Stok "${product.name}" tidak mencukupi (tersedia ${CurrencyHelper.formatNumber(product.stock)} ${product.baseUnit}).',
        );
      }
    }

    final idx = _cartItems.indexWhere(
      (i) => i.productId == product.id && i.unitName == unitName,
    );
    if (idx != -1) {
      final cur = _cartItems[idx];
      final nextQty = cur.qty + qtyDelta;
      final nextPrice =
          unit == null && product.tieredPrices.isNotEmpty ? product.getPriceForQty(nextQty) : cur.unitPrice;
      _cartItems[idx] = cur.copyWith(qty: nextQty, unitPrice: nextPrice);
    } else {
      final initPrice = unit != null
          ? unit.sellingPrice
          : (product.tieredPrices.isNotEmpty ? product.getPriceForQty(qtyDelta) : product.sellingPrice);
      _cartItems.add(StaffCartItem(
        productId: product.id,
        productCode: product.code,
        productName: product.name,
        unitName: unitName,
        conversionFactor: conv,
        qty: qtyDelta,
        unitPrice: initPrice,
        isService: product.isService,
      ));
    }

    await _persistCart();
    notifyListeners();
    return (success: true, message: null);
  }

  Future<void> updateCartItemQty(int index, double newQty) async {
    if (index < 0 || index >= _cartItems.length) return;
    if (newQty <= 0) {
      _cartItems.removeAt(index);
    } else {
      final item = _cartItems[index];
      final prod = _products.where((p) => p.id == item.productId).firstOrNull;
      if (prod != null && prod.managesStock) {
        final otherBase = _cartItems
            .asMap()
            .entries
            .where((e) => e.key != index && e.value.productId == prod.id)
            .fold(0.0, (s, e) => s + e.value.baseStockQty);
        if (otherBase + (newQty * item.conversionFactor) > prod.stock + 0.0001) {
          _lastError = 'Stok "${prod.name}" hanya tersedia ${CurrencyHelper.formatNumber(prod.stock)}.';
          notifyListeners();
          return;
        }
      }
      final nextPrice = prod != null && item.unitName == prod.baseUnit && prod.tieredPrices.isNotEmpty
          ? prod.getPriceForQty(newQty)
          : item.unitPrice;
      _cartItems[index] = item.copyWith(qty: newQty, unitPrice: nextPrice);
    }
    await _persistCart();
    notifyListeners();
  }

  Future<void> setManualDiscount(double value) async {
    _manualDiscount = value < 0 ? 0.0 : value;
    await _persistCart();
    notifyListeners();
  }

  Future<void> setSelectedPromo(StaffPromo? promo) async {
    _selectedPromo = promo;
    await _persistCart();
    notifyListeners();
  }

  Future<void> setCustomer(StaffCustomer? customer) async {
    if (customer == null || customer.isWalkIn) {
      _customerId = null;
      _customerName = 'Pelanggan Umum';
      _customerPhone = '';
      if (_paymentMethod == 'kasbon' || _paymentMethod == 'saldo_kredit') {
        _paymentMethod = 'tunai';
      }
      _creditUsed = 0.0;
    } else {
      _customerId = customer.id;
      _customerName = customer.name;
      _customerPhone = customer.phone;
    }
    await _persistCart();
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setCreditUsed(double val) {
    _creditUsed = val.clamp(0.0, grandTotal);
    notifyListeners();
  }

  void setAmountPaid(double val) {
    _amountPaid = val < 0 ? 0.0 : val;
    notifyListeners();
  }

  Future<void> holdCurrentCart() async {
    if (_cartItems.isEmpty) return;
    final hold = StaffHeldOrder(
      holdUuid: _uuid.v4(),
      customerId: _customerId,
      customerName: _customerName,
      customerPhone: _customerPhone,
      manualDiscount: _manualDiscount,
      heldAt: DateTime.now().toIso8601String(),
      items: List<StaffCartItem>.from(_cartItems),
    );
    await _localDb.saveHeldOrder(hold);
    _heldOrders = await _localDb.loadHeldOrders();
    await clearCart();
  }

  Future<void> resumeHeldOrder(String holdUuid) async {
    final target = _heldOrders.where((h) => h.holdUuid == holdUuid).firstOrNull;
    if (target == null) return;
    if (_cartItems.isNotEmpty) {
      await holdCurrentCart();
    }
    _cartItems = List<StaffCartItem>.from(target.items);
    _customerId = target.customerId;
    _customerName = target.customerName;
    _customerPhone = target.customerPhone;
    _manualDiscount = target.manualDiscount;
    await _localDb.deleteHeldOrder(holdUuid);
    _heldOrders = await _localDb.loadHeldOrders();
    await _persistCart();
    notifyListeners();
  }

  Future<void> clearCart() async {
    _cartItems = [];
    _customerId = null;
    _customerName = 'Pelanggan Umum';
    _customerPhone = '';
    _selectedPromo = null;
    _manualDiscount = 0.0;
    _paymentMethod = 'tunai';
    _creditUsed = 0.0;
    _amountPaid = 0.0;
    await _persistCart();
    notifyListeners();
  }

  Future<void> _persistCart() async {
    await _localDb.saveActiveCart(
      items: _cartItems,
      customerId: _customerId,
      customerName: _customerName,
      customerPhone: _customerPhone,
      selectedPromoId: _selectedPromo?.id,
      manualDiscount: _manualDiscount,
    );
  }

  // ==================== AUTHORITATIVE CHECKOUT + IDEMPOTENCY RECOVERY ====================

  Future<({StaffReceipt? receipt, StaffPrintJob? printJob, String? error})> submitCheckout({
    String note = '',
    bool requestPrint = true,
    String? overrideIdempotencyKey,
  }) async {
    if (!canSubmitCheckout) {
      return (
        receipt: null,
        printJob: null,
        error: 'Checkout diblokir: pastikan terhubung ke Admin, kasir login, dan shift aktif terbuka.',
      );
    }
    _isCheckingOut = true;
    _lastError = null;
    notifyListeners();

    final idemKey = overrideIdempotencyKey ?? RequestSigner.generateIdempotencyKey();
    final payload = {
      'idempotency_key': idemKey,
      'shift_id': _currentShift!.id,
      'cash_register_id': _currentShift!.cashRegisterId,
      'customer_id': _customerId,
      'customer_name': _customerName,
      'customer_phone': _customerPhone,
      'promo_id': _selectedPromo?.id,
      'manual_discount': _manualDiscount,
      'payment_method': _paymentMethod,
      'credit_used': _creditUsed,
      'amount_paid': _amountPaid,
      'expected_grand_total': grandTotal,
      'note': note.trim(),
      'request_print': requestPrint,
      'items': _cartItems.map((i) => i.toCheckoutItemPayload()).toList(),
    };

    // Persist intent BEFORE sending so Wi-Fi/app interruption enables deterministic reconciliation
    await _localDb.upsertPendingIntent(PendingCheckoutIntent(
      idempotencyKey: idemKey,
      requestJson: jsonEncode(payload),
      expectedGrandTotal: grandTotal,
      status: 'sending',
      createdAt: DateTime.now().toIso8601String(),
    ));

    try {
      final res = await httpClient.post(
        '/api/v1/transactions',
        body: payload,
        idempotencyKey: idemKey,
        timeout: const Duration(seconds: 12),
      );
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final receipt = StaffReceipt.fromApiJson(Map<String, dynamic>.from(data['transaction'] as Map));
      final pJob = data['print_job'] is Map
          ? StaffPrintJob.fromMap(Map<String, dynamic>.from(data['print_job'] as Map))
          : null;

      await _localDb.deletePendingIntent(idemKey);
      await _localDb.cacheRecentReceipt(receipt);
      _recentReceipts = await _localDb.loadCachedRecentReceipts();
      await clearCart();
      unawaited(syncCatalogIncremental());
      return (receipt: receipt, printJob: pJob, error: null);
    } on LanNetworkException catch (e) {
      // Network interrupted mid-flight: preserve cart & mark uncertain for reconnect reconciliation
      await _localDb.upsertPendingIntent(PendingCheckoutIntent(
        idempotencyKey: idemKey,
        requestJson: jsonEncode(payload),
        expectedGrandTotal: grandTotal,
        status: 'uncertain_reconciling',
        createdAt: DateTime.now().toIso8601String(),
      ));
      _adminReachable = false;
      _wsConnected = false;
      _lastError =
          'Koneksi ke Admin terputus saat mengirim transaksi. Keranjang dipertahankan; saat terhubung kembali status transaksi akan direkonsiliasi otomatis (${e.message}).';
      notifyListeners();
      return (receipt: null, printJob: null, error: _lastError);
    } on LanApiException catch (e) {
      await _localDb.deletePendingIntent(idemKey);
      await _inspectFatalAuthError(e);
      if (e.errorCode == 'PRICE_OR_PROMO_CHANGED') {
        unawaited(syncCatalogIncremental());
        unawaited(syncPromos());
      }
      _lastError = e.message;
      notifyListeners();
      return (receipt: null, printJob: null, error: e.message);
    } finally {
      _isCheckingOut = false;
      notifyListeners();
    }
  }

  /// Automatically reconciles any uncertain in-flight checkout intents after reconnect!
  /// If Admin already committed the transaction (`200 OK`), caches receipt and clears cart
  /// cleanly so the cashier NEVER accidentally double-charges via retry.
  Future<StaffReceipt?> reconcilePendingCheckoutIntents() async {
    final pending = await _localDb.getPendingIntents();
    StaffReceipt? recoveredReceipt;
    for (final intent in pending) {
      try {
        final res = await httpClient.get(
          '/api/v1/transactions/by-idempotency/${Uri.encodeComponent(intent.idempotencyKey)}',
        );
        final receipt = StaffReceipt.fromApiJson(
          Map<String, dynamic>.from(res['data']['transaction'] as Map),
        );
        await _localDb.deletePendingIntent(intent.idempotencyKey);
        await _localDb.cacheRecentReceipt(receipt);
        _recentReceipts = await _localDb.loadCachedRecentReceipts();
        recoveredReceipt = receipt;
        _statusMessage = 'Transaksi ${receipt.invoiceNumber} terkonfirmasi tersimpan di Admin.';
        await clearCart();
      } on LanApiException catch (e) {
        if (e.statusCode == 404) {
          // Confirmed NEVER committed by Admin -> delete pending intent and keep user's cart!
          await _localDb.deletePendingIntent(intent.idempotencyKey);
          _statusMessage =
              'Transaksi sebelumnya belum masuk ke Admin. Keranjang tetap utuh; silakan tekan Bayar lagi bila siap.';
        }
      } catch (_) {}
    }
    notifyListeners();
    return recoveredReceipt;
  }

  // ==================== RECEIPTS, PRINT & MANUAL DRAWER ====================

  Future<void> syncRecentReceiptsFromServer() async {
    try {
      final res = await httpClient.get('/api/v1/transactions?scope=terminal&page=1&limit=30');
      final list = (res['data']['transactions'] as List<dynamic>?) ?? const [];
      for (final raw in list) {
        await _localDb.cacheRecentReceipt(
          StaffReceipt.fromApiJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      _recentReceipts = await _localDb.loadCachedRecentReceipts();
      notifyListeners();
    } catch (_) {}
  }

  Future<({StaffPrintJob? job, String? error})> requestReprint(String invoiceNumber) async {
    try {
      final res = await httpClient.post(
        '/api/v1/print/receipt',
        idempotencyKey: RequestSigner.generateIdempotencyKey(),
        body: {'invoice_number': invoiceNumber, 'is_reprint': true},
      );
      final job = StaffPrintJob.fromMap(
        Map<String, dynamic>.from(res['data']['print_job'] as Map),
      );
      return (job: job, error: null);
    } catch (e) {
      return (job: null, error: _friendlyError(e));
    }
  }

  Future<StaffPrintJob?> getPrintJobStatus(String jobUuid) async {
    try {
      final res = await httpClient.get('/api/v1/print/jobs/${Uri.encodeComponent(jobUuid)}');
      return StaffPrintJob.fromMap(Map<String, dynamic>.from(res['data']['print_job'] as Map));
    } catch (_) {
      return null;
    }
  }

  Future<({bool triggered, String? error})> requestManualDrawerOpen(String reason) async {
    if (!_allowManualOpenDrawer) {
      return (triggered: false, error: 'Pembukaan laci manual dinonaktifkan Admin untuk terminal ini.');
    }
    try {
      final res = await httpClient.post(
        '/api/v1/printers/open-drawer',
        idempotencyKey: RequestSigner.generateIdempotencyKey(),
        body: {
          'reason': reason.trim(),
          if (_currentShift != null) 'cash_register_id': _currentShift!.cashRegisterId,
        },
      );
      return (triggered: res['data']['drawer_triggered'] == true, error: null);
    } catch (e) {
      await _inspectFatalAuthError(e);
      return (triggered: false, error: _friendlyError(e));
    }
  }

  // ==================== ERROR & REVOCATION HELPERS ====================

  Future<void> _inspectFatalAuthError(Object e) async {
    if (e is LanApiException) {
      if (e.isTerminalRevoked) {
        await _handleRevokedByServer();
      } else if (e.isSessionUnauthorized) {
        await _handleLocalSessionClear(message: e.message);
      }
    }
  }

  Future<void> _handleLocalSessionClear({String? message}) async {
    await wsClient.disconnect();
    await _credStore.clearSession();
    _credentials = _credentials?.copyWith(clearSession: true);
    _cashier = null;
    _currentShift = null;
    if (message != null && message.isNotEmpty) {
      _lastError = message;
    }
    notifyListeners();
  }

  Future<void> _handleRevokedByServer() async {
    _revokedFlag = true;
    await wsClient.disconnect();
    await _credStore.clearAll();
    await _localDb.clearAllLocalData();
    _credentials = null;
    _cashier = null;
    _currentShift = null;
    _lastError = 'Akses terminal ini telah dicabut Admin. Lakukan pairing ulang.';
    notifyListeners();
  }

  String _friendlyError(Object e) {
    if (e is LanApiException) return e.message;
    if (e is LanNetworkException) return e.message;
    return e.toString();
  }

  @override
  void dispose() {
    _wsEventSub?.cancel();
    _wsStateSub?.cancel();
    wsClient.dispose();
    super.dispose();
  }
}
