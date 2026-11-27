import 'package:flutter/services.dart';

/// Native beep + haptic feedback helper backed by `MainActivity.kt` Hardware Channel.
/// Safely no-ops on platforms/tests where the MethodChannel is unavailable.
class HardwareFeedback {
  static const MethodChannel _hardwareChannel = MethodChannel('com.kasirtoko.app.stafkasirtoko/hardware');

  static bool soundEnabled = true;
  static bool hapticEnabled = true;

  static Future<void> playSuccessBeep({int durationMs = 110}) async {
    if (hapticEnabled) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
    if (soundEnabled) {
      try {
        await _hardwareChannel.invokeMethod<bool>('playBeep', {'durationMs': durationMs});
      } catch (_) {}
    }
  }

  static Future<void> playErrorFeedback({int durationMs = 220}) async {
    if (hapticEnabled) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
    if (soundEnabled) {
      try {
        await _hardwareChannel.invokeMethod<bool>('playBeep', {'durationMs': durationMs});
      } catch (_) {}
    }
  }
}
