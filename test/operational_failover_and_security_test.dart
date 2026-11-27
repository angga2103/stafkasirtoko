import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stafkasirtoko/core/network/lan_discovery_client.dart';
import 'package:stafkasirtoko/core/security/secure_credential_store.dart';
import 'package:stafkasirtoko/data/local/staff_local_db.dart';
import 'package:stafkasirtoko/data/models/staff_models.dart';
import 'package:stafkasirtoko/providers/staff_session_controller.dart';

({SecurityContext context, String sha256Hex}) _createSelfSignedTls(String cn) {
  final fortuna = FortunaRandom();
  final rng = Random.secure();
  fortuna.seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)))));
  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
      fortuna,
    ));
  final pair = keyGen.generateKeyPair();
  final priv = pair.privateKey;
  final pub = pair.publicKey;

  final rsaOid = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]);
  final rsaAlgId = ASN1Sequence(elements: [rsaOid, ASN1Null()]);
  final spki = ASN1Sequence(elements: [
    rsaAlgId,
    ASN1BitString(
      stringValues: ASN1Sequence(elements: [
        ASN1Integer(pub.modulus),
        ASN1Integer(pub.exponent),
      ]).encode(),
    ),
  ]);
  final sigAlg = ASN1Sequence(elements: [
    ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 11]),
    ASN1Null(),
  ]);
  final name = ASN1Sequence(elements: [
    ASN1Set(elements: [
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier([2, 5, 4, 3]),
        ASN1UTF8String(utf8StringValue: cn),
      ]),
    ]),
  ]);
  final now = DateTime.now().toUtc();
  final tbs = ASN1Sequence(elements: [
    ASN1Sequence(tag: 0xA0, elements: [ASN1Integer(BigInt.from(2))]),
    ASN1Integer(BigInt.from(DateTime.now().microsecondsSinceEpoch)),
    sigAlg,
    name,
    ASN1Sequence(elements: [
      ASN1UtcTime(now.subtract(const Duration(minutes: 5))),
      ASN1UtcTime(now.add(const Duration(days: 30))),
    ]),
    name,
    spki,
  ]);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig = signer.generateSignature(tbs.encode());
  final certDer = ASN1Sequence(elements: [tbs, sigAlg, ASN1BitString(stringValues: sig.bytes)]).encode();
  final shaHex = sha256.convert(certDer).toString().toLowerCase();

  final p = priv.p!;
  final q = priv.q!;
  final d = priv.privateExponent!;
  final pkcs1 = ASN1Sequence(elements: [
    ASN1Integer(BigInt.zero),
    ASN1Integer(priv.modulus),
    ASN1Integer(priv.publicExponent),
    ASN1Integer(d),
    ASN1Integer(p),
    ASN1Integer(q),
    ASN1Integer(d % (p - BigInt.one)),
    ASN1Integer(d % (q - BigInt.one)),
    ASN1Integer(q.modInverse(p)),
  ]).encode();
  final pkcs8 = ASN1Sequence(elements: [
    ASN1Integer(BigInt.zero),
    rsaAlgId,
    ASN1OctetString(octets: pkcs1),
  ]).encode();

  String pem(String label, Uint8List bytes) =>
      '-----BEGIN $label-----\n${base64.encode(bytes)}\n-----END $label-----';

  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(pem('CERTIFICATE', certDer)))
    ..usePrivateKeyBytes(utf8.encode(pem('PRIVATE KEY', pkcs8)));
  return (context: ctx, sha256Hex: shaHex);
}

