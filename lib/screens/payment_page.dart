import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
import '../providers/photo_provider.dart';
import '../services/api_service.dart';
import 'static_frame_template_page.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _isSelectionMode = true;
  bool _isLoading = false;
  bool _isPaid = false;

  // Voucher state
  bool _isVoucherMode = false;
  final TextEditingController _voucherController = TextEditingController();
  String _voucherError = "";
  bool _isValidatingVoucher = false;

  // WebView state (menggantikan QRIS state)
  String? _paymentUrl;
  Timer? _pollingTimer;
  final WebviewController _webviewController = WebviewController();
  bool _isWebViewReady = false;

  final double _sessionPrice = 500;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _voucherController.dispose();
    _webviewController.dispose();
    super.dispose();
  }

  // ================================================================
  // BYPASS — Long press pojok kiri bawah, tetap catat ke DB
  // ================================================================
  void _triggerBypass() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    provider.reset();

    final apiService = Provider.of<ApiService>(context, listen: false);

    if (provider.machineId.isEmpty) await provider.initMachineId();

    final bypassUuid = "bypass-${DateTime.now().millisecondsSinceEpoch}";

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🚀 DEV MODE: Mendaftarkan sesi bypass..."),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );

    final success = await apiService.startSession(
      bypassUuid,
      hwid: provider.machineId,
      paymentMethod: 'bypass',
      amount: '0',
    );

    if (success) {
      provider.setSessionUuid(bypassUuid);
      _handlePaymentSuccess();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Gagal Bypass: Tidak bisa konek ke server."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ================================================================
  // QRIS FLOW (sekarang membuka WebView)
  // ================================================================
  void _onSelectQRIS() {
    setState(() {
      _isSelectionMode = false;
      _isLoading = true;
    });
    _initQrisPayment();
  }

  void _initQrisPayment() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    if (provider.machineId.isEmpty) await provider.initMachineId();

    final newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    provider.setSessionUuid(newUuid);

    final sessionCreated = await apiService.startSession(
      newUuid,
      hwid: provider.machineId,
      paymentMethod: 'qris',
      amount: _sessionPrice.toStringAsFixed(0),
    );

    if (!sessionCreated) {
      _resetToMenu("Gagal membuat sesi. Cek koneksi internet.");
      return;
    }

    // Dapatkan payment_url dari backend
    final paymentUrl = await apiService.generatePaymentLink(newUuid);

    if (mounted && paymentUrl != null) {
      // Inisialisasi WebView dan load URL
      await _initWebView(paymentUrl);
      setState(() {
        _paymentUrl = paymentUrl;
        _isLoading = false;
      });
      _startPolling(newUuid);
    } else {
      _resetToMenu("Gagal mendapatkan halaman pembayaran.");
    }
  }

  Future<void> _initWebView(String url) async {
    try {
      await _webviewController.initialize();
      await _webviewController.setBackgroundColor(Colors.white);
      await _webviewController.loadUrl(url);
      if (mounted) {
        setState(() => _isWebViewReady = true);
      }
    } catch (e) {
      print("❌ Error WebView: $e");
    }
  }

  // ================================================================
  // VOUCHER FLOW
  // ================================================================
  void _onSelectVoucher() {
    setState(() {
      _isSelectionMode = false;
      _isVoucherMode = true;
    });
  }

  void _validateAndUseVoucher() async {
    final code = _voucherController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _voucherError = "Masukkan kode voucher.");
      return;
    }

    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    setState(() {
      _isValidatingVoucher = true;
      _voucherError = "";
    });

    if (provider.machineId.isEmpty) await provider.initMachineId();

    final newUuid = "voucher-${DateTime.now().millisecondsSinceEpoch}";
    provider.setSessionUuid(newUuid);

    final success = await apiService.startSession(
      newUuid,
      hwid: provider.machineId,
      paymentMethod: 'voucher',
      amount: _sessionPrice.toStringAsFixed(0),
      voucherCode: code,
    );

    if (!mounted) return;

    if (success) {
      _handlePaymentSuccess();
    } else {
      setState(() {
        _voucherError = "Kode voucher tidak valid atau sudah habis.";
        _isValidatingVoucher = false;
      });
    }
  }

  // ================================================================
  // POLLING & SUCCESS
  // ================================================================
  void _startPolling(String uuid) {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final apiService = Provider.of<ApiService>(context, listen: false);
      final paid = await apiService.checkPaymentStatus(uuid);
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
      setState(() => _isPaid = true);
      Provider.of<PhotoProvider>(context, listen: false).reset();
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => StaticFrameTemplatePage()),
          );
        }
      });
    }
  }

  void _resetToMenu(String message) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isSelectionMode = true;
        _isVoucherMode = false;
        _paymentUrl = null;
        _isWebViewReady = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset("assets/images/bg.png", fit: BoxFit.cover),
          ),
          Center(
            child: _isSelectionMode
                ? _buildSelectionMenu()
                : _isVoucherMode
                    ? _buildVoucherInput()
                    : _buildPaymentWebView(),
          ),
          // Bypass button
          Positioned(
            bottom: 0,
            left: 0,
            child: GestureDetector(
              onLongPress: _triggerBypass,
              child:
                  Container(width: 80, height: 80, color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  // ── MENU PILIHAN ──
  Widget _buildSelectionMenu() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelCard(
                title: "QRIS",
                imagePath: "assets/images/qris.png",
                onTap: _onSelectQRIS),
            const SizedBox(width: 30),
            PixelCard(
                title: "VOUCHER",
                imagePath: "assets/images/voucher.png",
                onTap: _onSelectVoucher),
          ],
        ),
      ],
    );
  }

  // ── PAYMENT WEBVIEW (menggantikan QR View) ──
  Widget _buildPaymentWebView() {
    return Container(
      width: 500,
      height: 650,
      decoration: BoxDecoration(
        color: const Color(0xFFC0C0C0),
        border: Border.all(width: 3, color: Colors.black),
        boxShadow: const [
          BoxShadow(color: Colors.black45, offset: Offset(10, 10))
        ],
      ),
      child: Column(
        children: [
          // Title bar
          Container(
            width: double.infinity,
            height: 32,
            color: const Color(0xFF0000AA),
            child: const Center(
              child: Text("PAYMENT GATEWAY",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text("Memuat halaman pembayaran..."),
                      ],
                    ),
                  )
                : _isPaid
                    ? _buildSuccessView()
                    : _isWebViewReady
                        ? Webview(_webviewController)
                        : const Center(
                            child: Text("Memuat WebView..."),
                          ),
          ),

          // Cancel button
          if (!_isPaid)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: const BeveledRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    _pollingTimer?.cancel();
                    _resetToMenu("Transaksi dibatalkan.");
                  },
                  child: const Text("CANCEL"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── VOUCHER INPUT ──
  Widget _buildVoucherInput() {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFC0C0C0),
        border: Border.all(width: 3, color: Colors.black),
        boxShadow: const [
          BoxShadow(color: Colors.black45, offset: Offset(10, 10))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 32,
            color: const Color(0xFF0000AA),
            child: const Center(
                child: Text("MASUKKAN VOUCHER",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1))),
          ),
          const SizedBox(height: 20),
          if (_isPaid)
            _buildSuccessView()
          else ...[
            const Text("Masukkan kode voucher kamu:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: _voucherController,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: "XXXXX",
                hintStyle: const TextStyle(color: Colors.black38),
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                errorText: _voucherError.isNotEmpty ? _voucherError : null,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0000AA),
                  foregroundColor: Colors.white,
                  shape: const BeveledRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isValidatingVoucher ? null : _validateAndUseVoucher,
                child: _isValidatingVoucher
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text("GUNAKAN VOUCHER",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _isVoucherMode = false;
                _isSelectionMode = true;
                _voucherError = "";
                _voucherController.clear();
              }),
              child: const Text("← Kembali",
                  style: TextStyle(color: Colors.black54)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 20),
        Icon(Icons.check_circle, color: Colors.green, size: 72),
        SizedBox(height: 12),
        Text("BERHASIL!",
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Ambitsek')),
        SizedBox(height: 6),
        Text("Menuju pemilihan frame...",
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        SizedBox(height: 20),
      ],
    );
  }
}

// =========================================================
// WIDGETS (tidak berubah)
// =========================================================
class PixelCard extends StatefulWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;
  const PixelCard(
      {super.key,
      required this.title,
      required this.imagePath,
      required this.onTap});
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
            color: const Color(0xFFC0C0C0),
            border: Border.all(width: 3, color: Colors.black),
            boxShadow: _isPressed
                ? []
                : const [
                    BoxShadow(color: Colors.black54, offset: Offset(6, 6))
                  ],
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: const Color(0xFF0000AA),
                child: Text(widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Ambitsek',
                        color: Colors.white,
                        fontSize: 15,
                        letterSpacing: 2)),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Image.asset(widget.imagePath, fit: BoxFit.contain),
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
              top: 4,
              left: 4,
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      letterSpacing: letterSpacing,
                      height: 1.2,
                      color: Colors.black.withOpacity(0.6)))),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                letterSpacing: letterSpacing,
                height: 1.2,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 8
                  ..color = outlineColor)),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                letterSpacing: letterSpacing,
                height: 1.2,
                color: textColor)),
      ],
    );
  }
}
