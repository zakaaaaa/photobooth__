import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/config_service.dart';
import '../providers/photo_provider.dart';
import 'camera_page.dart';

// ==========================================
// MODEL
// ==========================================
class FrameTemplate {
  final String id;
  final String name;
  final String imageUrl;
  final String thumbnailUrl;
  final int photoCount;
  final double outputWidth;
  final double outputHeight;
  final FrameLayout layout;
  final List<PhotoSlot> photoSlots;

  FrameTemplate({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.photoCount,
    required this.outputWidth,
    required this.outputHeight,
    required this.layout,
    required this.photoSlots,
  });

  bool get hasCustomSlots => photoSlots.isNotEmpty;

  factory FrameTemplate.fromJson(Map<String, dynamic> json) {
    final count        = json['photo_count'] as int? ?? 4;
    final imageUrl     = json['image_url']     as String? ?? '';
    final thumbnailUrl = json['thumbnail_url'] as String?;

    List<PhotoSlot> slots = [];
    final rawSlots = json['photo_slots'];
    if (rawSlots != null && rawSlots is List) {
      slots = rawSlots
          .map((s) => PhotoSlot.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return FrameTemplate(
      id:           json['id'] as String,
      name:         json['name'] as String,
      imageUrl:     imageUrl,
      thumbnailUrl: (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                        ? thumbnailUrl
                        : imageUrl,
      photoCount:   count,
      outputWidth:  (json['output_width']  as num?)?.toDouble() ?? 344.0,
      outputHeight: (json['output_height'] as num?)?.toDouble() ?? 515.0,
      layout:       _layoutForCount(count),
      photoSlots:   slots,
    );
  }

  static FrameLayout _layoutForCount(int count) {
    switch (count) {
      case 3:
        return const FrameLayout(
          topPadding: 59, bottomPadding: 59,
          leftPadding: 10, rightPadding: 10,
          horizontalSpacing: 20, verticalSpacing: 10,
          childAspectRatio: 1.2,
        );
      case 4:
      default:
        return const FrameLayout(
          topPadding: 25, leftPadding: 10, rightPadding: 5,
          bottomPadding: 40, horizontalSpacing: 5, verticalSpacing: 13,
          childAspectRatio: 1.0,
        );
    }
  }
}

// ==========================================
// PAGE
// ==========================================
class StaticFrameTemplatePage extends StatefulWidget {
  const StaticFrameTemplatePage({super.key});

  @override
  State<StaticFrameTemplatePage> createState() => _StaticFrameTemplatePageState();
}

class _StaticFrameTemplatePageState extends State<StaticFrameTemplatePage> {
  List<FrameTemplate> _templates = [];
  bool _isLoading = true;
  String _error   = '';

  static final String _baseUrl = '${ConfigService().baseUrl}/api';

  @override
  void initState() {
    super.initState();
    _fetchFrames();
  }

  Future<void> _fetchFrames() async {
    setState(() { _isLoading = true; _error = ''; });

    try {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      if (provider.machineId.isEmpty) await provider.initMachineId();
      final hwid = provider.machineId;

      final uri = Uri.parse('$_baseUrl/frames?hwid=$hwid');

      // Auto-retry 3x dengan jeda 2 detik
      http.Response? response;
      Exception? lastError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await http.get(uri).timeout(const Duration(seconds: 15));
          break;
        } catch (e) {
          lastError = e as Exception?;
          debugPrint('⚠️ Attempt $attempt gagal: $e');
          if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
        }
      }
      if (response == null) throw lastError ?? Exception('Timeout');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> framesJson = data['frames'] ?? [];

          // ✅ Set durasi dari API
          final int durationMin = (data['session_duration_minutes'] as num? ?? 5).toInt();
          if (mounted) {
            final provider = Provider.of<PhotoProvider>(context, listen: false);
            provider.setSessionDuration(durationMin);
          }

          setState(() {
            _templates = framesJson.map((j) => FrameTemplate.fromJson(j)).toList();
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _error = 'Gagal memuat frame. Cek koneksi internet.';
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _error = 'Tidak dapat terhubung ke server.\n$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.5)),

          Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 60, bottom: 20),
                child: OutlinedText(
                  text: "CHOOSE YOUR FRAME",
                  fontFamily: 'Ambitsek',
                  fontSize: 40,
                  textColor: Color(0xFFFFED00),
                  outlineColor: Color(0xFFEF7D30),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  hasShadow: true,
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFED00)))
                    : _error.isNotEmpty
                        ? _buildError()
                        : _templates.isEmpty
                            ? _buildEmpty()
                            : _buildGrid(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 0.55,
        ),
        itemCount: _templates.length,
        itemBuilder: (context, index) => RetroFrameCard(template: _templates[index]),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white38, size: 64),
          const SizedBox(height: 16),
          Text(_error,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _fetchFrames,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0000AA),
                border: Border.all(color: Colors.white24)),
              child: const Text("Coba Lagi",
                style: TextStyle(fontFamily: 'Ambitsek', color: Colors.white,
                  fontSize: 16, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text("Belum ada frame tersedia.",
            style: TextStyle(color: Colors.white38, fontSize: 16, fontFamily: 'Ambitsek')),
          SizedBox(height: 8),
          Text("Hubungi admin untuk menambahkan frame.",
            style: TextStyle(color: Colors.white24, fontSize: 13)),
        ],
      ),
    );
  }
}

// ==========================================
// FRAME CARD
// ==========================================
class RetroFrameCard extends StatefulWidget {
  final FrameTemplate template;
  const RetroFrameCard({super.key, required this.template});

  @override
  State<RetroFrameCard> createState() => _RetroFrameCardState();
}

