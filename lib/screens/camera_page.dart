import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:http_parser/http_parser.dart';
import '../providers/photo_provider.dart';
import 'customization_page.dart';
import 'preview_print_page.dart';
import '../utils/image_filter.dart';
import 'package:flutter/services.dart' show rootBundle;

// ================================================================
// TOP-LEVEL ISOLATE FUNCTION — encode PNG di background thread
// ================================================================
Uint8List _encodePngInIsolate(Map<String, dynamic> args) {
  final int width     = args['width']  as int;
  final int height    = args['height'] as int;
  final Uint8List raw = args['raw']    as Uint8List;
  final image = img.Image.fromBytes(
    width: width, height: height,
    bytes: raw.buffer, order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraMacOSController? _cameraController;
  final GlobalKey _cameraKey = GlobalKey();
  bool _isCameraInitialized = false;
  String _debugMessage      = "Mendeteksi kamera...";

  bool _isSessionActive = false;
  bool _isCapturing     = false;
  int  _countdown       = 0;
  bool _showBlink       = false;
  int  _retakeCount     = 0;

  bool _isRendering = false;
  bool _renderDone  = false;

  // ── FIX FILTER: simpan filter yang dipilih sebelum sesi dimulai ──
  PhotoFilter _lockedFilter = PhotoFilter.none;

  static const String _backendUrl = 'http://168.231.125.203:8181';

  // ── Filter matrices ──
  static const ColorFilter _sepiaMatrix = ColorFilter.matrix(<double>[
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0,     0,     0,     1, 0,
  ]);
  static const ColorFilter _grayscaleMatrix = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);
  static const ColorFilter _brightnessMatrix = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 30,
    0, 1, 0, 0, 30,
    0, 0, 1, 0, 30,
    0, 0, 0, 1,  0,
  ]);
  // ── FIX: smooth filter matrix (soft blur effect) ──
  static const ColorFilter _smoothMatrix = ColorFilter.matrix(<double>[
    1.0,  0,    0,    0, 10,
    0,    1.0,  0,    0, 10,
    0,    0,    1.0,  0, 10,
    0,    0,    0,    1,  0,
  ]);

  final Map<PhotoFilter, String> _filterAssets = {
    PhotoFilter.none:       'assets/filters/filter_none.png',
    PhotoFilter.vintage:    'assets/filters/filter_vintage.png',
    PhotoFilter.grayscale:  'assets/filters/filter_grayscale.png',
    PhotoFilter.smooth:     'assets/filters/filter_smooth.png',
    PhotoFilter.brightness: 'assets/filters/filter_brightness.png',
  };

  @override
  void initState() {
    super.initState();
    // Baca filter awal dari provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      _lockedFilter = provider.selectedFilter;
    });
  }

  @override
  void dispose() {
    _cameraController?.destroy();
    super.dispose();
  }

  // ================================================================
  // INIT CAMERA
  // ================================================================
  void _onCameraInizialized(CameraMacOSController controller) {
    setState(() {
      _cameraController    = controller;
      _isCameraInitialized = true;
      _debugMessage        = "";
    });
    debugPrint("✅ Camera macOS initialized!");
  }

  // ── FIX: _getLiveFilter pakai _lockedFilter saat sesi aktif ──
  ColorFilter _getLiveFilter(PhotoFilter filter) {
    // Gunakan _lockedFilter jika sesi sudah dimulai supaya tidak reset
    final active = _isSessionActive ? _lockedFilter : filter;
    switch (active) {
      case PhotoFilter.vintage:    return _sepiaMatrix;
      case PhotoFilter.grayscale:  return _grayscaleMatrix;
      case PhotoFilter.brightness: return _brightnessMatrix;
      case PhotoFilter.smooth:     return _smoothMatrix; // ← FIX: smooth tidak lagi jatuh ke default
      default: return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
  }

  // ================================================================
  // SESI FOTO
  // ================================================================
  void _startAutoSession() async {
    if (_isSessionActive) return;

    final provider  = Provider.of<PhotoProvider>(context, listen: false);
    final int total = provider.targetPhotoCount;
    debugPrint("📸 Total foto: $total");

    // ── FIX: Lock filter sebelum clearPhotos() ──
    _lockedFilter = provider.selectedFilter;
    debugPrint("🎨 Filter dikunci: $_lockedFilter");

    provider.clearPhotos();
    setState(() {
      _isSessionActive = true;
      _retakeCount     = 0;
      _renderDone      = false;
    });

    while (provider.photos.length < total) {
      if (!mounted || !_isSessionActive) break;
      if (provider.photos.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 2));
      }
      await _performSingleCapture();
    }

    if (mounted) setState(() => _isSessionActive = false);

    if (mounted && provider.photos.length >= total) {
      // ── FIX FREEZE: render di background, tidak block navigasi ──
      _triggerBackgroundRender();
    }
  }

  void _retakeSpecificPhoto(int index) async {
    if (_isSessionActive || _isCapturing) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    provider.removePhotoAt(index);

    // Lock filter saat retake juga
    _lockedFilter = provider.selectedFilter;

    setState(() {
      _retakeCount++;
      _isSessionActive = true;
      _renderDone      = false;
    });

    await _performSingleCapture();

    if (mounted) setState(() => _isSessionActive = false);

    final prov = Provider.of<PhotoProvider>(context, listen: false);
    if (mounted && prov.isComplete) {
      _triggerBackgroundRender();
    }
  }

  Future<void> _performSingleCapture() async {
    setState(() => _isCapturing = true);

    for (int i = 5; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() => _countdown = 0);

    setState(() => _showBlink = true);
    await Future.delayed(const Duration(milliseconds: 120));
    if (mounted) setState(() => _showBlink = false);

    await _takePictureAndSave();
    if (mounted) setState(() => _isCapturing = false);
  }

  // ================================================================
  // AMBIL FOTO
  // ================================================================
  Future<void> _takePictureAndSave() async {
    if (_cameraController == null) return;
    try {
      final CameraMacOSFile? result = await _cameraController!.takePicture();
      if (result == null || result.bytes == null) { debugPrint("❌ Foto null"); return; }

      final Uint8List raw = result.bytes!;
      if (!mounted) return;

      final provider = Provider.of<PhotoProvider>(context, listen: false);

      // ── FIX: Gunakan _lockedFilter (bukan provider.selectedFilter yang bisa berubah) ──
      final Uint8List filtered = await ImageFilterUtil.applyFilter(raw, _lockedFilter);

      final int photoIndex = provider.photos.length;
      await _savePhotoLocally(filtered, photoIndex, provider.sessionUuid);
      _uploadPhotoToServer(filtered, photoIndex, provider.sessionUuid); // fire & forget
      provider.addPhoto(filtered);
    } catch (e) {
      debugPrint('❌ Error capture: $e');
    }
  }

  Future<void> _savePhotoLocally(Uint8List bytes, int index, String sessionId) async {
    try {
      final id         = sessionId.isNotEmpty ? sessionId : "session_${DateTime.now().millisecondsSinceEpoch}";
      final dir        = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${dir.path}/Photobooth/$id');
      if (!await sessionDir.exists()) await sessionDir.create(recursive: true);
      final file = File('${sessionDir.path}/photo_$index.jpg');
      await file.writeAsBytes(bytes);
      debugPrint("💾 Tersimpan: ${file.path}");
    } catch (e) {
      debugPrint("❌ Gagal simpan: $e");
    }
  }

  Future<void> _uploadPhotoToServer(Uint8List bytes, int index, String sessionUuid) async {
    try {
      if (sessionUuid.isEmpty) return;
      debugPrint("☁️ Upload foto ${index + 1} ke server...");

      final tempDir  = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/photo_${index}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);

      final uri     = Uri.parse('$_backendUrl/api/photobooth/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['session_uuid'] = sessionUuid
        ..files.add(await http.MultipartFile.fromPath(
            'photo', tempFile.path,
            contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      try { await tempFile.delete(); } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ Foto ${index + 1} terupload!");
      } else {
        debugPrint("❌ Upload foto ${index + 1} gagal: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Upload foto error: $e");
    }
  }

  // ================================================================
  // BACKGROUND RENDER & UPLOAD
  // ── FIX FREEZE: fire & forget, tidak block UI ──
  // ================================================================
  void _triggerBackgroundRender() {
    debugPrint("🎬 Trigger background render...");
    if (mounted) setState(() { _isRendering = true; _renderDone = false; });
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    // Tidak pakai await — jalan di background
    _renderAndUploadInBackground(provider);
  }

  Future<void> _renderAndUploadInBackground(PhotoProvider provider) async {
    try {
      debugPrint("🖼️ Rendering frame result...");

      const double scale = 3.0;
      final double w = provider.selectedFrameWidth  * scale;
      final double h = provider.selectedFrameHeight * scale;

      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // Background putih
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);

      // ──────────────────────────────────────────────────────────
      // PATH A: Custom slots dari web editor
      // ──────────────────────────────────────────────────────────
      if (provider.hasCustomSlots) {
        debugPrint("✅ Render dengan custom slots (${provider.photoSlots.length} slot, ${provider.photos.length} foto)");

        // Pre-decode semua foto sekali
        final List<ui.Image> decodedPhotos = [];
        for (int pi = 0; pi < provider.photos.length; pi++) {
          final codec = await ui.instantiateImageCodec(provider.photos[pi].imageData);
          final frame = await codec.getNextFrame();
          decodedPhotos.add(frame.image);
        }

        for (int si = 0; si < provider.photoSlots.length; si++) {
          final slot     = provider.photoSlots[si];
          final int pidx = slot.photoIndex.clamp(0, decodedPhotos.length - 1);
          final image    = decodedPhotos[pidx];

          debugPrint("  Slot ${si+1}: photoIndex=${slot.photoIndex} → foto ${pidx+1}, rot=${slot.rotation}°");

          final double dx = slot.x      * scale;
          final double dy = slot.y      * scale;
          final double dw = slot.width  * scale;
          final double dh = slot.height * scale;

          final double srcRatio = image.width  / image.height.toDouble();
          final double dstRatio = dw / dh;
          double srcX = 0, srcY = 0;
          double srcW = image.width.toDouble();
          double srcH = image.height.toDouble();

          if (srcRatio > dstRatio) {
            srcW = srcH * dstRatio;
            srcX = (image.width - srcW) / 2;
          } else {
            srcH = srcW / dstRatio;
            srcY = 0;
          }

          if (slot.rotation != 0) {
            final double cx = dx + dw / 2;
            final double cy = dy + dh / 2;
            canvas.save();
            canvas.translate(cx, cy);
            canvas.rotate(slot.rotation * (3.141592653589793 / 180));
            canvas.translate(-cx, -cy);
          }

          canvas.drawImageRect(
            image,
            Rect.fromLTWH(srcX, srcY, srcW, srcH),
            Rect.fromLTWH(dx, dy, dw, dh),
            Paint()..filterQuality = FilterQuality.high,
          );

          if (slot.rotation != 0) canvas.restore();
        }

      // ──────────────────────────────────────────────────────────
      // PATH B: Fallback FrameLayout (grid hardcoded)
      // ──────────────────────────────────────────────────────────
      } else {
        debugPrint("⚠️ Render dengan layout fallback");

        final layout   = provider.selectedLayout;
        final int count = provider.targetPhotoCount;
        final int cols  = count == 3 ? 1 : 2;
        final int rows  = (count / cols).ceil();

        final lTop    = layout.topPadding        * scale;
        final lBottom = layout.bottomPadding     * scale;
        final lLeft   = layout.leftPadding       * scale;
        final lRight  = layout.rightPadding      * scale;
        final lHSpace = layout.horizontalSpacing * scale;
        final lVSpace = layout.verticalSpacing   * scale;

        final double paddedW = w - lLeft - lRight;
        final double paddedH = h - lTop  - lBottom;
        final double cellW   = (paddedW - (cols - 1) * lHSpace) / cols;
        final double cellH   = (paddedH - (rows - 1) * lVSpace) / rows;

        for (int i = 0; i < provider.photos.length && i < count; i++) {
          final col = i % cols;
          final row = i ~/ cols;
          final dx  = lLeft + col * (cellW + lHSpace);
          final dy  = lTop  + row * (cellH + lVSpace);

          final codec = await ui.instantiateImageCodec(provider.photos[i].imageData);
          final frame = await codec.getNextFrame();
          final image = frame.image;

          final double srcRatio = image.width  / image.height.toDouble();
          final double dstRatio = cellW / cellH;
          double srcX = 0, srcY = 0;
          double srcW = image.width.toDouble();
          double srcH = image.height.toDouble();

          if (srcRatio > dstRatio) {
            srcW = srcH * dstRatio;
            srcX = (image.width - srcW) / 2;
          } else {
            srcH = srcW / dstRatio;
            srcY = 0;
          }

          canvas.drawImageRect(
            image,
            Rect.fromLTWH(srcX, srcY, srcW, srcH),
            Rect.fromLTWH(dx, dy, cellW, cellH),
            Paint()..filterQuality = FilterQuality.high,
          );
        }
      }

      // ──────────────────────────────────────────────────────────
      // FRAME OVERLAY
      // ──────────────────────────────────────────────────────────
      if (provider.selectedFrameAsset != null) {
        final frameUrl = provider.selectedFrameAsset!;
        Uint8List? frameBytes;

        if (frameUrl.startsWith('http')) {
          final httpClient = HttpClient();
          final request    = await httpClient.getUrl(Uri.parse(frameUrl));
          final response   = await request.close();
          frameBytes = await consolidateHttpClientResponseBytes(response);
        } else {
          final data = await rootBundle.load(frameUrl);
          frameBytes = data.buffer.asUint8List();
        }

        if (frameBytes != null) {
          final codec = await ui.instantiateImageCodec(frameBytes);
          final frame = await codec.getNextFrame();
          canvas.drawImageRect(
            frame.image,
            Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
            Rect.fromLTWH(0, 0, w, h),
            Paint()..filterQuality = FilterQuality.high,
          );
        }
      }

      // ──────────────────────────────────────────────────────────
      // CONVERT TO PNG — pakai compute() supaya tidak freeze UI
      // ──────────────────────────────────────────────────────────
      final picture = recorder.endRecording();
      final uiImage = await picture.toImage(w.toInt(), h.toInt());
      debugPrint("🖼️ toImage done: ${uiImage.width}x${uiImage.height}");

      // Step 1: rawRgba dulu (instant, tidak block)
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('toByteData null');
      final rawBytes = byteData.buffer.asUint8List();
      debugPrint("🖼️ rawRgba done: ${rawBytes.length} bytes");

      // Step 2: encode PNG di isolate background
      final pngBytes = await compute(_encodePngInIsolate, {
        'width':  uiImage.width,
        'height': uiImage.height,
        'raw':    rawBytes,
      });
      debugPrint("🖼️ PNG encode done: ${pngBytes.length} bytes");

      provider.setFinalImageBytes(pngBytes);
      await _uploadFinalResult(pngBytes, provider.sessionUuid);

      if (mounted) setState(() { _isRendering = false; _renderDone = true; });

    } catch (e) {
      debugPrint("❌ Render error: $e");
      if (mounted) setState(() { _isRendering = false; });
    }
  }

  Future<void> _uploadFinalResult(Uint8List pngBytes, String sessionUuid) async {
    try {
      debugPrint("📤 Mengupload hasil ke server...");

      final tempDir  = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/result_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes);

      final uri     = Uri.parse('$_backendUrl/api/photobooth/upload/final');
      final request = http.MultipartRequest('POST', uri)
        ..fields['session_uuid'] = sessionUuid
        ..files.add(await http.MultipartFile.fromPath(
            'photo', tempFile.path,
            contentType: MediaType('image', 'png')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      try { await tempFile.delete(); } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ Upload berhasil!");
      } else {
        debugPrint("❌ Upload gagal: ${response.statusCode} — ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Upload error: $e");
    }
  }

  // ================================================================
  // NAVIGASI
  // ── FIX FREEZE: navigasi langsung, render tetap jalan di background ──
  // ================================================================
  void _onNextPressed() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    // Navigasi langsung — _renderAndUploadInBackground sudah jalan
    // sebagai fire & forget sejak foto selesai
    if (provider.selectedMode == FrameMode.static) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const PreviewPrintPage()));
    } else {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const CustomizationPage()));
    }
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    final provider  = context.watch<PhotoProvider>();
    // ── FIX: gunakan _lockedFilter saat sesi aktif ──
    final filter    = _isSessionActive ? _lockedFilter : provider.selectedFilter;
    final int total = provider.targetPhotoCount;
    final int done  = provider.photos.length;
    final bool complete = provider.isComplete;
    final bool showBack = !_isSessionActive && done == 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── 1. CAMERA PREVIEW dengan filter ──
          ColorFiltered(
            colorFilter: _getLiveFilter(filter),
            child: CameraMacOSView(
              key: _cameraKey,
              cameraMode: CameraMacOSMode.photo,
              enableAudio: false,
              onCameraInizialized: _onCameraInizialized,
              onCameraDestroyed: () {
                debugPrint("📷 Camera destroyed");
                return Container();
              },
              fit: BoxFit.cover,
            ),
          ),

          // Loading overlay kamera belum siap
          if (!_isCameraInitialized)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 60),
                      child: Text(
                        _debugMessage.isEmpty ? "Memuat kamera..." : _debugMessage,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── 2. OVERLAY FRAME ──
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset("assets/images/cam_ovl.png", fit: BoxFit.cover),
            ),
          ),

          // ── 3. COUNTDOWN ──
          if (_countdown > 0)
            Container(
              color: Colors.black54,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_countdown),
                  tween: Tween(begin: 1.3, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontFamily: 'Ambitsek', fontSize: 260,
                      fontWeight: FontWeight.bold, color: Colors.white,
                      shadows: [Shadow(offset: Offset(4, 4), color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ),

          // ── 4. BLINK FLASH ──
          if (_showBlink) Container(color: Colors.white),

          // ── 5. SIDEBAR ──
          Positioned(
            right: 16, top: 20, bottom: 20,
            child: Container(
              width: 140,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  const Text("RESULTS",
                    style: TextStyle(
                      fontFamily: 'Ambitsek', color: Colors.white,
                      fontSize: 13, letterSpacing: 2)),

                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: done >= total
                          ? Colors.green.withOpacity(0.3)
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$done / $total',
                      style: TextStyle(
                        color: done >= total ? Colors.greenAccent : Colors.white60,
                        fontSize: 12, fontWeight: FontWeight.bold)),
                  ),

                  // Filter aktif indicator
                  if (_lockedFilter != PhotoFilter.none && _isSessionActive)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_fix_high, color: Colors.purpleAccent, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _lockedFilter.name,
                            style: const TextStyle(
                              color: Colors.purpleAccent, fontSize: 9,
                              fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                  // Render status
                  if (_isRendering)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 10, height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.orange)),
                          SizedBox(width: 5),
                          Text("render",
                            style: TextStyle(
                              color: Colors.orange, fontSize: 9,
                              fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                  if (_renderDone && !_isRendering)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done, color: Colors.greenAccent, size: 10),
                          SizedBox(width: 4),
                          Text("uploaded",
                            style: TextStyle(
                              color: Colors.greenAccent, fontSize: 9,
                              fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),

                  // Foto thumbnails
                  Expanded(
                    child: ListView.separated(
                      itemCount: total,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final has       = i < done;
                        final canRetake = has && !_isSessionActive && complete;

                        return GestureDetector(
                          onTap: canRetake ? () => _retakeSpecificPhoto(i) : null,
                          child: Stack(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: 110,
                                decoration: BoxDecoration(
                                  color: has
                                      ? Colors.transparent
                                      : Colors.white.withOpacity(0.08),
                                  border: Border.all(
                                    color: has ? Colors.white54 : Colors.white24,
                                    width: has ? 2 : 1),
                                  borderRadius: BorderRadius.circular(10),
                                  image: has
                                    ? DecorationImage(
                                        image: MemoryImage(provider.photos[i].imageData),
                                        fit: BoxFit.cover)
                                    : null,
                                ),
                                child: !has
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.camera_alt,
                                            color: Colors.white24,
                                            size: _isSessionActive && i == done ? 28 : 20),
                                          if (_isSessionActive && i == done)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: SizedBox(
                                                width: 16, height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white38)),
                                            ),
                                        ],
                                      ),
                                    )
                                  : null,
                              ),

                              if (canRetake)
                                Positioned(
                                  right: 0, bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        bottomRight: Radius.circular(9))),
                                    child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                                  ),
                                ),

                              Positioned(
                                top: 4, left: 6,
                                child: Text('${i + 1}',
                                  style: TextStyle(
                                    color: has ? Colors.white70 : Colors.white24,
                                    fontSize: 11, fontWeight: FontWeight.bold,
                                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  if (complete) ...[
                    const SizedBox(height: 8),
                    Text(
                      _retakeCount > 0 ? 'Retake: $_retakeCount×' : 'Tap foto\nuntuk retake',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ],
              ),
            ),
          ),

          // ── 6. BOTTOM CONTROLS ──
          Positioned(
            left: 0, right: 168, bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter selector — hanya tampil saat tidak ada sesi aktif
                if (!_isSessionActive)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: PhotoFilter.values.map((f) {
                        final sel   = (_isSessionActive ? _lockedFilter : provider.selectedFilter) == f;
                        final asset = _filterAssets[f];
                        return GestureDetector(
                          onTap: () {
                            provider.setSelectedFilter(f);
                            // Sync _lockedFilter juga
                            setState(() => _lockedFilter = f);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 58, height: 58,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sel ? Colors.yellowAccent : Colors.white38,
                                width: sel ? 3 : 1.5),
                              image: asset != null
                                ? DecorationImage(
                                    image: AssetImage(asset), fit: BoxFit.cover)
                                : null,
                              boxShadow: sel
                                ? [const BoxShadow(
                                    color: Colors.yellowAccent,
                                    blurRadius: 8, spreadRadius: 1)]
                                : [],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 28),

                if (!_isSessionActive && !complete)
                  GestureDetector(
                    onTap: _startAutoSession,
                    child: Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                        boxShadow: const [BoxShadow(color: Colors.white24, blurRadius: 12)],
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 42),
                    ),
                  ),

                if (complete && !_isSessionActive)
                  NextImageButton(onPressed: _onNextPressed),
              ],
            ),
          ),

          // ── 7. BACK BUTTON ──
          if (showBack)
            Positioned(
              top: 50, left: 30,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Image.asset("assets/images/back_cam.png", width: 150, fit: BoxFit.contain),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================
// NEXT BUTTON WIDGET
// ================================================================
class NextImageButton extends StatefulWidget {
  final VoidCallback onPressed;
  const NextImageButton({super.key, required this.onPressed});

  @override
  State<NextImageButton> createState() => _NextImageButtonState();
}

class _NextImageButtonState extends State<NextImageButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit:  (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _isPressed = true),
        onTapUp:     (_) { setState(() => _isPressed = false); widget.onPressed(); },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.9 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: Image.asset(
            "assets/images/next.png",
            width: 180, height: 96, fit: BoxFit.contain),
        ),
      ),
    );
  }
}