import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../security/secure_credential_store.dart';
import 'lan_http_client.dart';

class WsServerEvent {
  final String type;
  final Map<String, dynamic> data;
  final int? serverTimeMs;

  const WsServerEvent({
    required this.type,
    this.data = const {},
    this.serverTimeMs,
  });
}

class LanWsClient {
  static const Duration heartbeatInterval = Duration(seconds: 4);
  static const Duration pongTimeout = Duration(seconds: 9);

  final SecureCredentialStore _credentialStore;
  final LanHttpClient _httpClient;

  WebSocket? _socket;
  HttpClient? _wsHttpClient;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime _lastPongAt = DateTime.now();
  bool _shouldStayConnected = false;
  bool _disposed = false;
  bool _isConnecting = false;
  int _reconnectAttempt = 0;

  final StreamController<WsServerEvent> _eventsController =
      StreamController<WsServerEvent>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  LanWsClient({
    required this._credentialStore,
    required this._httpClient,
  });

  Stream<WsServerEvent> get events => _eventsController.stream;
  Stream<bool> get connectionStates => _connectionStateController.stream;
  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;
  bool get isConnecting => _isConnecting && !isConnected;
  bool get isReconnecting => _shouldStayConnected && !isConnected && _reconnectAttempt > 0;

  void _emitEvent(WsServerEvent event) {
    if (!_disposed && !_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void _emitConnectionState(bool connected) {
    if (!_disposed && !_connectionStateController.isClosed) {
      _connectionStateController.add(connected);
    }
  }

  Future<void> connect() async {
    if (_disposed) return;
    _shouldStayConnected = true;
    await _attemptConnect();
  }

  Future<void> disconnect() async {
    _shouldStayConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeCurrentSocket(notify: true);
  }

  Future<void> _attemptConnect() async {
    if (!_shouldStayConnected || _disposed) return;
    await _closeCurrentSocket(notify: false);

    final creds = await _credentialStore.loadCredentials();
    if (_disposed ||
        creds == null ||
        !creds.isPaired ||
        creds.sessionToken == null ||
        creds.sessionToken!.isEmpty) {
      return;
    }

    _httpClient.setPinnedFingerprints(
      primarySha256: creds.tlsCertSha256,
      nextSha256: creds.nextCertSha256,
    );

    final base = Uri.parse(creds.serverUrl);
    final wsUri = Uri(
      scheme: 'wss',
      host: base.host,
      port: base.port,
      path: '/ws/v1/terminal',
    );

    final headers = _httpClient.signer.buildSignedHeaders(
      terminalId: creds.terminalId,
      deviceToken: creds.deviceToken,
      deviceSecret: creds.deviceSecret,
      method: 'GET',
      pathAndQuery: '/ws/v1/terminal',
      bodyBytes: const [],
      sessionToken: creds.sessionToken,
    );

    final pinnedHttp = _httpClient.createPinnedHttpClient(
      timeout: const Duration(seconds: 5),
    );
    _wsHttpClient = pinnedHttp;

    _isConnecting = true;
    try {
      final sock = await WebSocket.connect(
        wsUri.toString(),
        headers: headers,
        customClient: pinnedHttp,
      ).timeout(const Duration(seconds: 5));

      if (_disposed) {
        try {
          await sock.close();
        } catch (_) {}
        return;
      }

      _socket = sock;
      _reconnectAttempt = 0;
      _lastPongAt = DateTime.now();
      _emitConnectionState(true);

      sock.listen(
        (raw) {
          if (_disposed) return;
          _lastPongAt = DateTime.now();
          try {
            final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
            final type = (map['type'] ?? '').toString();
            final data = map['data'] is Map
                ? Map<String, dynamic>.from(map['data'] as Map)
                : <String, dynamic>{};
            final srvMs = (map['server_time_ms'] as num?)?.toInt();
            if (srvMs != null) {
              _httpClient.signer.calibrateFromServerTimeMs(srvMs);
            }
            if (type.isNotEmpty) {
              _emitEvent(WsServerEvent(
                type: type,
                data: data,
                serverTimeMs: srvMs,
              ));
            }
          } catch (_) {}
        },
        onDone: () {
          _onSocketClosed(sock.closeCode);
        },
        onError: (_) {
          _onSocketClosed(null);
        },
        cancelOnError: true,
      );

      _startHeartbeat();
    } catch (_) {
      _emitConnectionState(false);
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_disposed) return;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_disposed) return;
      final sock = _socket;
      if (sock == null || sock.readyState != WebSocket.open) {
        _onSocketClosed(null);
        return;
      }
      if (DateTime.now().difference(_lastPongAt) > pongTimeout) {
        _onSocketClosed(null);
        return;
      }
      try {
        sock.add(jsonEncode({
          'type': 'ping',
          'ts': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {
        _onSocketClosed(null);
      }
    });
  }

  void _onSocketClosed(int? closeCode) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    try {
      _wsHttpClient?.close(force: true);
    } catch (_) {}
    _wsHttpClient = null;
    if (_disposed) return;

    _emitConnectionState(false);

    if (closeCode == 4003) {
      // Explicit server revocation stops auto-reconnect cleanly.
      _shouldStayConnected = false;
      return;
    }
    if (_shouldStayConnected && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!_shouldStayConnected || _disposed) return;
    final delays = [1, 2, 4, 8];
    final secs = delays[_reconnectAttempt.clamp(0, delays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: secs), () {
      unawaited(_attemptConnect());
    });
  }

  Future<void> _closeCurrentSocket({required bool notify}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    try {
      _wsHttpClient?.close(force: true);
    } catch (_) {}
    _wsHttpClient = null;
    if (notify) {
      _emitConnectionState(false);
    }
  }

  void dispose() {
    _disposed = true;
    _shouldStayConnected = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    unawaited(_closeCurrentSocket(notify: false));
    _eventsController.close();
    _connectionStateController.close();
  }
}
