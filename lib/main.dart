import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/diagnostic_page.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/services/api_service.dart';
import 'package:photobooth_app/services/config_service.dart';

// ── Global navigator key — dipakai untuk navigasi dari mana saja ──
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Backend Auto-Discovery ──
  // Await sebentar (max 2-3 detik) agar aplikasi punya BASE_URL yang benar saat pertama dibuka
  await ConfigService().init();

  // ── Fullscreen setup ──
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();

      // INITIAL: Mulai sebagai window normal dulu agar jika crash tidak mengunci layar
      WindowOptions windowOptions = const WindowOptions(
        fullScreen: false,
        alwaysOnTop: false,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();

        // TUNGGU 5 DETIK sebelum paksa fullscreen & alwaysOnTop
        // Ini memberi waktu bagi OS untuk "bernapas" jika ada error di awal
        Future.delayed(const Duration(seconds: 5), () async {
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setSkipTaskbar(true);
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        });
      });
    } catch (e) {
      debugPrint('WindowManager Init Error: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSessionExpiredCallback();
    });
  }

  void _setupSessionExpiredCallback() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    Provider.of<PhotoProvider>(context, listen: false).onSessionExpired = () {
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      final providerCtx = navigatorKey.currentContext;
      if (providerCtx != null) {
        Provider.of<PhotoProvider>(providerCtx, listen: false).reset();
      }

      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );

      debugPrint('⏱ Navigasi ke SplashScreen via navigatorKey ✅');
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PhotoProvider()),
        Provider(create: (_) => ApiService()),
      ],
      child: MaterialApp(
        title: 'Photobooth App',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'Poppins',
        ),
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _setupSessionExpiredCallback();
          });
          return _AppOverlay(child: child!);
        },
        home: const DiagnosticPage(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// App overlay — gabungan timer badge + hidden close button
// ─────────────────────────────────────────────────────────
class _AppOverlay extends StatelessWidget {
  final Widget child;
  const _AppOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        // 🚨 EMERGENCY EXIT: ESC + LEFT SHIFT
        final isEsc = event.logicalKey == LogicalKeyboardKey.escape;
        final isShift = HardwareKeyboard.instance.isShiftPressed;

        if (isEsc && isShift) {
          debugPrint("🆘 EMERGENCY EXIT TRIGGERED!");
          exit(0); // Force kill process
        }
      },
      child: Stack(
        children: [
          child,
          // ... rest of the overlay

          // ── Hidden close button (top center, hold 3 detik untuk close) ──
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _HiddenCloseButton()),
          ),

          // ── Timer badge ──
          Consumer<PhotoProvider>(
            builder: (context, provider, _) {
              if (!provider.isSessionActive) return const SizedBox.shrink();

              final progress = provider.timerProgress;
              final color = provider.timerColor;
              final timeStr = provider.timerString;
              final isUrgent = progress < 0.2;

              return Positioned(
                top: 20,
                right: 24,
                child: SafeArea(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black
                          .withValues(alpha: isUrgent ? 0.88 : 0.65),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: color.withValues(alpha: 0.8),
                        width: isUrgent ? 1.5 : 1.0,
                      ),
                      boxShadow: isUrgent
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.35),
                                blurRadius: 14,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 2.5,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Hidden close button — hold 3 detik di tengah atas untuk exit
// ─────────────────────────────────────────────────────────
class _HiddenCloseButton extends StatefulWidget {
  const _HiddenCloseButton();

  @override
  State<_HiddenCloseButton> createState() => _HiddenCloseButtonState();
}

class _HiddenCloseButtonState extends State<_HiddenCloseButton> {
  bool _isHolding = false;
  double _holdProgress = 0.0;
  Timer? _holdTimer;
  static const _holdDuration = Duration(seconds: 3);
  static const _tickInterval = Duration(milliseconds: 50);

  void _onLongPressStart(LongPressStartDetails _) {
    setState(() {
      _isHolding = true;
      _holdProgress = 0.0;
    });

    final totalTicks =
        _holdDuration.inMilliseconds / _tickInterval.inMilliseconds;

    _holdTimer = Timer.periodic(_tickInterval, (timer) {
      setState(() {
        _holdProgress += 1.0 / totalTicks;
      });

      if (_holdProgress >= 1.0) {
        timer.cancel();
        _closeApp();
      }
    });
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _cancelHold();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (mounted) {
      setState(() {
        _isHolding = false;
        _holdProgress = 0.0;
      });
    }
  }

  Future<void> _closeApp() async {
    await windowManager.setFullScreen(false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.close();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _cancelHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        height: 30,
        decoration: BoxDecoration(
          color: _isHolding
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: _isHolding
            ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 80,
                    height: 3,
                    child: LinearProgressIndicator(
                      value: _holdProgress,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              )
            : null,
      ),
    );
  }
}
