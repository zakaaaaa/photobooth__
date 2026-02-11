import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'camera_page.dart'; 

// Model Data Frame
class FrameTemplate {
  final String id;
  final String assetPath;
  final int photoCount;
  final FrameLayout layout;
  
  // Property ukuran output (Resolusi hasil akhir)
  final double outputWidth;
  final double outputHeight;

  FrameTemplate({
    required this.id,
    required this.assetPath,
    required this.photoCount,
    required this.layout,
    // Default ukuran Strip kecil jika tidak diisi
    this.outputWidth = 344.0, 
    this.outputHeight = 515.0,
  });
}

class StaticFrameTemplatePage extends StatelessWidget {
  StaticFrameTemplatePage({super.key});

  // DATA TEMPLATES
  final List<FrameTemplate> templates = [
    // FRAME 1 (Strip)
    FrameTemplate(
      id: 'frame_1',
      assetPath: 'assets/frames/frame_01.png', 
      photoCount: 3, 
      layout: const FrameLayout(
        topPadding: 92,
        bottomPadding: 18,
        leftPadding: 15,
        rightPadding: 15,
        horizontalSpacing: 35,
        verticalSpacing: 26,
        childAspectRatio: 1.2,
      ),
    ),
    // FRAME 2 (Strip)
    FrameTemplate(
      id: 'frame_2',
      assetPath: 'assets/frames/frame_02.png', 
      photoCount: 4, 
      layout: const FrameLayout(
        topPadding: 25,
        leftPadding: 10,
        rightPadding: 5,
        bottomPadding: 40,
        horizontalSpacing: 5,
        verticalSpacing: 13,
        childAspectRatio: 1.0,
      ),
    ),
    // FRAME 3 (Strip)
    FrameTemplate(
      id: 'frame_3',
      assetPath: 'assets/frames/frame_03.png', 
      photoCount: 3, 
      layout: const FrameLayout(
        topPadding: 59,
        bottomPadding: 59,
        leftPadding: 10,
        rightPadding: 10,
        horizontalSpacing: 20,
        verticalSpacing: 10,
        childAspectRatio: 1.2,
      ),
    ),
    
    // ===============================================
    // FRAME 4 (TAROT) - UKURAN BESAR 1080x1920
    // ===============================================
    FrameTemplate(
      id: 'frame_4',
      assetPath: 'assets/frames/frame_04.png', 
      photoCount: 4, 
      layout: const FrameLayout(
        topPadding: 35,
        leftPadding: 10,
        rightPadding: 5,
        bottomPadding: 40,
        horizontalSpacing: 5,
        verticalSpacing: 13,
        childAspectRatio: 1.0,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. BACKGROUND IMAGE
          Image.asset(
            'assets/images/splash_background.png',
            fit: BoxFit.cover,
          ),
          
          // 2. OVERLAY GELAP
          Container(color: Colors.black.withValues(alpha: 0.5)),

          // 3. KONTEN UTAMA
          Column(
            children: [
              // HEADER JUDUL
              const Padding(
                padding: EdgeInsets.only(top: 60, bottom: 20),
                child: OutlinedText(
                  text: "CHOOSE YOUR FRAME",
                  fontFamily: 'Ambitsek',
                  fontSize: 40,
                  textColor: Color(0xFFFFED00),
                  outlineColor: Color(0xFFEF7D30),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  hasShadow: true,
                ),
              ),

              // GRID FRAME
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, 
                      crossAxisSpacing: 20, 
                      mainAxisSpacing: 20, 
                      childAspectRatio: 0.55, // Rasio kartu di menu (agar terlihat memanjang)
                    ),
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return RetroFrameCard(template: template);
                    },
                  ),
                ),
              ),

              // TOMBOL BACK
              Padding(
                padding: const EdgeInsets.only(bottom: 40, top: 20),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Image.asset(
                    "assets/images/back.png",
                    width: 200,
                    height: 80,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET BARU: RETRO FRAME CARD
// =========================================================
class RetroFrameCard extends StatefulWidget {
  final FrameTemplate template;

  const RetroFrameCard({super.key, required this.template});

  @override
  State<RetroFrameCard> createState() => _RetroFrameCardState();
}

class _RetroFrameCardState extends State<RetroFrameCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _handleSelection();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFC0C0C0), 
              border: Border.all(width: 3, color: Colors.black),
              boxShadow: _isPressed 
                  ? [] 
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.6), offset: const Offset(6, 6), blurRadius: 0)],
            ),
            child: Column(
              children: [
                // HEADER BIRU
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: const Color(0xFF0000AA),
                  child: Text(
                    widget.template.id.toUpperCase().replaceAll('_', ' '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Ambitsek',
                      color: Colors.white,
                      fontSize: 16,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                // GAMBAR FRAME (PREVIEW KECIL)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Image.asset(
                      widget.template.assetPath,
                      fit: BoxFit.contain, // Agar seluruh frame terlihat dalam kartu
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSelection() {
    // 1. Simpan Data ke Provider (TERMASUK UKURAN 1080x1920)
    Provider.of<PhotoProvider>(context, listen: false).setFrameMode(
      FrameMode.static,
      photoCount: widget.template.photoCount,
      frameAsset: widget.template.assetPath,
      layout: widget.template.layout,
      // Kirim ukuran custom agar PreviewPage merender ukuran besar
      customWidth: widget.template.outputWidth,
      customHeight: widget.template.outputHeight,
    );

    // 2. NAVIGASI KE CAMERA PAGE
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
  }
}

// =========================================================
// WIDGET HELPER: OUTLINED TEXT
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