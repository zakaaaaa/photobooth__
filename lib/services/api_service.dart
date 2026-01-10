import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // IP VPS Anda
  final String baseUrl = "http://168.231.125.203/api"; 

  // =================================================================
  // 1. PAYMENT INTEGRATION (DOKU)
  // =================================================================

  // Generate Link Pembayaran (Minta ke Laravel)
  Future<String?> generatePaymentLink(String sessionUuid, double amount) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate");
      print("💰 Requesting payment url for: $sessionUuid");

      final response = await http.post(
        uri,
        headers: {"Accept": "application/json"}, // Header penting
        body: {
          'session_uuid': sessionUuid,
          'amount': amount.toStringAsFixed(0),
        },
      );

      print("💰 Response: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['payment_url']; // URL DOKU Checkout
      } else {
        print("❌ Gagal Generate Payment: ${response.body}");
      }
    } catch (e) {
      print("❌ Error Payment Connection: $e");
    }
    return null;
  }

  // Cek Status Pembayaran (Polling)
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
        // Return TRUE jika status 'paid'
        return data['status'] == 'paid';
      }
    } catch (e) {
      print("❌ Error Check Status: $e");
    }
    return false;
  }

  // =================================================================
  // 2. SESSION & UPLOAD (EXISTING)
  // =================================================================

  Future<bool> startSession(String uuid) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/photobooth/start-session"),
        body: {'session_uuid': uuid},
      );
      return response.statusCode == 201;
    } catch (e) {
      print("Error Start Session: $e");
      return false;
    }
  }

  Future<bool> uploadPhoto(String uuid, String filePath) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl/photobooth/upload"));
      request.fields['session_uuid'] = uuid;
      request.files.add(await http.MultipartFile.fromPath('image', filePath));
      var response = await request.send();
      return response.statusCode == 201;
    } catch (e) {
      print("Error Upload Photo: $e");
      return false;
    }
  }

  Future<bool> uploadFinalResult(String sessionUuid, String filePath) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/upload-final"); 
      
      print("🚀 Uploading Final to: $uri");

      var request = http.MultipartRequest('POST', uri);
      request.fields['session_uuid'] = sessionUuid;
      request.files.add(await http.MultipartFile.fromPath('image', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print("📡 Response: ${response.statusCode} - ${response.body}");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("❌ Error Upload Final: $e");
      return false;
    }
  }
}