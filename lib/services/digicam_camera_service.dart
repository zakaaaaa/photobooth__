// lib/services/digicam_camera_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:process_run/shell.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

class DigiCamCameraService {
  final Shell _shell = Shell();
  String? _digicamPath;
  bool _isInitialized = false;
  String? _outputFolder;

  // Initialize DigiCamControl
  Future<bool> initialize() async {
    try {
      // Path default instalasi DigiCamControl
      final possiblePaths = [
        r'C:\Program Files (x86)\digiCamControl\CameraControlCmd.exe',
        r'C:\Program Files\digiCamControl\CameraControlCmd.exe',
        r'C:\digiCamControl\CameraControlCmd.exe',
      ];

      for (final path in possiblePaths) {
        if (await File(path).exists()) {
          _digicamPath = path;
          print('✅ Found DigiCamControl: $path');
          break;
        }
      }

      if (_digicamPath == null) {
        print('❌ DigiCamControl not found in standard locations');
        return false;
      }

      // Setup output folder
      final tempDir = await getTemporaryDirectory();
      _outputFolder = '${tempDir.path}\\photobooth_captures';
      await Directory(_outputFolder!).create(recursive: true);
      print('📁 Output folder: $_outputFolder');

      _isInitialized = true;
      return true;
    } catch (e) {
      print('❌ DigiCamControl initialization error: $e');
      return false;
    }
  }

  // Detect Camera - Simplified (just check if DigiCamControl exe exists)
  Future<bool> detectCamera() async {
    if (!_isInitialized || _digicamPath == null) {
      print('❌ Not initialized');
      return false;
    }

    try {
      // We just check if the exe exists - actual camera test happens on capture
      print('✅ DigiCamControl ready at: $_digicamPath');
      print('⚠️ Camera will be tested on first capture');
      return true;
    } catch (e) {
      print('❌ Error detecting camera: $e');
      return false;
    }
  }

  // Take Picture (REVISED & ROBUST)
  Future<Uint8List?> takePicture() async {
    if (!_isInitialized || _digicamPath == null || _outputFolder == null) {
      throw Exception('DigiCamControl camera not initialized');
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'capture_$timestamp.jpg';
      final filepath = '$_outputFolder\\$filename';

      print('📷 Taking picture...');
      print('Output path: $filepath');
      
      // Capture image dengan DigiCamControl
      final command = '"$_digicamPath" /capturenoaf /filename "$filepath"';
      print('Command: $command');
      
      // REVISI: Timeout dinaikkan ke 20 detik & handle onTimeout agar tidak throw exception
      await _shell.run(command).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('⚠️ Shell command timeout (Process took too long), but proceeding to check file...');
          return []; // Return list kosong agar flow tidak putus
        },
      );

      print('Waiting for file transfer...');
      
      File? capturedFile;

      // REVISI: Polling loop lebih robust (Cek setiap 1 detik, max 15 kali)
      for (int i = 0; i < 15; i++) {
        final f = File(filepath);
        
        // Cek apakah file ada DAN ukurannya > 0 bytes (mencegah baca file corrupt/sedang ditulis)
        if (await f.exists()) {
          final len = await f.length();
          if (len > 0) {
            print('✅ Image file found! Size: $len bytes');
            capturedFile = f;
            break;
          }
        }
        
        await Future.delayed(const Duration(seconds: 1));
        print('⏳ Waiting for file... ${i + 1}/15');
      }

      // Proses file jika ditemukan
      if (capturedFile != null) {
        print('Reading image file...');
        final bytes = await capturedFile.readAsBytes();
        
        // Delete temp file setelah dibaca untuk menghemat storage
        try {
          await capturedFile.delete();
        } catch (e) {
          print('Warning: Could not delete temp file: $e');
        }
        
        return bytes;
      } else {
        print('❌ Image file not found after waiting');
        return null;
      }

    } catch (e) {
      print('❌ Error taking picture: $e');
      return null;
    }
  }

  // Capture without download (save to camera SD card only)
  Future<bool> captureImageOnly() async {
    if (!_isInitialized || _digicamPath == null) return false;

    try {
      await _shell.run('"$_digicamPath" /capturenoaf');
      return true;
    } catch (e) {
      print('Error capturing image: $e');
      return false;
    }
  }

  // Set ISO
  Future<bool> setISO(int iso) async {
    if (!_isInitialized || _digicamPath == null) return false;

    try {
      await _shell.run('"$_digicamPath" /iso $iso');
      return true;
    } catch (e) {
      print('Error setting ISO: $e');
      return false;
    }
  }

  // Set Aperture (f-number)
  Future<bool> setAperture(String aperture) async {
    if (!_isInitialized || _digicamPath == null) return false;

    try {
      // Format: f/5.6 -> 5.6
      await _shell.run('"$_digicamPath" /aperture $aperture');
      return true;
    } catch (e) {
      print('Error setting aperture: $e');
      return false;
    }
  }

  // Set Shutter Speed
  Future<bool> setShutterSpeed(String speed) async {
    if (!_isInitialized || _digicamPath == null) return false;

    try {
      // Format: "1/125"
      await _shell.run('"$_digicamPath" /shutter "$speed"');
      return true;
    } catch (e) {
      print('Error setting shutter speed: $e');
      return false;
    }
  }

  // Get Camera Info
  Future<String?> getCameraInfo() async {
    if (!_isInitialized || _digicamPath == null) return null;

    try {
      final result = await _shell.run('"$_digicamPath" /help');
      return result.first.stdout.toString();
    } catch (e) {
      print('Error getting camera info: $e');
      return null;
    }
  }

  // Cleanup
  Future<void> cleanup() async {
    if (_outputFolder != null) {
      try {
        final dir = Directory(_outputFolder!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        print('Error cleaning up: $e');
      }
    }
  }

  bool get isInitialized => _isInitialized;
}