Future<int> _getUnusedPort() async {
  final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = srv.port;
  await srv.close();
  return p;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await StaffLocalDb.instance.close();
  });

  group('Operational Architecture — Router <-> Hotspot Failover, Identity Pinning & UDP Discovery', () {
    test('Router -> Hotspot automatic failover switches URL while preserving session, cart & TLS pin',
        () async {
      await StaffLocalDb.instance.openTestDatabase();
      final tls = _createSelfSignedTls('kasirtoko-admin');
      final deadRouterPort = await _getUnusedPort();

      final hotspotServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        tls.context,
      );
      addTearDown(() => hotspotServer.close(force: true));

      final hotspotUrl = 'https://127.0.0.1:${hotspotServer.port}';
      final deadRouterUrl = 'https://127.0.0.1:$deadRouterPort';

      hotspotServer.listen((HttpRequest req) async {
        final path = req.uri.path;
        Future<void> reply(int code, Map<String, dynamic> map) async {
          req.response.statusCode = code;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(map));
          await req.response.close();
        }

        if (path == '/api/v1/health') {
          await reply(200, {
            'success': true,
            'data': {
              'server_id': 'srv-failover-01',
              'server_time_ms': DateTime.now().millisecondsSinceEpoch,
              'store_name': 'Toko Failover Utama',
              'network_mode': 'backup_hotspot',
              'endpoints': [
                {'profile_type': 'primary_router', 'base_url': deadRouterUrl},
                {'profile_type': 'backup_hotspot', 'base_url': hotspotUrl},
              ],
            },
          });
          return;
        }
        if (path == '/api/v1/security/cert-info') {
          await reply(200, {
            'success': true,
            'data': {'cert_sha256': tls.sha256Hex, 'next_cert_sha256': null},
          });
          return;
        }
        if (path == '/api/v1/auth/me' || path == '/api/v1/store/bootstrap') {
          await reply(200, {
            'success': true,
            'data': {
              'server_id': 'srv-failover-01',
              'network_mode': 'backup_hotspot',
              'store_name': 'Toko Failover Utama',
              'drawer_mode': 'SHARED_DRAWER',
              'cashier': {'id': 3, 'name': 'Kasir Failover', 'role': 'cashier', 'permissions': {'access_pos': true}},
              'current_shift': {
                'id': 1,
                'cashier_id': 3,
                'cashier_name': 'Kasir Failover',
                'terminal_id': 'TERM-01',
                'cash_register_id': 1,
                'drawer_mode': 'SHARED_DRAWER',
                'start_time': DateTime.now().toIso8601String(),
                'starting_cash': 100000,
                'status': 'open',
              },
            },
          });
          return;
        }
        if (path == '/api/v1/catalog/products') {
          await reply(200, {
            'success': true,
            'data': {'sync_version': 1, 'items': [], 'pagination': {'has_more': false}},
          });
          return;
        }
        if (path == '/api/v1/catalog/promos') {
          await reply(200, {'success': true, 'data': {'promos': []}});
          return;
        }
        if (path == '/api/v1/customers') {
          await reply(200, {'success': true, 'data': {'customers': []}});
          return;
        }
        if (path == '/api/v1/cash-registers') {
          await reply(200, {'success': true, 'data': {'authorized_register_id': 1, 'cash_registers': []}});
          return;
        }
        if (path == '/api/v1/shifts/current') {
          await reply(200, {
            'success': true,
            'data': {
              'drawer_mode': 'SHARED_DRAWER',
              'shift': {
                'id': 1,
                'cashier_id': 3,
                'cashier_name': 'Kasir Failover',
                'terminal_id': 'TERM-01',
                'cash_register_id': 1,
                'drawer_mode': 'SHARED_DRAWER',
                'start_time': DateTime.now().toIso8601String(),
                'starting_cash': 100000,
                'status': 'open',
              },
            },
          });
          return;
        }
        if (path == '/api/v1/transactions') {
          await reply(200, {'success': true, 'data': {'transactions': []}});
          return;
        }
        await reply(404, {'success': false, 'error': {'code': 'NOT_FOUND', 'message': 'Nope'}});
      });

      final credStore = InMemoryCredentialStore();
      await credStore.saveCredentials(StaffCredentials(
        terminalId: 'TERM-01',
        terminalCode: 'T01',
        terminalName: 'HP Kasir 1',
        deviceUuid: 'uuid-fo-1',
        deviceToken: 'tok',
        deviceSecret: 'sec',
        tlsCertSha256: tls.sha256Hex,
        serverUrl: deadRouterUrl,
        serverId: 'srv-failover-01',
        primaryServerUrl: deadRouterUrl,
        backupServerUrl: hotspotUrl,
        candidateServerUrls: [deadRouterUrl, hotspotUrl],
        sessionToken: 'keep-session-token',
      ));

      final ctrl = StaffSessionController(
        credentialStore: credStore,
        localDb: StaffLocalDb.instance,
        enableLanDiscovery: false,
      );
      addTearDown(ctrl.dispose);

      // Put an item into cart BEFORE reconnect
      await ctrl.addToCart(const StaffProduct(
        id: 9,
        code: 'P-FO',
        name: 'Kabel Data USB-C',
        category: 'Umum',
        baseUnit: 'Pcs',
        sellingPrice: 25000,
        stock: 10,
      ));

      await ctrl.initialize();

      // Must fail over cleanly to hotspotUrl, retain sessionToken & cart, and reflect Hotspot Cadangan!
      expect(ctrl.adminReachable, isTrue);
      expect(ctrl.networkStatus, StaffNetworkStatus.hotspotBackup);
      expect(ctrl.networkStatus.displayLabel, 'Hotspot Cadangan');
      expect(ctrl.credentials!.serverUrl, hotspotUrl);
      expect(ctrl.credentials!.sessionToken, 'keep-session-token');
      expect(ctrl.cartItems.length, 1);
      expect(ctrl.canSubmitCheckout, isTrue);
    });

    test('Rejects wrong server_id AND invalid TLS certificate during failover & enters Server Tidak Tersedia',
        () async {
      await StaffLocalDb.instance.openTestDatabase();
      final trustedTls = _createSelfSignedTls('trusted-admin');
      final attackerTls = _createSelfSignedTls('attacker-rogue');

      // 1. Rogue server with SAME cert but WRONG server_id
      final wrongIdServer = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, trustedTls.context);
      addTearDown(() => wrongIdServer.close(force: true));
      wrongIdServer.listen((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'data': {'server_id': 'srv-WRONG-STORE', 'server_time_ms': DateTime.now().millisecondsSinceEpoch},
        }));
        await req.response.close();
      });

      // 2. Rogue server with UNTRUSTED/MISMATCHED certificate
      final rogueCertServer = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, attackerTls.context);
      addTearDown(() => rogueCertServer.close(force: true));
      rogueCertServer.listen((req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'data': {'server_id': 'srv-REAL-01', 'server_time_ms': DateTime.now().millisecondsSinceEpoch},
        }));
        await req.response.close();
      });

      final credStore = InMemoryCredentialStore();
      await credStore.saveCredentials(StaffCredentials(
        terminalId: 'TERM-01',
        terminalCode: 'T01',
        terminalName: 'HP Kasir',
        deviceUuid: 'u1',
        deviceToken: 'tok',
        deviceSecret: 'sec',
        tlsCertSha256: trustedTls.sha256Hex,
        serverUrl: 'https://127.0.0.1:${wrongIdServer.port}',
        serverId: 'srv-REAL-01',
        primaryServerUrl: 'https://127.0.0.1:${wrongIdServer.port}',
        backupServerUrl: 'https://127.0.0.1:${rogueCertServer.port}',
        sessionToken: 'sess-1',
      ));

      final ctrl = StaffSessionController(
        credentialStore: credStore,
        localDb: StaffLocalDb.instance,
        enableLanDiscovery: false,
      );
      addTearDown(ctrl.dispose);

      await ctrl.initialize();
      expect(ctrl.adminReachable, isFalse);
      expect(ctrl.networkStatus, StaffNetworkStatus.serverUnavailable);
      expect(ctrl.canSubmitCheckout, isFalse);
      expect(ctrl.lastError, isNotNull);
    });

    test('UDP LanDiscoveryClient filters discovered servers strictly by expectedServerId', () async {
      final responder = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(responder.close);

      responder.listen((evt) {
        if (evt != RawSocketEvent.read) return;
        final d = responder.receive();
        if (d == null) return;
        final msg = utf8.decode(d.data);
        if (msg == LanDiscoveryClient.discoverMagic) {
          responder.send(
            utf8.encode('${LanDiscoveryClient.responsePrefix}${jsonEncode({
              'server_id': 'srv-OTHER',
              'port': 8443,
              'ips': ['192.168.99.9'],
            })}'),
            d.address,
            d.port,
          );
          responder.send(
            utf8.encode('${LanDiscoveryClient.responsePrefix}${jsonEncode({
              'server_id': 'srv-EXPECTED',
              'port': 8443,
              'ips': ['192.168.43.1'],
              'network_mode': 'backup_hotspot',
            })}'),
            d.address,
            d.port,
          );
        }
      });

      final client = LanDiscoveryClient();
      final results = await client.discover(
        expectedServerId: 'srv-EXPECTED',
        portOverride: responder.port,
        extraTargets: [InternetAddress.loopbackIPv4],
        timeout: const Duration(milliseconds: 300),
      );
      expect(results.length, 1);
      expect(results.first.serverId, 'srv-EXPECTED');
      expect(results.first.ips, contains('192.168.43.1'));
      expect(results.first.networkMode, 'backup_hotspot');
    });
  });
}
