import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // Base URL sesuai port 8080 yang sudah kita buka di Nginx
  final String baseUrl = "http://168.231.125.203:8080/api"; 

  // =================================================================
  // 1. PAYMENT INTEGRATION
  // =================================================================

  Future<String?> generatePaymentLink(String sessionUuid, double amount, String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate"); 
      print("💰 Requesting QRIS: $uri"); 

      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          'device_id': hwid, // Wajib dikirim agar lolos validasi Laravel
          'session_uuid': sessionUuid,
          'amount': amount.toInt(), // Mengirim integer sesuai ekspektasi Laravel
        }),
      );

      print("📡 Payment Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['qr_content']; // URL dari Doku
      } else {
        print("❌ Server rejected payment request: ${response.body}");
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
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({'session_uuid': sessionUuid}),
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

  Future<bool> checkLicense(String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/license/check");
      print("🔍 Checking License: $uri");
      
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({'hwid': hwid}),
      );

      print("🔍 License Response: ${response.body}");
      return response.statusCode == 200;
    } catch (e) {
      print("❌ Error License: $e");
      return false;
    }
  }

  Future<bool> startSession(String uuid, {
    required String hwid, 
    String paymentMethod = 'qris', 
    String amount = '0'
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/start-session");
      print("🚀 Start Session ($paymentMethod) HWID: $hwid");

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({
            'hwid': hwid,
            'transaction_code': uuid,
            'amount': amount,
            'payment_method': paymentMethod,
        }),
      );
      
      print("🚀 Start Response: ${response.statusCode} - ${response.body}");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error Start Session: $e");
      return false;
    }
  }

  // Untuk Upload tetap menggunakan MultipartRequest (bukan JSON)
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
        return data['url']; 
      }
    } catch (e) {
      print("❌ Error Upload Final: $e");
    }
    return null;
  }
}