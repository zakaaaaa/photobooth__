import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photobooth_app/providers/photo_provider.dart';
import 'package:photobooth_app/screens/camera_page.dart';

// ==========================================
// HALAMAN UTAMA: MENU PILIHAN PREVIEW
// ==========================================
class PreviewPrintPage extends StatefulWidget {
  const PreviewPrintPage({super.key});

  @override
  State<PreviewPrintPage> createState() => _PreviewPrintPageState();
}

class _PreviewPrintPageState extends State<PreviewPrintPage> {
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              // HEADER
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: const Text(
                  'Preview Result',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                  ),
                ),
              ),

              const Spacer(),

              // MENU PILIHAN (3 TOMBOL BESAR)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildMenuCard(
                    icon: Icons.photo_library, 
                    label: "PHOTO RESULT", 
                    color: Colors.blueAccent,
                    onTap: () => _navigateTo(context, const _PhotoPreviewPage()),
                  ),
                  const SizedBox(width: 20),
                  _buildMenuCard(
                    icon: Icons.gif_box, 
                    label: "GIF PREVIEW", 
                    color: Colors.purpleAccent,
                    onTap: () => _navigateTo(context, const _GifPreviewPage()),
                  ),
                  const SizedBox(width: 20),
                  _buildMenuCard(
                    icon: Icons.video_collection, 
                    label: "VIDEO PREVIEW", 
                    color: Colors.orangeAccent,
                    onTap: () => _navigateTo(context, const _VideoPreviewPage()),
                  ),
                ],
              ),

              const Spacer(),

              // FOOTER: PRINT & HOME
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.black54,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                         Provider.of<PhotoProvider>(context, listen: false).reset();
                         Navigator.of(context).pushAndRemoveUntil(
                           MaterialPageRoute(builder: (_) => const CameraPage()),
                           (route) => false,
                         );
                      },
                      icon: const Icon(Icons.home, color: Colors.white),
                      label: const Text("Home", style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Implement Print Functionality
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text("Processing Print...")),
                         );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text("PRINT NOW"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildMenuCard({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150, height: 150,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 15, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}


// =========================================================
// PAGE 1: PHOTO PREVIEW (Menampilkan Hasil Akhir + Random)
// =========================================================
class _PhotoPreviewPage extends StatefulWidget {
  const _PhotoPreviewPage();

  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  List<int> _strip1Order = [];
  List<int> _strip2Order = [];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final count = provider.photos.length;
    _strip1Order = List.generate(count, (i) => i);
    _strip2Order = List.from(_strip1Order)..shuffle(math.Random());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text(""), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
          return Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // STRIP 1 (ORIGINAL)
                  _buildFinalFrame(provider, _strip1Order),
                  
                  // JIKA CUSTOM, TAMPILKAN STRIP 2 (RANDOM)
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
    double width;
    double height;
    
    if (provider.selectedMode == FrameMode.custom) {
      if (provider.customLayout == CustomLayout.vertical) {
        width = 230.0; height = 515.0; 
      } else {
        width = 400.0; height = 515.0;
      }
    } else {
      width = 344.0; height = 515.0; // Static size estimation
    }

    return Container(
      width: width, height: height,
      decoration: const BoxDecoration(color: Colors.white),
      child: Stack(
        fit: StackFit.expand,
        children: [
           // LAYER 1: CONTENT
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

          // LAYER 2: FRAME (Static)
          if (provider.selectedMode == FrameMode.static && provider.selectedFrameAsset != null)
             IgnorePointer(child: Image.asset(provider.selectedFrameAsset!, fit: BoxFit.contain, width: width)),

          // LAYER 3: STICKERS
          ...provider.stickers.map((s) => Positioned(left: 0, top: 0, child: Image.asset(s.assetPath, width: width, height: height, fit: BoxFit.contain))),
        ],
      ),
    );
  }

  Widget _buildCustomContent(PhotoProvider provider, List<int> indices) {
    final photos = indices.map((i) => i < provider.photos.length ? provider.photos[i].imageData : Uint8List(0)).toList();
    if (provider.customLayout == CustomLayout.vertical) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: photos.map((img) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Image.memory(img, width: 170, height: 110, fit: BoxFit.cover))).toList()));
    } else {
      return Center(child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: photos.map((img) => Image.memory(img, width: 180, height: 160, fit: BoxFit.cover)).toList()));
    }
  }

  Widget _buildStaticContent(PhotoProvider provider, List<int> indices) {
    final photos = indices.map((i) => i < provider.photos.length ? provider.photos[i].imageData : Uint8List(0)).toList();
    final layout = provider.selectedLayout;
    return Container(
      padding: EdgeInsets.fromLTRB(layout.leftPadding, layout.topPadding, layout.rightPadding, layout.bottomPadding),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: layout.horizontalSpacing, mainAxisSpacing: layout.verticalSpacing, childAspectRatio: layout.childAspectRatio),
        itemCount: photos.length,
        itemBuilder: (context, index) => Image.memory(photos[index], fit: BoxFit.cover),
      ),
    );
  }
}


// =========================================================
// PAGE 2: GIF PREVIEW (Fullscreen Slideshow Tanpa Frame)
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
      if (provider.photos.isNotEmpty) setState(() => _index = (_index + 1) % provider.photos.length);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text(""), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
          if (provider.photos.isEmpty) return const Center(child: Text("No Photos", style: TextStyle(color: Colors.white)));
          return Center(
            child: Image.memory(
              provider.photos[_index].imageData,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
          );
        },
      ),
    );
  }
}


// =========================================================
// PAGE 3: VIDEO PREVIEW (Slideshow DENGAN Frame + Random)
// =========================================================
class _VideoPreviewPage extends StatefulWidget {
  const _VideoPreviewPage();

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  int _index = 0;
  Timer? _timer;
  List<int> _randomOrder = [];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    _randomOrder = List.generate(provider.photos.length, (i) => i)..shuffle();
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (provider.photos.isNotEmpty) setState(() => _index = (_index + 1) % provider.photos.length);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text(""), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: Consumer<PhotoProvider>(
        builder: (context, provider, _) {
           // VIDEO MODE: Frame Tetap, Tapi Foto di dalamnya berubah-ubah (Slideshow)
           // Kita gunakan _PhotoPreviewPage logic tapi dengan data dinamis
           
           // Hack: Kita buat List<int> palsu yang isinya index foto saat ini saja
           // Agar semua slot frame menampilkan foto slideshow yang sedang aktif
           // Atau jika ingin tetap 4 foto tapi posisinya ganti-ganti, bisa pakai logic lain.
           // Disini saya buat "Frame Diam, Isi Foto Slideshow"
           
           final currentPhotoIndex = _randomOrder[_index];
           final singlePhotoIndices = List.filled(provider.targetPhotoCount, currentPhotoIndex);

           return Center(
             child: Transform.scale(
               scale: 0.85,
               child: _PhotoPreviewPageState()._buildFinalFrame(provider, singlePhotoIndices), // Reuse widget
             ),
           );
        },
      ),
    );
  }
}