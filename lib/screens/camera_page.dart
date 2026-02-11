import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // [GANTI KE PLUGIN CAMERA RESMI]
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
  // --- CONTROLLER KAMERA BARU (PENGGANTI DCC) ---
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // Logic Sesi
  bool _isSessionActive = false;
  bool _isCapturing = false;
  int _countdown = 0;
  bool _showBlink = false;

  // Batas Retake
  int _retakeCount = 0;
  final int _maxRetakes = 2;

  // --- MATRIKS FILTER (TETAP SAMA) ---
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
    _initSonyCamera(); // Inisialisasi Kamera Sony
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // =================================================================
  // LOGIC BARU: CARI KAMERA SONY & CONNECT
  // =================================================================
  Future<void> _initSonyCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("❌ Tidak ada kamera terdeteksi!");
        return;
      }

      CameraDescription? selectedCamera;

      debugPrint("📸 Scanning Cameras...");
      
      // Cari kamera yang namanya mengandung "USB Video", "ZV-E10", atau "USB Camera"
      // PENTING: Hindari "Imaging Edge" agar tidak layar biru
      for (var cam in cameras) {
        debugPrint("   Found: ${cam.name}");
        
        // Skip driver lama yang bermasalah
        if (cam.name.toLowerCase().contains("imaging edge")) {
           continue; 
        }

        // Prioritaskan Kamera USB Streaming
        if (cam.name.toLowerCase().contains("usb video") || 
            cam.name.toLowerCase().contains("zv-e10") ||
            cam.name.toLowerCase().contains("usb camera") ||
            cam.lensDirection == CameraLensDirection.external) {
          
          selectedCamera = cam;
          break;
        }
      }

      // Fallback 1: Jika tidak ketemu nama spesifik, ambil kamera index 1 (biasanya eksternal)
      if (selectedCamera == null && cameras.length > 1) {
        selectedCamera = cameras[1];
      }
      
      // Fallback 2: Pakai kamera apa saja yang ada (Webcam laptop)
      selectedCamera ??= cameras.first;

      debugPrint("✅ Using Camera: ${selectedCamera.name}");

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.max, // Resolusi Maksimal Webcam (Biasanya 720p/1080p)
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint("❌ Error Init Camera: $e");
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
  // LOGIC UTAMA: AUTO SEQUENCE & RETAKE
  // =================================================================

  void _startAutoSession() async {
    if (_isSessionActive) return;

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final PhotoFilter userSelectedFilter = provider.selectedFilter;

    // 1. GENERATE UUID & RESET
    String newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    provider.setSessionUuid(newUuid);
    provider.reset();
    provider.setSelectedFilter(userSelectedFilter);

    // 2. KIRIM KE SERVER
    try {
       final apiService = Provider.of<ApiService>(context, listen: false);
       await apiService.startSession(newUuid);
    } catch (_) {}

    setState(() => _isSessionActive = true);

    // 3. Loop Otomatis
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

    // COUNTDOWN
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() => _countdown = 0);

    // BLINK
    setState(() => _showBlink = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _showBlink = false);

    // CAPTURE
    await _takePictureAndSave();
    setState(() => _isCapturing = false);
  }

  Future<void> _takePictureAndSave() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      // 1. AMBIL FOTO LANGSUNG DARI WEBCAM STREAM
      final XFile image = await _cameraController!.takePicture();
      
      final rawBytes = await image.readAsBytes();

      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);

      // 2. Apply Filter
      final filteredBytes = await ImageFilterUtil.applyFilter(
        rawBytes,
        provider.selectedFilter,
      );

      provider.addPhoto(filteredBytes);

      // 3. Upload Background (Opsional)
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        await apiService.uploadPhoto(provider.sessionUuid, image.path);
      } catch (e) {
        debugPrint("❌ Gagal Upload: $e");
      }

      // Hapus file temp
      try { await File(image.path).delete(); } catch (_) {}

    } catch (e) {
      debugPrint('Error Capture: $e');
    }
  }

  void _onNextPressed() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    
    if (provider.selectedMode == FrameMode.static) {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => const PreviewPrintPage())
      );
    } else {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => const CustomizationPage())
      );
    }
  }

  // =================================================================
  // UI BUILDER
  // =================================================================

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
          // ------------------------------------------
          // LAYER 1: SONY WEBCAM PREVIEW (FULLSCREEN)
          // ------------------------------------------
          if (_isCameraInitialized && _cameraController != null)
             // Trik agar Fullscreen (Cover) tidak gepeng
             SizedBox.expand(
               child: FittedBox(
                 fit: BoxFit.cover,
                 child: SizedBox(
                   width: _cameraController!.value.previewSize?.width ?? 1280,
                   height: _cameraController!.value.previewSize?.height ?? 720,
                   // Bungkus dengan ColorFiltered agar filter live tetap jalan
                   child: ColorFiltered(
                     colorFilter: _getLiveFilterMatrix(selectedFilter),
                     child: CameraPreview(_cameraController!),
                   ),
                 ),
               ),
             )
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 10),
                  Text("Menghubungkan Kamera Sony...", style: TextStyle(color: Colors.white)),
                ],
              ),
            ),

          // ------------------------------------------
          // LAYER 1.5: OVERLAY IMAGE (FRAME UI)
          // ------------------------------------------
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                "assets/images/cam_ovl.png",
                fit: BoxFit.cover,
              ),
            ),
          ),

          // ------------------------------------------
          // LAYER 2: EFEK VISUAL (Countdown & Blink)
          // ------------------------------------------
          if (_countdown > 0)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    fontFamily: 'Ambitsek',
                    fontSize: 250, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.white, 
                    shadows: [
                      Shadow(offset: Offset(-4, -4), color: Colors.black),
                      Shadow(offset: Offset(4, -4), color: Colors.black),
                      Shadow(offset: Offset(4, 4), color: Colors.black),
                      Shadow(offset: Offset(-4, 4), color: Colors.black),
                    ]
                  ),
                ),
              ),
            ),
          
          if (_showBlink) Container(color: Colors.white),

          // ------------------------------------------
          // LAYER 3: SIDEBAR PREVIEW (KANAN)
          // ------------------------------------------
          Positioned(
            right: 20, 
            top: 20,
            bottom: 20,
            child: Container(
              width: 140,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Text(
                    "RESULTS", 
                    style: TextStyle(
                      fontFamily: 'Ambitsek',
                      color: Colors.white, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 15,
                      letterSpacing: 2.0
                    )
                  ),
                  const SizedBox(height: 15),
                  
                  // LIST FOTO
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
                                  image: hasPhoto 
                                    ? DecorationImage(image: MemoryImage(provider.photos[index].imageData), fit: BoxFit.cover)
                                    : null
                                ),
                                child: !hasPhoto 
                                  ? const Center(child: Text("Empty", style: TextStyle(color: Colors.white54, fontSize: 12)))
                                  : null,
                              ),
                              
                              if (canRetake)
                                Positioned(
                                  right: 0, bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red, 
                                      borderRadius: BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(8))
                                    ),
                                    child: const Icon(Icons.refresh, size: 18, color: Colors.white),
                                  ),
                                )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  if (provider.isComplete)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text("Retake: ${_maxRetakes - _retakeCount} left", style: const TextStyle(color: Colors.yellow, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),

          // ------------------------------------------
          // LAYER 4: BOTTOM CONTROLS
          // ------------------------------------------
          Positioned(
            left: 0, 
            right: 160, 
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                // FILTER LIST
                Visibility(
                  visible: !_isSessionActive, 
                  child: Center(
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
                              width: 60, height: 60,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.yellowAccent : Colors.white, width: 3),
                                image: assetPath != null 
                                  ? DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover) 
                                  : null,
                                boxShadow: isSelected 
                                  ? [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)] 
                                  : [],
                              ),
                              child: assetPath == null ? const Icon(Icons.block, color: Colors.white) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),

                // TOMBOL START
                if (!_isSessionActive && !provider.isComplete)
                  GestureDetector(
                    onTap: _startAutoSession,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                      ),
                      child: const Center(
                        child: Icon(Icons.camera_alt, color: Colors.white, size: 45),
                      ),
                    ),
                  ),

                // TOMBOL NEXT
                if (provider.isComplete && !_isSessionActive)
                  NextImageButton(
                    onPressed: _onNextPressed,
                  ),
              ],
            ),
          ),

          // ------------------------------------------
          // LAYER 5: BACK BUTTON
          // ------------------------------------------
          if (showBackButton)
            Positioned(
              top: 50,
              left: 30,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Image.asset(
                  "assets/images/back_cam.png", 
                  width: 150, 
                  fit: BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Widget NextImageButton TETAP SAMA seperti kode Anda
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
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.9 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: Image.asset(
            "assets/images/next.png", 
            width: 180, 
            height: 96, 
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}