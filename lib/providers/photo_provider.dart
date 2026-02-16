import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; 
import '../services/license_service.dart'; // <--- WAJIB IMPORT INI

// ==========================================
// 1. ENUMS
// ==========================================
enum PhotoFilter { none, vintage, grayscale, smooth, brightness }
enum FrameShape { rectangle, circle, love }
enum FrameMode { static, custom }
enum CustomLayout { vertical, grid } 

// ==========================================
// 2. DATA MODELS
// ==========================================

class PhotoData {
  final Uint8List imageData;
  final PhotoFilter filter;

  PhotoData({required this.imageData, required this.filter});
}

class StickerData {
  String assetPath;
  Offset position;
  double size;
  double rotation;
  
  StickerData({
    required this.assetPath,
    this.position = const Offset(50, 50),
    this.size = 100,
    this.rotation = 0,
  });
}

class FrameLayout {
  final double topPadding;
  final double bottomPadding;
  final double leftPadding;
  final double rightPadding;
  final double horizontalSpacing;
  final double verticalSpacing;
  final double childAspectRatio;

  const FrameLayout({
    this.topPadding = 0,
    this.bottomPadding = 0,
    this.leftPadding = 0,
    this.rightPadding = 0,
    this.horizontalSpacing = 10,
    this.verticalSpacing = 10,
    this.childAspectRatio = 1.0, 
  });
}

// ==========================================
// 3. MAIN PROVIDER CLASS
// ==========================================
class PhotoProvider extends ChangeNotifier {

  // --- A. SESSION & TIMER MANAGEMENT ---
  Timer? _sessionTimer;
  int _remainingTime = 320; 
  bool _isSessionActive = false;

  int get remainingTime => _remainingTime;
  bool get isSessionActive => _isSessionActive;

