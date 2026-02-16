import 'dart:convert';
import 'dart:io'; // Untuk File
import 'package:http/http.dart' as http;

class ApiService {
  // Base URL (Pastikan IP VPS benar)
  final String baseUrl = "http://168.231.125.203:8080/api"; 

  // =================================================================
  // 1. PAYMENT INTEGRATION
  // =================================================================

  Future<String?> generatePaymentLink(String sessionUuid, double amount) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate"); 
      print("💰 Requesting QRIS: $uri");

      final response = await http.post(
        uri,
        headers: {"Accept": "application/json"},
        body: {
          'session_uuid': sessionUuid,
          'amount': amount.toStringAsFixed(0),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['qr_content']; 
      }
    } catch (e) {
      print("❌ Error Payment Connection: $e");
    }
    return null;
  }

  Future<bool> checkPaymentStatus(String sessionUuid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/check-status");
      final response = await http.post(
        uri,
        headers: {"Accept": "application/json"},
        body: {'session_uuid': sessionUuid},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'paid';
      }
    } catch (e) {
      print("❌ Error Check Status: $e");
    }
    return false;
  }

  // =================================================================
  // 2. SESSION & UPLOAD
  // =================================================================

  // 1. Cek License / Login
  Future<bool> checkLicense(String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/license/check");
      print("🔍 Checking License: $uri");
      
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'hwid': hwid}),
      );

      print("🔍 License Response: ${response.body}");
      return response.statusCode == 200;
    } catch (e) {
      print("❌ Error License: $e");
      return false;
    }
  }

  // 2. Start Session (UPDATED UNTUK BYPASS)
  // Menambahkan parameter paymentMethod & amount agar fleksibel
  Future<bool> startSession(String uuid, {String paymentMethod = 'qris', String amount = '0'}) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/start-session");
      print("🚀 Start Session ($paymentMethod): $uri");

      final response = await http.post(
        uri,
        body: {
            // NOTE: HWID sebaiknya dinamis dari LicenseService, 
            // tapi untuk sekarang hardcode dulu tidak apa-apa sesuai test Anda.
            'hwid': 'F4DAFFE8-75F5-5D21-AF51-ABD0A74A9A14', 
            'transaction_code': uuid,
            'amount': amount,          // <-- Kirim harga (0 jika bypass)
            'payment_method': paymentMethod, // <-- Kirim metode (bypass/qris)
        },
      );
      
      print("🚀 Start Response: ${response.statusCode} - ${response.body}");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error Start Session: $e");
      return false;
    }
  }

  // 3. Upload Foto Mentah (Saat jepret)
  Future<bool> uploadPhoto(String uuid, String filePath) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/upload");
      var request = http.MultipartRequest('POST', uri);
      
      request.fields['session_uuid'] = uuid;
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      var response = await request.send();
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error Upload Photo: $e");
      return false;
    }
  }

  // 4. Upload Final Result (Frame yang sudah jadi)
  // Return String URL jika sukses, null jika gagal
  Future<String?> uploadFinalResult(String sessionUuid, String filePath) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/upload-final");
      print("🚀 Uploading Final to: $uri");

      var request = http.MultipartRequest('POST', uri);
      request.fields['session_uuid'] = sessionUuid;
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print("📡 Response Upload Final: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        // Mengembalikan URL gambar hasil upload (dari controller: 'url')
        return data['url']; 
      }
    } catch (e) {
      print("❌ Error Upload Final: $e");
    }
    return null;
  }
}