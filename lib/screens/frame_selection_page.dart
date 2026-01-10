import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'camera_page.dart';
import 'static_frame_template_page.dart'; 

class FrameSelectionPage extends StatelessWidget {
  const FrameSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND IMAGE
          Positioned.fill(
            child: Image.asset(
              "assets/images/bg.png",
              fit: BoxFit.cover,
            ),
          ),

          // 2. KONTEN UTAMA
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // HEADLINE (Tetap pakai Ambitsek biar konsisten sama judul lain)
                const OutlinedText(
                  text: "CHOOSE\nCATEGORY TEMPLATE",
                  fontFamily: 'Ambitsek',
                  fontSize: 65, 
                  textColor: Color(0xFFFFED00), // Kuning
                  outlineColor: Color(0xFFEF7D30), // Oranye
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  hasShadow: true,
                ),

                const SizedBox(height: 60), 

                // --- TOMBOL 1: STATIC FRAME (Pakai btn.png + Font Pixeland) ---
                ImageButton(
                  text: "Static Frame",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => StaticFrameTemplatePage()), 
                    );
                  },
                ),

                const SizedBox(height: 30),

                // --- TOMBOL 2: DIY FRAME (Pakai btn.png + Font Pixeland) ---
                ImageButton(
                  text: "DIY Frame",
                  onTap: () {
                    // Set Provider: Custom Mode
                    Provider.of<PhotoProvider>(context, listen: false).setFrameMode(
                      FrameMode.custom,
                      photoCount: 3, 
                    );
                    
                    // Langsung ke Camera Page
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CameraPage()),
                    );
                  },
                ),

                const SizedBox(height: 60),

                // TOMBOL BACK

              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET BARU: IMAGE BUTTON (Pakai btn.png)
// =========================================================
class ImageButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;

  const ImageButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  @override
  State<ImageButton> createState() => _ImageButtonState();
}

class _ImageButtonState extends State<ImageButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Transform.scale(
        scale: _isPressed ? 0.95 : 1.0, // Efek mengecil saat ditekan
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. GAMBAR TOMBOL (btn.png)
            Image.asset(
              "assets/images/btn.png", 
              width: 320, // Sesuaikan lebar tombol
              height: 90, // Sesuaikan tinggi tombol
              fit: BoxFit.contain, // Agar gambar tidak gepeng
            ),

            // 2. TEKS DI ATASNYA (Font Pixeland)
            // Menggunakan Padding bottom sedikit karena biasanya tombol pixel ada efek 3D di bawah
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0), 
              child: Text(
                widget.text,
                style: const TextStyle(
                  fontFamily: 'ambitsek', // <--- FONT BARU
                  fontSize: 25, // Sesuaikan ukuran font pixeland (biasanya butuh lebih besar)
                  color: Color.fromARGB(255, 255, 255, 255), // Sesuaikan dengan warna btn.png (biasanya teks hitam/putih)
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// WIDGET: OUTLINED TEXT (Helper untuk Judul)
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
                fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = outlineColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            color: textColor,
          ),
        ),
      ],
    );
  }
}