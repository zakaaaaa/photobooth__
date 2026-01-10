import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

// ==========================================
// 1. ENUMS (DEFINISI TIPE DATA)
// ==========================================
enum PhotoFilter { none, vintage, grayscale, smooth, brightness }
enum FrameShape { rectangle, circle, love }
enum FrameMode { static, custom }
enum CustomLayout { vertical, grid } // Pilihan Layout untuk Mode Custom

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
// === TAMBAHKAN KODE INI ===
  String _sessionUuid = ''; 
  
  String get sessionUuid => _sessionUuid;

  void setSessionUuid(String uuid) {
    _sessionUuid = uuid;
    notifyListeners();
  }
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

void setFinalImageBytes(Uint8List bytes) {
  _finalImageBytes = bytes;
  notifyListeners();
}

  // --- B. FRAME CONFIGURATION STATE ---
  FrameMode _selectedMode = FrameMode.static;
  CustomLayout _customLayout = CustomLayout.vertical; 
  int _targetPhotoCount = 3; 
  String? _selectedFrameAsset;
  FrameLayout _selectedLayout = const FrameLayout();

  // Getters
  FrameMode get selectedMode => _selectedMode;
  CustomLayout get customLayout => _customLayout;
  int get targetPhotoCount => _targetPhotoCount;
  String? get selectedFrameAsset => _selectedFrameAsset;
  FrameLayout get selectedLayout => _selectedLayout;

  // Setters
  void setFrameMode(FrameMode mode, {
    int photoCount = 3, 
    String? frameAsset,
    FrameLayout? layout,
  }) {
    _selectedMode = mode;
    _selectedFrameAsset = frameAsset;
    _selectedLayout = layout ?? const FrameLayout();

    if (mode == FrameMode.custom) {
      _targetPhotoCount = 4; // Force 4 foto untuk custom
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
  
  // Frame Utama (Warna di belakang foto individual)
  Color _frameColor = Colors.blue;
  String? _frameTexture;
  FrameShape _frameShape = FrameShape.rectangle;
  
  // Container Frame (Warna latar belakang kertas keseluruhan) -> INI YANG TADI HILANG
  Color _frameContainerColor = Colors.white;
  String? _frameContainerTexture;

  final List<StickerData> _stickers = [];
  
  String _headlineText = '';
  double _textSize = 28;
  double _textRotation = 0;
  Offset _textPosition = const Offset(0, 0);

  // Getters
  Color get frameColor => _frameColor;
  String? get frameTexture => _frameTexture;
  FrameShape get frameShape => _frameShape;
  
  // Getter yang tadi error:
  Color get frameContainerColor => _frameContainerColor;
  String? get frameContainerTexture => _frameContainerTexture;

  List<StickerData> get stickers => _stickers;
  String get headlineText => _headlineText;
  double get textSize => _textSize;
  double get textRotation => _textRotation;
  Offset get textPosition => _textPosition;

  // Setters Background
  void setFrameColor(Color color) {
    _frameColor = color;
    _frameTexture = null; 
    notifyListeners();
  }

  void setFrameTexture(String texturePath) {
    _frameTexture = texturePath;
    notifyListeners();
  }

  // Setters Container (Background Kertas)
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

  // Sticker Logic
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

  // Text Logic
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

  // --- E. RESET & DISPOSE ---
  
  void reset() {
    _photos.clear();
    _selectedFilter = PhotoFilter.none;
    
    // Reset Customization
    _frameColor = Colors.blue;
    _frameTexture = null;
    _frameContainerColor = Colors.white; // Reset Container Color
    _frameContainerTexture = null;       // Reset Container Texture
    _frameShape = FrameShape.rectangle;
    _stickers.clear();
    _headlineText = '';
    _textSize = 28;
    _textRotation = 0;
    _textPosition = const Offset(0, 0);
    
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}