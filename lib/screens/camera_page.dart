import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; 
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'customization_page.dart';
import 'preview_print_page.dart';
import '../utils/image_filter.dart';
import '../services/api_service.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String _debugMessage = "Menghubungkan Canon R100...";

  // Logic Sesi
  bool _isSessionActive = false;
  bool _isCapturing = false;
  int _countdown = 0;
  bool _showBlink = false;

  // Batas Retake
  int _retakeCount = 0;
  final int _maxRetakes = 2;

  // --- MATRIKS FILTER ---
  static const ColorFilter _sepiaMatrix = ColorFilter.matrix(<double>[
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  static const ColorFilter _grayscaleMatrix = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  static const ColorFilter _brightnessMatrix = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 30,
    0, 1, 0, 0, 30,
    0, 0, 1, 0, 30,
    0, 0, 0, 1, 0,
  ]);

  final Map<PhotoFilter, String> _filterAssets = {
    PhotoFilter.none: 'assets/filters/filter_none.png',
    PhotoFilter.vintage: 'assets/filters/filter_vintage.png',
    PhotoFilter.grayscale: 'assets/filters/filter_grayscale.png',
    PhotoFilter.smooth: 'assets/filters/filter_smooth.png',
    PhotoFilter.brightness: 'assets/filters/filter_brightness.png',
  };

  @override
  void initState() {
    super.initState();
    _initCanonCamera(); 
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // =================================================================
  // LOGIC KHUSUS CANON EOS WEBCAM UTILITY (WINDOWS) - UPDATE
  // =================================================================
  Future<void> _initCanonCamera() async {
    try {
      final cameras = await availableCameras();
      
      if (cameras.isEmpty) {
        setState(() => _debugMessage = "❌ Tidak ada kamera terdeteksi!\nPastikan EOS Webcam Utility terinstall.");
        return;
      }

      CameraDescription? targetCamera;

      // 1. Prioritaskan nama "EOS Webcam Utility"
      try {
        targetCamera = cameras.firstWhere((cam) => cam.name.contains("EOS Webcam Utility"));
      } catch (_) {}

      // 2. Jika tidak ada, cari yang mengandung "Canon" atau "EOS"
      if (targetCamera == null) {
        try {
          targetCamera = cameras.firstWhere((cam) {
            String name = cam.name.toLowerCase();
            return name.contains("eos") || name.contains("canon") || name.contains("usb");
          });
        } catch (_) {}
      }

      // 3. Fallback ke kamera pertama apapun itu
      targetCamera ??= cameras.first;

      setState(() => _debugMessage = "Menginisialisasi: ${targetCamera!.name}");
      
      // --- PERBAIKAN PENTING DISINI ---
      // Ganti 'medium' ke 'max'. Driver Canon sering pakai resolusi aneh (misal 1024x576)
      // Preset 'medium' memaksa 720p, jika driver tidak dukung, maka crash.
      // Preset 'max' akan menerima resolusi apapun yang diberikan driver.
      _cameraController = CameraController(
        targetCamera,
        ResolutionPreset.max, // <--- GANTI KE MAX
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _debugMessage = "";
        });
      }
    } catch (e) {
      // Jika MAX gagal, coba fallback ke LOW sebagai upaya terakhir
      print("Init Max failed: $e");
      _retryWithLowResolution();
    }
  }

  // Fungsi Cadangan: Jika MAX gagal, coba resolusi terendah
  Future<void> _retryWithLowResolution() async {
    try {
      setState(() => _debugMessage = "Retrying with Low Res...");
      final cameras = await availableCameras();
      final target = cameras.isNotEmpty ? cameras.first : null;

      if (target != null) {
        _cameraController = CameraController(
          target,
          ResolutionPreset.low, // Resolusi 320x240 (Paling aman)
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _debugMessage = "";
          });
        }
      }
    } catch (e) {
      setState(() => _debugMessage = "FATAL ERROR:\nKamera menolak koneksi.\n$e");
    }
  }

  ColorFilter _getLiveFilterMatrix(PhotoFilter filter) {
    switch (filter) {
      case PhotoFilter.vintage: return _sepiaMatrix;
      case PhotoFilter.grayscale: return _grayscaleMatrix;
      case PhotoFilter.brightness: return _brightnessMatrix;
      case PhotoFilter.smooth: return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
      default: return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
  }

  // =================================================================
  // LOGIC SESI FOTO (SUDAH BENAR & AMAN)
  // =================================================================

  void _startAutoSession() async {
    if (_isSessionActive) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    // 1. GUNAKAN UUID DARI PAYMENT PAGE
    String sessionUuid = provider.sessionUuid;

    // Jika kosong (Mode Debug), buat dummy
    if (sessionUuid.isEmpty) {
       sessionUuid = "debug-${DateTime.now().millisecondsSinceEpoch}";
       provider.setSessionUuid(sessionUuid);
    }

    // Bersihkan foto lama
    provider.photos.clear(); 
    
    // 2. REGISTER SESI KE DATABASE
    try {
       final apiService = Provider.of<ApiService>(context, listen: false);
       if (provider.machineId.isEmpty) await provider.initMachineId();

       await apiService.startSession(
         sessionUuid, 
         hwid: provider.machineId 
       );
    } catch (_) {
       print("Info: Sesi mungkin sudah dibuat di payment page.");
    }

    setState(() => _isSessionActive = true);

    // Loop Pengambilan Foto
    while (provider.photos.length < provider.targetPhotoCount) {
      if (!mounted) break;
      if (provider.photos.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 2));
      }
      await _performSingleCapture();
      if (!mounted || !_isSessionActive) break;
    }

    if (mounted) setState(() => _isSessionActive = false);
  }

  void _retakeSpecificPhoto(int index) async {
    if (_retakeCount >= _maxRetakes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Batas retake habis!")));
      return;
    }
    if (_isSessionActive || _isCapturing) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    provider.removePhotoAt(index);

    setState(() {
      _retakeCount++;
      _isSessionActive = true;
    });

    await _performSingleCapture();

    if (mounted) setState(() => _isSessionActive = false);
  }

  Future<void> _performSingleCapture() async {
    setState(() => _isCapturing = true);

    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() => _countdown = 0);

    setState(() => _showBlink = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _showBlink = false);

    await _takePictureAndSave();
    setState(() => _isCapturing = false);
  }

  Future<void> _takePictureAndSave() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final XFile image = await _cameraController!.takePicture();
      final rawBytes = await image.readAsBytes();

      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);

      final filteredBytes = await ImageFilterUtil.applyFilter(
        rawBytes,
        provider.selectedFilter,
      );

      provider.addPhoto(filteredBytes);

      // Upload Foto ke Server
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        await apiService.uploadPhoto(provider.sessionUuid, image.path);
      } catch (e) {
        debugPrint("❌ Gagal Upload: $e");
      }
      
      // Hapus file temporary
      try { await File(image.path).delete(); } catch (_) {}

    } catch (e) {
      debugPrint('Error Capture: $e');
    }
  }

  void _onNextPressed() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    // Navigasi sesuai mode frame
    if (provider.selectedMode == FrameMode.static) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PreviewPrintPage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomizationPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoProvider>();
    final selectedFilter = provider.selectedFilter;
    final bool showBackButton = !_isSessionActive && provider.photos.isEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. KAMERA PREVIEW
          if (_isCameraInitialized && _cameraController != null)
             SizedBox.expand(
               child: FittedBox(
                 fit: BoxFit.cover,
                 child: SizedBox(
                   width: _cameraController!.value.previewSize?.width ?? 1280,
                   height: _cameraController!.value.previewSize?.height ?? 720,
                   child: ColorFiltered(
                     colorFilter: _getLiveFilterMatrix(selectedFilter),
                     child: CameraPreview(_cameraController!),
                   ),
                 ),
               ),
             )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 10),
                  Text(_debugMessage, style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center),
                ],
              ),
            ),

          // 2. OVERLAY FRAME
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset("assets/images/cam_ovl.png", fit: BoxFit.cover),
            ),
          ),

          // 3. COUNTDOWN ANIMATION
          if (_countdown > 0)
            Container(
              color: Colors.black45,
              child: Center(
                child: Text('$_countdown', style: const TextStyle(fontFamily: 'Ambitsek', fontSize: 250, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(offset: Offset(4, 4), color: Colors.black)])),
              ),
            ),
          
          // 4. EFEK BLINK
          if (_showBlink) Container(color: Colors.white),

          // 5. SIDEBAR HASIL FOTO
          Positioned(
            right: 20, top: 20, bottom: 20,
            child: Container(
              width: 140,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  const Text("RESULTS", style: TextStyle(fontFamily: 'Ambitsek', color: Colors.white, fontSize: 15, letterSpacing: 2.0)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: ListView.separated(
                      itemCount: provider.targetPhotoCount,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 15),
                      itemBuilder: (context, index) {
                        bool hasPhoto = index < provider.photos.length;
                        bool canRetake = hasPhoto && !_isSessionActive && _retakeCount < _maxRetakes;
                        return GestureDetector(
                          onTap: canRetake ? () => _retakeSpecificPhoto(index) : null,
                          child: Stack(
                            children: [
                              Container(
                                height: 110,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  border: Border.all(color: Colors.white, width: 2),
                                  borderRadius: BorderRadius.circular(10),
                                  image: hasPhoto ? DecorationImage(image: MemoryImage(provider.photos[index].imageData), fit: BoxFit.cover) : null
                                ),
                                child: !hasPhoto ? const Center(child: Text("Empty", style: TextStyle(color: Colors.white54, fontSize: 12))) : null,
                              ),
                              if (canRetake)
                                Positioned(
                                  right: 0, bottom: 0,
                                  child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(8))), child: const Icon(Icons.refresh, size: 18, color: Colors.white)),
                                )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (provider.isComplete)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text("Retake: ${_maxRetakes - _retakeCount} left", style: const TextStyle(color: Colors.yellow, fontSize: 12))),
                ],
              ),
            ),
          ),

          // 6. BOTTOM CONTROLS
          Positioned(
            left: 0, right: 160, bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Visibility(
                  visible: !_isSessionActive, 
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: PhotoFilter.values.map((filter) {
                        final isSelected = selectedFilter == filter;
                        final assetPath = _filterAssets[filter];
                        return GestureDetector(
                          onTap: () => provider.setSelectedFilter(filter),
                          child: Container(
                            width: 60, height: 60, margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.yellowAccent : Colors.white, width: 3), image: assetPath != null ? DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover) : null),
                            child: assetPath == null ? const Icon(Icons.block, color: Colors.white) : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),

                if (!_isSessionActive && !provider.isComplete)
                  GestureDetector(
                    onTap: _startAutoSession,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)),
                      child: const Center(child: Icon(Icons.camera_alt, color: Colors.white, size: 45)),
                    ),
                  ),

                if (provider.isComplete && !_isSessionActive)
                  NextImageButton(onPressed: _onNextPressed),
              ],
            ),
          ),

          // 7. TOMBOL KEMBALI
          if (showBackButton)
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

// Widget Tombol Next (Animasi)
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
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) { setState(() => _isPressed = false); widget.onPressed(); },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(scale: _isPressed ? 0.9 : (_isHovered ? 1.05 : 1.0), duration: const Duration(milliseconds: 100), child: Image.asset("assets/images/next.png", width: 180, height: 96, fit: BoxFit.contain)),
      ),
    );
  }
}