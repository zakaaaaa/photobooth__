import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'payment_page.dart';

class FrameTemplate {
  final String id;
  final String assetPath;
  final int photoCount;
  final FrameLayout layout; // <--- Tambah ini

  FrameTemplate({
    required this.id,
    required this.assetPath,
    required this.photoCount,
    required this.layout, // <--- Wajib diisi
  });
}

class StaticFrameTemplatePage extends StatelessWidget {
  StaticFrameTemplatePage({super.key});

// 2. Update Data Templates (INI BAGIAN PENTING)
// Kamu harus sesuaikan angka-angka ini dengan desain PNG kamu!
final List<FrameTemplate> templates = [
  // CONTOH 1: Frame Strip (Biasanya butuh padding atas/bawah besar)
  FrameTemplate(
    id: 'frame_1',
    assetPath: 'assets/frames/frame_01.png', 
    photoCount: 3, 
    layout: const FrameLayout(
      topPadding: 70,    // Dorong foto ke bawah
      bottomPadding: 15, // Dorong dari bawah
      leftPadding: 5,    // Strip kiri
      rightPadding: 5,   // Strip kanan
      horizontalSpacing: 2, // Jarak antar strip kiri & kanan
      verticalSpacing: 10,   // Jarak antar foto
      childAspectRatio: 1.2, // Foto agak landscape
    ),
  ),

  // CONTOH 2: Frame Grid (Biasanya padding rata)
  FrameTemplate(
    id: 'frame_2',
    assetPath: 'assets/frames/frame_02.png', 
    photoCount: 4, 
    layout: const FrameLayout(
      topPadding: 20,
      leftPadding: 10,
      rightPadding: 5,
      bottomPadding: 40, // Mungkin bawah lebih tebal ada logo
      horizontalSpacing: 5,
      verticalSpacing: 15,
      childAspectRatio: 1.0, // Foto kotak
    ),
  ),
  
  FrameTemplate(
    id: 'frame_3',
    assetPath: 'assets/frames/frame_03.png', 
    photoCount: 3, 
    layout: const FrameLayout(
      topPadding: 120,    // Dorong foto ke bawah
      bottomPadding: 120, // Dorong dari bawah
      leftPadding: 40,    // Strip kiri
      rightPadding: 40,   // Strip kanan
      horizontalSpacing: 30, // Jarak antar strip kiri & kanan
      verticalSpacing: 15,   // Jarak antar foto
      childAspectRatio: 1.2, // Foto agak landscape
    ),
  ),
  FrameTemplate(
    id: 'frame_4',
    assetPath: 'assets/frames/frame_04.png', 
    photoCount: 3, 
    layout: const FrameLayout(
      topPadding: 120,    // Dorong foto ke bawah
      bottomPadding: 120, // Dorong dari bawah
      leftPadding: 40,    // Strip kiri
      rightPadding: 40,   // Strip kanan
      horizontalSpacing: 30, // Jarak antar strip kiri & kanan
      verticalSpacing: 15,   // Jarak antar foto
      childAspectRatio: 1.2, // Foto agak landscape
    ),
  ),
];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "PILIH FRAME",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. BACKGROUND
          Image.asset(
            'assets/images/camera_background.png', 
            fit: BoxFit.cover,
          ),
          
          // 2. OVERLAY GELAP
          Container(color: Colors.black.withOpacity(0.7)),

          // 3. GRID FRAME (UKURAN LEBIH KECIL)
          Padding(
            padding: const EdgeInsets.fromLTRB(150, 100, 150, 40), // Padding lebih besar
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, // REVISI: Jadi 3 Kolom (Otomatis lebih kecil)
                crossAxisSpacing: 30,
                mainAxisSpacing: 30,
                childAspectRatio: 0.6, // Rasio tetap memanjang
              ),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return _buildFrameCard(context, template);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameCard(BuildContext context, FrameTemplate template) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
       onTap: () {
  Provider.of<PhotoProvider>(context, listen: false).setFrameMode(
    FrameMode.static,
    photoCount: template.photoCount,
    frameAsset: template.assetPath,
    layout: template.layout, // <--- KIRIM DATA LAYOUT KE PROVIDER
  );

  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const PaymentPage()),
  );
},
        borderRadius: BorderRadius.circular(15),
        splashColor: Colors.white.withOpacity(0.3),
        child: Container(
          padding: const EdgeInsets.all(8), // Padding dalam container
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15), // Agak lebih terang dikit
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Column(
            children: [
              // GAMBAR FRAME
              Expanded(
                child: Image.asset(
                  template.assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    // Tampilan jika gambar masih error/missing
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.broken_image, color: Colors.redAccent, size: 30),
                          const SizedBox(height: 5),
                          Text(
                            template.assetPath.split('/').last,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // Keterangan Kecil (Opsional, biar tau ini frame apa)
              const SizedBox(height: 8),
              Text(
                "${template.photoCount} Pose",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}