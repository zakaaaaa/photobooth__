import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart'; // IMPORT WAJIB UNTUK WINDOWS
import '../providers/photo_provider.dart';
import '../services/api_service.dart';
import 'frame_selection_page.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // State UI
  bool _isSelectionMode = true; 
  bool _isLoading = false;
  bool _isPaid = false;
  
  // Payment Data
  String? _currentUuid;
  Timer? _pollingTimer;
  final double _sessionPrice = 10000;

  // WEBVIEW CONTROLLER (KHUSUS WINDOWS)
  final WebviewController _webviewController = WebviewController();
  bool _isWebviewReady = false;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _webviewController.dispose(); // Hapus controller saat keluar
    super.dispose();
  }

  // --- LOGIC 1: MEMILIH METODE PEMBAYARAN ---
  void _onSelectQRIS() {
    setState(() {
      _isSelectionMode = false; 
      _isLoading = true;
    });
    _initPaymentProcess();
  }

  void _onSelectVoucher() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fitur Voucher akan segera hadir!")),
    );
  }

  // --- LOGIC 2: PROSES GENERATE LINK & INIT WEBVIEW ---
  void _initPaymentProcess() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // 1. Setup Data
    String newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    _currentUuid = newUuid; 
    provider.setSessionUuid(newUuid); 

    // 2. Start Session di DB
    bool sessionCreated = await apiService.startSession(newUuid);
    if (!sessionCreated) {
      _resetToMenu("Gagal membuat sesi database");
      return;
    }

    // 3. Request URL DOKU dari Laravel
    // NOTE: Backend Anda mengembalikan 'payment_url'
    String? url = await apiService.generatePaymentLink(newUuid, _sessionPrice);

    if (mounted && url != null) {
      // 4. Inisialisasi WebView Windows
      try {
        await _webviewController.initialize();
        await _webviewController.loadUrl(url);
        
        // Listen URL changes (Opsional: Deteksi redirect sukses DOKU)
        _webviewController.url.listen((currentUrl) {
           // Di PaymentController.php, callback_url Anda = http://google.com
           if (currentUrl.contains("google.com")) {
             _handlePaymentSuccess(); // Auto success jika redirect
           }
        });

        if (mounted) {
          setState(() {
            _isWebviewReady = true;
            _isLoading = false; 
          });
          _startPolling(newUuid); // Tetap polling untuk jaga-jaga
        }
      } catch (e) {
        _resetToMenu("Gagal memuat WebView: $e");
      }
    } else {
      _resetToMenu("Gagal mendapatkan link pembayaran");
    }
  }

  void _resetToMenu(String message) {
    if (mounted) {
      setState(() { _isLoading = false; _isSelectionMode = true; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- LOGIC 3: POLLING ---
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
    if (_isPaid) return; // Prevent double call

    setState(() { _isPaid = true; });
    Provider.of<PhotoProvider>(context, listen: false).reset();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
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
          // 1. BACKGROUND
          Positioned.fill(
            child: Image.asset("assets/images/bg.png", fit: BoxFit.cover),
          ),

          // 2. KONTEN
          Center(
            child: _isSelectionMode 
              ? _buildSelectionMenu() 
              : _buildPaymentProcessUI(), 
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionMenu() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const OutlinedText(
          text: "CHOOSE\nPAYMENT METHOD",
          fontFamily: 'Ambitsek', fontSize: 70, textColor: Color(0xFFFFED00), outlineColor: Color(0xFFEF7D30), fontWeight: FontWeight.w900, letterSpacing: 1.0, hasShadow: true,
        ),
        const SizedBox(height: 50),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelCard(title: "QRIS", imagePath: "assets/images/qris.png", onTap: _onSelectQRIS),
            const SizedBox(width: 30),
            PixelCard(title: "VOUCHER", imagePath: "assets/images/voucher.png", onTap: _onSelectVoucher),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentProcessUI() {
    return Container(
      // Ukuran Container disesuaikan agar WebView muat
      width: 500, 
      height: 600,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFC0C0C0), // Warna dasar Windows 95
        border: Border.all(width: 4, color: Colors.black),
        boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(8, 8), blurRadius: 0)],
      ),
      child: Column(
        children: [
          // HEADER WINDOWS 95 STYLE
          Container(
            height: 30,
            color: const Color(0xFF0000AA),
            child: const Center(
              child: Text("PAYMENT GATEWAY - QRIS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 10),

          // ISI KONTEN (LOADING / WEBVIEW / SUKSES)
          Expanded(
            child: _isPaid 
            ? Column( // TAMPILAN SUKSES
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 20),
                  const Text("PAYMENT SUCCESS!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Ambitsek')),
                  const Text("Redirecting...", style: TextStyle(fontSize: 16)),
                ],
              )
            : _isLoading || !_isWebviewReady
              ? const Center(child: CircularProgressIndicator()) // TAMPILAN LOADING
              : Stack( // TAMPILAN WEBVIEW
                  children: [
                    // WIDGET WEBVIEW (Browser Embedded)
                    Webview(_webviewController),
                    
                    // Tombol Cancel Kecil di pojok (Optional)
                    Positioned(
                      bottom: 0, right: 0,
                      child: TextButton(
                        onPressed: () {
                           setState(() { _isSelectionMode = true; _isWebviewReady = false; });
                           _webviewController.stop(); // Stop loading
                        },
                        child: const Text("CANCEL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

// ... (Simpan Code PixelCard dan OutlinedText seperti file asli Anda di sini) ...
// Pastikan menyalin ulang kelas PixelCard dan OutlinedText di bawah sini 
// agar tidak ada error undefined class.

// Widget PixelCard dan OutlinedText TETAP SAMA (tidak saya tulis ulang agar hemat tempat)
// Pastikan bagian bawah file ini tetap ada class PixelCard dan OutlinedText dari kode lama Anda.

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