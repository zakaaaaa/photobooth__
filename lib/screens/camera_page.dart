import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui'; // Diperlukan untuk ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:provider/provider.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/customization_page.dart';
import 'package:photobooth_app/utils/image_filter.dart';
import 'package:photobooth_app/services/http_camera_service.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final HttpCameraService _cameraService = HttpCameraService();
  
  bool _isTakingPicture = false;
  int _countdown = 0;
  bool _showBlink = false;
  
  // Key unik untuk memaksa Mjpeg widget refresh
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

  // Map aset untuk UI Selector
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

  // Helper untuk mendapatkan Matrix Filter Live Preview
  ColorFilter _getLiveFilterMatrix(PhotoFilter filter) {
    switch (filter) {
      case PhotoFilter.vintage:
        return _sepiaMatrix;
      case PhotoFilter.grayscale:
        return _grayscaleMatrix;
      case PhotoFilter.brightness:
        return _brightnessMatrix;
      // Note: Smooth biasanya butuh shader kompleks, 
      // untuk preview live kita biarkan normal/brightness sedikit saja
      case PhotoFilter.smooth: 
         return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
      default:
        return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
  }

  void _startCaptureSequence() async {
    if (_isTakingPicture) return;

    setState(() {
      _isTakingPicture = true;
    });

    // 1. COUNTDOWN
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    setState(() => _countdown = 0);

    // 2. BLINK EFFECT
    setState(() => _showBlink = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _showBlink = false);

    // 3. CAPTURE
    await _takePicture();
  }

  Future<void> _takePicture() async {
    try {
      // Pause Stream UI agar tidak flickering saat proses
      setState(() => _isStreamActive = false);

      // CAPTURE VIA HTTP
      final File? imageFile = await _cameraService.takePicture();

      if (imageFile == null) {
        throw Exception('Gagal mengambil foto');
      }

      final rawBytes = await imageFile.readAsBytes();

      // PROSES FILTER (SIMPAN HASIL JADI)
      if (!mounted) return;
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      final filteredBytes = await ImageFilterUtil.applyFilter(
        rawBytes,
        provider.selectedFilter,
      );

      provider.addPhoto(filteredBytes);
      try { await imageFile.delete(); } catch (_) {}

      // CEK APAKAH SUDAH SELESAI SEMUA FOTO
      if (provider.isComplete) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CustomizationPage()),
        );
      } else {
        // --- LOGIC RESTART LIVE VIEW ---
        debugPrint('🔄 Restarting Live View stream...');
        
        await _cameraService.startLiveView();
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          setState(() {
            _isTakingPicture = false;
            _isStreamActive = true;
            _streamKey = UniqueKey(); 
          });
        }
      }

    } catch (e) {
      debugPrint('❌ Error: $e');
      // Recovery jika error
      await _cameraService.startLiveView();
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
          _isStreamActive = true;
          _streamKey = UniqueKey();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ambil filter yang sedang dipilih dari Provider
    final selectedFilter = context.watch<PhotoProvider>().selectedFilter;

    return Scaffold(
      backgroundColor: Colors.black, // Background dasar
      body: Stack(
        fit: StackFit.expand, // Memastikan children memenuhi layar
        children: [
          // ------------------------------------------
          // LAYER 1: KAMERA FULLSCREEN
          // ------------------------------------------
          _isStreamActive
              ? ColorFiltered(
                  // Aplikasikan filter matrix ke Live View
                  colorFilter: _getLiveFilterMatrix(selectedFilter),
                  child: Mjpeg(
                    key: _streamKey,
                    isLive: true,
                    stream: _cameraService.liveViewUrl,
                    fit: BoxFit.cover, // <--- KUNCI FULLSCREEN (Zoom to fill)
                    error: (context, error, stack) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off, color: Colors.white54, size: 50),
                            const SizedBox(height: 10),
                            const Text(
                              'Menghubungkan ke Kamera...', 
                              style: TextStyle(color: Colors.white54)
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () => setState(() => _streamKey = UniqueKey()),
                              child: const Text("Reconnect"),
                            )
                          ],
                        ),
                      );
                    },
                    loading: (context) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                )
              : Container(
                  color: Colors.black,
                  child: const Center(child: CircularProgressIndicator()),
                ),

          // ------------------------------------------
          // LAYER 2: EFEK VISUAL (Countdown & Blink)
          // ------------------------------------------
          if (_countdown > 0)
            Container(
              color: Colors.black45,
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    fontSize: 200, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 20, color: Colors.black)],
                  ),
                ),
              ),
            ),
          
          if (_showBlink) 
            Container(color: Colors.white),

          // ------------------------------------------
          // LAYER 3: UI CONTROLS (Floating Overlay)
          // ------------------------------------------
          SafeArea(
            child: Column(
              children: [
                // --- HEADER: Counter Foto ---
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Consumer<PhotoProvider>(
                    builder: (context, provider, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Pose ${provider.photoCount + 1} / ${provider.targetPhotoCount}',
                          style: const TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(), // Mendorong sisa UI ke bawah

                // --- FOOTER: Filter & Tombol Capture ---
                
                // 1. Filter List
                SizedBox(
                  height: 90,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // Center alignment trick for ListView
                    itemCount: PhotoFilter.values.length,
                    itemBuilder: (context, index) {
                      final filter = PhotoFilter.values[index];
                      final isSelected = selectedFilter == filter;
                      final assetPath = _filterAssets[filter];
                      
                      return Center(
                        child: GestureDetector(
                          onTap: _isTakingPicture ? null : () {
                             Provider.of<PhotoProvider>(context, listen: false)
                                .setSelectedFilter(filter);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: isSelected ? 70 : 55,
                            height: isSelected ? 70 : 55,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.yellowAccent : Colors.white54,
                                width: isSelected ? 3 : 2,
                              ),
                              image: assetPath != null 
                                ? DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover) 
                                : null,
                              boxShadow: isSelected 
                                ? [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)] 
                                : [],
                            ),
                            child: assetPath == null 
                              ? const Icon(Icons.block, color: Colors.white) 
                              : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Tombol Capture Besar
                GestureDetector(
                  onTap: _isTakingPicture ? null : _startCaptureSequence,
                  child: Container(
                    width: 80, 
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isTakingPicture ? Colors.grey : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withOpacity(0.5), width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3), 
                          blurRadius: 10,
                          offset: const Offset(0, 4)
                        )
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isTakingPicture ? Colors.transparent : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: _isTakingPicture
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.camera_alt, color: Colors.white, size: 35),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30), // Margin bawah
              ],
            ),
          ),
        ],
      ),
    );
  }
}