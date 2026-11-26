import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class RequestSigner {
  static const Uuid _uuid = Uuid();
  int _clockOffsetMs = 0;

  int get clockOffsetMs => _clockOffsetMs;

  void calibrateFromServerTimeMs(int serverTimeMs, {int? localTimeMs}) {
    final local = localTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    _clockOffsetMs = serverTimeMs - local;
  }

  int calibratedTimestampMs() => DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  static String generateNonce() => _uuid.v4();
  static String generateIdempotencyKey() => _uuid.v4();

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
  static String sha256HexString(String text) => sha256.convert(utf8.encode(text)).toString();

  static String sign({
    required String deviceSecret,
    required String method,
    required String pathAndQuery,
    required String timestampMs,
    required String nonce,
    required List<int> bodyBytes,
  }) {
    final bodyHash = sha256Hex(bodyBytes);
    final canonical =
        '${method.toUpperCase()}\n$pathAndQuery\n$timestampMs\n$nonce\n$bodyHash';
    return Hmac(sha256, utf8.encode(deviceSecret))
        .convert(utf8.encode(canonical))
        .toString();
  }

  Map<String, String> buildSignedHeaders({
    required String terminalId,
    required String deviceToken,
    required String deviceSecret,
    required String method,
    required String pathAndQuery,
    List<int> bodyBytes = const [],
    String? sessionToken,
    String? idempotencyKey,
  }) {
    final ts = calibratedTimestampMs().toString();
    final nonce = generateNonce();
    final sig = sign(
      deviceSecret: deviceSecret,
      method: method,
      pathAndQuery: pathAndQuery,
      timestampMs: ts,
      nonce: nonce,
      bodyBytes: bodyBytes,
    );
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'X-API-Version': '1.1',
      'X-Terminal-Id': terminalId,
      'X-Device-Token': deviceToken,
      'X-Request-Timestamp': ts,
      'X-Request-Nonce': nonce,
      'X-Signature': sig,
      if (sessionToken != null && sessionToken.isNotEmpty)
        'Authorization': 'Bearer $sessionToken',
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'X-Idempotency-Key': idempotencyKey,
    };
  }
}
