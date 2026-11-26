import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stafkasirtoko/core/security/request_signer.dart';
import 'package:stafkasirtoko/core/security/secure_credential_store.dart';
import 'package:stafkasirtoko/data/local/staff_local_db.dart';
import 'package:stafkasirtoko/data/models/staff_models.dart';
import 'package:stafkasirtoko/providers/staff_session_controller.dart';

({SecurityContext context, String sha256Hex}) _createTestTlsContext() {
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
        ASN1UTF8String(utf8StringValue: 'localhost'),
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await StaffLocalDb.instance.close();
  });

  test('In-flight network drop preserves cart + intent; reconnect reconciles committed TX without duplicate POST',
      () async {
    await StaffLocalDb.instance.openTestDatabase();
    final tls = _createTestTlsContext();
    final tlsNext = _createTestTlsContext();
    var postCheckoutCalls = 0;
    var dropDuringCheckout = true;
    String? committedIdemKey;

    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      tls.context,
    );

    server.listen((req) async {
      final path = req.uri.path;
      final bodyStr = await utf8.decoder.bind(req).join();
      Future<void> reply(int code, Map<String, dynamic> payload) async {
        req.response.statusCode = code;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(payload));
        await req.response.close();
      }

      if (path == '/api/v1/health') {
        await reply(200, {
          'success': true,
          'data': {'server_time_ms': DateTime.now().millisecondsSinceEpoch, 'store_name': 'Toko Test'},
        });
        return;
      }
      if (path == '/api/v1/security/cert-info') {
        await reply(200, {
          'success': true,
          'data': {'next_cert_sha256': tlsNext.sha256Hex, 'rotation_pending': true},
        });
        return;
      }
      if (path == '/api/v1/auth/me' || path == '/api/v1/store/bootstrap') {
        await reply(200, {
          'success': true,
          'data': {
            'store_name': 'Toko Test',
            'drawer_mode': 'SHARED_DRAWER',
            'cashier': {'id': 3, 'name': 'Kasir 1', 'role': 'cashier', 'permissions': {'access_pos': true}},
            'current_shift': {
              'id': 11,
              'cashier_id': 3,
              'cashier_name': 'Kasir 1',
              'terminal_id': 'TERM-001',
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
      if (path == '/api/v1/cash-registers') {
        await reply(200, {
          'success': true,
          'data': {'authorized_register_id': 1, 'cash_registers': []},
        });
        return;
      }
      if (path == '/api/v1/shifts/current') {
        await reply(200, {
          'success': true,
          'data': {
            'drawer_mode': 'SHARED_DRAWER',
            'shift': {
              'id': 11,
              'cashier_id': 3,
              'cashier_name': 'Kasir 1',
              'terminal_id': 'TERM-001',
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
      if (path == '/api/v1/catalog/products' ||
          path == '/api/v1/catalog/promos' ||
          path == '/api/v1/customers' ||
          path == '/api/v1/transactions') {
        if (req.method == 'POST' && path == '/api/v1/transactions') {
          postCheckoutCalls++;
          final bodyMap = jsonDecode(bodyStr) as Map<String, dynamic>;
          committedIdemKey = bodyMap['idempotency_key'].toString();
          if (dropDuringCheckout) {
            dropDuringCheckout = false;
            // Server actually committed before response dropped mid-socket!
            await req.response.detachSocket().then((s) => s.destroy());
            return;
          }
        }
        await reply(200, {
          'success': true,
          'data': {
            'sync_version': 1,
            'items': [],
            'promos': [],
            'customers': [],
            'transactions': [],
            'pagination': {'page': 1, 'limit': 200, 'total': 0, 'has_more': false},
          },
        });
        return;
      }
      if (path.startsWith('/api/v1/transactions/by-idempotency/')) {
        await reply(200, {
          'success': true,
          'data': {
            'found': true,
            'transaction': {
              'id': 77,
              'invoice_number': 'INV-RECONCILED-77',
              'date': DateTime.now().toIso8601String(),
              'cashier_id': 3,
              'cashier_name': 'Kasir 1',
              'terminal_id': 'TERM-001',
              'cash_register_id': 1,
              'shift_id': 11,
              'customer_name': 'Pelanggan Umum',
              'subtotal': 30000,
              'discount_total': 0,
              'tax_amount': 0,
              'promo_name': '',
              'grand_total': 30000,
              'payment_method': 'tunai',
              'credit_used': 0,
              'amount_paid': 50000,
              'change_amount': 20000,
              'qr_code_payload': 'TRX|INV-RECONCILED-77|30000',
              'items': [],
            },
          },
        });
        return;
      }
      await reply(404, {'success': false, 'error': {'code': 'NOT_FOUND', 'message': 'Nope'}});
    });

    try {
      final credStore = InMemoryCredentialStore();
      await credStore.saveCredentials(StaffCredentials(
        terminalId: 'TERM-001',
        terminalCode: 'TERM-001',
        terminalName: 'HP Kasir',
        deviceUuid: 'uuid-r1',
        deviceToken: 'tok',
        deviceSecret: 'sec',
        tlsCertSha256: tls.sha256Hex,
        serverUrl: 'https://127.0.0.1:${server.port}',
        sessionToken: 'sess',
      ));

      final ctrl = StaffSessionController(
        credentialStore: credStore,
        localDb: StaffLocalDb.instance,
      );
      addTearDown(ctrl.dispose);
      await ctrl.initialize();
      // Gracefully learned staged next certificate pin
      expect(ctrl.credentials!.nextCertSha256, tlsNext.sha256Hex);

      await ctrl.addToCart(const StaffProduct(
        id: 1,
        code: 'P1',
        name: 'Charger 20W',
        category: 'Umum',
        baseUnit: 'Pcs',
        sellingPrice: 30000,
        stock: 10,
      ));
      expect(ctrl.canSubmitCheckout, isTrue);

      ctrl.setAmountPaid(50000);
      final fixedIdem = RequestSigner.generateIdempotencyKey();
      final failedDueToDrop = await ctrl.submitCheckout(overrideIdempotencyKey: fixedIdem);
      expect(failedDueToDrop.receipt, isNull);
      expect(failedDueToDrop.error, isNotNull);
      // Cart MUST still be intact and pending intent stored cleanly!
      expect(ctrl.cartItems.length, 1);
      final intents = await StaffLocalDb.instance.getPendingIntents();
      expect(intents.length, 1);
      expect(intents.first.idempotencyKey, committedIdemKey);

      // Simulate reconnect reconciliation -> discovers Admin ALREADY saved transaction -> caches receipt & clears cart!
      final recovered = await ctrl.reconcilePendingCheckoutIntents();
      expect(recovered, isNotNull);
      expect(recovered!.invoiceNumber, 'INV-RECONCILED-77');
      expect(ctrl.cartItems, isEmpty);
      expect(postCheckoutCalls, 1); // NEVER re-POSTed blindly!
      expect(ctrl.recentReceipts.first.invoiceNumber, 'INV-RECONCILED-77');
    } finally {
      await server.close(force: true);
    }
  });
}
