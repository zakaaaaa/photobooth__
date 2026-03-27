import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/services/api_service.dart';

// ── Global navigator key — dipakai untuk navigasi dari mana saja ──
// tanpa bergantung pada BuildContext yang mungkin sudah tidak valid
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    // Set onSessionExpired setelah provider tersedia
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSessionExpiredCallback();
    });
  }

  void _setupSessionExpiredCallback() {
    // Ambil provider via navigatorKey context — selalu valid
    final context = navigatorKey.currentContext;
    if (context == null) return;

    Provider.of<PhotoProvider>(context, listen: false).onSessionExpired = () {
      // Gunakan navigatorKey — tidak bergantung pada context screen manapun
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      // Reset provider
      final providerCtx = navigatorKey.currentContext;
      if (providerCtx != null) {
        Provider.of<PhotoProvider>(providerCtx, listen: false).reset();
      }

      // Navigasi ke SplashScreen, hapus semua route
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
        navigatorKey: navigatorKey, // ← global key
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'Poppins',
        ),
        builder: (context, child) {
          // Setup callback di sini karena provider sudah tersedia di context ini
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _setupSessionExpiredCallback();
          });
          return _TimerBadgeOverlay(child: child!);
        },
        home: const SplashScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Hanya timer badge visual — navigasi ditangani via navigatorKey
// ─────────────────────────────────────────────────────────
class _TimerBadgeOverlay extends StatelessWidget {
  final Widget child;
  const _TimerBadgeOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<PhotoProvider>(
          builder: (context, provider, _) {
            if (!provider.isSessionActive) return const SizedBox.shrink();

            final progress = provider.timerProgress;
            final color    = provider.timerColor;
            final timeStr  = provider.timerString;
            final isUrgent = progress < 0.2;

            return Positioned(
              top: 20,
              right: 24,
              child: SafeArea(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(isUrgent ? 0.88 : 0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: color.withOpacity(0.8),
                      width: isUrgent ? 1.5 : 1.0,
                    ),
                    boxShadow: isUrgent
                        ? [BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 14,
                            spreadRadius: 2,
                          )]
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
                          backgroundColor: Colors.white.withOpacity(0.15),
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
    );
  }
}