import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart'; 
import 'package:photobooth_app/services/api_service.dart';

// ==========================================
// HALAMAN UTAMA: MENU PILIHAN PREVIEW
// ==========================================
class PreviewPrintPage extends StatefulWidget {
  const PreviewPrintPage({super.key});

  @override
  State<PreviewPrintPage> createState() => _PreviewPrintPageState();
}

class _PreviewPrintPageState extends State<PreviewPrintPage> {
  
  // [KONFIGURASI MANUAL] ATUR POSISI & UKURAN DI SINI
  final double previewTextTopMargin = 105.0; 
  final double previewTextLeftMargin = 0.0;
  final double previewTextSize = 40.0; 
  
  final double cardRowTopMargin = 30.0;
  final double cardWidth = 250.0; 
  final double cardHeight = 270.0;
  final double cardSpacing = 20.0;

  Future<void> _printPhoto(BuildContext context) async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please wait, rendering photo...")),
      );
      return;
    }

    try {
      final doc = pw.Document();
      // Epson SLD 500: 1205 x 1795 pixels (~300 DPI)
      final pdfFormat = PdfPageFormat(289.2, 430.8, marginAll: 0);
      final image = pw.MemoryImage(provider.finalImageBytes!);

      doc.addPage(pw.Page(
        pageFormat: pdfFormat,
        build: (pw.Context context) {
          return pw.FullPage(ignoreMargins: true, child: pw.Image(image, fit: pw.BoxFit.cover));
        },
      ));

      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'Photobooth_Print_${provider.sessionUuid}',
      );
    } catch (e) {
      debugPrint("Print Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final String qrUrl = "http://168.231.125.203/download/${provider.sessionUuid}"; 

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash_background.png',
            fit: BoxFit.cover,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3, 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: previewTextTopMargin, 
                          left: previewTextLeftMargin,
                          bottom: cardRowTopMargin
                        ),
                        child: Text(
                          "Preview",
                          style: TextStyle(
                            fontFamily: 'Ambitsek',
                            fontSize: previewTextSize,
                            color: Colors.white,
                            letterSpacing: 2.0,
                            shadows: const [Shadow(offset: Offset(3, 3), color: Colors.black)],
                          ),
                        ),
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          _buildCustomCard(
                            label: "Photo",
                            assetPath: "assets/images/photo.png", 
                            colorAccent: Colors.blueAccent,
                            onTap: () => _navigateTo(context, const _PhotoPreviewPage()),
                          ),
                          SizedBox(width: cardSpacing),
                          _buildCustomCard(
                            label: "GIF",
                            assetPath: "assets/images/gif.png", 
                            colorAccent: Colors.purpleAccent,
                            onTap: () => _navigateTo(context, const _GifPreviewPage()),
                          ),
                          SizedBox(width: cardSpacing),
                          _buildCustomCard(
                            label: "Video",
                            assetPath: "assets/images/vid.png", 
                            colorAccent: Colors.orangeAccent,
                            onTap: () => _navigateTo(context, const _VideoPreviewPage()),
                          ),
                        ],
                      ),
                      
                      const Spacer(),

                      Row(
                        children: [
                           RetroButton(
                             icon: Icons.home,
                             label: "HOME",
                             color: Colors.redAccent,
                             onTap: () {
                                Provider.of<PhotoProvider>(context, listen: false).reset();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const SplashScreen()), 
                                  (route) => false,
                                );
                             },
                           ),
                           
                           const SizedBox(width: 20),

                           RetroButton(
                             icon: Icons.print,
                             label: "PRINT NOW",
                             color: Colors.green,
                             onTap: () => _printPhoto(context),
                           ),
                        ],
                      )
                    ],
                  ),
                ),

                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const OutlinedText(
                        text: "SCAN\nTHE\nQR CODE",
                        fontFamily: 'Ambitsek',
                        fontSize: 32,
                        textColor: Color(0xFFFFED00),
                        outlineColor: Color(0xFFEF7D30),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        hasShadow: true,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0C0C0), 
                          border: Border.all(width: 4, color: Colors.black),
                          boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(8, 8), blurRadius: 0)],
                        ),
                        child: Container(
                          color: Colors.white, 
                          padding: const EdgeInsets.all(5),
                          child: QrImageView(
                            data: qrUrl,
                            version: QrVersions.auto,
                            size: 180.0,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildCustomCard({required String label, required String assetPath, required Color colorAccent, required VoidCallback onTap}) {
    return RetroInteractiveCard(
      label: label,
      assetPath: assetPath,
      colorAccent: colorAccent,
      width: cardWidth,   
      height: cardHeight, 
      onTap: onTap,
    );
  }
}

// =========================================================
// WIDGET RETRO INTERACTIVE CARD
// =========================================================
class RetroInteractiveCard extends StatefulWidget {
  final String label;
  final String assetPath;
  final Color colorAccent;
  final double width;
  final double height;
  final VoidCallback onTap;

  const RetroInteractiveCard({
    super.key, 
    required this.label, 
    required this.assetPath, 
    required this.colorAccent,
    required this.width,
    required this.height,
    required this.onTap
  });

  @override
  State<RetroInteractiveCard> createState() => _RetroInteractiveCardState();
}

class _RetroInteractiveCardState extends State<RetroInteractiveCard> {
  bool _isHovered = false;
  bool _isPressed = false;

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
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: widget.width,   
            height: widget.height, 
            decoration: BoxDecoration(
              color: const Color(0xFFC0C0C0), 
              border: Border.all(
                width: 3, 
                color: _isHovered ? widget.colorAccent : Colors.black
              ),
              boxShadow: _isPressed 
                ? [] 
                : [const BoxShadow(color: Colors.black54, offset: Offset(6, 6), blurRadius: 0)],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  color: const Color(0xFF0000AA),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Ambitsek',
                      color: Colors.white,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Image.asset(widget.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// WIDGET RETRO BUTTON
// =========================================================
class RetroButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const RetroButton({super.key, required this.icon, required this.label, required this.color, required this.onTap});

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isHovered = false;
  bool _isPressed = false;

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
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: widget.color,
              border: Border.all(width: 3, color: Colors.white),
              boxShadow: _isPressed ? [] : [const BoxShadow(color: Colors.black54, offset: Offset(4, 4))],
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.white),
                const SizedBox(width: 10),
                Text(widget.label, style: const TextStyle(fontFamily: 'Ambitsek', color: Colors.white, fontSize: 22, shadows: [Shadow(offset: Offset(2,2), color: Colors.black)])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// WIDGET OUTLINED TEXT
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

  const OutlinedText({super.key, required this.text, required this.fontFamily, required this.fontSize, required this.textColor, required this.outlineColor, this.fontWeight = FontWeight.normal, this.letterSpacing = 0.0, this.hasShadow = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (hasShadow)
          Positioned(top: 4, left: 4, child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2, color: Colors.black.withValues(alpha: 0.6)))),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2, foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = outlineColor)),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2, color: textColor)),
      ],
    );
  }
}

