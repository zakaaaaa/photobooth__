import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/app_config_provider.dart';
import '../providers/photo_provider.dart';
import '../services/api_service.dart';
import '../services/license_service.dart';
import '../services/config_service.dart';
import 'payment_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LicenseService _licenseService = LicenseService();
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isLicenseValid = false;
  String _errorMessage = "";
  bool _isHoveringClose = false;

  static final String _backendUrl = ConfigService().baseUrl;

  @override
  void initState() {
    super.initState();
    _preWarmConnection(); // ✅ Fire & forget — warm up sebelum user sampai frame selection
    _checkAccess();
  }

  /// Kirim request dummy ke backend supaya koneksi TCP & Supabase pool
  /// sudah hangat saat user membuka frame selection.
  void _preWarmConnection() async {
    try {
      await http
          .get(Uri.parse('$_backendUrl/api/frames?hwid=warmup'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Sembunyikan error pre-warm karena hanya untuk "pemanasan" koneksi
    }
  }

  Future<void> _checkAccess() async {
    await Future.delayed(const Duration(seconds: 2));

    final result = await _licenseService.checkLicense();
    if (!mounted) return;

    if (result['success'] == true) {
      final settings = (result['data'] as Map?)?['settings'] as Map<String, dynamic>?;
      if (settings != null && mounted) {
        Provider.of<AppConfigProvider>(context, listen: false)
            .applyBootstrap({'settings': settings, 'data': result['data']});
        Provider.of<PhotoProvider>(context, listen: false).setSessionDuration(
          (settings['session_duration_minutes'] as num?)?.toInt() ?? 5,
        );
      }

      final hwid = await _licenseService.getHardwareId();
      final bootstrap = await _apiService.fetchBootstrap(hwid);
      if (bootstrap != null && mounted) {
        Provider.of<AppConfigProvider>(context, listen: false)
            .applyBootstrap(bootstrap);
        final bootstrapSettings =
            bootstrap['settings'] as Map<String, dynamic>? ?? const {};
        Provider.of<PhotoProvider>(context, listen: false).setSessionDuration(
          (bootstrapSettings['session_duration_minutes'] as num?)?.toInt() ?? 5,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _isLicenseValid = true;
      } else {
        _isLicenseValid = false;
        _errorMessage = result['message'] ?? "Gagal memuat lisensi.";
      }
    });
  }

  void _onStartPressed() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const PaymentPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND
          Positioned.fill(
            child:
                Image.asset("assets/images/splash_bg.png", fit: BoxFit.cover),
          ),

          // 2. KONTEN UTAMA
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 150),

                // JUDUL
                const OutlinedText(
                  text: "",
                  fontFamily: 'Ambitsek',
                  fontSize: 85,
                  textColor: Color(0xFFFFED00),
                  outlineColor: Color(0xFFEF7D30),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  hasShadow: true,
                ),

                const SizedBox(height: 260),

                // LOGIKA TOMBOL
                if (_isLoading)
                  const CircularProgressIndicator(color: Color(0xFFFFED00))
                else if (_isLicenseValid)
                  RetroButton(onPressed: _onStartPressed)
                else
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black.withValues(alpha: 0.7),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = "";
                          });
                          _preWarmConnection();
                          _checkAccess();
                        },
                        child: const Text("Coba Lagi"),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // 3. HOVER CLOSE BUTTON (TOP CENTER)
          Positioned(
            top: 0,
            left: MediaQuery.of(context).size.width / 2 - 100,
            width: 200,
            height: 60,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHoveringClose = true),
              onExit: (_) => setState(() => _isHoveringClose = false),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isHoveringClose ? 1.0 : 0.0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.only(top: 8),
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        if (Platform.isWindows ||
                            Platform.isMacOS ||
                            Platform.isLinux) {
                          exit(0);
                        } else {
                          SystemNavigator.pop();
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.8),
                        hoverColor: Colors.red,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET: OUTLINED TEXT
// =========================================================
class OutlinedText extends StatelessWidget {
  final String text;
  final String fontFamily;
  final double fontSize;
  final Color textColor;
  final Color outlineColor;
  final FontWeight fontWeight;
  final double letterSpacing;
  final bool hasShadow;

  const OutlinedText({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.outlineColor,
    this.fontWeight = FontWeight.normal,
    this.letterSpacing = 0.0,
    this.hasShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (hasShadow)
          Positioned(
            top: 4,
            left: 4,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                letterSpacing: letterSpacing,
                height: 1.2,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
            height: 1.2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10
              ..color = outlineColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
            height: 1.2,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// WIDGET: RETRO BUTTON
// =========================================================
class RetroButton extends StatefulWidget {
  final VoidCallback onPressed;
  const RetroButton({super.key, required this.onPressed});

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: 220,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(width: 4, color: Colors.black),
          boxShadow: _isPressed
              ? []
              : [
                  const BoxShadow(
                      color: Colors.black54,
                      offset: Offset(6, 6),
                      blurRadius: 4)
                ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFC0C0C0),
            border: Border(
              top: BorderSide(
                  color: _isPressed ? Colors.black : Colors.white, width: 4),
              left: BorderSide(
                  color: _isPressed ? Colors.black : Colors.white, width: 4),
              right: BorderSide(
                  color: _isPressed ? Colors.white : Colors.black, width: 4),
              bottom: BorderSide(
                  color: _isPressed ? Colors.white : Colors.black, width: 4),
            ),
          ),
          child: const Center(
            child: Text(
              "Start",
              style: TextStyle(
                  fontFamily: 'Ambitsek',
                  fontSize: 20,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}
