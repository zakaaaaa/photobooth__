import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:photobooth_app/screens/splash_screen.dart';
import 'package:photobooth_app/services/license_service.dart';

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage>
    with TickerProviderStateMixin {
  // ── State ──
  String _hwid = '';

  // Camera
  _CheckStatus _cameraStatus = _CheckStatus.loading;
  String _cameraMessage = 'Mendeteksi kamera...';
  String _cameraName = '';

  // Printer
  _CheckStatus _printerStatus = _CheckStatus.loading;
  String _printerMessage = 'Mendeteksi printer...';
  List<_PrinterInfo> _printers = [];

  // Recent photos
  _CheckStatus _photosStatus = _CheckStatus.loading;
  String _photosMessage = 'Mengambil foto terakhir...';
  List<_RecentPhoto> _recentPhotos = [];

  // Server
  _CheckStatus _serverStatus = _CheckStatus.loading;
  String _serverMessage = 'Mengecek koneksi server...';

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;

  static const String _backendUrl = 'http://168.231.125.203:8181';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _runAllChecks();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ================================================================
  // RUN ALL CHECKS
  // ================================================================
  Future<void> _runAllChecks() async {
    // Get HWID first — needed for photo fetch
    final licenseService = LicenseService();
    _hwid = await licenseService.getHardwareId();

    // Run checks in parallel
    await Future.wait([
      _checkCamera(),
      _checkPrinters(),
      _checkServer(),
    ]);

    // Photos depend on server being reachable
    await _checkRecentPhotos();
  }

  // ================================================================
  // 1. CAMERA CHECK
  // ================================================================
  Future<void> _checkCamera() async {
    try {
      if (Platform.isMacOS) {
        // camera_macos — we can't list cameras without initializing the view,
        // so we check via system_profiler CLI
        final result =
            await Process.run('system_profiler', ['SPCameraDataType']);
        final output = result.stdout.toString();

        if (output.contains('Camera') ||
            output.contains('FaceTime') ||
            output.contains('USB')) {
          // Extract camera name
          final lines = output.split('\n');
          String name = 'Camera Terdeteksi';
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('Camera') &&
                !trimmed.contains(':') &&
                trimmed != 'Camera:') {
              // Usually the camera name is an indented line without a colon
            }
            if (trimmed.contains('Model ID:') ||
                trimmed.contains('Unique ID:')) {
              continue;
            }
            // Find the first line that looks like a device name
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('SPCameraDataType') &&
                !trimmed.contains('Model ID') &&
                !trimmed.contains('Unique ID') &&
                !trimmed.contains(':') &&
                lines.indexOf(line) > 1) {
              name = trimmed;
              break;
            }
          }

          if (mounted) {
            setState(() {
              _cameraStatus = _CheckStatus.success;
              _cameraName = name;
              _cameraMessage = name;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _cameraStatus = _CheckStatus.error;
              _cameraMessage = 'Tidak ada kamera terdeteksi';
            });
          }
        }
      } else if (Platform.isWindows) {
        // Windows — use PowerShell to detect cameras
        final result = await Process.run('powershell', [
          '-Command',
          'Get-PnpDevice -Class Camera -Status OK | Select-Object -ExpandProperty FriendlyName'
        ]);
        final output = result.stdout.toString().trim();

        if (output.isNotEmpty && !output.contains('Error')) {
          final cameras = output
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

          if (mounted) {
            setState(() {
              _cameraStatus = _CheckStatus.success;
              _cameraName = cameras.first;
              _cameraMessage =
                  '${cameras.first}${cameras.length > 1 ? ' (+${cameras.length - 1} lainnya)' : ''}';
            });
          }
        } else {
          // Fallback: try WMIC
          final wmic = await Process.run('cmd', [
            '/c',
            'wmic path Win32_PnPEntity where "PNPClass=\'Camera\' OR PNPClass=\'Image\'" get Name /format:list'
          ]);
          final wmicOutput = wmic.stdout.toString().trim();
          final nameMatch = RegExp(r'Name=(.+)').firstMatch(wmicOutput);

          if (nameMatch != null) {
            if (mounted) {
              setState(() {
                _cameraStatus = _CheckStatus.success;
                _cameraName = nameMatch.group(1)!.trim();
                _cameraMessage = nameMatch.group(1)!.trim();
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _cameraStatus = _CheckStatus.error;
                _cameraMessage = 'Tidak ada kamera terdeteksi';
              });
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _cameraStatus = _CheckStatus.error;
            _cameraMessage = 'Platform tidak didukung';
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Camera check error: $e');
      if (mounted) {
        setState(() {
          _cameraStatus = _CheckStatus.error;
          _cameraMessage = 'Gagal mendeteksi kamera: $e';
        });
      }
    }
  }

  // ================================================================
  // 2. PRINTER CHECK
  // ================================================================
  Future<void> _checkPrinters() async {
    try {
      final printers = await Printing.listPrinters();

      if (printers.isEmpty) {
        if (mounted) {
          setState(() {
            _printerStatus = _CheckStatus.error;
            _printerMessage = 'Tidak ada printer terdeteksi';
          });
        }
        return;
      }

      final printerList = printers.map((p) {
        return _PrinterInfo(
          name: p.name,
          isDefault: p.isDefault,
          isAvailable: p.isAvailable,
        );
      }).toList();

      // Sort: available + default first
      printerList.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        if (a.isAvailable && !b.isAvailable) return -1;
        return 0;
      });

      if (mounted) {
        setState(() {
          _printers = printerList;
          _printerStatus = printerList.any((p) => p.isAvailable)
              ? _CheckStatus.success
              : _CheckStatus.warning;
          _printerMessage = printerList.any((p) => p.isAvailable)
              ? '${printerList.where((p) => p.isAvailable).length} printer tersedia'
              : 'Printer ditemukan tapi tidak tersedia';
        });
      }
    } catch (e) {
      debugPrint('❌ Printer check error: $e');
      if (mounted) {
        setState(() {
          _printerStatus = _CheckStatus.error;
          _printerMessage = 'Gagal mendeteksi printer: $e';
        });
      }
    }
  }

  // ================================================================
  // 3. SERVER CHECK
  // ================================================================
  Future<void> _checkServer() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/api/frames?hwid=warmup'))
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 422) {
          setState(() {
            _serverStatus = _CheckStatus.success;
            _serverMessage = 'Server terhubung (${response.statusCode})';
          });
        } else {
          setState(() {
            _serverStatus = _CheckStatus.warning;
            _serverMessage = 'Server merespon: ${response.statusCode}';
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _serverStatus = _CheckStatus.error;
          _serverMessage = 'Server timeout (>8s)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverStatus = _CheckStatus.error;
          _serverMessage = 'Tidak bisa terhubung ke server';
        });
      }
    }
  }

  // ================================================================
  // 4. RECENT PHOTOS CHECK
  // ================================================================
  Future<void> _checkRecentPhotos() async {
    if (_hwid.isEmpty) {
      if (mounted) {
        setState(() {
          _photosStatus = _CheckStatus.error;
          _photosMessage = 'HWID tidak terdeteksi';
        });
      }
      return;
    }

    try {
      final response = await http
          .get(Uri.parse(
              '$_backendUrl/api/photobooth/photos/recent?hwid=$_hwid&limit=10'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> photos = data['data'] ?? data['photos'] ?? [];

        final photoList = photos.map((p) {
          return _RecentPhoto(
            url: p['url'] ?? p['photo_url'] ?? '',
            sessionCode: p['transaction_code'] ?? p['session_code'] ?? '',
            createdAt: p['created_at'] ?? '',
          );
        }).toList();

        if (mounted) {
          setState(() {
            _recentPhotos = photoList;
            _photosStatus =
                photoList.isEmpty ? _CheckStatus.warning : _CheckStatus.success;
            _photosMessage = photoList.isEmpty
                ? 'Belum ada foto dari device ini'
                : '${photoList.length} foto terakhir ditemukan';
          });
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            _photosStatus = _CheckStatus.warning;
            _photosMessage =
                'Endpoint belum tersedia (404). Tambahkan API /recent-photos di backend.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _photosStatus = _CheckStatus.error;
            _photosMessage = 'Error: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _photosStatus = _CheckStatus.error;
          _photosMessage = 'Gagal mengambil foto: $e';
        });
      }
    }
  }

  // ================================================================
  // TEST PRINT
  // ================================================================
  Future<void> _testPrint(_PrinterInfo printer) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final printers = await Printing.listPrinters();
      final target = printers.firstWhere(
        (p) => p.name == printer.name,
        orElse: () => printers.first,
      );

      await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async {
          // Simple test page
          final doc = await _generateTestPage();
          return doc;
        },
      );

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Test print dikirim ke ${printer.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal print: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Uint8List> _generateTestPage() async {
    // Using pdf package to generate a simple test page
    // Import is already available from printing package
    final pdf = await rootBundle_workaround();
    return pdf;
  }

  /// Simple PDF test page without importing pdf package directly here
  /// (it's already a transitive dependency via printing)
  Future<Uint8List> rootBundle_workaround() async {
    // Generate a minimal valid PDF manually
    // This is a minimal PDF that prints "PHOTOBOOTH TEST PAGE"
    const content = '''%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 288 432]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 134>>
stream
BT
/F1 18 Tf
50 380 Td
(PHOTOBOOTH) Tj
/F1 14 Tf
50 350 Td
(TEST PAGE) Tj
/F1 10 Tf
50 320 Td
(Printer is working!) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000266 00000 n 
0000000340 00000 n 
trailer<</Size 6/Root 1 0 R>>
startxref
526
%%EOF''';
    return Uint8List.fromList(utf8.encode(content));
  }

  // ================================================================
  // NAVIGATION
  // ================================================================
  void _proceedToApp() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  bool get _allPassed =>
      _cameraStatus == _CheckStatus.success &&
      _printerStatus != _CheckStatus.error &&
      _serverStatus == _CheckStatus.success;

  bool get _allDone =>
      _cameraStatus != _CheckStatus.loading &&
      _printerStatus != _CheckStatus.loading &&
      _serverStatus != _CheckStatus.loading &&
      _photosStatus != _CheckStatus.loading;

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Row(
          children: [
            // ── LEFT PANEL: Checks ──
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: const Icon(
                            Icons.monitor_heart_outlined,
                            color: Colors.white70,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'System Diagnostic',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'HWID: ${_hwid.isNotEmpty ? _hwid.substring(0, _hwid.length > 20 ? 20 : _hwid.length) + '...' : 'detecting...'}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 36),

                    // ── Check cards ──
                    Expanded(
                      child: ListView(
                        children: [
                          // 1. Server
                          _buildCheckCard(
                            icon: Icons.dns_outlined,
                            title: 'Server Connection',
                            message: _serverMessage,
                            status: _serverStatus,
                            accentColor: const Color(0xFF6C63FF),
                          ),

                          const SizedBox(height: 12),

                          // 2. Camera
                          _buildCheckCard(
                            icon: Icons.camera_alt_outlined,
                            title: 'Camera Driver',
                            message: _cameraMessage,
                            status: _cameraStatus,
                            accentColor: const Color(0xFF00BFA5),
                            trailing: _cameraStatus == _CheckStatus.success
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00BFA5)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      Platform.isMacOS ? 'macOS' : 'Windows',
                                      style: const TextStyle(
                                        color: Color(0xFF00BFA5),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : null,
                          ),

                          const SizedBox(height: 12),

                          // 3. Printer
                          _buildCheckCard(
                            icon: Icons.print_outlined,
                            title: 'Printer Driver',
                            message: _printerMessage,
                            status: _printerStatus,
                            accentColor: const Color(0xFFFF6B6B),
                            expandedContent: _printers.isNotEmpty
                                ? Column(
                                    children: _printers.map((p) {
                                      return _buildPrinterRow(p);
                                    }).toList(),
                                  )
                                : null,
                          ),

                          const SizedBox(height: 12),

                          // 4. Recent Photos
                          _buildCheckCard(
                            icon: Icons.photo_library_outlined,
                            title: 'Recent Photos',
                            message: _photosMessage,
                            status: _photosStatus,
                            accentColor: const Color(0xFFFFB74D),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Bottom buttons ──
                    Row(
                      children: [
                        // Refresh
                        _buildActionButton(
                          icon: Icons.refresh,
                          label: 'Re-check',
                          onTap: () {
                            setState(() {
                              _cameraStatus = _CheckStatus.loading;
                              _printerStatus = _CheckStatus.loading;
                              _serverStatus = _CheckStatus.loading;
                              _photosStatus = _CheckStatus.loading;
                              _cameraMessage = 'Mendeteksi kamera...';
                              _printerMessage = 'Mendeteksi printer...';
                              _serverMessage = 'Mengecek koneksi server...';
                              _photosMessage = 'Mengambil foto terakhir...';
                              _printers = [];
                              _recentPhotos = [];
                            });
                            _runAllChecks();
                          },
                          color: Colors.white.withOpacity(0.08),
                          textColor: Colors.white70,
                        ),

                        const SizedBox(width: 12),

                        // Continue
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final glow = _allPassed && _allDone
                                  ? _pulseController.value * 0.3
                                  : 0.0;
                              return Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _allPassed && _allDone
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF00BFA5)
                                                .withOpacity(glow),
                                            blurRadius: 20,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : [],
                                ),
                                child: child,
                              );
                            },
                            child: _buildActionButton(
                              icon: Icons.arrow_forward_rounded,
                              label: _allDone
                                  ? (_allPassed
                                      ? 'Lanjutkan'
                                      : 'Lanjutkan Anyway')
                                  : 'Checking...',
                              onTap: _allDone ? _proceedToApp : null,
                              color: _allDone
                                  ? (_allPassed
                                      ? const Color(0xFF00BFA5)
                                      : const Color(0xFFFF9800))
                                  : Colors.white.withOpacity(0.05),
                              textColor:
                                  _allDone ? Colors.white : Colors.white38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── RIGHT PANEL: Recent photos grid ──
            Container(
              width: 360,
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: Colors.white.withOpacity(0.4),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hasil Foto Terakhir',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _photosStatus == _CheckStatus.loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white24,
                              strokeWidth: 2,
                            ),
                          )
                        : _recentPhotos.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.photo_library_outlined,
                                      color: Colors.white.withOpacity(0.1),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Belum ada foto',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.25),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 0.7,
                                ),
                                itemCount: _recentPhotos.length,
                                itemBuilder: (ctx, i) {
                                  final photo = _recentPhotos[i];
                                  return _buildPhotoCard(photo, i);
                                },
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // UI BUILDERS
  // ================================================================
  Widget _buildCheckCard({
    required IconData icon,
    required String title,
    required String message,
    required _CheckStatus status,
    required Color accentColor,
    Widget? trailing,
    Widget? expandedContent,
  }) {
    final Color statusColor;
    final IconData statusIcon;

    switch (status) {
      case _CheckStatus.loading:
        statusColor = Colors.white38;
        statusIcon = Icons.hourglass_empty;
        break;
      case _CheckStatus.success:
        statusColor = const Color(0xFF4CAF50);
        statusIcon = Icons.check_circle;
        break;
      case _CheckStatus.warning:
        statusColor = const Color(0xFFFF9800);
        statusIcon = Icons.warning_amber_rounded;
        break;
      case _CheckStatus.error:
        statusColor = const Color(0xFFFF5252);
        statusIcon = Icons.cancel;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == _CheckStatus.loading
              ? Colors.white.withOpacity(0.05)
              : statusColor.withOpacity(0.15),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
              const SizedBox(width: 8),
              status == _CheckStatus.loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor.withOpacity(0.5),
                      ),
                    )
                  : Icon(statusIcon, color: statusColor, size: 20),
            ],
          ),
          if (expandedContent != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
              child: expandedContent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrinterRow(_PrinterInfo printer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: printer.isAvailable
                  ? const Color(0xFF4CAF50)
                  : Colors.white24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              printer.name,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: printer.isAvailable
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.3),
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (printer.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'DEFAULT',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          if (printer.isAvailable) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _testPrint(printer),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFF6B6B).withOpacity(0.2),
                  ),
                ),
                child: const Text(
                  'Test Print',
                  style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoCard(_RecentPhoto photo, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            photo.url.isNotEmpty
                ? Image.network(
                    photo.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.03),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white.withOpacity(0.15),
                        size: 28,
                      ),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.white.withOpacity(0.03),
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.white.withOpacity(0.03),
                    child: Icon(
                      Icons.image_outlined,
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),

            // Bottom info overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (photo.sessionCode.isNotEmpty)
                      Text(
                        photo.sessionCode.length > 12
                            ? '${photo.sessionCode.substring(0, 12)}...'
                            : photo.sessionCode,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (photo.createdAt.isNotEmpty)
                      Text(
                        _formatDate(photo.createdAt),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 8,
                          fontFamily: 'Poppins',
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Index badge
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}

// ================================================================
// MODELS
// ================================================================
enum _CheckStatus { loading, success, warning, error }

class _PrinterInfo {
  final String name;
  final bool isDefault;
  final bool isAvailable;

  _PrinterInfo({
    required this.name,
    required this.isDefault,
    required this.isAvailable,
  });
}

class _RecentPhoto {
  final String url;
  final String sessionCode;
  final String createdAt;

  _RecentPhoto({
    required this.url,
    required this.sessionCode,
    required this.createdAt,
  });
}
