import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/services/hardware_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_and_scan_helpers.dart';
import '../../providers/staff_session_controller.dart';

enum ScannerErrorReason {
  permissionDenied,
  controllerInitializing,
  unsupported,
  genericError,
}

enum StaffScannerMode {
  single,
  continuous,
}

class ScannerScanFeedback {
  final String barcode;
  final String title;
  final String? subtitle;
  final bool success;

  const ScannerScanFeedback({
    required this.barcode,
    required this.title,
    this.subtitle,
    required this.success,
  });
}

class ScannerViewState {
  final bool isInitialized;
  final bool isRunning;
  final bool isStarting;
  final bool hasCameraPermission;
  final bool torchEnabled;
  final bool torchAvailable;
  final int? availableCameras;
  final ScannerErrorReason? errorReason;
  final String? errorMessage;

  const ScannerViewState({
    this.isInitialized = false,
    this.isRunning = false,
    this.isStarting = false,
    this.hasCameraPermission = true,
    this.torchEnabled = false,
    this.torchAvailable = false,
    this.availableCameras,
    this.errorReason,
    this.errorMessage,
  });

  ScannerViewState copyWith({
    bool? isInitialized,
    bool? isRunning,
    bool? isStarting,
    bool? hasCameraPermission,
    bool? torchEnabled,
    bool? torchAvailable,
    int? availableCameras,
    ScannerErrorReason? errorReason,
    bool clearError = false,
    String? errorMessage,
  }) {
    return ScannerViewState(
      isInitialized: isInitialized ?? this.isInitialized,
      isRunning: isRunning ?? this.isRunning,
      isStarting: isStarting ?? this.isStarting,
      hasCameraPermission: hasCameraPermission ?? this.hasCameraPermission,
      torchEnabled: torchEnabled ?? this.torchEnabled,
      torchAvailable: torchAvailable ?? this.torchAvailable,
      availableCameras: availableCameras ?? this.availableCameras,
      errorReason: clearError ? null : (errorReason ?? this.errorReason),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Abstract camera controller adapter so hardware CameraX lifecycle and widget tests share one path.
abstract class ScannerCameraAdapter extends ChangeNotifier {
  ScannerViewState get viewState;
  Stream<List<String>> get detectedBarcodes;
  bool get isDisposed;

  Future<void> start();
  Future<void> stop();
  Future<void> pause();
  Future<void> toggleTorch();
  Future<void> switchCamera();

  Widget buildPreview({
    required BuildContext context,
    required Widget Function(BuildContext context) placeholderBuilder,
    required Widget Function(BuildContext context, ScannerErrorReason reason, String message) errorBuilder,
  });

  @override
  Future<void> dispose();
}

/// Global serializer so rapid close -> reopen of the scanner never overlaps native CameraX teardown.
class _CameraSessionCoordinator {
  static Future<void> _pending = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() action) {
    final next = _pending.catchError((Object _) {}).then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}

class MobileScannerCameraAdapter extends ScannerCameraAdapter {
  final MobileScannerController _controller;
  final StreamController<List<String>> _barcodeStream = StreamController<List<String>>.broadcast();
  StreamSubscription<BarcodeCapture>? _rawSub;

  ScannerViewState _state = const ScannerViewState();
  bool _disposed = false;
  bool _startingNow = false;

  MobileScannerCameraAdapter({
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
    CameraFacing facing = CameraFacing.back,
  }) : _controller = MobileScannerController(
          autoStart: false,
          detectionSpeed: DetectionSpeed.normal,
          detectionTimeoutMs: 300,
          facing: facing,
          formats: formats,
        ) {
    _controller.addListener(_syncFromNative);
    _rawSub = _controller.barcodes.listen(
      (capture) {
        if (_disposed) return;
        final codes = capture.barcodes
            .map((b) => (b.rawValue ?? '').trim())
            .where((raw) => raw.isNotEmpty)
            .toList(growable: false);
        if (codes.isNotEmpty && !_barcodeStream.isClosed) {
          _barcodeStream.add(codes);
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  @override
  ScannerViewState get viewState => _state;

  @override
  Stream<List<String>> get detectedBarcodes => _barcodeStream.stream;

  @override
  bool get isDisposed => _disposed;

  ScannerErrorReason _mapErrorCode(MobileScannerErrorCode code) {
    switch (code) {
      case MobileScannerErrorCode.permissionDenied:
        return ScannerErrorReason.permissionDenied;
      case MobileScannerErrorCode.controllerInitializing:
        return ScannerErrorReason.controllerInitializing;
      case MobileScannerErrorCode.unsupported:
        return ScannerErrorReason.unsupported;
      default:
        return ScannerErrorReason.genericError;
    }
  }

  String _friendlyErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Izin kamera ditolak. Aktifkan izin kamera pada pengaturan perangkat lalu tekan Coba Lagi.';
      case MobileScannerErrorCode.unsupported:
        return 'Kamera atau fitur pemindai tidak didukung pada perangkat ini.';
      case MobileScannerErrorCode.controllerInitializing:
        return 'Kamera sedang bersiap. Tunggu sejenak lalu tekan Coba Lagi.';
      default:
        return error.errorDetails?.message?.isNotEmpty == true
            ? error.errorDetails!.message!
            : 'Kamera gagal diaktifkan. Periksa apakah kamera sedang dipakai aplikasi lain.';
    }
  }

  void _syncFromNative() {
    if (_disposed) return;
    final v = _controller.value;
    final err = v.error;
    _state = ScannerViewState(
      isInitialized: v.isInitialized,
      isRunning: v.isRunning,
      isStarting: v.isStarting || _startingNow,
      hasCameraPermission: v.hasCameraPermission,
      torchEnabled: v.torchState == TorchState.on || v.torchState == TorchState.auto,
      torchAvailable: v.torchState != TorchState.unavailable,
      availableCameras: v.availableCameras,
      errorReason: err != null ? _mapErrorCode(err.errorCode) : null,
      errorMessage: err != null ? _friendlyErrorMessage(err) : null,
    );
    notifyListeners();
  }

  @override
  Future<void> start() {
    return _CameraSessionCoordinator.run(() async {
      if (_disposed || _startingNow) return;
      if (_controller.value.isRunning) return;
      _startingNow = true;
      _state = _state.copyWith(isStarting: true, clearError: true);
      notifyListeners();
      try {
        await _controller.start();
        _syncFromNative();
      } on MobileScannerException catch (e) {
        if (_disposed) return;
        if (e.errorCode == MobileScannerErrorCode.controllerAlreadyInitialized) {
          _syncFromNative();
          return;
        }
        _state = _state.copyWith(
          isInitialized: true,
          isRunning: false,
          isStarting: false,
          hasCameraPermission: e.errorCode != MobileScannerErrorCode.permissionDenied,
          errorReason: _mapErrorCode(e.errorCode),
          errorMessage: _friendlyErrorMessage(e),
        );
        notifyListeners();
      } catch (e) {
        if (_disposed) return;
        _state = _state.copyWith(
          isInitialized: true,
          isRunning: false,
          isStarting: false,
          errorReason: ScannerErrorReason.genericError,
          errorMessage: 'Kamera tidak merespons ($e). Silakan coba lagi atau input kode manual.',
        );
        notifyListeners();
      } finally {
        _startingNow = false;
        if (!_disposed) {
          _syncFromNative();
        }
      }
    });
  }

  @override
  Future<void> stop() {
    return _CameraSessionCoordinator.run(() async {
      try {
        await _controller.stop().timeout(const Duration(milliseconds: 600));
      } catch (_) {}
      if (!_disposed) {
        _syncFromNative();
      }
    });
  }

  @override
  Future<void> pause() {
    return _CameraSessionCoordinator.run(() async {
      try {
        await _controller.pause().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      if (!_disposed) {
        _syncFromNative();
      }
    });
  }

  @override
  Future<void> toggleTorch() async {
    if (_disposed || !_state.isRunning) return;
    try {
      await _controller.toggleTorch();
      _syncFromNative();
    } catch (_) {}
  }

  @override
  Future<void> switchCamera() async {
    if (_disposed) return;
    try {
      await _controller.switchCamera();
      _syncFromNative();
    } catch (_) {}
  }

  @override
  Widget buildPreview({
    required BuildContext context,
    required Widget Function(BuildContext context) placeholderBuilder,
    required Widget Function(BuildContext context, ScannerErrorReason reason, String message) errorBuilder,
  }) {
    if (_disposed) return placeholderBuilder(context);
    return MobileScanner(
      controller: _controller,
      useAppLifecycleState: false,
      fit: BoxFit.cover,
      tapToFocus: true,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: (ctx, err) => errorBuilder(ctx, _mapErrorCode(err.errorCode), _friendlyErrorMessage(err)),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_syncFromNative);
    await _rawSub?.cancel();
    _rawSub = null;
    if (!_barcodeStream.isClosed) {
      await _barcodeStream.close();
    }
    super.dispose();
    await _CameraSessionCoordinator.run(() async {
      try {
        await _controller.stop().timeout(const Duration(milliseconds: 600));
      } catch (_) {}
      try {
        await _controller.dispose();
      } catch (_) {}
    });
  }
}

/// Reusable, lifecycle-safe, black-screen-proof Barcode & QR Scanner Screen.
///
/// Used for both:
/// - QR pairing ([StaffScannerMode.single], returning scanned String once via Navigator.pop)
/// - POS barcode scanning ([StaffScannerMode.continuous] or single-shot toggle)
class StaffBarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final StaffScannerMode initialMode;
  final bool allowModeToggle;
  final bool showCartSummary;
  final List<BarcodeFormat> formats;
  final bool Function(String code)? barcodeValidator;
  final String invalidCodeMessage;
  final Future<ScannerScanFeedback> Function(String code)? onContinuousScan;
  final ScannerCameraAdapter? adapterOverride;
  final String manualInputHint;

  const StaffBarcodeScannerScreen({
    super.key,
    required this.title,
    this.subtitle = 'Arahkan kode ke dalam kotak bidik kamera',
    this.initialMode = StaffScannerMode.continuous,
    this.allowModeToggle = true,
    this.showCartSummary = false,
    this.formats = const <BarcodeFormat>[],
    this.barcodeValidator,
    this.invalidCodeMessage = 'Format kode tidak valid.',
    this.onContinuousScan,
    this.adapterOverride,
    this.manualInputHint = 'Masukkan kode barcode / SKU secara manual',
  });

  @override
  State<StaffBarcodeScannerScreen> createState() => _StaffBarcodeScannerScreenState();
}

class _StaffBarcodeScannerScreenState extends State<StaffBarcodeScannerScreen>
    with WidgetsBindingObserver {
  late final ScannerCameraAdapter _adapter;
  late final bool _ownsAdapter;
  late StaffScannerMode _mode;

  final BarcodeScanGuard _scanGuard = BarcodeScanGuard(cooldown: const Duration(milliseconds: 1400));
  StreamSubscription<List<String>>? _barcodeSub;

  bool _isClosing = false;
  bool _popExecuted = false;
  bool _isProcessingDetection = false;
  bool _pausedByLifecycle = false;
  bool _manualDialogOpen = false;
  ScannerScanFeedback? _lastFeedback;
  String? _validationWarning;
  Timer? _warningTimer;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _ownsAdapter = widget.adapterOverride == null;
    _adapter = widget.adapterOverride ?? MobileScannerCameraAdapter(formats: widget.formats);
    WidgetsBinding.instance.addObserver(this);

    _barcodeSub = _adapter.detectedBarcodes.listen(
      _onBarcodesDetected,
      onError: (Object _) {},
      cancelOnError: false,
    );

    // Wait for first frame so MobileScanner widget attaches controller cleanly before start().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isClosing) {
        unawaited(_safeStartCamera());
      }
    });
  }

  Future<void> _safeStartCamera() async {
    if (_isClosing || !mounted || _adapter.isDisposed) return;
    await _adapter.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isClosing || _adapter.isDisposed) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pausedByLifecycle = true;
        unawaited(_adapter.stop());
      case AppLifecycleState.inactive:
        // Only stop during transient inactive if camera is NOT waiting for initial OS permission prompt.
        if (!_adapter.viewState.isStarting && _adapter.viewState.isRunning) {
          _pausedByLifecycle = true;
          unawaited(_adapter.pause());
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle ||
            (!_adapter.viewState.isRunning &&
                !_adapter.viewState.isStarting &&
                _adapter.viewState.errorReason != ScannerErrorReason.unsupported)) {
          _pausedByLifecycle = false;
          unawaited(_safeStartCamera());
        }
    }
  }

  void _showTransientWarning(String message) {
    _warningTimer?.cancel();
    if (!mounted) return;
    setState(() => _validationWarning = message);
    _warningTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _validationWarning = null);
      }
    });
  }

  Future<void> _onBarcodesDetected(List<String> codes) async {
    if (_isClosing || _popExecuted || !mounted || _manualDialogOpen) return;
    for (final raw in codes) {
      final clean = raw.trim();
      if (clean.isEmpty) continue;

      if (widget.barcodeValidator != null && !widget.barcodeValidator!(clean)) {
        if (_scanGuard.shouldAccept('__invalid__:$clean')) {
          unawaited(HardwareFeedback.playErrorFeedback());
          _showTransientWarning(widget.invalidCodeMessage);
        }
        continue;
      }

      if (_mode == StaffScannerMode.single) {
        if (_isClosing || _popExecuted) return;
        unawaited(HardwareFeedback.playSuccessBeep());
        await _closeSafely(result: clean);
        return;
      }

      // Continuous mode with cooldown & sequential lookup lock
      if (_isProcessingDetection) return;
      if (!_scanGuard.shouldAccept(clean)) return;

      _isProcessingDetection = true;
      try {
        if (widget.onContinuousScan != null) {
          final fb = await widget.onContinuousScan!(clean);
          if (!mounted || _isClosing) return;
          if (fb.success) {
            unawaited(HardwareFeedback.playSuccessBeep());
          } else {
            unawaited(HardwareFeedback.playErrorFeedback());
          }
          setState(() {
            _lastFeedback = fb;
            _validationWarning = null;
          });
        }
      } catch (e) {
        if (!mounted || _isClosing) return;
        unawaited(HardwareFeedback.playErrorFeedback());
        setState(() {
          _lastFeedback = ScannerScanFeedback(
            barcode: clean,
            title: 'Gagal memproses barcode',
            subtitle: e.toString(),
            success: false,
          );
        });
      } finally {
        _isProcessingDetection = false;
      }
      return;
    }
  }

  Future<void> _openManualInputDialog() async {
    if (_isClosing || !mounted) return;
    _manualDialogOpen = true;
    String? entered;
    try {
      entered = await showDialog<String>(
        context: context,
        builder: (_) => _ManualCodeInputDialog(hintText: widget.manualInputHint),
      );
    } finally {
      _manualDialogOpen = false;
    }
    if (entered == null || entered.isEmpty || !mounted || _isClosing) return;
    _scanGuard.reset();
    await _onBarcodesDetected([entered]);
  }

  /// Atomic single-exit route close: guarantees camera stops and Navigator.pop runs AT MOST ONCE.
  Future<void> _closeSafely({String? result}) async {
    if (_isClosing || _popExecuted) return;
    _isClosing = true;
    _warningTimer?.cancel();
    final sub = _barcodeSub;
    _barcodeSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (!_adapter.isDisposed) {
      await _adapter.stop();
    }

    if (!mounted || _popExecuted) return;
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    // Guard against double-pop or underflowing root route when route is already departing.
    if (nav.canPop() && (route == null || route.isCurrent)) {
      _popExecuted = true;
      nav.pop<String?>(result);
    }
  }

  @override
  void dispose() {
    _isClosing = true;
    _warningTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_barcodeSub?.cancel());
    _barcodeSub = null;
    if (_ownsAdapter) {
      unawaited(_adapter.dispose());
    }
    super.dispose();
  }

  Widget _buildLoadingFallback(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          const Text(
            'Menyiapkan Kamera Scanner...',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Pastikan izin kamera aktif. Anda juga dapat langsung mengetik kode barcode.',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _openManualInputDialog,
                icon: const Icon(Icons.keyboard_rounded, size: 18),
                label: const Text('Input Manual'),
              ),
              ElevatedButton.icon(
                onPressed: () => _closeSafely(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Kembali ke Kasir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorRecovery(BuildContext context, ScannerErrorReason reason, String message) {
    final isPerm = reason == ScannerErrorReason.permissionDenied;
    return Container(
      color: const Color(0xFF0F172A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPerm ? Icons.no_photography_rounded : Icons.videocam_off_rounded,
                  size: 36,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPerm ? 'Izin Kamera Diperlukan' : 'Kamera Tidak Dapat Dibuka',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _safeStartCamera,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Coba Lagi'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: _openManualInputDialog,
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: const Text('Input Barcode Manual'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  onPressed: () => _closeSafely(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Kembali ke Kasir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionCtrl = widget.showCartSummary
        ? context.watch<StaffSessionController?>()
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_closeSafely());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: ListenableBuilder(
          listenable: _adapter,
          builder: (context, _) {
            final view = _adapter.viewState;
            final hasError = view.errorReason != null;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (hasError)
                  _buildErrorRecovery(
                    context,
                    view.errorReason!,
                    view.errorMessage ?? 'Kamera gagal diakses.',
                  )
                else
                  _adapter.buildPreview(
                    context: context,
                    placeholderBuilder: _buildLoadingFallback,
                    errorBuilder: _buildErrorRecovery,
                  ),

                // Subtle reticle overlay only when camera is actively running without error
                if (!hasError && view.isInitialized)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 250,
                        height: 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _lastFeedback == null
                                ? const Color(0xFF34D399)
                                : (_lastFeedback!.success ? const Color(0xFF22C55E) : AppTheme.accentRed),
                            width: 2.6,
                          ),
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ),

                // Top Header Controls
                SafeArea(
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Kembali',
                              onPressed: () => _closeSafely(),
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    widget.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            if (!hasError && view.isRunning && view.torchAvailable)
                              IconButton(
                                tooltip: view.torchEnabled ? 'Matikan Lampu' : 'Nyalakan Lampu',
                                onPressed: () => _adapter.toggleTorch(),
                                icon: Icon(
                                  view.torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                  color: view.torchEnabled ? Colors.amberAccent : Colors.white,
                                ),
                              ),
                            if (!hasError && view.isRunning && (view.availableCameras ?? 2) >= 2)
                              IconButton(
                                tooltip: 'Ganti Kamera',
                                onPressed: () => _adapter.switchCamera(),
                                icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                              ),
                            IconButton(
                              tooltip: 'Ketik Barcode Manual',
                              onPressed: _openManualInputDialog,
                              icon: const Icon(Icons.keyboard_rounded, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      if (widget.allowModeToggle)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0F172A),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _modePill(
                                  label: 'Multi Scan',
                                  selected: _mode == StaffScannerMode.continuous,
                                  onTap: () => setState(() => _mode = StaffScannerMode.continuous),
                                ),
                                _modePill(
                                  label: '1x & Tutup',
                                  selected: _mode == StaffScannerMode.single,
                                  onTap: () => setState(() => _mode = StaffScannerMode.single),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (_validationWarning != null)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _validationWarning!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_lastFeedback != null || widget.showCartSummary)
                        _buildBottomFeedbackBar(sessionCtrl),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _modePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomFeedbackBar(StaffSessionController? sessionCtrl) {
    final fb = _lastFeedback;
    final totalItems = sessionCtrl?.cartItems.length ?? 0;
    final grandTotal = sessionCtrl?.grandTotal ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEB0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fb == null
              ? Colors.white24
              : (fb.success ? const Color(0xFF22C55E) : AppTheme.accentRed),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fb != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: (fb.success ? AppTheme.success : AppTheme.accentRed)
                        .withValues(alpha: 0.2),
                    child: Icon(
                      fb.success ? Icons.check_rounded : Icons.error_outline_rounded,
                      size: 18,
                      color: fb.success ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fb.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        if (fb.subtitle != null && fb.subtitle!.isNotEmpty)
                          Text(
                            fb.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (widget.showCartSummary)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalItems > 0 ? '$totalItems item di keranjang' : 'Keranjang masih kosong',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                      Text(
                        CurrencyHelper.format(grandTotal),
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _closeSafely(),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(totalItems > 0 ? 'Selesai Scan' : 'Kembali'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ManualCodeInputDialog extends StatefulWidget {
  final String hintText;

  const _ManualCodeInputDialog({required this.hintText});

  @override
  State<_ManualCodeInputDialog> createState() => _ManualCodeInputDialogState();
}

class _ManualCodeInputDialogState extends State<_ManualCodeInputDialog> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ketik Kode Barcode / SKU'),
      content: TextField(
        controller: _textCtrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.qr_code_rounded),
        ),
        onSubmitted: (val) => Navigator.pop(context, val.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _textCtrl.text.trim()),
          child: const Text('Proses'),
        ),
      ],
    );
  }
}
