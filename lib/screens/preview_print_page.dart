import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:webview_windows/webview_windows.dart';
import 'package:photobooth_app/providers/app_config_provider.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/services/config_service.dart';
import 'package:photobooth_app/services/history_service.dart';
import 'package:photobooth_app/services/print_service.dart';
import 'package:photobooth_app/services/api_service.dart';
import 'package:photobooth_app/services/license_service.dart';

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
  bool _hasPrinted = false;
  int _extraPrints = 0;
  bool _isExtraPaid = false;

  static final String _frontendUrl = ConfigService().frontendUrl;

  Future<void> _printPhoto({int quantity = 1}) async {
    if (_hasPrinted && quantity == 1) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfigProvider>(context, listen: false);
    if (provider.finalImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please wait, preparing photo...")));
      return;
    }

    setState(() => _hasPrinted = true);

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

    try {
      final success = await PrintService().printStrip(
        context,
        provider.finalImageBytes!,
        sessionUuid: provider.sessionUuid,
        copies: appConfig.autoPrintCopies + quantity - 1,
        printerKeyword: appConfig.preferredPrinterKeyword,
        paperSize: appConfig.paperSize,
      );

      if (success) {
        // ✅ SAVE TO LOCAL HISTORY
        await HistoryService()
            .saveToHistory(provider.sessionUuid, provider.finalImageBytes!);
        debugPrint("💾 Photo saved to local history after printing.");
      }

      if (!mounted) return;
      Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Sent to Printer!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("❌ Print error: $e");
    }
  }

  Future<void> _payAndPrintExtra() async {
    if (_extraPrints <= 0) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final appConfig = Provider.of<AppConfigProvider>(context, listen: false);
    final totalAmount = _extraPrints * appConfig.extraPrintPrice;
    final extraUuid =
        "${provider.sessionUuid}-extra-${DateTime.now().millisecondsSinceEpoch}";
    final hwid = await LicenseService().getHardwareId();

    try {
      // 1. Start extra session
      final started = await ApiService().startSession(extraUuid,
          hwid: hwid,
          paymentMethod: 'qris',
          transactionType: 'extra_print',
          extraPrintCount: _extraPrints);
      if (!started) throw Exception("Failed to connect to payment server.");

      // 2. Get payment link
      final paymentUrl = await ApiService().generatePaymentLink(extraUuid);
      if (paymentUrl == null) {
        throw Exception("Could not generate payment link.");
      }

      // 3. Show payment dialog
      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ExtraPaymentDialog(
          paymentUrl: paymentUrl,
          sessionUuid: extraUuid,
          amount: totalAmount,
        ),
      );

      if (paid == true) {
        if (mounted) {
          setState(() {
            _isExtraPaid = true;
          });
          // After success, do the print
          _printPhoto(quantity: 1 + _extraPrints);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent));
      }
    }
  }

  bool get _hasPrintsLocked => _hasPrinted && _extraPrints == 0;

  Widget _buildQuantityBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white30),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionUuid = Provider.of<PhotoProvider>(context).sessionUuid;
    final appConfig = Provider.of<AppConfigProvider>(context, listen: false);
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
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                              top: math.min(previewTextTopMargin,
                                  MediaQuery.of(context).size.height * 0.05),
                              left: previewTextLeftMargin,
                              bottom: math.min(cardRowTopMargin, 20.0)),
                          child: Text("Preview & Print",
                              style: TextStyle(
                                  fontFamily: 'Ambitsek',
                                  fontSize: previewTextSize,
                                  color: Colors.white,
                                  letterSpacing: 2.0,
                                  shadows: const [
                                    Shadow(
                                        offset: Offset(3, 3),
                                        color: Colors.black)
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
                              onTap: () => _navigateTo(
                                  context, const _PhotoPreviewPage()),
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
                        const SizedBox(height: 20),
                        // PRINT CONFIGURATION UI
                        if (appConfig.extraPrintEnabled)
                          LayoutBuilder(builder: (context, constraints) {
                          return Container(
                            constraints: const BoxConstraints(maxWidth: 550),
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: Colors.white24, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.print_outlined,
                                        color: Colors.blueAccent, size: 20),
                                    const SizedBox(width: 10),
                                    Text("EXTRA PRINTS",
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.9),
                                            fontFamily: 'Ambitsek',
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5)),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    _buildQuantityBtn(Icons.remove, () {
                                      if (_extraPrints > 0) {
                                        setState(() {
                                          _extraPrints--;
                                          _isExtraPaid = false;
                                        });
                                      }
                                    }),
                                    Container(
                                      width: 80,
                                      alignment: Alignment.center,
                                      child: Text("$_extraPrints",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Ambitsek')),
                                    ),
                                    _buildQuantityBtn(Icons.add, () {
                                      setState(() {
                                        _extraPrints++;
                                        _isExtraPaid = false;
                                      });
                                    }),
                                    const Spacer(),
                                    if (_extraPrints > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.yellowAccent
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: Colors.yellowAccent
                                                  .withValues(alpha: 0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                "Rp${_extraPrints * appConfig.extraPrintPrice}",
                                                style: const TextStyle(
                                                    color: Colors.yellowAccent,
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Ambitsek')),
                                            const Text("Additional Cost",
                                                style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 10,
                                                    letterSpacing: 0.5)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 40),
                        Row(
                          children: [
                            RetroButton(
                              icon: Icons.home,
                              label: "HOME",
                              color: Colors.redAccent,
                              onTap: () {
                                Provider.of<PhotoProvider>(context,
                                        listen: false)
                                    .reset();
                                Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                                        builder: (_) => const SplashScreen()),
                                    (r) => false);
                              },
                            ),
                            const SizedBox(width: 20),
                            RetroButton(
                                icon: _hasPrinted && _extraPrints == 0
                                    ? Icons.check_circle
                                    : Icons.print,
                                label: (_extraPrints > 0 && !_isExtraPaid)
                                    ? "PAY & PRINT"
                                    : (_hasPrinted && _extraPrints == 0
                                        ? "PRINTED"
                                        : "PRINT"),
                                color: (_extraPrints > 0 && !_isExtraPaid)
                                    ? Colors.orangeAccent
                                    : (_hasPrinted && _extraPrints == 0
                                        ? Colors.grey
                                        : Colors.green),
                                onTap: (_hasPrintsLocked)
                                    ? () {}
                                    : () {
                                        if (_extraPrints > 0 && !_isExtraPaid) {
                                          _payAndPrintExtra();
                                        } else {
                                          _printPhoto(
                                              quantity: 1 + _extraPrints);
                                        }
                                      }),
                          ],
                        ),
                        const SizedBox(height: 50), // Final spacing for scroll
                      ],
                    ),
                  ),
                ),

                if (appConfig.downloadQrEnabled)
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
  static final String _backendUrl = ConfigService().baseUrl;

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
      await Future.delayed(const Duration(milliseconds: 200));
      _captureAndUpload();
    }
  }

  Future<void> _captureAndUpload() async {
    if (_isUploaded) return;
    final provider = Provider.of<PhotoProvider>(context, listen: false);

    if (provider.finalImageBytes != null) {
      debugPrint(
          '🚀 [Optimized] Menggunakan hasil render asli dari CameraPage...');
      await _uploadFinalResult(provider.finalImageBytes!, provider.sessionUuid);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Merender foto...';
    });

    try {
      final boundary = _globalKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Gagal capture widget.';
        });
        return;
      }

      final frameW = provider.selectedFrameWidth;
      final renderW = boundary.size.width;
      final ratio = (frameW / renderW).clamp(1.0, 4.0);

      final uiImage = await boundary.toImage(pixelRatio: ratio);
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('toByteData null');
      final rawBytes = byteData.buffer.asUint8List();

      if (mounted) setState(() => _uploadStatus = 'Encoding PNG...');
      final pngBytes = await compute(_encodePngInIsolate, {
        'width': uiImage.width,
        'height': uiImage.height,
        'raw': rawBytes,
      });

      if (!mounted) return;
      provider.setFinalImageBytes(pngBytes);

      await _uploadFinalResult(pngBytes, provider.sessionUuid);
    } catch (e) {
      debugPrint('❌ Capture/Upload error: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Gagal render/upload.';
        });
      }
    }
  }

  Future<void> _uploadFinalResult(
      Uint8List pngBytes, String sessionUuid) async {
    final sw = Stopwatch()..start();
    if (mounted) setState(() => _uploadStatus = 'Mengupload ke server...');

    try {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      if (provider.machineId.isEmpty) {
        await provider.initMachineId();
      }
      final hwid = provider.machineId;
      if (hwid.isEmpty) {
        throw Exception('HWID kosong, upload final dibatalkan.');
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/result_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes);

      // 💾 Simpan ke history lokal (Owner Dashboard)
      await HistoryService().saveToHistory(sessionUuid, pngBytes);

      final uri = Uri.parse('$_backendUrl/api/photobooth/upload/final');
      final request = http.MultipartRequest('POST', uri)
        ..fields['session_uuid'] = sessionUuid
        ..fields['hwid'] = hwid
        ..files.add(await http.MultipartFile.fromPath('photo', tempFile.path,
            contentType: http_parser.MediaType('image', 'png')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      try {
        await tempFile.delete();
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint(
            '✅ Upload berhasil! status: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');
        if (mounted) {
          setState(() {
            _isUploaded = true;
            _isUploading = false;
            _uploadStatus = '';
          });
        }
      } else {
        throw Exception('Upload Failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("❌ Upload error: $e");
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Error upload.';
        });
      }
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
          if (provider.hasCustomSlots)
            ..._buildSlotWidgets(provider, w, h)
          else
            _buildGridFallback(provider),
          if (provider.selectedFrameAsset != null)
            IgnorePointer(
              child: provider.selectedFrameAsset!.startsWith('http')
                  ? Image.network(
                      provider.selectedFrameAsset!,
                      fit: BoxFit.fill,
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

class _ExtraPaymentDialog extends StatefulWidget {
  final String paymentUrl;
  final String sessionUuid;
  final int amount;

  const _ExtraPaymentDialog({
    required this.paymentUrl,
    required this.sessionUuid,
    required this.amount,
  });

  @override
  State<_ExtraPaymentDialog> createState() => _ExtraPaymentDialogState();
}

class _ExtraPaymentDialogState extends State<_ExtraPaymentDialog> {
  final WebviewController _webviewController = WebviewController();
  bool _isWebViewReady = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_isWebViewReady) _webviewController.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    try {
      await _webviewController.initialize();
      await _webviewController.setBackgroundColor(Colors.white);

      _webviewController.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          _injectAutoSelectQrisScript();
        }
      });

      await _webviewController.loadUrl(widget.paymentUrl);
      if (mounted) setState(() => _isWebViewReady = true);
    } catch (e) {
      debugPrint("❌ WebView Error: $e");
    }
  }

  void _injectAutoSelectQrisScript() async {
    const jsCode = '''
      (function() {
        var qrisClicked = false;

        function simulateClick(el) {
          ['mousedown', 'mouseup', 'click'].forEach(function(evtType) {
            el.dispatchEvent(new MouseEvent(evtType, {
              bubbles: true, cancelable: true, view: window
            }));
          });
        }

        function trySelectQris(attempt) {
          if (attempt > 30 || qrisClicked) return;

          var xpathResult = document.evaluate(
            "//*[contains(translate(text(),'qris','QRIS'),'QRIS')]",
            document, null,
            XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null
          );

          for (var i = 0; i < xpathResult.snapshotLength; i++) {
            var node = xpathResult.snapshotItem(i);
            var target = node;
            for (var depth = 0; depth < 8; depth++) {
              if (!target) break;
              var tag = (target.tagName || '').toUpperCase();
              var role = (target.getAttribute && target.getAttribute('role')) || '';
              var cursor = window.getComputedStyle(target).cursor;

              if (tag === 'BUTTON' || tag === 'A' || tag === 'LI' ||
                  role === 'button' || role === 'tab' || role === 'option' ||
                  cursor === 'pointer' ||
                  target.onclick != null ||
                  (target.className && target.className.toString().match(/channel|method|option|item|card|tab|accordion/i))) {
                simulateClick(target);
                qrisClicked = true;
                console.log('[AutoQRIS] Clicked QRIS element:', tag, target.className);
                setTimeout(function() { scrollToQrCode(0); }, 2000);
                return;
              }
              target = target.parentElement;
            }
          }

          var fallbackSelectors = [
            '[data-channel*="qris" i]',
            '[data-channel*="QRIS"]',
            '[data-payment*="qris" i]',
            '[data-value*="qris" i]',
            '[id*="qris" i]',
            '[class*="qris" i]',
            '[class*="channel" i]',
          ];
          for (var s = 0; s < fallbackSelectors.length; s++) {
            try {
              var els = document.querySelectorAll(fallbackSelectors[s]);
              for (var j = 0; j < els.length; j++) {
                var txt = (els[j].textContent || '').toUpperCase();
                if (txt.indexOf('QRIS') !== -1) {
                  simulateClick(els[j]);
                  qrisClicked = true;
                  console.log('[AutoQRIS] Fallback clicked:', els[j].tagName, els[j].className);
                  setTimeout(function() { scrollToQrCode(0); }, 2000);
                  return;
                }
              }
            } catch(e) {}
          }

          if (!qrisClicked) {
            var all = document.querySelectorAll('*');
            for (var k = 0; k < all.length; k++) {
              var el = all[k];
              var directText = '';
              for (var c = 0; c < el.childNodes.length; c++) {
                if (el.childNodes[c].nodeType === 3) {
                  directText += el.childNodes[c].textContent;
                }
              }
              if (directText.trim().toUpperCase().indexOf('QRIS') !== -1) {
                var clickTarget = el;
                while (clickTarget && clickTarget !== document.body) {
                  var cs = window.getComputedStyle(clickTarget).cursor;
                  if (cs === 'pointer') {
                    simulateClick(clickTarget);
                    qrisClicked = true;
                    console.log('[AutoQRIS] Last-resort clicked:', clickTarget.tagName);
                    setTimeout(function() { scrollToQrCode(0); }, 2000);
                    return;
                  }
                  clickTarget = clickTarget.parentElement;
                }
                simulateClick(el);
                qrisClicked = true;
                console.log('[AutoQRIS] Direct clicked:', el.tagName);
                setTimeout(function() { scrollToQrCode(0); }, 2000);
                return;
              }
            }
          }

          setTimeout(function() { trySelectQris(attempt + 1); }, 500);
        }

        function scrollToQrCode(attempt) {
          if (attempt > 30) return;
          var qrSelectors = [
            'img[src*="qr"]', 'img[alt*="qr" i]', 'img[alt*="QRIS" i]',
            'canvas', '[class*="qr-code" i]', '[class*="qrcode" i]',
            '[id*="qr" i]', 'img[src*="payment"]',
            'img[src*="doku"]', 'img[src*="shopeepay"]',
          ];
          var qrElement = null;
          for (var s = 0; s < qrSelectors.length; s++) {
            try {
              qrElement = document.querySelector(qrSelectors[s]);
              if (qrElement) break;
            } catch(e) {}
          }
          if (qrElement) {
            qrElement.scrollIntoView({behavior: 'smooth', block: 'center'});
          } else {
            setTimeout(function() { scrollToQrCode(attempt + 1); }, 500);
          }
        }

        var observer = new MutationObserver(function(mutations) {
          if (!qrisClicked) {
            trySelectQris(0);
          } else {
            observer.disconnect();
          }
        });
        observer.observe(document.body || document.documentElement, {
          childList: true, subtree: true
        });

        setTimeout(function() { trySelectQris(0); }, 1500);
      })();
    ''';

    try {
      await _webviewController.executeScript(jsCode);
    } catch (e) {
      debugPrint("⚠️ JS injection error: $e");
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final paid = await ApiService().checkPaymentStatus(widget.sessionUuid);
      if (paid && mounted) {
        timer.cancel();
        Navigator.pop(context, true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFC0C0C0),
      shape: const BeveledRectangleBorder(
        side: BorderSide(color: Colors.black, width: 3),
      ),
      child: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: const Color(0xFF000080),
              child: Row(
                children: [
                  const Text("ADDITIONAL PRINT PAYMENT",
                      style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Ambitsek',
                          fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Text(
                "Total Amount: Rp${widget.amount}",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Expanded(
              child: _isWebViewReady
                  ? Webview(_webviewController)
                  : const Center(child: CircularProgressIndicator()),
            ),
            const Padding(
              padding: EdgeInsets.all(10.0),
              child: Text(
                "Please scan the QR code to finish the payment.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
