import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart'; // Library Khusus Windows
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
  final double _sessionPrice = 500; // Pastikan harga sesuai dengan testing (misal 50000)
  Timer? _pollingTimer;

  // WEBVIEW CONTROLLER (Engine Browser Windows)
  final WebviewController _webviewController = WebviewController();
  bool _isWebviewReady = false;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    
    // Bungkus dispose webview dalam try-catch
    try {
      if (_isWebviewReady) {
        _webviewController.dispose();
      }
    } catch (e) {
      debugPrint("WebView dispose error (Ignored): $e");
    }
    
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

  // --- LOGIC 2: PROSES REQUEST URL & EMBED WEBVIEW ---
  void _initPaymentProcess() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // 1. PASTIKAN HWID SUDAH DILOAD (DINAMIS)
    // HWID ini didapat dari PhotoProvider yang membaca Unique ID Windows
    if (provider.machineId.isEmpty) {
       await provider.initMachineId();
    }

    // A. Generate UUID Baru untuk sesi ini
    String newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    provider.setSessionUuid(newUuid); 

    // B. Start Session di Database (Mencatat sesi masuk DB)
    // Parameter 'amount' di startSession adalah String
    bool sessionCreated = await apiService.startSession(
      newUuid, 
      hwid: provider.machineId, // <--- WAJIB: Dikirim untuk validasi license
      paymentMethod: 'qris', 
      amount: _sessionPrice.toStringAsFixed(0)
    );

    if (!sessionCreated) {
      _resetToMenu("Gagal membuat sesi database. Cek koneksi internet.");
      return;
    }

    // C. Request URL DOKU (UPDATE PENTING DISINI)
    // Sekarang kita wajib mengirim provider.machineId sebagai parameter ke-3
    String? url = await apiService.generatePaymentLink(
        newUuid, 
        _sessionPrice, 
        provider.machineId // <--- TAMBAHAN: Kirim HWID agar Laravel lolos validasi 'device_id'
    );

    if (mounted && url != null) {
      try {
        await _webviewController.initialize();
        
        // Listener URL untuk mendeteksi redirect sukses
        _webviewController.url.listen((currentUrl) {
           if (currentUrl.contains("google.com") || currentUrl.contains("success")) {
             _handlePaymentSuccess(); 
           }
        });

        // 1. LOAD URL DARI DOKU
        await _webviewController.loadUrl(url);
        
        // 2. TAMPILKAN UI WEBVIEW
        if (mounted) {
          setState(() {
            _isWebviewReady = true;
            _isLoading = false; 
          });
          
          // Mulai cek status pembayaran ke database secara berkala
          _startPolling(newUuid);
        }

        // 3. AUTO SCROLL (Opsional, kadang webview Doku perlu di scroll sedikit)
        await Future.delayed(const Duration(seconds: 2));
        try {
          await _webviewController.executeScript('window.scrollBy(0, 400);'); 
        } catch (_) {}

      } catch (e) {
        _resetToMenu("Error WebView: Silakan install Edge WebView2 Runtime.");
      }
    } else {
      _resetToMenu("Gagal mendapatkan link pembayaran.");
    }
  }

  // --- LOGIC BARU: BYPASS PAYMENT (DEV MODE - LONG PRESS) ---
  void _triggerBypass() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    if (provider.machineId.isEmpty) {
       await provider.initMachineId();
    }

    String bypassUuid = "bypass-${DateTime.now().millisecondsSinceEpoch}";
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🚀 DEV MODE: Mendaftarkan Sesi Gratis..."),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );

    bool success = await apiService.startSession(
      bypassUuid, 
      hwid: provider.machineId, 
      paymentMethod: 'bypass', 
      amount: '0' 
    );

    if (success) {
      provider.setSessionUuid(bypassUuid);
      _handlePaymentSuccess();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Gagal Bypass: Tidak bisa konek ke server."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _resetToMenu(String message) {
    if (mounted) {
      setState(() { _isLoading = false; _isSelectionMode = true; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- LOGIC 3: POLLING STATUS ---
  void _startPolling(String uuid) {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      final apiService = Provider.of<ApiService>(context, listen: false);
      
      // Cek ke Laravel apakah status sesi sudah 'paid'
      bool paid = await apiService.checkPaymentStatus(uuid);

      if (paid) {
        timer.cancel();
        if (mounted) _handlePaymentSuccess();
      }
    });
  }

  void _handlePaymentSuccess() {
    _pollingTimer?.cancel();
    if (_isPaid) return; 

    if (mounted) {
      setState(() { _isPaid = true; });
      
      Provider.of<PhotoProvider>(context, listen: false).reset();

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FrameSelectionPage()),
          );
        }
      });
    }
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

          // 2. KONTEN UTAMA
          Center(
            child: _isSelectionMode 
              ? _buildSelectionMenu() 
              : _buildPaymentContainer(), 
          ),

          // 3. HIDDEN BYPASS BUTTON (POJOK KIRI BAWAH)
          Positioned(
            bottom: 0,
            left: 0,
            child: GestureDetector(
              onLongPress: _triggerBypass,
              child: Container(
                width: 60,
                height: 60,
                color: Colors.transparent, 
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TAMPILAN MENU
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

  // TAMPILAN KOTAK PEMBAYARAN (WEBVIEW CONTAINER)
  Widget _buildPaymentContainer() {
    return Container(
      width: 500, 
      height: 650, 
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFC0C0C0), 
        border: Border.all(width: 3, color: Colors.black),
        boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(10, 10), blurRadius: 0)],
      ),
      child: Column(
        children: [
          // HEADER KOTAK
          Container(
            height: 35,
            color: const Color(0xFF0000AA),
            child: const Center(
              child: Text("DOKU PAYMENT GATEWAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
          
          // AREA KONTEN (WEBVIEW DISINI)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black54, width: 2), 
              ),
              child: _isPaid 
                ? _buildSuccessView()
                : (_isLoading || !_isWebviewReady)
                    ? const Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text("Connecting to DOKU...")
                        ],
                      ))
                    : Webview(_webviewController), 
            ),
          ),

          // FOOTER (TOMBOL BATAL)
          if (!_isPaid)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: const BeveledRectangleBorder(),
                ),
                onPressed: () {
                  _pollingTimer?.cancel();
                  setState(() { _isSelectionMode = true; _isWebviewReady = false; });
                },
                child: const Text("CANCEL TRANSACTION"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 80),
        const SizedBox(height: 20),
        const Text("PAYMENT RECEIVED!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Ambitsek')),
        const SizedBox(height: 10),
        const Text("Redirecting to frame selection...", style: TextStyle(fontSize: 14)),
      ],
    );
  }
}

// ... Widget PixelCard dan OutlinedText tetap sama seperti sebelumnya ...
// Silakan paste ulang widget PixelCard dan OutlinedText di bawah sini jika perlu, 
// tapi bagian logic utamanya ada di atas.
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