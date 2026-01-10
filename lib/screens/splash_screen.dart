import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND IMAGE
          Positioned.fill(
            child: Image.asset(
              "assets/images/splash_bg.png",
              fit: BoxFit.cover,
            ),
          ),

          // 2. KONTEN UTAMA
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start, 
              children: [
                
                // JARAK DARI ATAS
                const SizedBox(height: 150), 

                // JUDUL TEKS DENGAN SHADOW & SPACING
                const OutlinedText(
                  text: "",
                  fontFamily: 'Ambitsek', 
                  fontSize: 85, 
                  textColor: Color(0xFFFFED00),
                  outlineColor: Color(0xFFEF7D30),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5, // [BARU] Jarak antar huruf
                  hasShadow: true,    // [BARU] Aktifkan shadow
                ),


                
                // Jarak antara teks dan tombol
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
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = "";
                          });
                          _checkAccess();
                        },
                        child: const Text("Coba Lagi"),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET TEXT OUTLINE (DIPERBARUI DENGAN SHADOW & SPACING)
// =========================================================
class OutlinedText extends StatelessWidget {
  final String text;
  final String fontFamily;
  final double fontSize;
  final Color textColor;
  final Color outlineColor;
  final FontWeight fontWeight;
  final double letterSpacing; // [BARU] Parameter Spacing
  final bool hasShadow;       // [BARU] Parameter Shadow

  const OutlinedText({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.outlineColor,
    this.fontWeight = FontWeight.normal,
    this.letterSpacing = 0.0, // Default 0
    this.hasShadow = false,   // Default false
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 1: Shadow (Bayangan Hitam di paling belakang)
        if (hasShadow)
          Positioned(
            top: 4, // Geser bayangan ke bawah
            left: 4, // Geser bayangan ke kanan
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                letterSpacing: letterSpacing,
                height: 1.2,
                color: Colors.black.withOpacity(0.6), // Warna bayangan
              ),
            ),
          ),

        // Layer 2: Outline (Stroke)
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing, // [BARU] Terapkan spacing
            height: 1.2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10 // Sedikit dipertebal agar shadow outline terlihat jelas
              ..color = outlineColor,
          ),
        ),

        // Layer 3: Fill (Warna Utama Kuning)
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing, // [BARU] Terapkan spacing
            height: 1.2,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// WIDGET RETRO BUTTON (DIPERBARUI DENGAN SHADOW)
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
        // [BARU] Menambahkan BoxShadow di Container luar
        decoration: BoxDecoration(
          color: Colors.black, 
          border: Border.all(width: 4, color: Colors.black),
          boxShadow: _isPressed ? [] : [ // Shadow hilang saat ditekan
            const BoxShadow(
              color: Colors.black54, // Warna bayangan
              offset: Offset(6, 6),  // Arah bayangan (kanan bawah)
              blurRadius: 4,         // Tingkat blur
            )
          ],
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
              style: TextStyle(
                fontFamily: 'Ambitsek', 
                fontSize: 20,
                color: Colors.black,
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}