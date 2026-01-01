import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔍 Testing camera detection...');
  List<CameraDescription> cameras = [];
  
  try {
    cameras = await availableCameras();
    print('✅ Found ${cameras.length} camera(s)');
    for (var cam in cameras) {
      print('   - ${cam.name}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
  
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text(
          cameras.isEmpty ? 'NO CAMERAS' : '${cameras.length} CAMERAS FOUND',
          style: TextStyle(fontSize: 24),
        ),
      ),
    ),
  ));
}
