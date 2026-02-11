import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../providers/photo_provider.dart';
import '../services/api_service.dart';
import 'frame_selection_page.dart'; // <--- 1. UBAH IMPORT KE SINI

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // State UI
  bool _isSelectionMode = true; // True = Pilih Menu, False = Proses Bayar
  bool _isLoading = false;
  bool _isPaid = false;
  bool _isChecking = false;

  // Payment Data
  String? _paymentUrl;
  String? _currentUuid;
  Timer? _pollingTimer;
  final double _sessionPrice = 10000;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // --- LOGIC 1: MEMILIH METODE PEMBAYARAN ---
  void _onSelectQRIS() {
    setState(() {
      _isSelectionMode = false; // Sembunyikan menu, tampilkan loading
      _isLoading = true;
    });
    // Jalankan proses generate link (Existing Logic)
    _initPaymentProcess();
  }

  void _onSelectVoucher() {
    // Logic Voucher (Placeholder)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fitur Voucher akan segera hadir!")),
    );
  }

  // --- LOGIC 2: PROSES GENERATE LINK ---
  void _initPaymentProcess() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // A. Generate UUID Baru
    String newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    _currentUuid = newUuid; 
    provider.setSessionUuid(newUuid); 

    // B. Start Session Database
    bool sessionCreated = await apiService.startSession(newUuid);
    if (!sessionCreated) {
      if (mounted) {
        setState(() { _isLoading = false; _isSelectionMode = true; }); // Balik ke menu
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal membuat sesi database")));
      }
      return;
    }

    // C. Request URL Pembayaran
    String? url = await apiService.generatePaymentLink(newUuid, _sessionPrice);

    if (mounted) {
      if (url != null) {
        setState(() {
          _paymentUrl = url;
          _isLoading = false; // Loading selesai, tampilkan tombol kontrol
        });

        _launchPaymentUrl();
        _startPolling(newUuid);
      } else {
        setState(() { _isLoading = false; _isSelectionMode = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal mendapatkan link pembayaran")));
      }
    }
  }

  void _launchPaymentUrl() async {
    if (_paymentUrl != null) {
      final Uri uri = Uri.parse(_paymentUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // --- LOGIC 3: CEK STATUS & POLLING ---
  void _checkStatusManual() async {
    if (_currentUuid == null) return;
    setState(() => _isChecking = true);
    
    final apiService = Provider.of<ApiService>(context, listen: false);
    bool paid = await apiService.checkPaymentStatus(_currentUuid!);

    if (mounted) {
      setState(() => _isChecking = false);
      if (paid) {
        _handlePaymentSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pembayaran belum diterima. Coba refresh lagi.")),
        );
      }
    }
  }

  void _startPolling(String uuid) {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      final apiService = Provider.of<ApiService>(context, listen: false);
      bool paid = await apiService.checkPaymentStatus(uuid);

      if (paid) {
        timer.cancel();
        if (mounted) _handlePaymentSuccess();
      }
    });
  }

  void _handlePaymentSuccess() {
    _pollingTimer?.cancel();
    setState(() { _isPaid = true; });
    
    // Reset data foto lama agar bersih untuk sesi baru
    Provider.of<PhotoProvider>(context, listen: false).reset();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // 2. NAVIGASI KE FRAME SELECTION PAGE
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const FrameSelectionPage()),
        );
      }
    });
  }

  // =========================================================================
  // UI BUILDER
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. BACKGROUND IMAGE
          Positioned.fill(
            child: Image.asset(
              "assets/images/bg.png", // Background Pixel Art
              fit: BoxFit.cover,
            ),
          ),

          // 2. KONTEN UTAMA
          Center(
            child: _isSelectionMode 
              ? _buildSelectionMenu() // TAMPILAN PILIH MENU (QRIS/VOUCHER)
              : _buildPaymentProcessUI(), // TAMPILAN PROSES BAYAR
          ),
        ],
      ),
    );
  }

  // --- WIDGET: MENU PILIHAN (QRIS / VOUCHER) ---
  Widget _buildSelectionMenu() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // TITLE
        const OutlinedText(
          text: "CHOOSE\nPAYMENT METHOD",
          fontFamily: 'Ambitsek',
          fontSize: 70,
          textColor: Color(0xFFFFED00),
          outlineColor: Color(0xFFEF7D30),
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          hasShadow: true,
        ),
        
        const SizedBox(height: 50),

        // KARTU PILIHAN (ROW)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // KARTU 1: QRIS
            PixelCard(
              title: "QRIS",
              imagePath: "assets/images/qris.png", 
              onTap: _onSelectQRIS,
            ),

            const SizedBox(width: 30), // Jarak antar kartu

            // KARTU 2: VOUCHER
            PixelCard(
              title: "VOUCHER",
              imagePath: "assets/images/voucher.png", 
              onTap: _onSelectVoucher,
            ),
          ],
        ),
      ],
    );
  }

  // --- WIDGET: UI SAAT PROSES BAYAR (LOADING / TOMBOL BROWSER) ---
  Widget _buildPaymentProcessUI() {
    // Container Putih Transparan agar tulisan terbaca di atas background pixel
    return Container(
      padding: const EdgeInsets.all(25),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(width: 4, color: Colors.black),
        boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(5, 5), blurRadius: 0)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text("Menghubungkan ke Server...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ] 
          else if (_isPaid) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text("SUKSES!", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, fontFamily: 'Ambitsek')),
            const Text("Silakan Pilih Frame...", style: TextStyle(fontSize: 16)), // Text diupdate
          ] 
          else ...[
            const Text("Menunggu Pembayaran", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Ambitsek')),
            const SizedBox(height: 10),
            Text("Total: Rp ${_sessionPrice.toStringAsFixed(0)}", style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 30),
            
            // Tombol Buka Browser
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: _launchPaymentUrl,
              icon: const Icon(Icons.open_in_browser),
              label: const Text("Buka Halaman Bayar"),
            ),
            
            const SizedBox(height: 15),
            
            // Tombol Cek Status (Dengan Fitur Bypass Long Press)
            GestureDetector(
              onLongPress: () {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚡ DEV MODE: Bypassing Payment...")));
                 _handlePaymentSuccess();
              },
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                onPressed: _isChecking ? null : _checkStatusManual,
                icon: _isChecking 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.refresh),
                label: Text(_isChecking ? "Mengecek..." : "Saya Sudah Bayar"),
              ),
            ),
            
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                setState(() => _isSelectionMode = true); // Tombol Kembali ke Menu
              }, 
              child: const Text("Kembali ke Pilihan")
            ),
          ]
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET: PIXEL CARD (TIDAK BERUBAH)
// =========================================================
class PixelCard extends StatefulWidget {
  final String title;
  final String imagePath; 
  final VoidCallback onTap;

