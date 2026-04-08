import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
import '../providers/app_config_provider.dart';
import '../providers/photo_provider.dart';
import '../services/api_service.dart';
import 'static_frame_template_page.dart';
import '../widgets/retro_keyboard.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _isSelectionMode = true;
  bool _isLoading = false;
  bool _isPaid = false;
  int _paymentAttemptId = 0;
  bool _paymentFlowCancelled = false;

  // Voucher state
  bool _isVoucherMode = false;
  final TextEditingController _voucherController = TextEditingController();
  String _voucherError = "";
  bool _isValidatingVoucher = false;

  // WebView state
  Timer? _pollingTimer;
  final WebviewController _webviewController = WebviewController();
  bool _isWebViewReady = false;

  // ── DEBUG STATE ──
  final List<String> _debugLogs = [];
  String _webViewError = "";

  @override
  void initState() {
    super.initState();
    _runEnvironmentCheck();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _voucherController.dispose();
    if (_isWebViewReady) {
      _webviewController.dispose();
    }
    super.dispose();
  }

  // ================================================================
  // DEBUG HELPERS
  // ================================================================
  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final entry = "[$timestamp] $message";
    debugPrint("🔍 WEBVIEW_DEBUG: $entry");
    if (mounted) {
      setState(() => _debugLogs.add(entry));
    }
  }

  /// Run environment diagnostics on page load
  Future<void> _runEnvironmentCheck() async {
    _log("=== ENVIRONMENT CHECK START ===");
    _log(
        "Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}");
    _log("Dart version: ${Platform.version}");
    _log("Executable: ${Platform.resolvedExecutable}");

    // Check WebView2 Runtime availability
    try {
      final webviewVersion = await WebviewController.getWebViewVersion();
      _log("✅ WebView2 Runtime version: $webviewVersion");
    } catch (e) {
      _log("❌ WebView2 Runtime NOT FOUND or error: $e");
      _log(
          "   → Install from: https://developer.microsoft.com/en-us/microsoft-edge/webview2/");
    }

    // Check network connectivity to common endpoints
    _log("--- Network connectivity test ---");
    for (final host in ['google.com', 'doku.com', '8.8.8.8']) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          _log("✅ DNS resolve OK: $host → ${result[0].address}");
        }
      } catch (e) {
        _log("❌ DNS resolve FAIL: $host → $e");
      }
    }

    // Check environment variables that might affect WebView
    final envVars = [
      'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
      'WEBVIEW2_USER_DATA_FOLDER',
      'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS',
    ];
    for (final v in envVars) {
      final val = Platform.environment[v];
      _log("ENV $v = ${val ?? '(not set)'}");
    }

    _log("=== ENVIRONMENT CHECK END ===");
  }

  // ================================================================
  // QRIS FLOW (WebView)
  // ================================================================
  void _onSelectQRIS() {
    _log("User selected QRIS payment");
    _paymentAttemptId++;
    _paymentFlowCancelled = false;
    setState(() {
      _isSelectionMode = false;
      _isLoading = true;
      _webViewError = "";
    });
    _initQrisPayment();
  }

  void _initQrisPayment() async {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    if (provider.machineId.isEmpty) {
      _log("Machine ID empty, initializing...");
      await provider.initMachineId();
    }
    _log("Machine ID: ${provider.machineId}");

    final newUuid = "sesi-${DateTime.now().millisecondsSinceEpoch}";
    provider.setSessionUuid(newUuid);
    _log("Session UUID: $newUuid");

    _log("Creating session on backend...");
    final sessionCreated = await apiService.startSession(
      newUuid,
      hwid: provider.machineId,
      paymentMethod: 'qris',
    );

    if (!sessionCreated) {
      _log("❌ Backend session creation FAILED");
      _resetToMenu("Gagal membuat sesi. Cek koneksi internet.");
      return;
    }
    _log("✅ Backend session created");

    _log("Requesting payment link from backend...");
    final paymentUrl =
        await apiService.generatePaymentLink(newUuid, hwid: provider.machineId);
    _log("Payment URL response: $paymentUrl");

    if (mounted && paymentUrl != null) {
      _log("Initializing WebView with URL: $paymentUrl");
      await _initWebView(paymentUrl);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _startPolling(newUuid);
    } else {
      _log("❌ Payment URL is null or widget not mounted");
      _resetToMenu("Gagal mendapatkan halaman pembayaran.");
    }
  }

  Future<void> _initWebView(String url) async {
    _log("--- WebView Init START ---");

    // Step 1: Check WebView2 version again right before init
    try {
      final version = await WebviewController.getWebViewVersion();
      _log("Step 1/5: WebView2 version confirmed: $version");
    } catch (e) {
      _log("Step 1/5: ❌ WebView2 version check FAILED: $e");
      if (mounted) {
        setState(() => _webViewError =
            "WebView2 Runtime tidak ditemukan.\n\nInstall dari:\nhttps://developer.microsoft.com/en-us/microsoft-edge/webview2/\n\nError: $e");
      }
      return;
    }

    // Step 2: Initialize controller
    try {
      _log("Step 2/5: Calling _webviewController.initialize()...");
      await _webviewController.initialize();
      _log("Step 2/5: ✅ Controller initialized");
    } catch (e, stack) {
      _log("Step 2/5: ❌ Controller initialize FAILED: $e");
      _log("Stack: $stack");
      if (mounted) {
        setState(() => _webViewError =
            "WebView controller gagal initialize.\n\nError: $e\n\nCoba:\n1. Restart aplikasi\n2. Jalankan sebagai Administrator\n3. Update WebView2 Runtime");
      }
      return;
    }

    // Step 3: Set background color
    try {
      _log("Step 3/5: Setting background color...");
      await _webviewController.setBackgroundColor(Colors.white);
      _log("Step 3/5: ✅ Background color set");
    } catch (e) {
      _log("Step 3/5: ⚠️ setBackgroundColor failed (non-critical): $e");
    }

    // Step 4: Register event listeners
    try {
      _log("Step 4/5: Registering event listeners...");

      _webviewController.loadingState.listen((state) {
        _log("📡 LoadingState changed: $state");
        if (state == LoadingState.navigationCompleted) {
          _log("✅ Navigation completed — injecting QRIS auto-select script");
          _injectAutoSelectQrisScript();
        }
      });

      _webviewController.url.listen((url) {
        _log("📡 URL changed: $url");
      });

      // WebErrorStatus is an enum, not an object with .errorCode/.url
      _webviewController.onLoadError.listen((WebErrorStatus error) {
        _log("❌ WebView LOAD ERROR: $error (${error.name})");
        if (mounted) {
          setState(() => _webViewError =
              "Halaman gagal dimuat.\n\nWebErrorStatus: ${error.name}");
        }
      });

      _webviewController.containsFullScreenElementChanged.listen((flag) {
        _log("📡 Fullscreen changed: $flag");
      });

      _webviewController.securityStateChanged.listen((state) {
        _log("📡 Security state changed: $state");
      });

      _log("Step 4/5: ✅ Event listeners registered");
    } catch (e) {
      _log("Step 4/5: ⚠️ Some event listeners failed: $e");
    }

    // Step 5: Load URL
    try {
      _log("Step 5/5: Loading URL: $url");
      await _webviewController.loadUrl(url);
      _log("Step 5/5: ✅ loadUrl() called successfully");

      if (mounted) {
        setState(() => _isWebViewReady = true);
        _log("WebView marked as READY");
      }
    } catch (e, stack) {
      _log("Step 5/5: ❌ loadUrl FAILED: $e");
      _log("Stack: $stack");
      if (mounted) {
        setState(() => _webViewError =
            "Gagal memuat URL pembayaran.\n\nURL: $url\nError: $e");
      }
    }

    _log("--- WebView Init END ---");
  }

  /// Inject JavaScript to auto-select QRIS payment on DOKU checkout page
  /// and scroll to the QR code
  void _injectAutoSelectQrisScript() async {
    const jsCode = '''
      (function() {
        var qrisClicked = false;

        function simulateClick(el) {
          ['mousedown', 'mouseup', 'click'].forEach(function(evtType) {
            el.dispatchEvent(new MouseEvent(evtType, {
              bubbles: true, cancelable: true, view: window
            }));
          });
        }

        function trySelectQris(attempt) {
          if (attempt > 30 || qrisClicked) return;

          var xpathResult = document.evaluate(
            "//*[contains(translate(text(),'qris','QRIS'),'QRIS')]",
            document, null,
            XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null
          );

          for (var i = 0; i < xpathResult.snapshotLength; i++) {
            var node = xpathResult.snapshotItem(i);
            var target = node;
            for (var depth = 0; depth < 8; depth++) {
              if (!target) break;
              var tag = (target.tagName || '').toUpperCase();
              var role = (target.getAttribute && target.getAttribute('role')) || '';
              var cursor = window.getComputedStyle(target).cursor;

              if (tag === 'BUTTON' || tag === 'A' || tag === 'LI' ||
                  role === 'button' || role === 'tab' || role === 'option' ||
                  cursor === 'pointer' ||
                  target.onclick != null ||
                  (target.className && target.className.toString().match(/channel|method|option|item|card|tab|accordion/i))) {
                simulateClick(target);
                qrisClicked = true;
                console.log('[AutoQRIS] Clicked QRIS element:', tag, target.className);
                setTimeout(function() { scrollToQrCode(0); }, 2000);
                return;
              }
              target = target.parentElement;
            }
          }

          var fallbackSelectors = [
            '[data-channel*="qris" i]',
            '[data-channel*="QRIS"]',
            '[data-payment*="qris" i]',
            '[data-value*="qris" i]',
            '[id*="qris" i]',
            '[class*="qris" i]',
            '[class*="channel" i]',
          ];
          for (var s = 0; s < fallbackSelectors.length; s++) {
            try {
              var els = document.querySelectorAll(fallbackSelectors[s]);
              for (var j = 0; j < els.length; j++) {
                var txt = (els[j].textContent || '').toUpperCase();
                if (txt.indexOf('QRIS') !== -1) {
                  simulateClick(els[j]);
                  qrisClicked = true;
                  console.log('[AutoQRIS] Fallback clicked:', els[j].tagName, els[j].className);
                  setTimeout(function() { scrollToQrCode(0); }, 2000);
                  return;
                }
              }
            } catch(e) {}
          }

          if (!qrisClicked) {
            var all = document.querySelectorAll('*');
            for (var k = 0; k < all.length; k++) {
              var el = all[k];
              var directText = '';
              for (var c = 0; c < el.childNodes.length; c++) {
                if (el.childNodes[c].nodeType === 3) {
                  directText += el.childNodes[c].textContent;
                }
              }
              if (directText.trim().toUpperCase().indexOf('QRIS') !== -1) {
                var clickTarget = el;
                while (clickTarget && clickTarget !== document.body) {
                  var cs = window.getComputedStyle(clickTarget).cursor;
                  if (cs === 'pointer') {
                    simulateClick(clickTarget);
                    qrisClicked = true;
                    console.log('[AutoQRIS] Last-resort clicked:', clickTarget.tagName);
                    setTimeout(function() { scrollToQrCode(0); }, 2000);
                    return;
                  }
                  clickTarget = clickTarget.parentElement;
                }
                simulateClick(el);
                qrisClicked = true;
                console.log('[AutoQRIS] Direct clicked:', el.tagName);
                setTimeout(function() { scrollToQrCode(0); }, 2000);
                return;
              }
            }
          }

          setTimeout(function() { trySelectQris(attempt + 1); }, 500);
        }

        function scrollToQrCode(attempt) {
          if (attempt > 30) return;
          var qrSelectors = [
            'img[src*="qr"]', 'img[alt*="qr" i]', 'img[alt*="QRIS" i]',
            'canvas', '[class*="qr-code" i]', '[class*="qrcode" i]',
            '[id*="qr" i]', 'img[src*="payment"]',
            'img[src*="doku"]', 'img[src*="shopeepay"]',
          ];
          var qrElement = null;
          for (var s = 0; s < qrSelectors.length; s++) {
            try {
              qrElement = document.querySelector(qrSelectors[s]);
              if (qrElement) break;
            } catch(e) {}
          }
          if (qrElement) {
            qrElement.scrollIntoView({behavior: 'smooth', block: 'center'});
          } else {
            setTimeout(function() { scrollToQrCode(attempt + 1); }, 500);
          }
        }

        var observer = new MutationObserver(function(mutations) {
          if (!qrisClicked) {
            trySelectQris(0);
          } else {
            observer.disconnect();
          }
        });
        observer.observe(document.body || document.documentElement, {
          childList: true, subtree: true
        });

        setTimeout(function() { trySelectQris(0); }, 1500);
      })();
    ''';

    try {
      await _webviewController.executeScript(jsCode);
      _log("✅ QRIS auto-select JS injected");
    } catch (e) {
      _log("⚠️ JS injection error: $e");
    }
  }

  // ================================================================
  // VOUCHER FLOW
  // ================================================================
  void _onSelectVoucher() {
    _paymentAttemptId++;
    _paymentFlowCancelled = false;
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
    final attemptId = _paymentAttemptId;
    _log("Starting payment polling for $uuid");
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_paymentFlowCancelled || attemptId != _paymentAttemptId) {
        _log("Stopping stale payment polling for $uuid");
        timer.cancel();
        return;
      }
      final apiService = Provider.of<ApiService>(context, listen: false);
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      final paid = await apiService.checkPaymentStatus(uuid, hwid: provider.machineId);
      _log("Poll check: paid=$paid");
      if (paid && !_paymentFlowCancelled && attemptId == _paymentAttemptId) {
        timer.cancel();
        if (mounted) _handlePaymentSuccess();
      }
    });
  }

  void _handlePaymentSuccess() {
    _pollingTimer?.cancel();
    if (_isPaid || _paymentFlowCancelled) {
      _log("Ignoring late payment success because flow already ended.");
      return;
    }
    _log("🎉 Payment success!");
    if (mounted) {
      setState(() => _isPaid = true);
      Provider.of<PhotoProvider>(context, listen: false).reset();
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const StaticFrameTemplatePage()),
          );
        }
      });
    }
  }

  void _resetToMenu(String message) {
    _paymentFlowCancelled = true;
    _paymentAttemptId++;
    _pollingTimer?.cancel();
    _log("Reset to menu: $message");
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isSelectionMode = true;
        _isVoucherMode = false;
        _isWebViewReady = false;
        _webViewError = "";
        _isPaid = false;
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
        ],
      ),
    );
  }

  // ── MENU PILIHAN ──
  Widget _buildSelectionMenu() {
    final appConfig = Provider.of<AppConfigProvider>(context, listen: false);
    final canUseQris = appConfig.paymentMethodsEnabled.contains('qris');
    final canUseVoucher =
        appConfig.paymentMethodsEnabled.contains('voucher') &&
        appConfig.voucherEnabled;

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
            if (canUseQris)
              PixelCard(
                  title: "QRIS",
                  imagePath: "assets/images/qris.png",
                  onTap: _onSelectQRIS),
            if (canUseQris && canUseVoucher) const SizedBox(width: 30),
            if (canUseVoucher)
              PixelCard(
                  title: "VOUCHER",
                  imagePath: "assets/images/voucher.png",
                  onTap: _onSelectVoucher),
          ],
        ),
      ],
    );
  }

  // ── PAYMENT WEBVIEW ──
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
                : _webViewError.isNotEmpty
                    ? _buildWebViewErrorView()
                    : _isPaid
                        ? _buildSuccessView()
                        : _isWebViewReady
                            ? Webview(_webviewController)
                            : const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text("Memuat WebView..."),
                                    SizedBox(height: 4),
                                    Text(
                                      "Jika stuck, klik SHOW DEBUG",
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.black45),
                                    ),
                                  ],
                                ),
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

  // ── WEBVIEW ERROR VIEW ──
  Widget _buildWebViewErrorView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 12),
          const Text("WebView Error",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _webViewError,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text("Coba Lagi"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0000AA),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              setState(() => _webViewError = "");
              _onSelectQRIS();
            },
          ),
        ],
      ),
    );
  }

  // ── VOUCHER INPUT ──
  Widget _buildVoucherInput() {
    return Container(
      width: 580, // Increased width to fit keyboard
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
              readOnly: true, // Prevent system keyboard
              enableInteractiveSelection: false, // Prevent cursor/selection
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, // Slightly larger
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6), // Increased letter spacing
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
            const SizedBox(height: 20),

            // Integrated Retro Keyboard
            RetroKeyboard(
              controller: _voucherController,
              onKeyTapped: () {
                if (_voucherError.isNotEmpty) {
                  setState(() => _voucherError = "");
                }
              },
            ),

            const SizedBox(height: 20),
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
                      color: Colors.black.withValues(alpha: 0.6)))),
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
