import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:math' as math;
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/camera_page.dart';
import 'package:photobooth_app/screens/preview_print_page.dart';
import 'dart:typed_data';

class CustomizationPage extends StatefulWidget {
  const CustomizationPage({super.key});

  @override
  State<CustomizationPage> createState() => _CustomizationPageState();
}

class _CustomizationPageState extends State<CustomizationPage> {
  int? _selectedStickerIndex;
  List<Uint8List>? _randomizedPhotos;

  final List<String> _textures = [
    'assets/textures/texture1.png',
    'assets/textures/texture2.png',
    'assets/textures/texture3.png',
    'assets/textures/texture4.png',
    'assets/textures/texture5.png',
    'assets/textures/texture6.png',
  ];

  final List<String> _stickers = [
    'assets/stickers/sticker1.png',
    'assets/stickers/sticker2.png',
    'assets/stickers/sticker3.png',
    'assets/stickers/sticker4.png',
    'assets/stickers/sticker5.png',
    'assets/stickers/sticker6.png',
    'assets/stickers/sticker7.png',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareRandomizedPhotos();
    });
  }

  void _prepareRandomizedPhotos() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    if (provider.selectedMode == FrameMode.static && provider.targetPhotoCount == 3) {
      final originalPhotos = provider.photos.map((p) => p.imageData).toList();
      List<Uint8List> pool = [...originalPhotos, ...originalPhotos]; 
      pool.shuffle(math.Random()); 
      setState(() {
        _randomizedPhotos = pool;
      });
    }
  }

  void _showColorPicker(BuildContext context) {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Background Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: provider.frameColor,
            onColorChanged: (color) => provider.setFrameColor(color),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/camera_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Customize Your Photo',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(flex: 2, child: _buildPreviewPanel()),
                    Expanded(flex: 3, child: _buildCustomizationPanel()),
                  ],
                ),
              ),
              _buildFooterButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        const double frameWidth = 460.0; 
        const double frameHeight = 500.0; 

        return GestureDetector(
          onTap: () => setState(() => _selectedStickerIndex = null),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              width: frameWidth,
              height: frameHeight,
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // LAYER 1: SUSUNAN FOTO (Custom / Static)
                  _buildPhotoLayout(provider, frameWidth, frameHeight),

                  // LAYER 2: FRAME OVERLAY (Static Only)
                  if (provider.selectedMode == FrameMode.static && provider.selectedFrameAsset != null)
                    IgnorePointer( 
                      child: Image.asset(provider.selectedFrameAsset!, fit: BoxFit.fill),
                    ),

                  // LAYER 3: STICKERS (Statis, hanya resize/rotate)
                  ...provider.stickers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final sticker = entry.value;
                    return Positioned(
                      left: sticker.position.dx,
                      top: sticker.position.dy,
                      child: _buildEditableSticker(sticker, index, _selectedStickerIndex == index, provider),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoLayout(PhotoProvider provider, double containerWidth, double containerHeight) {
    // === LOGIKA CUSTOM MODE (4 Foto: Vertical vs Grid) ===
    if (provider.selectedMode == FrameMode.custom) {
      
      // Background Custom
      return Container(
        decoration: BoxDecoration(
          color: provider.frameColor,
          image: provider.frameTexture != null
            ? DecorationImage(image: AssetImage(provider.frameTexture!), fit: BoxFit.cover)
            : null,
        ),
        child: provider.customLayout == CustomLayout.vertical 
          ? _buildCustomVerticalLayout(provider, containerWidth, containerHeight)
          : _buildCustomGridLayout(provider, containerWidth, containerHeight),
      );
    } 
    // === LOGIKA STATIC MODE (Grid Template) ===
    else {
      final layout = provider.selectedLayout;
      return Container(
        color: Colors.white, 
        padding: EdgeInsets.fromLTRB(layout.leftPadding, layout.topPadding, layout.rightPadding, layout.bottomPadding), 
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, 
            crossAxisSpacing: layout.horizontalSpacing,
            mainAxisSpacing: layout.verticalSpacing,
            childAspectRatio: layout.childAspectRatio,
          ),
          itemCount: provider.targetPhotoCount == 3 ? 6 : 4,
          itemBuilder: (context, index) {
            final photosToShow = (provider.targetPhotoCount == 3) 
                ? (_randomizedPhotos ?? []) 
                : provider.photos.map((e) => e.imageData).toList();
            if (index >= photosToShow.length) return Container(); 
            return Image.memory(photosToShow[index], fit: BoxFit.cover);
          },
        ),
      );
    }
  }

