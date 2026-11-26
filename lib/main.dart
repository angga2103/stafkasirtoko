import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/staff_session_controller.dart';
import 'ui/screens/pairing_screen.dart';
import 'ui/screens/pin_login_screen.dart';
import 'ui/screens/staff_pos_screen.dart';
import 'ui/screens/staff_shift_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const KasirTokoStaffApp());
}

class KasirTokoStaffApp extends StatelessWidget {
  final StaffSessionController? controllerOverride;

  const KasirTokoStaffApp({super.key, this.controllerOverride});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StaffSessionController>(
      create: (_) {
        if (controllerOverride != null) return controllerOverride!;
        return StaffSessionController()..initialize();
      },
      child: MaterialApp(
        title: 'KasirToko Staff',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const StaffRootRouter(),
      ),
    );
  }
}

class StaffRootRouter extends StatelessWidget {
  const StaffRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Provider.of<StaffSessionController>(context);
    switch (ctrl.connectionState) {
      case TerminalConnectionState.unpaired:
      case TerminalConnectionState.revoked:
        return const PairingScreen();
      case TerminalConnectionState.connectedNoSession:
        return const PinLoginScreen();
      case TerminalConnectionState.pairedOffline:
        if (ctrl.cashier == null) return const PinLoginScreen();
        return const StaffPosScreen();
      case TerminalConnectionState.shiftClosed:
        if (ctrl.cartItems.isEmpty) {
          return const StaffShiftScreen();
        }
        return const StaffPosScreen();
      case TerminalConnectionState.onlineReady:
        return const StaffPosScreen();
    }
  }
}
