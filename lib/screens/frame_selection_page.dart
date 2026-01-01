import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'payment_page.dart';
import 'static_frame_template_page.dart'; // <-- PENTING: IMPORT HALAMAN BARU TADI

class FrameSelectionPage extends StatelessWidget {
  const FrameSelectionPage({super.key});

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
          "PILIH GAYA FOTO",
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
          // 1. BACKGROUND IMAGE (Gunakan aset yang diminta)
          Image.asset(
            'assets/images/camera_background.png',
            fit: BoxFit.cover,
          ),
          // 2. OVERLAY GELAP (Agar konten terbaca jelas)
          Container(color: Colors.black.withOpacity(0.6)),

          // 3. KONTEN KARTU PILIHAN
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- KARTU 1: STATIC FRAME ---
                  Expanded(
                    child: _buildSelectionCard(
                      context,
                      title: "STATIC FRAME",
                      subtitle: "Pilihan Template Siap Pakai",
                      description: "Pilih berbagai layout menarik.\nAda pilihan 3 foto (strip) atau 4 foto (grid).",
                      icon: Icons.grid_view_rounded,
                      colorAccent: Colors.blueAccent,
                      photoCountBadge: "3 / 4 Foto",
                      onTap: () => _selectStaticFrame(context), // <-- Arahkan ke fungsi baru
                    ),
                  ),

                  const SizedBox(width: 30),

                  // --- KARTU 2: CUSTOM MODE ---
                  Expanded(
                    child: _buildSelectionCard(
                      context,
                      title: "CUSTOM MODE",
                      subtitle: "Bebas Berkreasi",
                      description: "Mode bebas! Edit fotomu dengan filter & stiker sesuka hati nanti.",
                      icon: Icons.brush_rounded,
                      colorAccent: Colors.pinkAccent,
                      photoCountBadge: "Fix 3 Foto",
                      onTap: () => _selectCustomFrame(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET CARD (Masih sama dengan desain modern sebelumnya)
  Widget _buildSelectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color colorAccent,
    required String photoCountBadge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        splashColor: colorAccent.withOpacity(0.3),
        hoverColor: colorAccent.withOpacity(0.1),
        child: Container(
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: colorAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorAccent.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Icon(icon, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 40),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorAccent,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white54,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.only(bottom: 30),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: colorAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  photoCountBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGIKA NAVIGASI BARU ---

  void _selectStaticFrame(BuildContext context) {
    // REVISI: Tidak langsung set provider & payment.
    // Tapi masuk ke halaman pemilihan template dulu.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => StaticFrameTemplatePage()),
    );
  }

  void _selectCustomFrame(BuildContext context) {
    // Custom mode masih sama, langsung set 3 foto dan ke payment
    Provider.of<PhotoProvider>(context, listen: false).setFrameMode(
      FrameMode.custom,
      photoCount: 4,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PaymentPage()),
    );
  }
}