class _RetroFrameCardState extends State<RetroFrameCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  static const List<Color> _slotColors = [
    Color(0xFF6366f1), Color(0xFF10b981), Color(0xFFf59e0b), Color(0xFFef4444),
    Color(0xFF8b5cf6), Color(0xFF06b6d4), Color(0xFFf472b6), Color(0xFF84cc16),
    Color(0xFFfb923c), Color(0xFF38bdf8),
  ];

  List<Widget> _buildSlotPreviews(
    List<PhotoSlot> slots,
    double frameW, double frameH,
    double dispW,  double dispH,
  ) {
    final scaleX = dispW / frameW;
    final scaleY = dispH / frameH;

    return slots.asMap().entries.map((entry) {
      final i     = entry.key;
      final slot  = entry.value;
      final color = _slotColors[slot.photoIndex % _slotColors.length];

      final left     = slot.x      * scaleX;
      final top      = slot.y      * scaleY;
      final width    = slot.width  * scaleX;
      final height   = slot.height * scaleY;
      final fontSize = (width * 0.28).clamp(8.0, 22.0);

      return Positioned(
        left: left, top: top, width: width, height: height,
        child: Transform.rotate(
          angle: slot.rotation * (3.14159265 / 180),
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.75),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: Colors.white, fontSize: fontSize,
                      fontWeight: FontWeight.w900, fontFamily: 'Poppins',
                      shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                      height: 1,
                    ),
                  ),
                  if (width > 30 && height > 30)
                    Text(
                      'F${slot.photoIndex + 1}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: (fontSize * 0.55).clamp(6.0, 12.0),
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _handleSelection() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    final template = widget.template;

    if (template.hasCustomSlots) {
      provider.setFrameModeWithSlots(
        FrameMode.static,
        photoCount:   template.photoCount,
        frameAsset:   template.imageUrl,
        photoSlots:   template.photoSlots,
        customWidth:  template.outputWidth,
        customHeight: template.outputHeight,
      );
      debugPrint('✅ Frame "${template.name}" — ${template.photoSlots.length} slots, ${template.photoCount} foto');
    } else {
      provider.setFrameMode(
        FrameMode.static,
        photoCount:   template.photoCount,
        frameAsset:   template.imageUrl,
        layout:       template.layout,
        customWidth:  template.outputWidth,
        customHeight: template.outputHeight,
      );
      debugPrint('⚠️ Frame "${template.name}" — fallback layout (belum ada slots)');
    }

    // ✅ MULAI TIMER SESI DI SINI — Setelah frame dipilih
    if (!provider.isSessionActive) {
      provider.startSession();
    }

    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CameraPage()));
  }

  @override
  Widget build(BuildContext context) {
    final hasSlots = widget.template.hasCustomSlots;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit:  (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _isPressed = true),
        onTapUp:     (_) { setState(() => _isPressed = false); _handleSelection(); },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFC0C0C0),
              border: Border.all(width: 3, color: Colors.black),
              boxShadow: _isPressed
                  ? []
                  : [BoxShadow(color: Colors.black.withOpacity(0.6), offset: const Offset(6, 6))],
            ),
            child: Column(
              children: [
                // Header bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: const Color(0xFF0000AA),
                  child: Text(
                    widget.template.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Ambitsek', color: Colors.white,
                      fontSize: 13, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis, maxLines: 1,
                  ),
                ),

                // Photo count + slot badge
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt, color: Colors.white54, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.template.photoCount} FOTO',
                        style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5),
                      ),
                      if (hasSlots) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${widget.template.photoSlots.length}SL',
                            style: const TextStyle(
                              color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Frame preview — pakai thumbnailUrl
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final frameW = widget.template.outputWidth;
                        final frameH = widget.template.outputHeight;
                        final scaleX = constraints.maxWidth  / frameW;
                        final scaleY = constraints.maxHeight / frameH;
                        final scale  = scaleX < scaleY ? scaleX : scaleY;
                        final dispW  = frameW * scale;
                        final dispH  = frameH * scale;

                        return Center(
                          child: SizedBox(
                            width: dispW, height: dispH,
                            child: Stack(
                              children: [
                                if (widget.template.hasCustomSlots)
                                  ..._buildSlotPreviews(
                                    widget.template.photoSlots,
                                    frameW, frameH, dispW, dispH,
                                  ),

                                Positioned.fill(
                                  child: Image.network(
                                    widget.template.thumbnailUrl,
                                    fit: BoxFit.fill,
                                    cacheWidth: 400,
                                    loadingBuilder: (ctx, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: Colors.black12,
                                        child: Center(
                                          child: SizedBox(
                                            width: 20, height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: const Color(0xFF0000AA),
                                              value: progress.expectedTotalBytes != null
                                                  ? progress.cumulativeBytesLoaded /
                                                    progress.expectedTotalBytes!
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (ctx, err, st) => const Center(
                                      child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// OUTLINED TEXT WIDGET
// ==========================================
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
    super.key, required this.text, required this.fontFamily,
    required this.fontSize, required this.textColor, required this.outlineColor,
    this.fontWeight = FontWeight.normal, this.letterSpacing = 0.0, this.hasShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (hasShadow) Positioned(top: 4, left: 4, child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: fontFamily, fontSize: fontSize,
            fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            color: Colors.black.withOpacity(0.6)))),
        Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: fontFamily, fontSize: fontSize,
            fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = outlineColor)),
        Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: fontFamily, fontSize: fontSize,
            fontWeight: fontWeight, letterSpacing: letterSpacing, height: 1.2,
            color: textColor)),
      ],
    );
  }
}