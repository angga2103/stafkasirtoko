import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../security/request_signer.dart';
import '../security/secure_credential_store.dart';

class LanApiException implements Exception {
  final int statusCode;
  final String errorCode;
  final String message;
  final Map<String, dynamic> details;

  const LanApiException({
    required this.statusCode,
    required this.errorCode,
    required this.message,
    this.details = const {},
  });

  bool get isTerminalRevoked =>
      statusCode == 403 && errorCode == 'TERMINAL_REVOKED';

  bool get isSessionUnauthorized =>
      statusCode == 401 &&
      (errorCode == 'UNAUTHORIZED_SESSION' ||
          errorCode == 'SESSION_EXPIRED' ||
          errorCode == 'SESSION_REVOKED' ||
          errorCode == 'SESSION_INVALID');

  bool get isSessionLimitExceeded =>
      statusCode == 409 && errorCode == 'SESSION_LIMIT_EXCEEDED';

  @override
  String toString() => '$errorCode ($statusCode): $message';
}

class LanNetworkException implements Exception {
  final String message;
  final bool isCertificateMismatch;
  final bool isServerIdMismatch;
  final String? observedCertSha256;

  const LanNetworkException(
    this.message, {
    this.isCertificateMismatch = false,
    this.isServerIdMismatch = false,
    this.observedCertSha256,
  });

  @override
  String toString() => message;
}

class LanHttpClient {
  final SecureCredentialStore _credentialStore;
  final RequestSigner _signer;
  final Duration requestTimeout;

  String _pinnedSha256 = '';
  String? _nextPinnedSha256;
  String? _lastObservedMismatchSha256;

  LanHttpClient({
    required this._credentialStore,
    RequestSigner? signer,
    this.requestTimeout = const Duration(seconds: 6),
  }) : _signer = signer ?? RequestSigner();

  RequestSigner get signer => _signer;

  void setPinnedFingerprints({
    required String primarySha256,
    String? nextSha256,
  }) {
    _pinnedSha256 = primarySha256.trim().toLowerCase();
    _nextPinnedSha256 = nextSha256?.trim().toLowerCase();
  }

