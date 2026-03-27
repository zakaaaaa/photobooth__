import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/license_service.dart';
import 'payment_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LicenseService _licenseService = LicenseService();

  bool _isLoading = true;
  bool _isLicenseValid = false;
  String _errorMessage = "";

  String _hwid = "";
  bool _showDebugPanel = false;
  bool _hwidCopied = false;
  bool _isHoveringClose = false;

  static const String _backendUrl = 'http://168.231.125.203:8181';

  @override
  void initState() {
    super.initState();
    _preWarmConnection(); // ✅ Fire & forget — warm up sebelum user sampai frame selection
    _checkAccess();
  }

  /// Kirim request dummy ke backend supaya koneksi TCP & Supabase pool
  /// sudah hangat saat user membuka frame selection.
  void _preWarmConnection() {
    http
        .get(Uri.parse('$_backendUrl/api/frames?hwid=warmup'))
        .timeout(const Duration(seconds: 10))
        .catchError((_) {});
  }

  Future<void> _checkAccess() async {
    final hwid = await _licenseService.getHardwareId();

    setState(() {
      _hwid = hwid;
    });

    print("🔑 HWID DETECTED: $hwid");

    await Future.delayed(const Duration(seconds: 2));

    final result = await _licenseService.checkLicense();
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

  Future<void> _copyHwid() async {
    await Clipboard.setData(ClipboardData(text: _hwid));
    setState(() => _hwidCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _hwidCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND
          Positioned.fill(
            child: Image.asset("assets/images/splash_bg.png", fit: BoxFit.cover),
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
                        color: Colors.black.withOpacity(0.7),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          setState(() { _isLoading = true; _errorMessage = ""; });
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

          // 3. DEBUG PANEL — Long press pojok kiri atas untuk toggle
          Positioned(
            top: 0, left: 0,
            child: GestureDetector(
              onLongPress: () => setState(() => _showDebugPanel = !_showDebugPanel),
              child: Container(
                width: 60, height: 60,
                color: Colors.transparent,
              ),
            ),
          ),

          // 4. DEBUG INFO PANEL
          if (_showDebugPanel)
            Positioned(
              top: 20, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow.withOpacity(0.5), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.bug_report, color: Colors.yellow, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          "DEBUG INFO",
                          style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _showDebugPanel = false),
                          child: const Icon(Icons.close, color: Colors.white54, size: 16),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 16),

                    // HWID
                    const Text("HARDWARE ID (HWID):", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _hwid.isEmpty ? "Memuat..." : _hwid,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _hwid.isNotEmpty ? _copyHwid : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _hwidCopied ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _hwidCopied ? Colors.greenAccent : Colors.white24,
                              ),
                            ),
                            child: Text(
                              _hwidCopied ? "✓ Copied!" : "Copy",
                              style: TextStyle(
                                color: _hwidCopied ? Colors.greenAccent : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Status
                    Row(
                      children: [
                        const Text("STATUS: ", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isLoading
                                ? Colors.orange.withOpacity(0.2)
                                : _isLicenseValid
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isLoading ? "CHECKING..." : _isLicenseValid ? "LICENSED ✓" : "UNLICENSED ✗",
                            style: TextStyle(
                              color: _isLoading ? Colors.orange : _isLicenseValid ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Server
                    const Text("SERVER:", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    const Text(
                      "http://168.231.125.203:8181/api",
                      style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontFamily: 'monospace'),
                    ),

                    const SizedBox(height: 8),

                    // Pre-warm indicator
                    const Text("PRE-WARM:", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    const Text(
                      "✅ Connection warmed on startup",
                      style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),

          // 5. HOVER CLOSE BUTTON (TOP CENTER)
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
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () {
                        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                          exit(0);
                        } else {
                          SystemNavigator.pop();
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.8),
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
            top: 4, left: 4,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily, fontSize: fontSize,
                fontWeight: fontWeight, letterSpacing: letterSpacing,
                height: 1.2, color: Colors.black.withOpacity(0.6),
              ),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize,
            fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = outlineColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize,
            fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
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
      onTapUp: (_) { setState(() => _isPressed = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: 220, height: 70,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(width: 4, color: Colors.black),
          boxShadow: _isPressed ? [] : [const BoxShadow(color: Colors.black54, offset: Offset(6, 6), blurRadius: 4)],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFC0C0C0),
            border: Border(
              top: BorderSide(color: _isPressed ? Colors.black : Colors.white, width: 4),
              left: BorderSide(color: _isPressed ? Colors.black : Colors.white, width: 4),
              right: BorderSide(color: _isPressed ? Colors.white : Colors.black, width: 4),
              bottom: BorderSide(color: _isPressed ? Colors.white : Colors.black, width: 4),
            ),
          ),
          child: const Center(
            child: Text(
              "Start",
              style: TextStyle(fontFamily: 'Ambitsek', fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}