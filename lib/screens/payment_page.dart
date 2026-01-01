import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import 'camera_page.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _isLoading = true;
  bool _isPaid = false;

  @override
  void initState() {
    super.initState();
    // Simulasi loading QRIS dari Midtrans
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _handlePaymentSuccess() {
    setState(() {
      _isPaid = true;
    });

    // 1. MULAI TIMER SESI (5 Menit 20 Detik)
    Provider.of<PhotoProvider>(context, listen: false).startSession();

    // 2. Delay sebentar lalu masuk Kamera
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CameraPage()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pembayaran")),
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Membuat QRIS Midtrans..."),
                ],
              )
            : _isPaid
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 100),
                      SizedBox(height: 20),
                      Text("Pembayaran Berhasil!", style: TextStyle(fontSize: 24)),
                      Text("Sesi dimulai...", style: TextStyle(color: Colors.grey)),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Scan QRIS di bawah ini",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      // Placeholder QR Code
                      Container(
                        width: 250,
                        height: 250,
                        color: Colors.grey.shade300,
                        child: const Center(
                          child: Icon(Icons.qr_code_2, size: 150),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text("Total: Rp 25.000", style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 40),
                      
                      // TOMBOL DUMMY (Nanti diganti Callback Midtrans)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        ),
                        onPressed: _handlePaymentSuccess,
                        child: const Text("Simulasi Bayar Sukses", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
      ),
    );
  }
}