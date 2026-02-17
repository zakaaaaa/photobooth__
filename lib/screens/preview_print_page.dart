import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart'; 
import 'package:qr_flutter/qr_flutter.dart'; // [WAJIB] Library QR Code

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
  
  // [KONFIGURASI TATA LETAK]
  final double previewTextTopMargin = 80.0; 
  final double previewTextLeftMargin = 0.0;
  final double previewTextSize = 40.0; 
  
  final double cardRowTopMargin = 20.0;
  final double cardWidth = 220.0; 
  final double cardHeight = 250.0;
  final double cardSpacing = 20.0;

  // [KONFIGURASI URL WEBSITE ANDA]
  final String _websiteBaseUrl = "http://168.231.125.203:8080/download"; 

  // =========================================================
  // FITUR 1: ROBUST PRINT (Direct Print -> Fallback Dialog)
  // =========================================================
  Future<void> _printPhoto(BuildContext context) async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please wait, preparing photo...")),
      );
      return;
    }

    // 1. Tampilkan Loading agar user tidak bingung menunggu
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 10),
            Text("Sending to Printer...", style: TextStyle(color: Colors.white, fontFamily: 'Ambitsek'))
          ],
        ),
      ),
    );

    bool printSuccess = false;

    try {
      // --- PERSIAPAN DOKUMEN PDF (4R 300 DPI) ---
      const double width4R = 4.0 * 72.0;
      const double height4R = 6.0 * 72.0;
      final pdfFormat = PdfPageFormat(width4R, height4R, marginAll: 0);

      // Fungsi Helper untuk generate PDF bytes
      Future<Uint8List> generateDoc(PdfPageFormat format) async {
        final doc = pw.Document();
        final image = pw.MemoryImage(provider.finalImageBytes!);
        doc.addPage(pw.Page(
          pageFormat: format,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true, 
              child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300)
            );
          },
        ));
        return doc.save();
      }

      // --- LOGIKA PENCARIAN PRINTER ---
      Printer? targetPrinter;
      try {
        final printers = await Printing.listPrinters();
        print("📡 PRINTERS FOUND: ${printers.map((e) => e.name).toList()}");
        
        // Cari Epson atau D500, jika tidak ada cari yang Default
        targetPrinter = printers.firstWhere(
          (p) => p.name.toLowerCase().contains("epson") || p.name.toLowerCase().contains("d500"),
          orElse: () => printers.firstWhere((p) => p.isDefault, orElse: () => printers.first),
        );
      } catch (e) {
        print("⚠️ Gagal scan printer: $e");
      }

      // --- EKSEKUSI PRINT ---
      if (targetPrinter != null && targetPrinter.isAvailable) {
        print("🖨️ MENCOBA DIRECT PRINT KE: ${targetPrinter.name}");
        printSuccess = await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (PdfPageFormat format) async => generateDoc(pdfFormat),
          format: pdfFormat,
          usePrinterSettings: true, 
        );
      } else {
        print("⚠️ Printer target null atau tidak available.");
      }

    } catch (e) {
      print("❌ ERROR CRITICAL SAAT PRINT: $e");
    } finally {
      // 2. Tutup Loading
      if (context.mounted) Navigator.pop(context);

      // --- FALLBACK SYSTEM ---
      // Jika Direct Print GAGAL atau Printer TIDAK KETEMU, Paksa Buka Dialog Windows
      if (!printSuccess) {
        print("🔄 DIRECT PRINT GAGAL. MEMBUKA DIALOG MANUAL...");
        if (context.mounted) {
          await Printing.layoutPdf(
            onLayout: (format) async {
              final doc = pw.Document();
              final image = pw.MemoryImage(provider.finalImageBytes!);
              const double width4R = 4.0 * 72.0;
              const double height4R = 6.0 * 72.0;
              
              doc.addPage(pw.Page(
                pageFormat: PdfPageFormat(width4R, height4R, marginAll: 0),
                build: (pw.Context context) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300),
                ),
              ));
              return doc.save();
            },
            name: 'Photobooth_Print_${provider.sessionUuid}',
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Sent to Printer!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  // =========================================================
  // FITUR 2: DOWNLOAD FILE KE LAPTOP (FOLDER DOWNLOADS)
  // =========================================================
  Future<void> _downloadPhotoToLocal(BuildContext context) async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please wait, preparing photo...")),
      );
      return;
    }

    try {
      Directory? downloadsDirectory;
      if (Platform.isWindows) {
        downloadsDirectory = await getDownloadsDirectory();
      } else {
        downloadsDirectory = await getApplicationDocumentsDirectory();
      }

      if (downloadsDirectory == null) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'Photobooth_Result_$timestamp.png';
      final savePath = '${downloadsDirectory.path}/$fileName';

      final file = File(savePath);
      await file.writeAsBytes(provider.finalImageBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Saved: $fileName"),
            backgroundColor: Colors.blueAccent,
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () => Process.run('explorer.exe', ['/select,', savePath]),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Download Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionUuid = Provider.of<PhotoProvider>(context).sessionUuid;
    final String qrUrl = "$_websiteBaseUrl/$sessionUuid"; 

    return Scaffold(
      resizeToAvoidBottomInset: true, 
      body: Stack(
        fit: StackFit.expand,
        children: [
          // BACKGROUND IMAGE
          Image.asset(
            'assets/images/splash_background.png',
            fit: BoxFit.cover,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BAGIAN KIRI: PREVIEW MENU
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
                          "Preview & Print",
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

                      // BARIS TOMBOL AKSI
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
                              icon: Icons.download,
                              label: "SAVE",
                              color: Colors.blue,
                              onTap: () => _downloadPhotoToLocal(context),
                            ),
                            const SizedBox(width: 20),
                            RetroButton(
                              icon: Icons.print,
                              label: "PRINT",
                              color: Colors.green,
                              onTap: () => _printPhoto(context),
                            ),
                        ],
                      )
                    ],
                  ),
                ),

                // BAGIAN KANAN: QR CODE ONLY
                Expanded(
                  flex: 1,
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 50),
                          Container(
                            padding: const EdgeInsets.all(4),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC0C0C0), 
                              border: Border.all(width: 3, color: Colors.black),
                              boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(8, 8))],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  color: const Color(0xFF000080), 
                                  child: const Text("ScanMe.exe", style: TextStyle(fontFamily: 'Ambitsek', color: Colors.white, fontSize: 14)),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(10),
                                  child: QrImageView(
                                    data: qrUrl, 
                                    version: QrVersions.auto,
                                    size: 180.0,
                                    backgroundColor: Colors.white,
                                    gapless: false,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text("SCAN TO DOWNLOAD", style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 5),
                                Text("ID: $sessionUuid", style: const TextStyle(fontFamily: 'Courier', fontSize: 10, color: Colors.grey)),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
// WIDGET HELPERS (Retro UI)
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

class RetroButton extends StatefulWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const RetroButton({super.key, this.icon, required this.label, required this.color, required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: widget.color,
              border: const Border(
                top: BorderSide(color: Colors.white, width: 3),
                left: BorderSide(color: Colors.white, width: 3),
                bottom: BorderSide(color: Colors.black, width: 3),
                right: BorderSide(color: Colors.black, width: 3),
              ),
              boxShadow: _isPressed 
                  ? [] 
                  : [const BoxShadow(color: Colors.black54, offset: Offset(2, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label, 
                  style: const TextStyle(
                    fontFamily: 'Ambitsek', 
                    color: Colors.white, 
                    fontSize: 20, 
                    shadows: [Shadow(offset: Offset(1,1), color: Colors.black)]
                  )
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
// PAGE 1: PHOTO PREVIEW (With High Res Capture)
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
      
      RenderRepaintBoundary? boundary = 
          _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      // 1. Capture Widget ke ui.Image (Pixel Ratio 5.0 - SUPER TAJAM UNTUK PRINT)
      ui.Image image = await boundary.toImage(pixelRatio: 5.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      
      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      
      // Simpan data mentah high-res untuk PRINT
      provider.setFinalImageBytes(pngBytes);

      // 2. Decode & Encode JPG 100% Quality (Agar tidak pecah saat upload)
      img.Image? decodedImage = img.decodeImage(pngBytes);
      if (decodedImage == null) return;

      Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: 100));

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/web_result_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(jpgBytes);
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      
      String? uploadUrl = await apiService.uploadFinalResult(
        provider.sessionUuid, 
        tempFile.path
      );

      if (uploadUrl != null && mounted) setState(() => _isUploaded = true);
      try { await tempFile.delete(); } catch (_) {}
    } catch (e) {
      debugPrint("❌ Error Capture/Upload: $e");
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
    // --- PERBAIKAN MERAH ---
    // Menggunakan string check agar tidak error jika Enum belum diupdate
    bool isHorizontal = provider.customLayout.toString().contains("horizontal");

    double width = (provider.selectedMode == FrameMode.custom && isHorizontal) ? 400.0 : 344.0;
    double height = 515.0; 
    
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
            IgnorePointer(child: Image.asset(provider.selectedFrameAsset!, fit: BoxFit.cover)),
          
          ...provider.stickers.map((s) => Positioned(
            left: 0, top: 0,
            child: Transform.rotate(
              angle: s.rotation,
              child: Image.asset(s.assetPath, width: width, height: height, fit: BoxFit.contain),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCustomContent(PhotoProvider provider, List<int> indices) {
    final photos = indices.map((i) => i < provider.photos.length ? provider.photos[i].imageData : Uint8List(0)).toList();
    
    // --- PERBAIKAN MERAH ---
    bool isVertical = !provider.customLayout.toString().contains("horizontal");

    if (isVertical) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: photos.map((img) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), 
        child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(img, width: 150, height: 95, fit: BoxFit.cover)))).toList()));
    } else {
      return Center(child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: photos.map((img) => 
        ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(img, width: 160, height: 140, fit: BoxFit.cover))).toList()));
    }
  }

  Widget _buildStaticContent(PhotoProvider provider, List<int> indices) {
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
        itemBuilder: (context, index) => Image.memory(provider.photos[indices[index]].imageData, fit: BoxFit.cover),
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
          return Center(child: Image.memory(provider.photos[_index].imageData, fit: BoxFit.contain));
        },
      ),
    );
  }
}

// =========================================================
// PAGE 3: VIDEO PREVIEW
// =========================================================
class _VideoPreviewPage extends StatefulWidget {
  const _VideoPreviewPage();
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
    _currentDisplayIndices = List.generate(count, (i) => (i + _tick) % count);
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
           return Center(child: _VideoFrameBuilder(provider: provider, orderIndices: _currentDisplayIndices));
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
    return Container(
      width: 344, height: 515,
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildStaticContent(orderIndices),
          if (provider.selectedFrameAsset != null)
            Image.asset(provider.selectedFrameAsset!, fit: BoxFit.cover),
        ],
      ),
    );
  }

  Widget _buildStaticContent(List<int> indices) {
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
        itemBuilder: (context, index) => Image.memory(provider.photos[indices[index]].imageData, fit: BoxFit.cover),
      ),
    );
  }
}