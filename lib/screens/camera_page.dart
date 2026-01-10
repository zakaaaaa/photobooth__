import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'customization_page.dart';
import 'preview_print_page.dart';
import '../utils/image_filter.dart';
import '../services/http_camera_service.dart';
import '../services/api_service.dart'; 

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final HttpCameraService _cameraService = HttpCameraService();
  
  bool _isSessionActive = false;
  bool _isCapturing = false;    
  int _countdown = 0;
  bool _showBlink = false;
  
  // Batas Retake
  int _retakeCount = 0;
  final int _maxRetakes = 2;

  // Stream Key
  Key _streamKey = UniqueKey();
  bool _isStreamActive = true;

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
    _initService();
  }

  Future<void> _initService() async {
    await _cameraService.initialize();
    if (mounted) setState(() {});
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
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Warning: Server not connected")));
    }

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

    if (mounted) {
       setState(() => _isSessionActive = false);
    }
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
    try {
      setState(() => _isStreamActive = false);

      final File? imageFile = await _cameraService.takePicture();
      if (imageFile == null) throw Exception('Gagal mengambil foto');

      final rawBytes = await imageFile.readAsBytes();

      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      
      final filteredBytes = await ImageFilterUtil.applyFilter(
        rawBytes,
        provider.selectedFilter,
      );

      provider.addPhoto(filteredBytes);

      // UPLOAD
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        await apiService.uploadPhoto(provider.sessionUuid, imageFile.path);
      } catch (e) {
        debugPrint("❌ Gagal Upload: $e");
      }

      try { await imageFile.delete(); } catch (_) {}

      await _cameraService.startLiveView();
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          _isStreamActive = true;
          _streamKey = UniqueKey(); 
        });
      }

    } catch (e) {
      debugPrint('Error Capture: $e');
      await _cameraService.startLiveView();
      if (mounted) {
        setState(() {
          _isStreamActive = true;
          _streamKey = UniqueKey(); 
        });
      }
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

    // LOGIKA BACK BUTTON: Hilang jika sesi aktif ATAU sudah ada foto
    final bool showBackButton = !_isSessionActive && provider.photos.isEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ------------------------------------------
          // LAYER 1: KAMERA (FULLSCREEN)
          // ------------------------------------------
          _isStreamActive
              ? ColorFiltered(
                  colorFilter: _getLiveFilterMatrix(selectedFilter),
                  child: Mjpeg(
                    key: _streamKey,
                    isLive: true,
                    stream: _cameraService.liveViewUrl,
                    fit: BoxFit.cover,
                    error: (context, error, stack) => const Center(child: Text("Connecting Camera...", style: TextStyle(color: Colors.white))),
                    loading: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                )
              : Container(color: Colors.black, child: const Center(child: CircularProgressIndicator())),

          // ------------------------------------------
          // LAYER 1.5: OVERLAY IMAGE (FRAME UI)
          // ------------------------------------------
          Positioned.fill(
            child: Image.asset(
              "assets/images/cam_ovl.png",
              fit: BoxFit.cover,
            ),
          ),

          // ------------------------------------------
          // LAYER 2: EFEK VISUAL (Countdown & Blink)
          // ------------------------------------------
          if (_countdown > 0)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
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
              color: Colors.black.withValues(alpha: 0.5), 
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
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
                                    decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topLeft: Radius.circular(10))),
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
          // LAYER 4: BOTTOM CONTROLS (FILTER & START/NEXT)
          // ------------------------------------------
          Positioned(
            left: 0, 
            right: 160, 
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                // FILTER LIST (Hanya muncul jika belum Start)
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
                                image: assetPath != null ? DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover) : null,
                                boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)] : [],
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

                // TOMBOL START (BALIK KE ICON FLUTTER)
                if (!_isSessionActive && !provider.isComplete)
                  GestureDetector(
                    onTap: _startAutoSession,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                      ),
                      child: const Center(
                        // [KEMBALI KE ICON DEFAULT]
                        child: Icon(Icons.camera_alt, color: Colors.white, size: 45),
                      ),
                    ),
                  ),

                // TOMBOL NEXT (Custom Image Button)
                if (provider.isComplete && !_isSessionActive)
                  NextImageButton(
                    onPressed: _onNextPressed,
                  ),
              ],
            ),
          ),

          // ------------------------------------------
          // LAYER 5: BACK BUTTON (POJOK KIRI ATAS)
          // ------------------------------------------
          // Menggunakan Path yang sudah diperbaiki
          if (showBackButton)
            Positioned(
              top: 50,
              left: 30,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Image.asset(
                  "assets/images/back_cam.png", // [PATH SUDAH BENAR]
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

// =========================================================
// WIDGET: NEXT IMAGE BUTTON (Hover & Click Animation)
// =========================================================
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
            width: 180, // [SIZE UPDATED]
            height: 96, 
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}