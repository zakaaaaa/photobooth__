import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show compute, consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart';

// ============================================================
// TOP-LEVEL ISOLATE FUNCTION — encode PNG di background thread
// ── FIX UTAMA: tidak blok UI thread ──
// ============================================================
Uint8List _encodePngInIsolate(Map<String, dynamic> args) {
  final int width = args['width'] as int;
  final int height = args['height'] as int;
  final Uint8List raw = args['raw'] as Uint8List;

  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: raw.buffer,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

// ============================================================
// MAIN PAGE
// ============================================================
class PreviewPrintPage extends StatefulWidget {
  const PreviewPrintPage({super.key});

  @override
  State<PreviewPrintPage> createState() => _PreviewPrintPageState();
}

class _PreviewPrintPageState extends State<PreviewPrintPage> {
  final double previewTextTopMargin = 80.0;
  final double previewTextLeftMargin = 0.0;
  final double previewTextSize = 40.0;
  final double cardRowTopMargin = 80.0;
  final double cardWidth = 242.0;
  final double cardHeight = 275.0;
  final double cardSpacing = 20.0;

  static const String _frontendUrl = 'https://app.amandya.tech';
  static const String _backendUrl = 'https://api.amandya.tech';

  Future<void> _printPhoto(BuildContext context) async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please wait, preparing photo...")));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 10),
          Text("Sending to Printer...",
              style: TextStyle(color: Colors.white, fontFamily: 'Ambitsek')),
        ]),
      ),
    );

    bool printSuccess = false;

    try {
      const double width4R = 4.0 * 72.0;
      const double height4R = 6.0 * 72.0;
      final pdfFormat = PdfPageFormat(width4R, height4R, marginAll: 0);

      Future<Uint8List> generateDoc(PdfPageFormat format) async {
        final doc = pw.Document();
        final image = pw.MemoryImage(provider.finalImageBytes!);
        doc.addPage(pw.Page(
          pageFormat: format,
          build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300)),
        ));
        return doc.save();
      }

      Printer? targetPrinter;
      try {
        final printers = await Printing.listPrinters();
        targetPrinter = printers.firstWhere(
          (p) =>
              p.name.toLowerCase().contains("epson") ||
              p.name.toLowerCase().contains("d500"),
          orElse: () => printers.firstWhere((p) => p.isDefault,
              orElse: () => printers.first),
        );
      } catch (e) {
        debugPrint("⚠️ Gagal scan printer: $e");
      }

      if (targetPrinter != null && targetPrinter.isAvailable) {
        printSuccess = await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (f) async => generateDoc(pdfFormat),
          format: pdfFormat,
          usePrinterSettings: true,
        );
      }
    } catch (e) {
      debugPrint("❌ Print error: $e");
    } finally {
      if (context.mounted) Navigator.pop(context);
      if (!printSuccess) {
        if (context.mounted) {
          await Printing.layoutPdf(
            onLayout: (_) async {
              final doc = pw.Document();
              final image = pw.MemoryImage(provider.finalImageBytes!);
              doc.addPage(pw.Page(
                pageFormat: PdfPageFormat(4.0 * 72, 6.0 * 72, marginAll: 0),
                build: (_) => pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300)),
              ));
              return doc.save();
            },
            name: 'Photobooth_${provider.sessionUuid}',
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("✅ Sent to Printer!"),
              backgroundColor: Colors.green));
        }
      }
    }
  }

  Future<void> _downloadPhotoToLocal(BuildContext context) async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please wait, preparing photo...")));
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'Photobooth_Result_$timestamp.png';
      final savePath = '${dir.path}/$fileName';
      await File(savePath).writeAsBytes(provider.finalImageBytes!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("✅ Saved: $fileName"),
            backgroundColor: Colors.blueAccent));
      }
    } catch (e) {
      debugPrint("Download Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionUuid = Provider.of<PhotoProvider>(context).sessionUuid;
    final String qrUrl = '$_frontendUrl/download/$sessionUuid';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/splash_background.png', fit: BoxFit.cover),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 40.0, vertical: 30.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kiri: Preview cards + buttons
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                            top: previewTextTopMargin,
                            left: previewTextLeftMargin,
                            bottom: cardRowTopMargin),
                        child: Text("Preview & Print",
                            style: TextStyle(
                                fontFamily: 'Ambitsek',
                                fontSize: previewTextSize,
                                color: Colors.white,
                                letterSpacing: 2.0,
                                shadows: const [
                                  Shadow(
                                      offset: Offset(3, 3), color: Colors.black)
                                ])),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          RetroInteractiveCard(
                            label: "Photo",
                            assetPath: "assets/images/photo.png",
                            colorAccent: Colors.blueAccent,
                            width: cardWidth,
                            height: cardHeight,
                            onTap: () =>
                                _navigateTo(context, const _PhotoPreviewPage()),
                          ),
                          SizedBox(width: cardSpacing),
                          RetroInteractiveCard(
                            label: "GIF",
                            assetPath: "assets/images/gif.png",
                            colorAccent: Colors.purpleAccent,
                            width: cardWidth,
                            height: cardHeight,
                            onTap: () =>
                                _navigateTo(context, const _GifPreviewPage()),
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
                              Provider.of<PhotoProvider>(context, listen: false)
                                  .reset();
                              Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                      builder: (_) => const SplashScreen()),
                                  (r) => false);
                            },
                          ),
                          const SizedBox(width: 20),
                          // RetroButton(
                          //     icon: Icons.download,
                          //     label: "SAVE",
                          //     color: Colors.blue,
                          //     onTap: () => _downloadPhotoToLocal(context)),
                          const SizedBox(width: 20),
                          RetroButton(
                              icon: Icons.print,
                              label: "PRINT",
                              color: Colors.green,
                              onTap: () => _printPhoto(context)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Kanan: QR Code
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
                                border:
                                    Border.all(width: 3, color: Colors.black),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black54,
                                      offset: Offset(8, 8))
                                ]),
                            child: Column(
                              children: [
                                Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 8),
                                    color: const Color(0xFF000080),
                                    child: const Text("ScanMe.exe",
                                        style: TextStyle(
                                            fontFamily: 'Ambitsek',
                                            color: Colors.white,
                                            fontSize: 14))),
                                const SizedBox(height: 10),
                                Container(
                                    color: Colors.white,
                                    padding: const EdgeInsets.all(10),
                                    child: QrImageView(
                                        data: qrUrl,
                                        version: QrVersions.auto,
                                        size: 180.0,
                                        backgroundColor: Colors.white,
                                        gapless: false)),
                                const SizedBox(height: 10),
                                const Text("SCAN TO DOWNLOAD",
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                const SizedBox(height: 5),
                                Text("ID: $sessionUuid",
                                    style: const TextStyle(
                                        fontFamily: 'Courier',
                                        fontSize: 10,
                                        color: Colors.grey)),
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

  void _navigateTo(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

// ============================================================
// WIDGET HELPERS
// ============================================================
class RetroInteractiveCard extends StatefulWidget {
  final String label, assetPath;
  final Color colorAccent;
  final double width, height;
  final VoidCallback onTap;
  const RetroInteractiveCard({
    super.key,
    required this.label,
    required this.assetPath,
    required this.colorAccent,
    required this.width,
    required this.height,
    required this.onTap,
  });
  @override
  State<RetroInteractiveCard> createState() => _RetroInteractiveCardState();
}

class _RetroInteractiveCardState extends State<RetroInteractiveCard> {
  bool _isHovered = false, _isPressed = false;
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
                    color: _isHovered ? widget.colorAccent : Colors.black),
                boxShadow: _isPressed
                    ? []
                    : const [
                        BoxShadow(
                            color: Colors.black54,
                            offset: Offset(6, 6),
                            blurRadius: 0)
                      ]),
            child: Column(children: [
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  color: const Color(0xFF0000AA),
                  child: Text(widget.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Ambitsek',
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 1.5))),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.all(15.0),
                      child:
                          Image.asset(widget.assetPath, fit: BoxFit.contain))),
            ]),
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
  const RetroButton({
    super.key,
    this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isHovered = false, _isPressed = false;
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
                    right: BorderSide(color: Colors.black, width: 3)),
                boxShadow: _isPressed
                    ? []
                    : const [
                        BoxShadow(color: Colors.black54, offset: Offset(2, 2))
                      ]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              Text(widget.label,
                  style: const TextStyle(
                      fontFamily: 'Ambitsek',
                      color: Colors.white,
                      fontSize: 20,
                      shadows: [
                        Shadow(offset: Offset(1, 1), color: Colors.black)
                      ])),
            ]),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PAGE 1: PHOTO PREVIEW
