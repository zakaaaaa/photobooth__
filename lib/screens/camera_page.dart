import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // Wajib punya ini
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'customization_page.dart';
import 'preview_print_page.dart';
import '../services/api_service.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  // Tidak butuh controller kamera
  int _currentPhotoIndex = 0;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Reset provider saat masuk halaman ini
    Future.microtask(() {
      final provider = Provider.of<PhotoProvider>(context, listen: false);
      provider.reset(); 
      // Pastikan session UUID ada (jika dari bypass)
      if (provider.sessionUuid.isEmpty) {
        provider.setSessionUuid("manual-${DateTime.now().millisecondsSinceEpoch}");
      }
    });
  }

  // LOGIC: PILIH FILE DARI MAC
  Future<void> _pickPhoto() async {
    setState(() => _isUploading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        if (!mounted) return;
        final provider = Provider.of<PhotoProvider>(context, listen: false);

        // 1. Simpan ke Provider (Memory)
        provider.addPhoto(bytes);

        // 2. Upload ke Database (Background)
        // Agar flow data tetap sama seperti flow asli
        try {
          final apiService = Provider.of<ApiService>(context, listen: false);
          await apiService.uploadPhoto(provider.sessionUuid, file.path);
        } catch (e) {
          debugPrint("Gagal upload background: $e");
        }

        setState(() {
          _currentPhotoIndex++;
        });

        // 3. Cek Jika Sudah Selesai
        if (provider.photos.length >= provider.targetPhotoCount) {
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("All photos collected! Processing...")),
          );
          
          await Future.delayed(const Duration(seconds: 1));
          _onFinish();
        }

      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _onFinish() {
    final provider = Provider.of<PhotoProvider>(context, listen: false);
    if (provider.selectedMode == FrameMode.static) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PreviewPrintPage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomizationPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoProvider>();
    int target = provider.targetPhotoCount; // Biasanya 3 atau 4

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // BACKGROUND (Bisa gambar statis biar gak polos)
          Image.asset(
            "assets/images/bg.png", // Pastikan aset ini ada, atau ganti container warna
            fit: BoxFit.cover,
            errorBuilder: (c, o, s) => Container(color: Colors.grey[900]),
          ),

          // OVERLAY FRAME KAMERA (Agar feel-nya tetap sama)
          IgnorePointer(
            child: Image.asset("assets/images/cam_ovl.png", fit: BoxFit.cover),
          ),

          // TENGAH: TOMBOL UPLOAD ATAU PREVIEW FOTO TERAKHIR
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Judul
                Text(
                  "DEVELOPER MODE (MANUAL UPLOAD)", 
                  style: TextStyle(fontFamily: 'Ambitsek', color: Colors.yellowAccent, fontSize: 20, letterSpacing: 2),
                ),
                const SizedBox(height: 10),
                Text(
                  "Photo ${_currentPhotoIndex + 1} of $target", 
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),

                // Area Preview / Tombol
                GestureDetector(
                  onTap: _isUploading ? null : _pickPhoto,
                  child: Container(
                    width: 400,
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _isUploading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : provider.photos.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(
                                  provider.photos.last.imageData, // Tampilkan foto terakhir yg diupload
                                  fit: BoxFit.contain,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.upload_file, color: Colors.white, size: 60),
                                  SizedBox(height: 10),
                                  Text("CLICK TO UPLOAD PHOTO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),

          // SIDEBAR KANAN (RESULTS)
          Positioned(
            right: 20, top: 20, bottom: 20,
            child: Container(
              width: 140,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  const Text("RESULTS", style: TextStyle(fontFamily: 'Ambitsek', color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: ListView.separated(
                      itemCount: target,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 15),
                      itemBuilder: (context, index) {
                        bool hasPhoto = index < provider.photos.length;
                        return Container(
                          height: 110,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            border: Border.all(color: hasPhoto ? Colors.greenAccent : Colors.white30, width: 2),
                            borderRadius: BorderRadius.circular(10),
                            image: hasPhoto 
                              ? DecorationImage(image: MemoryImage(provider.photos[index].imageData), fit: BoxFit.cover)
                              : null
                          ),
                          child: !hasPhoto ? const Center(child: Text("Empty", style: TextStyle(color: Colors.white30, fontSize: 10))) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // TOMBOL BACK
          Positioned(
            top: 50, left: 30,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 40),
            ),
          ),
        ],
      ),
    );
  }
}