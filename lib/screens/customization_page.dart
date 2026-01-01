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
    'assets/stickers/sticker1.png', // Index 0 (Vertical)
    'assets/stickers/sticker2.png', // Index 1 (Vertical)
    'assets/stickers/sticker3.png', // Index 2 (Vertical)
    'assets/stickers/sticker4.png', // Index 3 (Vertical)
    'assets/stickers/sticker5.png', // Index 4 (Grid)
    'assets/stickers/sticker6.png', // Index 5 (Grid)
    'assets/stickers/sticker7.png', // Index 6 (Grid)
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
      // 🔴 FITUR 2: DESELECT KETIKA KLIK DI MANA SAJA
      body: GestureDetector(
        onTap: () {
          // Jika user klik area kosong (selain stiker), hilangkan seleksi
          if (_selectedStickerIndex != null) {
            setState(() {
              _selectedStickerIndex = null;
            });
          }
        },
        behavior: HitTestBehavior.translucent, // Agar bisa klik tembus area kosong
        child: Container(
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
      ),
    );
  }

  // ==========================================
  // PANEL 1: PREVIEW (CANVAS)
  // ==========================================
  Widget _buildPreviewPanel() {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        
        // -----------------------------------------------------------
        // 📐 1. PENGATURAN UKURAN KERTAS / FRAME (FRAME SIZE)
        // -----------------------------------------------------------
        double currentFrameWidth;
        double? currentFrameHeight; 

        if (provider.selectedMode == FrameMode.custom) {
          if (provider.customLayout == CustomLayout.vertical) {
            // A. Ukuran Kertas Custom Vertical (Strip)
            currentFrameWidth = 230.0;  
            currentFrameHeight = 515.0; 
          } else {
            // B. Ukuran Kertas Custom Grid (Kartu)
            currentFrameWidth = 400.0; 
            currentFrameHeight = 515.0; 
          }
        } else {
          // C. Ukuran Kertas Static Mode
          currentFrameWidth = 344.0; 
          currentFrameHeight = null; // Auto height mengikuti gambar frame
        }
        // -----------------------------------------------------------

        // GestureDetector di sini dihapus karena sudah ada di Body (Global)
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 40, left: 20, right: 20),
            width: currentFrameWidth,
            height: currentFrameHeight,
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
            ),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // LAYER 1: LAYOUT FOTO (Isi)
                _buildPhotoLayout(provider),

                // LAYER 2: FRAME OVERLAY (Static Only)
                if (provider.selectedMode == FrameMode.static && provider.selectedFrameAsset != null)
                   IgnorePointer(
                     child: Image.asset(
                       provider.selectedFrameAsset!,
                       fit: BoxFit.contain, 
                       width: currentFrameWidth,
                     ),
                   ),

                // LAYER 3: STICKERS (SATU PAKET)
                ...provider.stickers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final sticker = entry.value;
                  return Positioned(
                    // 🔴 PAKSA POSISI DI 0,0 (Supaya pas menutup frame)
                    left: 0, 
                    top: 0,
                    // 🔴 KIRIM UKURAN FRAME KE WIDGET STIKER
                    child: _buildEditableSticker(
                      sticker, 
                      index, 
                      _selectedStickerIndex == index, 
                      provider,
                      frameWidth: currentFrameWidth, // <-- Kirim Lebar Frame
                      frameHeight: currentFrameHeight, // <-- Kirim Tinggi Frame
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // LOGIKA LAYOUT MANAGER
  // ==========================================
  Widget _buildPhotoLayout(PhotoProvider provider) {
    if (provider.selectedMode == FrameMode.custom) {
      return Container(
        decoration: BoxDecoration(
          color: provider.frameColor,
          image: provider.frameTexture != null
            ? DecorationImage(image: AssetImage(provider.frameTexture!), fit: BoxFit.cover)
            : null,
        ),
        child: provider.customLayout == CustomLayout.vertical 
          ? _buildCustomVerticalLayout(provider) 
          : _buildCustomGridLayout(provider),
      );
    } 
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
  // ⚙️ 1. PENGATURAN FOTO CUSTOM VERTIKAL (STRIP)
  // =========================================================
  Widget _buildCustomVerticalLayout(PhotoProvider provider) {
    // Ukuran Foto
    const double photoWidth  = 170.0; 
    const double photoHeight = 110.0; 
    const double spacing     = 8.0;   
    const double radius      = 20.0;  
    const double border      = 1.0;   

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: provider.photos.map((photo) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: spacing / 2),
            child: _buildSinglePhoto(
              bytes: photo.imageData, 
              w: photoWidth, 
              h: photoHeight,
              radius: radius,
              border: border,
            ),
          );
        }).toList(),
      ),
    );
  }

  // =========================================================
  // ⚙️ 2. PENGATURAN FOTO CUSTOM GRID (KARTU 2x2)
  // =========================================================
  Widget _buildCustomGridLayout(PhotoProvider provider) {
    // Ukuran Foto
    const double gridPhotoWidth  = 180.0; 
    const double gridPhotoHeight = 160.0; 
    const double gridSpacing     = 10.0;  
    const double gridRadius      = 20.0;  
    const double gridBorder      = 2.0;   

    return Center(
      child: Wrap(
        spacing: gridSpacing,    
        runSpacing: gridSpacing, 
        alignment: WrapAlignment.center,
        children: provider.photos.map((photo) {
          return _buildSinglePhoto(
            bytes: photo.imageData, 
            w: gridPhotoWidth, 
            h: gridPhotoHeight,
            radius: gridRadius,
            border: gridBorder,
          );
        }).toList(),
      ),
    );
  }

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
        border: Border.all(color: Colors.white, width: border),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - border > 0 ? radius - border : 0),
        child: Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }

  // ==========================================
  // PANEL 2: TOOLS (MENU KANAN)
  // ==========================================
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

              if (provider.selectedMode == FrameMode.custom) ...[
                 const Text("Choose Layout:", style: TextStyle(fontWeight: FontWeight.bold)),
                 const SizedBox(height: 10),
                 Row(
                   children: [
                     _buildLayoutOption(provider, CustomLayout.vertical, Icons.view_agenda, "Strip"),
                     const SizedBox(width: 15),
                     _buildLayoutOption(provider, CustomLayout.grid, Icons.grid_view, "Grid Card"),
                   ],
                 ),
                 const SizedBox(height: 20),
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
      onTap: () {
        // Cek apakah layout berubah
        if (provider.customLayout != layout) {
          provider.setCustomLayout(layout);
          
          // 🔴 FITUR 1: AUTO CLEAR STICKERS KETIKA GANTI LAYOUT
          // Kita hapus stiker satu per satu karena Provider tidak punya fungsi clearSticker khusus
          while (provider.stickers.isNotEmpty) {
            provider.removeSticker(0);
          }
          // Reset seleksi juga
          setState(() {
            _selectedStickerIndex = null;
          });
        }
      },
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
        
        // LOGIKA FILTER STIKER
        List<String> displayedStickers;
        if (provider.selectedMode == FrameMode.custom) {
           if (provider.customLayout == CustomLayout.vertical) {
             displayedStickers = _stickers.sublist(0, 4); 
           } else {
             displayedStickers = _stickers.sublist(4); 
           }
        } else {
           displayedStickers = _stickers;
        }

        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Sticker Package', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5, 
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: displayedStickers.length, 
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => provider.addSticker(displayedStickers[index]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Image.asset(displayedStickers[index]),
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

// --- STIKER STATIS & FULL SIZE (PAKET) ---
  Widget _buildEditableSticker(
    StickerData sticker, 
    int index, 
    bool isSelected, 
    PhotoProvider provider, {
    required double frameWidth, 
    required double? frameHeight,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStickerIndex = index;
        });
      },
      child: Stack(
        children: [
          Transform.rotate(
            angle: sticker.rotation,
            // Container pembungkus stiker TANPA DECORATION BORDER
            child: Container(
              // 🔴 Alignment TopLeft tetap penting untuk anchor point
              alignment: Alignment.topLeft, 

              // HAPUS DECORATION BORDER DISINI AGAR UKURAN MURNI
              // decoration: isSelected ? ... : null,  <-- HAPUS INI

              // Gambar Stiker
              child: Image.asset(
                sticker.assetPath, 
                width: frameWidth, 
                height: frameHeight, 
                fit: BoxFit.contain, 
              ),
            ),
          ),
          
          // Indikator Seleksi: Hanya Tombol Hapus (X)
          // Border biru dihilangkan agar tidak mengganggu layout pixel-perfect
          if (isSelected)
            Positioned(
              right: 10, top: 10, 
              child: GestureDetector(
                onTap: () {
                  provider.removeSticker(index);
                  setState(() => _selectedStickerIndex = null);
                },
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Icon(Icons.cancel, color: Colors.red, size: 30),
                ),
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