// =========================================================
  // 1. LAYOUT CUSTOM: VERTIKAL (Pengaturan Ukuran Sendiri)
  // =========================================================
  Widget _buildCustomVerticalLayout(PhotoProvider provider, double containerWidth, double containerHeight) {
    
    // --- ⚙️ KONFIGURASI KHUSUS VERTIKAL ⚙️ ---
    const double photoWidth = 180.0;   // Lebar Foto
    const double photoHeight = 90.0;   // Tinggi Foto
    const double spacing = 10.0;       // Jarak antar foto
    const double borderRadius = 10.0;  // Lengkungan sudut
    const double borderWidth = 4.0;    // Tebal frame putih
    // ------------------------------------------

    return Column(
      mainAxisAlignment: MainAxisAlignment.center, // Posisi di tengah vertikal
      children: provider.photos.map((photo) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: spacing / 2),
          child: _buildSinglePhoto(
            bytes: photo.imageData, 
            w: photoWidth, 
            h: photoHeight,
            radius: borderRadius,
            border: borderWidth,
          ),
        );
      }).toList(),
    );
  }

  // =========================================================
  // 2. LAYOUT CUSTOM: GRID 2x2 (Pengaturan Ukuran Sendiri)
  // =========================================================
  Widget _buildCustomGridLayout(PhotoProvider provider, double containerWidth, double containerHeight) {
    
    // --- ⚙️ KONFIGURASI KHUSUS GRID ⚙️ ---
    const double photoWidth = 100.0;   // Lebar Foto (Lebih kecil biar muat 2)
    const double photoHeight = 100.0;  // Tinggi Foto (Misal kotak)
    const double spacing = 15.0;       // Jarak antar foto
    const double borderRadius = 15.0;  // Lengkungan sudut (Beda dengan vertikal)
    const double borderWidth = 2.0;    // Tebal frame putih (Lebih tipis)
    // --------------------------------------

    return Center(
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        alignment: WrapAlignment.center,
        children: provider.photos.map((photo) {
          return _buildSinglePhoto(
            bytes: photo.imageData, 
            w: photoWidth, 
            h: photoHeight,
            radius: borderRadius,
            border: borderWidth,
          );
        }).toList(),
      ),
    );
  }

  // =========================================================
  // 3. WIDGET FOTO SATUAN (Helper)
  // =========================================================
  Widget _buildSinglePhoto({
    required Uint8List bytes, 
    required double w, 
    required double h,
    required double radius,
    required double border,
  }) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        // Frame Putih
        border: Border.all(color: Colors.white, width: border),
        borderRadius: BorderRadius.circular(radius),
        // Shadow
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      // ClipRRect agar foto mengikuti lengkungan border
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - border),
        child: Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCustomizationPanel() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.selectedMode == FrameMode.static ? 'Stickers' : 'Custom Layout & Tools',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              const SizedBox(height: 10),

              // === FITUR KHUSUS CUSTOM MODE ===
              if (provider.selectedMode == FrameMode.custom) ...[
                 // 1. PILIHAN LAYOUT (Vertical vs Grid)
                 const Text("Choose Layout:", style: TextStyle(fontWeight: FontWeight.bold)),
                 const SizedBox(height: 10),
                 Row(
                   children: [
                     _buildLayoutOption(provider, CustomLayout.vertical, Icons.view_agenda, "Vertical"),
                     const SizedBox(width: 15),
                     _buildLayoutOption(provider, CustomLayout.grid, Icons.grid_view, "Grid 2x2"),
                   ],
                 ),
                 const SizedBox(height: 20),
                 
                 // 2. Background Color/Texture
                 _buildFrameColorSection(),
                 const SizedBox(height: 20),
              ],

              _buildStickersSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayoutOption(PhotoProvider provider, CustomLayout layout, IconData icon, String label) {
    final isSelected = provider.customLayout == layout;
    return GestureDetector(
      onTap: () => provider.setCustomLayout(layout),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black54),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameColorSection() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Background Style', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _showColorPicker(context),
                  child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: provider.frameColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey, width: 2),
                    ),
                    child: const Icon(Icons.colorize, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _textures.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () => provider.setFrameTexture(_textures[index]),
                          child: Container(
                            width: 60,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: provider.frameTexture == _textures[index] ? Colors.blue : Colors.grey, width: 2),
                              image: DecorationImage(image: AssetImage(_textures[index]), fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStickersSection() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Stickers (Resize Only)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _stickers.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => provider.addSticker(_stickers[index]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Image.asset(_stickers[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- REVISI: STIKER STATIS (TIDAK BISA DIGESER) ---
  Widget _buildEditableSticker(StickerData sticker, int index, bool isSelected, PhotoProvider provider) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStickerIndex = index;
        });
      },
      // ❌ onPanUpdate DIHAPUS (Biar posisi tidak bisa digeser)
      
      child: Stack(
        children: [
          Transform.rotate(
            angle: sticker.rotation,
            child: Container(
              decoration: isSelected 
                ? BoxDecoration(border: Border.all(color: Colors.blue, width: 2)) 
                : null,
              child: Image.asset(
                sticker.assetPath,
                width: sticker.size,
                height: sticker.size,
              ),
            ),
          ),
          // Handle Resize (Tetap Ada)
          if (isSelected)
            Positioned(
              right: -10, bottom: -10,
              child: GestureDetector(
                onPanUpdate: (details) {
                   provider.updateStickerSize(index, sticker.size + details.delta.dx);
                },
                child: const Icon(Icons.zoom_out_map, color: Colors.blue, size: 20),
              ),
            ),
          // Handle Rotate (Tetap Ada)
          if (isSelected)
            Positioned(
              right: -10, top: -10,
              child: GestureDetector(
                onPanUpdate: (details) {
                   final center = Offset(sticker.size / 2, sticker.size / 2);
                   final angle = math.atan2(
                     details.localPosition.dy - center.dy,
                     details.localPosition.dx - center.dx,
                   );
                   provider.updateStickerRotation(index, angle);
                },
                child: const Icon(Icons.rotate_right, color: Colors.green, size: 20),
              ),
            ),
          // Handle Delete (Tetap Ada)
          if (isSelected)
            Positioned(
              left: -10, top: -10,
              child: GestureDetector(
                onTap: () {
                  provider.removeSticker(index);
                  setState(() => _selectedStickerIndex = null);
                },
                child: const Icon(Icons.cancel, color: Colors.red, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooterButtons() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              Provider.of<PhotoProvider>(context, listen: false).clearPhotos();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const CameraPage()),
              );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            ),
          ),

          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PreviewPrintPage()),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Finish & Print'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            ),
          ),
        ],
      ),
    );
  }
}