  String get timerString {
    final minutes = (_remainingTime / 60).floor().toString().padLeft(2, '0');
    final seconds = (_remainingTime % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // --- HWID & UUID MANAGEMENT (UPDATED) ---
  String _sessionUuid = ''; 
  String get sessionUuid => _sessionUuid;

  // Variable untuk menyimpan HWID mesin
  String _machineId = '';
  String get machineId => _machineId;

  // Fungsi untuk Load HWID (Dipanggil di awal / Splash Screen / Payment)
  Future<void> initMachineId() async {
    if (_machineId.isEmpty) {
      try {
        // Panggil fungsi getHardwareId dari LicenseService (Pastikan Public)
        _machineId = await LicenseService().getHardwareId();
        notifyListeners();
        print("💻 Machine ID Loaded: $_machineId");
      } catch (e) {
        print("❌ Gagal Load Machine ID: $e");
      }
    }
  }

  void setSessionUuid(String uuid) {
    _sessionUuid = uuid;
    notifyListeners();
  }

  // --- PHOTO MANAGEMENT ---

  void removePhotoAt(int index) {
    if (index >= 0 && index < _photos.length) {
      _photos.removeAt(index);
      notifyListeners();
    }
  }

  void startSession() {
    reset(); 
    _remainingTime = 320; 
    _isSessionActive = true;
    notifyListeners();

    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 0) {
        _remainingTime--;
        notifyListeners();
      } else {
        stopSession(); 
      }
    });
  }

  void stopSession() {
    _sessionTimer?.cancel();
    _isSessionActive = false;
    notifyListeners();
  }

  Uint8List? _finalImageBytes;
  Uint8List? get finalImageBytes => _finalImageBytes;

  // Property finalFramePath (Untuk kompatibilitas dengan UI lama)
  String? _finalFramePath;
  String? get finalFramePath => _finalFramePath;

  void setFinalImageBytes(Uint8List bytes) {
    _finalImageBytes = bytes;
    notifyListeners();
  }

  void setFinalFrame(String path) {
    _finalFramePath = path;
    notifyListeners();
  }

  // --- B. FRAME CONFIGURATION STATE ---
  FrameMode _selectedMode = FrameMode.static;
  CustomLayout _customLayout = CustomLayout.vertical; 
  int _targetPhotoCount = 3; 
  String? _selectedFrameAsset;
  FrameLayout _selectedLayout = const FrameLayout();

  double? _selectedFrameWidth;
  double? _selectedFrameHeight;

  FrameMode get selectedMode => _selectedMode;
  CustomLayout get customLayout => _customLayout;
  int get targetPhotoCount => _targetPhotoCount;
  String? get selectedFrameAsset => _selectedFrameAsset;
  FrameLayout get selectedLayout => _selectedLayout;
  
  double get selectedFrameWidth => _selectedFrameWidth ?? 344.0;
  double get selectedFrameHeight => _selectedFrameHeight ?? 515.0;

  void setFrameMode(
    FrameMode mode, {
    int photoCount = 3, 
    String? frameAsset,
    FrameLayout? layout,
    double? customWidth,
    double? customHeight,
  }) {
    _selectedMode = mode;
    _selectedFrameAsset = frameAsset;
    _selectedLayout = layout ?? const FrameLayout();
    _selectedFrameWidth = customWidth;
    _selectedFrameHeight = customHeight;

    if (mode == FrameMode.custom) {
      _targetPhotoCount = 4; 
    } else {
      _targetPhotoCount = photoCount;
    }
    notifyListeners();
  }

  void setCustomLayout(CustomLayout layout) {
    _customLayout = layout;
    notifyListeners();
  }

  // --- C. PHOTO DATA MANAGEMENT ---
  final List<PhotoData> _photos = [];
  PhotoFilter _selectedFilter = PhotoFilter.none;

  List<PhotoData> get photos => _photos;
  int get photoCount => _photos.length;
  bool get isComplete => _photos.length >= _targetPhotoCount;
  PhotoFilter get selectedFilter => _selectedFilter;

  void addPhoto(Uint8List imageData) {
    if (_photos.length < _targetPhotoCount) {
      _photos.add(PhotoData(
        imageData: imageData,
        filter: _selectedFilter,
      ));
      notifyListeners();
    }
  }

  // Overload addPhoto untuk string path (Kompatibilitas)
  void addPhotoPath(String path) {
    // Implementasi jika diperlukan, saat ini kita fokus byte data
    // _photos.add(...)
  }

  void setSelectedFilter(PhotoFilter filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  void clearPhotos() {
    _photos.clear();
    _selectedFilter = PhotoFilter.none;
    notifyListeners();
  }

  // --- D. CUSTOMIZATION STATE ---
  Color _frameColor = Colors.blue;
  String? _frameTexture;
  FrameShape _frameShape = FrameShape.rectangle;
  
  Color _frameContainerColor = Colors.white;
  String? _frameContainerTexture;

  final List<StickerData> _stickers = [];
  
  String _headlineText = '';
  double _textSize = 28;
  double _textRotation = 0;
  Offset _textPosition = const Offset(0, 0);

  Color get frameColor => _frameColor;
  String? get frameTexture => _frameTexture;
  FrameShape get frameShape => _frameShape;
  
  Color get frameContainerColor => _frameContainerColor;
  String? get frameContainerTexture => _frameContainerTexture;

  List<StickerData> get stickers => _stickers;
  String get headlineText => _headlineText;
  double get textSize => _textSize;
  double get textRotation => _textRotation;
  Offset get textPosition => _textPosition;

  void setFrameColor(Color color) {
    _frameColor = color;
    _frameTexture = null; 
    notifyListeners();
  }

  void setFrameTexture(String texturePath) {
    _frameTexture = texturePath;
    notifyListeners();
  }

  void setFrameContainerColor(Color color) {
    _frameContainerColor = color;
    _frameContainerTexture = null;
    notifyListeners();
  }

  void setFrameContainerTexture(String texturePath) {
    _frameContainerTexture = texturePath;
    notifyListeners();
  }

  void setFrameShape(FrameShape shape) {
    _frameShape = shape;
    notifyListeners();
  }

  void addSticker(String assetPath) {
    _stickers.add(StickerData(assetPath: assetPath));
    notifyListeners();
  }

  void updateStickerPosition(int index, Offset position) {
    if (index < _stickers.length) {
      _stickers[index].position = position;
      notifyListeners();
    }
  }

  void updateStickerSize(int index, double size) {
    if (index < _stickers.length) {
      _stickers[index].size = size;
      notifyListeners();
    }
  }

  void updateStickerRotation(int index, double rotation) {
    if (index < _stickers.length) {
      _stickers[index].rotation = rotation;
      notifyListeners();
    }
  }

  void removeSticker(int index) {
    if (index < _stickers.length) {
      _stickers.removeAt(index);
      notifyListeners();
    }
  }

  void setHeadlineText(String text) {
    _headlineText = text;
    notifyListeners();
  }

  void updateTextSize(double size) {
    _textSize = size;
    notifyListeners();
  }

  void updateTextRotation(double rotation) {
    _textRotation = rotation;
    notifyListeners();
  }

  void updateTextPosition(Offset position) {
    _textPosition = position;
    notifyListeners();
  }

  // ==========================================
  // E. SAVE PHOTOS LOCALLY
  // ==========================================
  Future<String> savePhotosLocally(String userEmail, Uint8List? finalStripBytes) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dateStr = DateTime.now().toString().split(' ')[0];
      final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      
      final sessionFolder = Directory('${directory.path}/Photobooth_Backup/$dateStr/$sessionId');
      
      if (!await sessionFolder.exists()) {
        await sessionFolder.create(recursive: true);
      }

      // 2. SIMPAN FOTO MENTAH
      for (int i = 0; i < _photos.length; i++) {
        final file = File('${sessionFolder.path}/raw_photo_$i.jpg');
        await file.writeAsBytes(_photos[i].imageData);
      }

      // 3. SIMPAN FOTO STRIP / FINAL
      if (finalStripBytes != null) {
        final stripFile = File('${sessionFolder.path}/final_strip_result.png');
        await stripFile.writeAsBytes(finalStripBytes);
        print("✅ Final Strip Tersimpan!");
      } else {
        print("⚠️ Peringatan: Final Strip belum ada/belum dirender");
      }

      // 4. Catat Log CSV
      final logFile = File('${directory.path}/Photobooth_Backup/$dateStr/data_pengunjung.csv');
      final csvLine = '$sessionId,$userEmail,${sessionFolder.path},PENDING\n';
      await logFile.writeAsString(csvLine, mode: FileMode.append);

      return sessionFolder.path;

    } catch (e) {
      print("❌ Gagal Simpan Lokal: $e");
      return "";
    }
  }

  // ==========================================
  // F. RESET & DISPOSE
  // ==========================================
  
  void reset() {
    print("🧹 RESET SESSION: Membersihkan memori foto...");

    _photos.clear();
    _finalImageBytes = null; 
    _finalFramePath = null;
    
    // Jangan reset _machineId di sini karena HWID tetap sama
    // Jangan reset _sessionUuid di sini jika flow payment -> foto (UUID dibuat di payment)
    // Kecuali start session baru dari awal.
    
    _selectedFilter = PhotoFilter.none;
    _isSessionActive = false;
    _sessionTimer?.cancel();
    
    _frameColor = Colors.blue;
    _frameTexture = null;
    _frameContainerColor = Colors.white; 
    _frameContainerTexture = null;       
    _frameShape = FrameShape.rectangle;
    _stickers.clear();
    _headlineText = '';
    _textSize = 28;
    _textRotation = 0;
    _textPosition = const Offset(0, 0);
    _selectedFrameWidth = null;
    _selectedFrameHeight = null;
    
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}