// =========================================================
// PAGE 1: PHOTO PREVIEW
// =========================================================
class _PhotoPreviewPage extends StatefulWidget {
  const _PhotoPreviewPage();
  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  final GlobalKey _globalKey = GlobalKey();
  List<int> _strip1Order = [];
  List<int> _strip2Order = [];
  bool _isUploaded = false; 

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final count = provider.photos.length;
    if (count == 3) {
      List<int> leftColumn = List.generate(count, (i) => i);
      List<int> rightColumn = List.from(leftColumn)..shuffle(math.Random());
      _strip1Order = [];
      for (int i = 0; i < count; i++) {
        _strip1Order.add(leftColumn[i]);
        _strip1Order.add(rightColumn[i]);
      }
    } else {
      _strip1Order = List.generate(count, (i) => i);
    }
    _strip2Order = List.from(_strip1Order)..shuffle(math.Random());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureAndUploadWidget();
    });
  }

  Future<void> _captureAndUploadWidget() async {
    if (_isUploaded) return;
    try {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      RenderRepaintBoundary? boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      ui.Image image = await boundary.toImage(pixelRatio: 4.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      
      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      provider.setFinalImageBytes(pngBytes);

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/final_strip_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes);
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      bool success = await apiService.uploadFinalResult(provider.sessionUuid, tempFile.path);
      
      if (success) {
        if(mounted) setState(() => _isUploaded = true);
      } 
      try { await tempFile.delete(); } catch (_) {}
    } catch (e) {
      print("❌ Error Capture/Upload: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Photo Result"), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
          return Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RepaintBoundary(
                    key: _globalKey, 
                    child: Container(
                      color: Colors.white,
                      child: _buildFinalFrame(provider, _strip1Order),
                    ),
                  ),
                  if (provider.selectedMode == FrameMode.custom) ...[
                    const SizedBox(width: 20),
                    _buildFinalFrame(provider, _strip2Order),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFinalFrame(PhotoProvider provider, List<int> orderIndices) {
    double width;
    double height;
    if (provider.selectedMode == FrameMode.custom) {
      if (provider.customLayout == CustomLayout.vertical) {
        width = 230.0; height = 515.0; 
      } else {
        width = 400.0; height = 515.0;
      }
    } else {
      width = 344.0; height = 515.0; 
    }
    return Container(
      width: width, height: height,
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        fit: StackFit.expand,
        children: [
           if (provider.selectedMode == FrameMode.custom)
            Container(
              decoration: BoxDecoration(
                color: provider.frameColor,
                image: provider.frameTexture != null ? DecorationImage(image: AssetImage(provider.frameTexture!), fit: BoxFit.cover) : null,
              ),
              child: _buildCustomContent(provider, orderIndices),
            )
          else 
            _buildStaticContent(provider, orderIndices),
          if (provider.selectedMode == FrameMode.static && provider.selectedFrameAsset != null)
             IgnorePointer(child: Image.asset(provider.selectedFrameAsset!, fit: BoxFit.contain, width: width)),
          
          // [REVISI] STICKERS DIRENDER DI SINI (POSISI & ROTASI)
          ...provider.stickers.map((s) => Positioned(
            left: 0, top: 0,
            child: Transform.rotate(
              angle: s.rotation,
              child: Container(
                alignment: Alignment.topLeft,
                child: Image.asset(s.assetPath, width: width, height: height, fit: BoxFit.contain),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCustomContent(PhotoProvider provider, List<int> indices) {
    final photos = indices.map((i) => i < provider.photos.length ? provider.photos[i].imageData : Uint8List(0)).toList();
    
    // [REVISI] CORNER RADIUS DI SINI (15.0)
    final double radius = 15.0; 

    if (provider.customLayout == CustomLayout.vertical) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: photos.map((img) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), 
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.memory(img, width: 150, height: 95, fit: BoxFit.cover)))).toList()));
    } else {
      return Center(child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: photos.map((img) => 
        ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.memory(img, width: 160, height: 140, fit: BoxFit.cover))).toList()));
    }
  }

  Widget _buildStaticContent(PhotoProvider provider, List<int> indices) {
    final photos = indices.map((i) => i < provider.photos.length ? provider.photos[i].imageData : Uint8List(0)).toList();
    final layout = provider.selectedLayout;
    return Container(
      padding: EdgeInsets.fromLTRB(layout.leftPadding, layout.topPadding, layout.rightPadding, layout.bottomPadding),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          crossAxisSpacing: layout.horizontalSpacing, 
          mainAxisSpacing: layout.verticalSpacing, 
          childAspectRatio: layout.childAspectRatio
        ),
        itemCount: photos.length, 
        itemBuilder: (context, index) => Image.memory(photos[index], fit: BoxFit.cover),
      ),
    );
  }
}

