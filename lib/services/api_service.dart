import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class ApiService {
  // ✅ Dinamis: Local (dev) atau VPS (prod)
  String get baseUrl => "${ConfigService().baseUrl}/api";

  // =================================================================
  // 1. LICENSE CHECK
  // =================================================================
  Future<bool> checkLicense(String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/license/check");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
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
  Future<bool> startSession(
    String uuid, {
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
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: jsonEncode(body),
      );

      print("🚀 Start Response: ${response.statusCode} - ${response.body}");

      // ── DEBUG: Extract session_id from response jika ada ──
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);
          print("🔍 Session response keys: ${data.keys.toList()}");
          if (data['session_id'] != null) {
            print("🔍 Backend session_id: ${data['session_id']}");
          }
          if (data['uuid'] != null) {
            print("🔍 Backend uuid: ${data['uuid']}");
          }
          if (data['transaction_code'] != null) {
            print("🔍 Backend transaction_code: ${data['transaction_code']}");
          }
          // Print all data for debugging
          print("🔍 Full session response data: $data");
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      print("Error Start Session: $e");
      return false;
    }
  }

  // =================================================================
  // 3. PAYMENT
  // =================================================================
  Future<String?> generatePaymentLink(String sessionUuid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate");

      print("──────────────────────────────────────────");
      print("💳 generatePaymentLink DEBUG");
      print("💳 URL: $uri");
      print("💳 session_uuid being sent: $sessionUuid");
      print("──────────────────────────────────────────");

      final requestBody = jsonEncode({
        'session_uuid': sessionUuid,
      });
      print("💳 Request body: $requestBody");

      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: requestBody,
      );

      print("💳 Response status: ${response.statusCode}");
      print("💳 Response headers: ${response.headers}");
      print("💳 Response body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print("💳 Decoded response keys: ${data.keys.toList()}");
        print("💳 Full decoded data: $data");

        // Coba beberapa kemungkinan field name
        final paymentUrl = data['payment_url']
            ?? data['paymentUrl']
            ?? data['url']
            ?? data['checkout_url']
            ?? data['redirect_url']
            ?? data['link'];

        if (paymentUrl != null) {
          print("💳 ✅ Payment URL found: $paymentUrl");
          return paymentUrl;
        } else {
          print("💳 ❌ No payment URL field found in response!");
          print("💳 Available keys: ${data.keys.toList()}");
          print("💳 Tip: Check backend response format");
          return null;
        }
      } else {
        print("💳 ❌ Non-200 status code: ${response.statusCode}");
        print("💳 Error body: ${response.body}");

        // Try to decode error response
        try {
          final errorData = json.decode(response.body);
          print("💳 Error message: ${errorData['message'] ?? errorData['error'] ?? 'unknown'}");
        } catch (_) {
          print("💳 Could not decode error response");
        }
      }
    } on SocketException catch (e) {
      print("💳 ❌ SocketException (no internet/DNS fail): $e");
    } on http.ClientException catch (e) {
      print("💳 ❌ ClientException: $e");
    } on FormatException catch (e) {
      print("💳 ❌ FormatException (invalid JSON response): $e");
    } catch (e) {
      print("💳 ❌ Unexpected error: $e");
      print("💳 Error type: ${e.runtimeType}");
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
          "Accept": "application/json"
        },
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
  Future<Map<String, dynamic>?> validateVoucher(
      String code, String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/validate-voucher");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
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