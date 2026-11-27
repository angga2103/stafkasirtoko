import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class StaffCredentials {
  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String deviceUuid;
  final String deviceToken;
  final String deviceSecret;
  final String tlsCertSha256;
  final String? nextCertSha256;
  final String serverUrl;
  final String serverId;
  final String primaryServerUrl;
  final String backupServerUrl;
  final List<String> candidateServerUrls;
  final String? sessionToken;
  final String? sessionExpiresAt;

  const StaffCredentials({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.deviceUuid,
    required this.deviceToken,
    required this.deviceSecret,
    required this.tlsCertSha256,
    this.nextCertSha256,
    required this.serverUrl,
    this.serverId = '',
    this.primaryServerUrl = '',
    this.backupServerUrl = '',
    this.candidateServerUrls = const [],
    this.sessionToken,
    this.sessionExpiresAt,
  });

  bool get isPaired =>
      terminalId.isNotEmpty &&
      deviceToken.isNotEmpty &&
      deviceSecret.isNotEmpty &&
      tlsCertSha256.isNotEmpty &&
      serverUrl.isNotEmpty;

  StaffCredentials copyWith({
    String? terminalId,
    String? terminalCode,
    String? terminalName,
    String? deviceUuid,
    String? deviceToken,
    String? deviceSecret,
    String? tlsCertSha256,
    String? nextCertSha256,
    bool clearNextCert = false,
    String? serverUrl,
    String? serverId,
    String? primaryServerUrl,
    String? backupServerUrl,
    List<String>? candidateServerUrls,
    String? sessionToken,
    bool clearSession = false,
    String? sessionExpiresAt,
  }) =>
      StaffCredentials(
        terminalId: terminalId ?? this.terminalId,
        terminalCode: terminalCode ?? this.terminalCode,
        terminalName: terminalName ?? this.terminalName,
        deviceUuid: deviceUuid ?? this.deviceUuid,
        deviceToken: deviceToken ?? this.deviceToken,
        deviceSecret: deviceSecret ?? this.deviceSecret,
        tlsCertSha256: tlsCertSha256 ?? this.tlsCertSha256,
        nextCertSha256: clearNextCert ? null : (nextCertSha256 ?? this.nextCertSha256),
        serverUrl: serverUrl ?? this.serverUrl,
        serverId: serverId ?? this.serverId,
        primaryServerUrl: primaryServerUrl ?? this.primaryServerUrl,
        backupServerUrl: backupServerUrl ?? this.backupServerUrl,
        candidateServerUrls: candidateServerUrls ?? this.candidateServerUrls,
        sessionToken: clearSession ? null : (sessionToken ?? this.sessionToken),
        sessionExpiresAt: clearSession ? null : (sessionExpiresAt ?? this.sessionExpiresAt),
      );
}

abstract class SecureCredentialStore {
  Future<void> put(String key, String value);
  Future<String?> get(String key);
  Future<void> delete(String key);
  Future<void> clearAll();
  Future<String> getDeviceModel();

  static const _kTerminalId = 'terminal_id';
  static const _kTerminalCode = 'terminal_code';
  static const _kTerminalName = 'terminal_name';
  static const _kDeviceUuid = 'device_uuid';
  static const _kDeviceToken = 'device_token';
  static const _kDeviceSecret = 'device_secret';
  static const _kTlsCertSha = 'tls_cert_sha256';
  static const _kNextCertSha = 'next_cert_sha256';
  static const _kServerUrl = 'server_url';
  static const _kServerId = 'server_id';
  static const _kPrimaryServerUrl = 'primary_server_url';
  static const _kBackupServerUrl = 'backup_server_url';
  static const _kCandidateServerUrls = 'candidate_server_urls';
  static const _kSessionToken = 'cashier_session_token';
  static const _kSessionExp = 'cashier_session_expires_at';

