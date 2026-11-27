import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:stafkasirtoko/core/network/lan_http_client.dart';
import 'package:stafkasirtoko/core/security/secure_credential_store.dart';
import 'package:stafkasirtoko/data/local/staff_local_db.dart';
import 'package:stafkasirtoko/providers/staff_session_controller.dart';
import 'package:stafkasirtoko/ui/screens/connection_and_receipts_screen.dart';
import 'package:stafkasirtoko/ui/screens/pin_login_screen.dart';
import 'package:stafkasirtoko/ui/screens/staff_pos_screen.dart';

class _SessionLimitHttpClient extends LanHttpClient {
  _SessionLimitHttpClient({required super.credentialStore});

  @override
  Future<Map<String, dynamic>> checkHealth({
    required String baseUrl,
    String? expectedSha256,
    String? expectedShortPin,
  }) async =>
      {
        'server_time_ms': DateTime.now().millisecondsSinceEpoch,
        'store_name': 'Toko Session Policy',
        'server_id': 'srv-limit-test',
        'network_mode': 'primary_router',
      };

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool requireSession = true,
    String? idempotencyKey,
    Duration? timeout,
  }) async {
    final path = Uri.parse('https://localhost$pathAndQuery').path;
    if (path == '/api/v1/auth/cashiers') {
      return {
        'success': true,
        'data': {
          'cashiers': [
            {
              'id': 3,
              'name': 'Kasir 1',
              'username': 'kasir1',
              'role': 'cashier',
              'role_label': 'Kasir',
              'permissions': {'access_pos': true},
            },
          ],
        },
      };
    }
    if (path == '/api/v1/auth/pin-login') {
      throw const LanApiException(
        statusCode: 409,
        errorCode: 'SESSION_LIMIT_EXCEEDED',
        message: 'Akun "Kasir 1" sudah mencapai batas maksimum 1 perangkat aktif.',
      );
    }
    return {'success': true, 'data': {}};
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('PinLoginScreen renders 409 SESSION_LIMIT_EXCEEDED error & ConnectionAndReceiptsScreen renders network diagnostics without overflow',
      (tester) async {
    await tester.runAsync(() async => await StaffLocalDb.instance.openTestDatabase());
    final credStore = InMemoryCredentialStore();
    await credStore.saveCredentials(const StaffCredentials(
      terminalId: 'TERM-01',
      terminalCode: 'T01',
      terminalName: 'HP Kasir 2',
      deviceUuid: 'u2',
      deviceToken: 'tok',
      deviceSecret: 'sec',
      tlsCertSha256: 'aabbccddeeff11223344',
      serverUrl: 'https://192.168.43.1:8443',
      serverId: 'srv-limit-test',
      primaryServerUrl: 'https://192.168.1.50:8443',
      backupServerUrl: 'https://192.168.43.1:8443',
    ));

    final fakeHttp = _SessionLimitHttpClient(credentialStore: credStore);
    final ctrl = StaffSessionController(
      credentialStore: credStore,
      localDb: StaffLocalDb.instance,
      httpClient: fakeHttp,
      enableLanDiscovery: false,
    );
    addTearDown(() async {
      await tester.runAsync(() async {
        ctrl.dispose();
        await StaffLocalDb.instance.close();
      });
    });

    await tester.runAsync(() async {
      await ctrl.initialize();
      final ok = await ctrl.loginWithPin(userId: 3, pin: '1111');
      expect(ok, isFalse);
    });

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StaffSessionController>.value(
          value: ctrl,
          child: const PinLoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('batas maksimum 1 perangkat aktif'), findsOneWidget);
    expect(ctrl.connectionState, isNot(TerminalConnectionState.revoked));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StaffSessionController>.value(
          value: ctrl,
          child: const ConnectionAndReceiptsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('srv-limit-test'), findsOneWidget);
    expect(find.textContaining('Ganti IP Manual'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StaffSessionController>.value(
          value: ctrl,
          child: const StaffPosScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