// ── FIX UTAMA: RepaintBoundary di LUAR FittedBox ──
// ============================================================
class _PhotoPreviewPage extends StatefulWidget {
  const _PhotoPreviewPage();
  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  final GlobalKey _globalKey = GlobalKey();
  bool _isUploading = false;
  bool _isUploaded = false;
  String _uploadStatus = '';

  static const String _backendUrl = 'https://api.amandya.tech';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _waitForFrameAndCapture());
  }

  Future<void> _waitForFrameAndCapture() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final frameUrl = provider.selectedFrameAsset;

    debugPrint('⏱ [0] _waitForFrameAndCapture — frameUrl: $frameUrl');

    // Pre-warm: pastikan network image sudah di-cache sebelum toImage()
    if (frameUrl != null && frameUrl.startsWith('http')) {
      debugPrint('⏱ [0a] Pre-loading frame image dari network...');
      try {
        await precacheImage(NetworkImage(frameUrl), context);
        debugPrint('⏱ [0b] Frame image ready di cache ✅');
      } catch (e) {
        debugPrint('⚠️ [0b] precacheImage gagal: $e — lanjut capture saja');
      }
    }

    if (mounted) {
      // Delay singkat agar widget rebuild dengan frame image yang sudah di-cache
      await Future.delayed(const Duration(milliseconds: 200));
      _captureAndUpload();
    }
  }

  Future<void> _captureAndUpload() async {
    if (_isUploaded) return;
    setState(() {
      _isUploading = true;
      _uploadStatus = 'Merender foto...';
    });

    try {
      final sw = Stopwatch()..start();
      debugPrint('⏱ [1] Mulai capture...');

      final boundary = _globalKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('❌ [1] boundary null');
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Gagal capture widget.';
        });
        return;
      }
      debugPrint(
          '⏱ [2] boundary OK — size: ${boundary.size} (${sw.elapsedMilliseconds}ms)');

      // ── boundary.size sekarang ~ukuran layar (misal 500x707px) ──
      // bukan 2480x3508 seperti sebelumnya
      final prov = Provider.of<PhotoProvider>(context, listen: false);
      final frameW = prov.selectedFrameWidth;
      final renderW = boundary.size.width;
      // Ratio: frameW/renderW misal 2480/500 = 4.96 → clamp ke 4.0
      // Output: 500*4 = 2000px wide — tajam untuk print tanpa terlalu berat
      final ratio = (frameW / renderW).clamp(1.0, 4.0);
      debugPrint('⏱ [3] frameW=$frameW renderW=$renderW ratio=$ratio');

      // Step A — toImage: ukuran output = renderSize * ratio
      final uiImage = await boundary.toImage(pixelRatio: ratio);
      debugPrint(
          '⏱ [4] toImage done — ${uiImage.width}x${uiImage.height}px (${sw.elapsedMilliseconds}ms)');

      // Step B — rawRgba: CEPAT, tidak ada encoding
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('toByteData null');
      final rawBytes = byteData.buffer.asUint8List();
      debugPrint(
          '⏱ [5] toByteData rawRgba done — ${rawBytes.length} bytes (${sw.elapsedMilliseconds}ms)');

      // Step C — encode PNG di background isolate, UI tetap responsive
      if (mounted) setState(() => _uploadStatus = 'Encoding PNG...');
      final pngBytes = await compute(_encodePngInIsolate, {
        'width': uiImage.width,
        'height': uiImage.height,
        'raw': rawBytes,
      });
      debugPrint(
          '⏱ [6] PNG encode done — ${pngBytes.length} bytes (${sw.elapsedMilliseconds}ms)');

      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      provider.setFinalImageBytes(pngBytes);

      if (mounted) setState(() => _uploadStatus = 'Mengupload ke server...');

      // Step D — upload ke server
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/result_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes);
      debugPrint('⏱ [7] tempFile written (${sw.elapsedMilliseconds}ms)');

      final uri = Uri.parse('$_backendUrl/api/photobooth/upload/final');
      final request = http.MultipartRequest('POST', uri)
        ..fields['session_uuid'] = provider.sessionUuid
        ..files.add(await http.MultipartFile.fromPath('photo', tempFile.path,
            contentType: http_parser.MediaType('image', 'png')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      debugPrint(
          '⏱ [8] upload done — status: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      try {
        await tempFile.delete();
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          setState(() {
            _isUploaded = true;
            _isUploading = false;
            _uploadStatus = '';
          });
        }
        debugPrint('✅ [9] Total: ${sw.elapsedMilliseconds}ms');
      } else {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadStatus = 'Upload gagal: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Capture/Upload error: $e");
      if (mounted)
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Error: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Photo Result"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_isUploading) ...[
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white54)),
                const SizedBox(width: 8),
                Text(_uploadStatus,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11)),
              ] else if (_isUploaded) ...[
                const Icon(Icons.cloud_done_rounded,
                    color: Colors.greenAccent, size: 18),
                const SizedBox(width: 6),
                const Text("Uploaded",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ]),
          ),
        ],
      ),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
          final frameW = provider.selectedFrameWidth;
          final frameH = provider.selectedFrameHeight;

          return Center(
            // ✅ FIX: RepaintBoundary di LUAR FittedBox
            // → boundary.size = ukuran layar (~500px), bukan frameW (2480px)
            // → toImage() jauh lebih ringan, PNG encode turun dari 5s ke ~0.5s
            child: RepaintBoundary(
              key: _globalKey,
              child: AspectRatio(
                aspectRatio: frameW / frameH,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: frameW,
                    height: frameH,
                    child: _buildFrameResult(provider),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrameResult(PhotoProvider provider) {
    final double w = provider.selectedFrameWidth;
    final double h = provider.selectedFrameHeight;

    return Container(
      width: w,
      height: h,
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // PATH A: Custom slots dari web editor
          if (provider.hasCustomSlots)
            ..._buildSlotWidgets(provider, w, h)
          // PATH B: Fallback GridView lama
          else
            _buildGridFallback(provider),

          // Frame overlay — di atas foto
          if (provider.selectedFrameAsset != null)
            IgnorePointer(
              child: provider.selectedFrameAsset!.startsWith('http')
                  ? Image.network(
                      provider.selectedFrameAsset!,
                      fit: BoxFit.fill,
                      // Tidak perlu loading builder — sudah di-precache
                      frameBuilder: (ctx, child, frame, _) => child,
                      errorBuilder: (ctx, e, st) => const SizedBox.shrink(),
                    )
                  : Image.asset(provider.selectedFrameAsset!, fit: BoxFit.fill),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSlotWidgets(PhotoProvider provider, double w, double h) {
    final photos = provider.photos;
    if (photos.isEmpty) return [];

    return provider.photoSlots.map((slot) {
      final int idx = slot.photoIndex.clamp(0, photos.length - 1);
      final photoBytes = photos[idx].imageData;

      return Positioned(
        left: slot.x,
        top: slot.y,
        width: slot.width,
        height: slot.height,
        child: Transform.rotate(
          angle: slot.rotation * (math.pi / 180),
          child: ClipRect(
            child: Image.memory(
              photoBytes,
              width: slot.width,
              height: slot.height,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildGridFallback(PhotoProvider provider) {
    final layout = provider.selectedLayout;
    final int count = provider.targetPhotoCount;
    final int cols = count == 3 ? 1 : 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.leftPadding, layout.topPadding,
          layout.rightPadding, layout.bottomPadding),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: layout.horizontalSpacing,
          mainAxisSpacing: layout.verticalSpacing,
          childAspectRatio: layout.childAspectRatio,
        ),
        itemCount: provider.photos.length,
        itemBuilder: (_, i) => Image.memory(provider.photos[i].imageData,
            fit: BoxFit.cover, alignment: Alignment.topCenter),
      ),
    );
  }
}

// ============================================================
// PAGE 2: GIF PREVIEW
// ============================================================
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
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      if (provider.photos.isNotEmpty && mounted) {
        setState(() => _index = (_index + 1) % provider.photos.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<PhotoProvider>(
        builder: (_, provider, __) {
          if (provider.photos.isEmpty) {
            return const Center(
                child: Text("No Photos",
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Ambitsek',
                        fontSize: 24)));
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Image.memory(
                  provider.photos[_index].imageData,
                  key: ValueKey(_index),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.topCenter,
                ),
              ),
              IgnorePointer(
                child: Image.asset(
                  'assets/images/cam_ovl.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Positioned(
                top: 40,
                left: 20,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        border: Border.all(color: Colors.white30),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    provider.photos.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _index == i ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: _index == i ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