  Future<void> saveCredentials(StaffCredentials creds) async {
    await put(_kTerminalId, creds.terminalId);
    await put(_kTerminalCode, creds.terminalCode);
    await put(_kTerminalName, creds.terminalName);
    await put(_kDeviceUuid, creds.deviceUuid);
    await put(_kDeviceToken, creds.deviceToken);
    await put(_kDeviceSecret, creds.deviceSecret);
    await put(_kTlsCertSha, creds.tlsCertSha256);
    await put(_kServerUrl, creds.serverUrl);
    if (creds.serverId.isNotEmpty) {
      await put(_kServerId, creds.serverId);
    } else {
      await delete(_kServerId);
    }
    if (creds.primaryServerUrl.isNotEmpty) {
      await put(_kPrimaryServerUrl, creds.primaryServerUrl);
    } else {
      await delete(_kPrimaryServerUrl);
    }
    if (creds.backupServerUrl.isNotEmpty) {
      await put(_kBackupServerUrl, creds.backupServerUrl);
    } else {
      await delete(_kBackupServerUrl);
    }
    if (creds.candidateServerUrls.isNotEmpty) {
      await put(_kCandidateServerUrls, jsonEncode(creds.candidateServerUrls));
    } else {
      await delete(_kCandidateServerUrls);
    }
    if (creds.nextCertSha256 != null && creds.nextCertSha256!.isNotEmpty) {
      await put(_kNextCertSha, creds.nextCertSha256!);
    } else {
      await delete(_kNextCertSha);
    }
    if (creds.sessionToken != null && creds.sessionToken!.isNotEmpty) {
      await put(_kSessionToken, creds.sessionToken!);
      await put(_kSessionExp, creds.sessionExpiresAt ?? '');
    } else {
      await delete(_kSessionToken);
      await delete(_kSessionExp);
    }
  }

  Future<StaffCredentials?> loadCredentials() async {
    final tid = await get(_kTerminalId) ?? '';
    final tok = await get(_kDeviceToken) ?? '';
    final sec = await get(_kDeviceSecret) ?? '';
    final cert = await get(_kTlsCertSha) ?? '';
    final url = await get(_kServerUrl) ?? '';
    if (tid.isEmpty || tok.isEmpty || sec.isEmpty || cert.isEmpty || url.isEmpty) {
      return null;
    }
    List<String> candidates = const [];
    final rawCandidates = await get(_kCandidateServerUrls);
    if (rawCandidates != null && rawCandidates.isNotEmpty) {
      try {
        candidates = (jsonDecode(rawCandidates) as List<dynamic>)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    return StaffCredentials(
      terminalId: tid,
      terminalCode: await get(_kTerminalCode) ?? tid,
      terminalName: await get(_kTerminalName) ?? 'Terminal Kasir',
      deviceUuid: await get(_kDeviceUuid) ?? '',
      deviceToken: tok,
      deviceSecret: sec,
      tlsCertSha256: cert,
      nextCertSha256: await get(_kNextCertSha),
      serverUrl: url,
      serverId: await get(_kServerId) ?? '',
      primaryServerUrl: await get(_kPrimaryServerUrl) ?? '',
      backupServerUrl: await get(_kBackupServerUrl) ?? '',
      candidateServerUrls: candidates,
      sessionToken: await get(_kSessionToken),
      sessionExpiresAt: await get(_kSessionExp),
    );
  }

  Future<void> saveSession(String token, String expiresAt) async {
    await put(_kSessionToken, token);
    await put(_kSessionExp, expiresAt);
  }

  Future<void> clearSession() async {
    await delete(_kSessionToken);
    await delete(_kSessionExp);
  }
}

class AndroidKeystoreCredentialStore extends SecureCredentialStore {
  static const MethodChannel _channel =
      MethodChannel('com.kasirtoko.app.stafkasirtoko/security');
  final InMemoryCredentialStore _fallback = InMemoryCredentialStore();

  @override
  Future<void> put(String key, String value) async {
    if (!Platform.isAndroid) {
      await _fallback.put(key, value);
      return;
    }
    try {
      await _channel.invokeMethod('putSecure', {'key': key, 'value': value});
    } on MissingPluginException {
      await _fallback.put(key, value);
    }
  }

  @override
  Future<String?> get(String key) async {
    if (!Platform.isAndroid) return _fallback.get(key);
    try {
      return await _channel.invokeMethod<String>('getSecure', {'key': key});
    } on MissingPluginException {
      return _fallback.get(key);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!Platform.isAndroid) {
      await _fallback.delete(key);
      return;
    }
    try {
      await _channel.invokeMethod('deleteSecure', {'key': key});
    } on MissingPluginException {
      await _fallback.delete(key);
    }
  }

  @override
  Future<void> clearAll() async {
    if (!Platform.isAndroid) {
      await _fallback.clearAll();
      return;
    }
    try {
      await _channel.invokeMethod('clearAllSecure');
    } on MissingPluginException {
      await _fallback.clearAll();
    }
  }

  @override
  Future<String> getDeviceModel() async {
    if (!Platform.isAndroid) return Platform.operatingSystem;
    try {
      return (await _channel.invokeMethod<String>('getDeviceModel')) ?? 'Android';
    } on MissingPluginException {
      return 'Android';
    }
  }
}

@visibleForTesting
class InMemoryCredentialStore extends SecureCredentialStore {
  final Map<String, String> _map = {};

  @override
  Future<void> put(String key, String value) async => _map[key] = value;

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> clearAll() async => _map.clear();

  @override
  Future<String> getDeviceModel() async => 'TestDevice';
}
