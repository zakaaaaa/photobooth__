import 'package:flutter/material.dart';
import '../services/license_service.dart';
import 'home_screen.dart'; // <--- 1. JANGAN LUPA IMPORT HALAMAN TUJUAN

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LicenseService _licenseService = LicenseService();
  String _statusMessage = "Memeriksa Lisensi...";
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    await Future.delayed(const Duration(seconds: 2)); // Estetika delay

    final result = await _licenseService.checkLicense();

    if (!mounted) return; // Cek apakah widget masih aktif

    if (result['success'] == true) {
      // LISENSI VALID
      setState(() {
        _statusMessage = "Selamat Datang, ${result['data']['client']}";
      });
      
      // Tampilkan Dialog Sukses
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        _showSuccessDialog();
      }
    } else {
      // LISENSI GAGAL
      setState(() {
        _isError = true;
        _statusMessage = result['message'];
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User gabisa tutup dialog dengan klik luar
      builder: (context) => AlertDialog(
        title: const Text("Akses Diterima"),
        content: const Text("Lisensi Valid. Silakan masuk."),
        actions: [
          TextButton(
            onPressed: () {
              // 2. LOGIKA PINDAH HALAMAN (Navigation)
              Navigator.pop(context); // Tutup Dialog dulu
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomeScreen(), // <--- Arahkan ke HomeScreen
                ),
              );
            },
            child: const Text("LANJUT", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 80, color: Colors.white),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isError ? Colors.red : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            if (!_isError)
              const CircularProgressIndicator(color: Colors.white),
            if (_isError)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isError = false;
                      _statusMessage = "Mencoba lagi...";
                    });
                    _checkAccess();
                  },
                  child: const Text("Coba Lagi"),
                ),
              )
          ],
        ),
      ),
    );
  }
}