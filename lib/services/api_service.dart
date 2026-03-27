import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  // ✅ Ganti ke VPS baru
  final String baseUrl = "http://168.231.125.203:8181/api";

  // =================================================================
  // 1. LICENSE CHECK
  // =================================================================
  Future<bool> checkLicense(String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/license/check");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({'hwid': hwid}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("❌ Error License: $e");
      return false;
    }
  }

  // =================================================================
  // 2. SESSION
  // =================================================================
  Future<bool> startSession(String uuid, {
    required String hwid,
    String paymentMethod = 'qris',
    String amount = '0',
    String? voucherCode,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/start");
      print("🚀 Start Session ($paymentMethod) HWID: $hwid");

      final body = {
        'hwid': hwid,
        'transaction_code': uuid,
        'amount': amount,
        'payment_method': paymentMethod,
      };

      // Tambahkan voucher code jika ada
      if (voucherCode != null && voucherCode.isNotEmpty) {
        body['code'] = voucherCode;
      }

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode(body),
      );

      print("🚀 Start Response: ${response.statusCode} - ${response.body}");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Error Start Session: $e");
      return false;
    }
  }

  // =================================================================
  // 3. PAYMENT
  // =================================================================
  Future<String?> generatePaymentLink(String sessionUuid, double amount, String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({
          'device_id': hwid,
          'session_uuid': sessionUuid,
          'amount': amount.toInt(),
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['qr_content'];
      }
    } catch (e) {
      print("❌ Error Payment: $e");
    }
    return null;
  }

  Future<bool> checkPaymentStatus(String sessionUuid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/check-status");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({'session_uuid': sessionUuid}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'paid' || data['status'] == 'free';
      }
    } catch (e) {
      print("❌ Error Check Status: $e");
    }
    return false;
  }

  // =================================================================
  // 4. VOUCHER VALIDATION
  // =================================================================
  Future<Map<String, dynamic>?> validateVoucher(String code, String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/validate-voucher");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: jsonEncode({'code': code, 'hwid': hwid}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("❌ Error Voucher: $e");
    }
    return null;
  }

  // =================================================================
  // 5. UPLOAD
  // =================================================================
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
      final uri = Uri.parse("$baseUrl/photobooth/upload/final");
      var request = http.MultipartRequest('POST', uri);
      request.fields['session_uuid'] = sessionUuid;
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

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