  const PixelCard({
    super.key,
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  State<PixelCard> createState() => _PixelCardState();
}

class _PixelCardState extends State<PixelCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Transform.scale(
        scale: _isPressed ? 0.95 : 1.0,
        child: Container(
          width: 300,
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFFC0C0C0), // Abu-abu Windows 95
            border: Border.all(width: 3, color: Colors.black),
            boxShadow: _isPressed 
                ? [] 
                : const [BoxShadow(color: Colors.black54, offset: Offset(6, 6), blurRadius: 0)],
          ),
          child: Column(
            children: [
              // HEADER BIRU
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: const Color(0xFF0000AA), // Biru Tua Retro
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Ambitsek',
                    color: Colors.white,
                    fontSize: 15,
                    letterSpacing: 2,
                  ),
                ),
              ),
              
              // BODY GAMBAR
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Image.asset(
                      widget.imagePath, 
                      fit: BoxFit.contain, 
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
// WIDGET: OUTLINED TEXT (TIDAK BERUBAH)
// =========================================================
class OutlinedText extends StatelessWidget {
  final String text;
  final String fontFamily;
  final double fontSize;
  final Color textColor;
  final Color outlineColor;
  final FontWeight fontWeight;
  final double letterSpacing;
  final bool hasShadow;

  const OutlinedText({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.outlineColor,
    this.fontWeight = FontWeight.normal,
    this.letterSpacing = 0.0,
    this.hasShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (hasShadow)
          Positioned(
            top: 4, left: 4,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
                color: Colors.black.withOpacity(0.6),
              ),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = outlineColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            color: textColor,
          ),
        ),
      ],
    );
  }
}