// =========================================================
// PAGE 2: GIF PREVIEW
// =========================================================
class _GifPreviewPage extends StatefulWidget {
  const _GifPreviewPage();
  @override
  State<_GifPreviewPage> createState() => _GifPreviewPageState();
}

class _GifPreviewPageState extends State<_GifPreviewPage> {
  int _index = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      if (provider.photos.isNotEmpty) {
        if(mounted) setState(() => _index = (_index + 1) % provider.photos.length);
      }
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("GIF Preview"), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
          if (provider.photos.isEmpty) return const Center(child: Text("No Photos", style: TextStyle(color: Colors.white)));
          return Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.memory(
                  provider.photos[_index].imageData,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =========================================================
// PAGE 3: VIDEO PREVIEW
// =========================================================
class _VideoPreviewPage extends StatefulWidget {
  const _VideoPreviewPage({super.key});
  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  Timer? _timer;
  List<int> _currentDisplayIndices = [];
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _updateSlideshow();
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted) {
        setState(() {
          _tick++;
          _updateSlideshow();
        });
      }
    });
  }

  void _updateSlideshow() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    int count = provider.photos.length;
    if (count == 0) return;
    if (count == 3) {
      _currentDisplayIndices = [];
      for (int i = 0; i < 6; i++) {
        int photoIndex = (i + _tick) % count; 
        _currentDisplayIndices.add(photoIndex);
      }
    } else {
      _currentDisplayIndices = List.generate(count, (i) => i);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Video Preview"), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
           return Center(
             child: Transform.scale(
               scale: 0.85,
               child: _VideoFrameBuilder(provider: provider, orderIndices: _currentDisplayIndices), 
             ),
           );
        },
      ),
    );
  }
}