  /// Creates an `HttpClient` enforcing strict TLS certificate fingerprint pinning
  /// via DER SHA-256 verification. Rejects ALL certificates whose SHA-256 doesn't match.
  HttpClient createPinnedHttpClient({
    String? explicitExpectedSha256,
    String? explicitShortPin,
    Duration timeout = const Duration(seconds: 6),
  }) {
    _lastObservedMismatchSha256 = null;
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final observedSha = sha256.convert(cert.der).toString().toLowerCase();
      if (explicitExpectedSha256 != null && explicitExpectedSha256.isNotEmpty) {
        final ok = observedSha == explicitExpectedSha256.toLowerCase();
        if (!ok) _lastObservedMismatchSha256 = observedSha;
        return ok;
      }
      if (explicitShortPin != null && explicitShortPin.trim().isNotEmpty) {
        final pinClean = explicitShortPin.trim().toLowerCase();
        final ok = observedSha.startsWith(pinClean);
        if (!ok) _lastObservedMismatchSha256 = observedSha;
        return ok;
      }
      if (_pinnedSha256.isNotEmpty && observedSha == _pinnedSha256) {
        return true;
      }
      if (_nextPinnedSha256 != null &&
          _nextPinnedSha256!.isNotEmpty &&
          observedSha == _nextPinnedSha256) {
        return true;
      }
      _lastObservedMismatchSha256 = observedSha;
      return false;
    };
    return client;
  }

  /// Health check over TLS. During initial manual pairing, validates against
  /// either full [expectedSha256] or user-entered 6-8 char [expectedShortPin].
  Future<Map<String, dynamic>> checkHealth({
    required String baseUrl,
    String? expectedSha256,
    String? expectedShortPin,
  }) async {
    final uri = Uri.parse('${_cleanBaseUrl(baseUrl)}/api/v1/health');
    final client = createPinnedHttpClient(
      explicitExpectedSha256: expectedSha256,
      explicitShortPin: expectedShortPin,
      timeout: const Duration(seconds: 4),
    );
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 4));
      req.headers.set('X-API-Version', '1.1');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || decoded['success'] != true) {
        final err = (decoded['error'] as Map<String, dynamic>?) ?? {};
        throw LanApiException(
          statusCode: res.statusCode,
          errorCode: (err['code'] ?? 'HEALTH_FAILED').toString(),
          message: (err['message'] ?? 'Server Admin mengembalikan error.').toString(),
        );
      }
      final data = Map<String, dynamic>.from(decoded['data'] as Map);
      final srvMs = (data['server_time_ms'] as num?)?.toInt();
      if (srvMs != null) {
        _signer.calibrateFromServerTimeMs(srvMs);
      }
      return data;
    } on HandshakeException catch (e) {
      throw LanNetworkException(
        'Verifikasi sertifikat TLS server Admin gagal (checksum tidak cocok): $e',
        isCertificateMismatch: true,
        observedCertSha256: _lastObservedMismatchSha256,
      );
    } on HttpException catch (e) {
      throw LanNetworkException('Koneksi HTTP ke POS Admin terputus: ${e.message}');
    } on FormatException {
      throw const LanNetworkException('Respons server Admin tidak lengkap atau korup.');
    } on SocketException catch (e) {
      throw LanNetworkException('Server POS Admin tidak terjangkau: ${e.message}');
    } on TimeoutException {
      throw const LanNetworkException('Koneksi ke server POS Admin timeout.');
    } finally {
      client.close(force: true);
    }
  }

  /// Verifies health over pinned TLS AND rejects endpoints whose persistent
  /// `server_id` disagrees with [expectedServerId] when configured.
  Future<Map<String, dynamic>> checkHealthVerified({
    required String baseUrl,
    String? expectedSha256,
    String? expectedShortPin,
    String? expectedServerId,
  }) async {
    final data = await checkHealth(
      baseUrl: baseUrl,
      expectedSha256: expectedSha256,
      expectedShortPin: expectedShortPin,
    );
    final cleanExpected = expectedServerId?.trim() ?? '';
    final observedServerId = (data['server_id'] ?? '').toString().trim();
    if (cleanExpected.isNotEmpty && observedServerId != cleanExpected) {
      throw LanNetworkException(
        'Server ID tidak cocok (diharapkan $cleanExpected, ditemukan ${observedServerId.isEmpty ? "-" : observedServerId}).',
        isServerIdMismatch: true,
      );
    }
    return data;
  }

  /// Exchanges a short-lived pairing code for terminal credentials over pinned TLS.
  Future<Map<String, dynamic>> pairTerminal({
    required String baseUrl,
    required String pairingCode,
    required String deviceName,
    required String deviceModel,
    required String deviceUuid,
    String? expectedSha256,
    String? expectedShortPin,
  }) async {
    final uri = Uri.parse('${_cleanBaseUrl(baseUrl)}/api/v1/pairing/register');
    final client = createPinnedHttpClient(
      explicitExpectedSha256: expectedSha256,
      explicitShortPin: expectedShortPin,
      timeout: requestTimeout,
    );
    try {
      final req = await client.postUrl(uri).timeout(requestTimeout);
      req.headers.contentType = ContentType.json;
      req.headers.set('X-API-Version', '1.1');
      req.write(jsonEncode({
        'pairing_code': pairingCode.trim(),
        'device_name': deviceName.trim(),
        'device_model': deviceModel.trim(),
        'device_uuid': deviceUuid.trim(),
        'app_version': '1.1.0',
      }));
      final res = await req.close().timeout(requestTimeout);
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode >= 400 || decoded['success'] != true) {
        final err = (decoded['error'] as Map<String, dynamic>?) ?? {};
        throw LanApiException(
          statusCode: res.statusCode,
          errorCode: (err['code'] ?? 'PAIRING_FAILED').toString(),
          message: (err['message'] ?? 'Pairing gagal').toString(),
        );
      }
      final data = Map<String, dynamic>.from(decoded['data'] as Map);
      final certSha = (data['cert_sha256'] ?? expectedSha256 ?? '').toString().toLowerCase();
      if (certSha.isNotEmpty) {
        setPinnedFingerprints(primarySha256: certSha);
      }
      return data;
    } on HandshakeException catch (e) {
      throw LanNetworkException(
        'Sertifikat TLS Admin ditolak saat pairing: $e',
        isCertificateMismatch: true,
        observedCertSha256: _lastObservedMismatchSha256,
      );
    } on HttpException catch (e) {
      throw LanNetworkException('Koneksi pairing ke Admin terputus: ${e.message}');
    } on FormatException {
      throw const LanNetworkException('Respons pairing Admin tidak lengkap.');
    } on SocketException catch (e) {
      throw LanNetworkException('Tidak dapat terhubung ke Admin saat pairing: ${e.message}');
    } on TimeoutException {
      throw const LanNetworkException('Pairing ke Admin timeout.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> get(
    String pathAndQuery, {
    bool requireSession = true,
  }) =>
      request('GET', pathAndQuery, requireSession: requireSession);

  Future<Map<String, dynamic>> post(
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool requireSession = true,
    String? idempotencyKey,
    Duration? timeout,
  }) =>
      request(
        'POST',
        pathAndQuery,
        body: body,
        requireSession: requireSession,
        idempotencyKey: idempotencyKey,
        timeout: timeout,
      );

  Future<Map<String, dynamic>> request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool requireSession = true,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    final creds = await _credentialStore.loadCredentials();
    if (creds == null || !creds.isPaired) {
      throw const LanApiException(
        statusCode: 401,
        errorCode: 'NOT_PAIRED',
        message: 'Terminal belum dipasangkan dengan POS Admin.',
      );
    }
    if (requireSession && (creds.sessionToken == null || creds.sessionToken!.isEmpty)) {
      throw const LanApiException(
        statusCode: 401,
        errorCode: 'UNAUTHORIZED_SESSION',
        message: 'Kasir belum login di terminal ini.',
      );
    }

    setPinnedFingerprints(
      primarySha256: creds.tlsCertSha256,
      nextSha256: creds.nextCertSha256,
    );

    final bodyBytes = body != null ? utf8.encode(jsonEncode(body)) : const <int>[];
    final headers = _signer.buildSignedHeaders(
      terminalId: creds.terminalId,
      deviceToken: creds.deviceToken,
      deviceSecret: creds.deviceSecret,
      method: method,
      pathAndQuery: pathAndQuery,
      bodyBytes: bodyBytes,
      sessionToken: requireSession ? creds.sessionToken : null,
      idempotencyKey: idempotencyKey,
    );

    final fullUri = Uri.parse('${_cleanBaseUrl(creds.serverUrl)}$pathAndQuery');
    final effTimeout = timeout ?? requestTimeout;
    final client = createPinnedHttpClient(timeout: effTimeout);
    try {
      final req = await client.openUrl(method.toUpperCase(), fullUri).timeout(effTimeout);
      headers.forEach((k, v) => req.headers.set(k, v));
      if (bodyBytes.isNotEmpty) {
        req.add(bodyBytes);
      }
      final res = await req.close().timeout(effTimeout);
      final raw = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (res.statusCode >= 400 || decoded['success'] != true) {
        final err = (decoded['error'] as Map<String, dynamic>?) ?? {};
        throw LanApiException(
          statusCode: res.statusCode,
          errorCode: (err['code'] ?? 'API_ERROR').toString(),
          message: (err['message'] ?? 'Permintaan ditolak server Admin').toString(),
          details: err['details'] is Map
              ? Map<String, dynamic>.from(err['details'] as Map)
              : const {},
        );
      }
      return decoded;
    } on HandshakeException catch (e) {
      throw LanNetworkException(
        'Pin sertifikat TLS tidak cocok (kemungkinan sertifikat berubah): $e',
        isCertificateMismatch: true,
        observedCertSha256: _lastObservedMismatchSha256,
      );
    } on HttpException catch (e) {
      throw LanNetworkException('Koneksi ke server Admin terputus saat transfer data: ${e.message}');
    } on FormatException {
      throw const LanNetworkException('Respons server Admin terputus sebelum selesai.');
    } on SocketException catch (e) {
      throw LanNetworkException('Koneksi ke server Admin terputus: ${e.message}');
    } on TimeoutException {
      throw const LanNetworkException('Permintaan ke server Admin timeout.');
    } finally {
      client.close(force: true);
    }
  }

  static String _cleanBaseUrl(String raw) {
    final trimmed = raw.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }
}