class _VideoFrameBuilder extends StatelessWidget {
  final PhotoProvider provider;
  final List<int> orderIndices;
  const _VideoFrameBuilder({required this.provider, required this.orderIndices});

  @override
  Widget build(BuildContext context) {
    double width;
    double height;
    if (provider.selectedMode == FrameMode.custom) {
      if (provider.customLayout == CustomLayout.vertical) {
        width = 230.0; height = 515.0; 
      } else {
        width = 400.0; height = 515.0;
      }
    } else {
      width = 344.0; height = 515.0; 
    }
    return Container(
      width: width, height: height,
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        fit: StackFit.expand,
        children: [
           if (provider.selectedMode == FrameMode.custom)
            Container(
              decoration: BoxDecoration(
                color: provider.frameColor,
                image: provider.frameTexture != null ? DecorationImage(image: AssetImage(provider.frameTexture!), fit: BoxFit.cover) : null,
              ),
              child: _buildCustomContent(orderIndices),
            )
          else 
            _buildStaticContent(orderIndices), 
          
          if (provider.selectedMode == FrameMode.static && provider.selectedFrameAsset != null)
             IgnorePointer(child: Image.asset(provider.selectedFrameAsset!, fit: BoxFit.contain, width: width)),
          
          // [REVISI] STIKER DI VIDEO JUGA HARUS MUNCUL
          ...provider.stickers.map((s) => Positioned(
            left: 0, top: 0,
            child: Transform.rotate(
              angle: s.rotation,
              child: Container(
                alignment: Alignment.topLeft,
                child: Image.asset(s.assetPath, width: width, height: height, fit: BoxFit.contain),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCustomContent(List<int> indices) {
    final photos = indices.map((i) {
      return (i < provider.photos.length) ? provider.photos[i].imageData : Uint8List(0);
    }).toList();

    // [REVISI] CORNER RADIUS DI SINI (15.0)
    final double radius = 15.0; 

    if (provider.customLayout == CustomLayout.vertical) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: photos.map((img) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), 
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.memory(img, width: 150, height: 95, fit: BoxFit.cover)))).toList()));
    } else {
      return Center(child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: photos.map((img) => 
        ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.memory(img, width: 160, height: 140, fit: BoxFit.cover))).toList()));
    }
  }

  Widget _buildStaticContent(List<int> indices) {
    final photos = indices.map((i) {
      return (i < provider.photos.length) ? provider.photos[i].imageData : Uint8List(0);
    }).toList();

    final layout = provider.selectedLayout;
    
    return Container(
      padding: EdgeInsets.fromLTRB(layout.leftPadding, layout.topPadding, layout.rightPadding, layout.bottomPadding),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          crossAxisSpacing: layout.horizontalSpacing, 
          mainAxisSpacing: layout.verticalSpacing, 
          childAspectRatio: layout.childAspectRatio
        ),
        itemCount: indices.length, 
        itemBuilder: (context, index) {
          if (photos[index].isEmpty) return Container(color: Colors.grey);
          return Image.memory(photos[index], fit: BoxFit.cover);
        },
      ),
    );
  }
}