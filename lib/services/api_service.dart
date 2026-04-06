import 'package:photobooth_app/services/app_logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class ApiService {
  static const Set<String> _allowedPaymentMethods = {'qris', 'voucher'};

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
      AppLogger.debug("❌ Error License: $e");
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
    if (!_allowedPaymentMethods.contains(paymentMethod)) {
      AppLogger.warn(
          "Rejected unsupported payment method: $paymentMethod (uuid: $uuid)");
      return false;
    }
    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/start");
      AppLogger.debug("🚀 Start Session ($paymentMethod) HWID: $hwid");

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

      AppLogger.debug(
          "🚀 Start Response: ${response.statusCode} - ${response.body}");

      // ── DEBUG: Extract session_id from response jika ada ──
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);
          AppLogger.debug("🔍 Session response keys: ${data.keys.toList()}");
          if (data['session_id'] != null) {
            AppLogger.debug("🔍 Backend session_id: ${data['session_id']}");
          }
          if (data['uuid'] != null) {
            AppLogger.debug("🔍 Backend uuid: ${data['uuid']}");
          }
          if (data['transaction_code'] != null) {
            AppLogger.debug(
                "🔍 Backend transaction_code: ${data['transaction_code']}");
          }
          // Print all data for debugging
          AppLogger.debug("🔍 Full session response data: $data");
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.debug("Error Start Session: $e");
      return false;
    }
  }

  // =================================================================
  // 3. PAYMENT
  // =================================================================
  Future<String?> generatePaymentLink(String sessionUuid) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate");

      AppLogger.debug("──────────────────────────────────────────");
      AppLogger.debug("💳 generatePaymentLink DEBUG");
      AppLogger.debug("💳 URL: $uri");
      AppLogger.debug("💳 session_uuid being sent: $sessionUuid");
      AppLogger.debug("──────────────────────────────────────────");

      final requestBody = jsonEncode({
        'session_uuid': sessionUuid,
      });
      AppLogger.debug("💳 Request body: $requestBody");

      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: requestBody,
      );

      AppLogger.debug("💳 Response status: ${response.statusCode}");
      AppLogger.debug("💳 Response headers: ${response.headers}");
      AppLogger.debug("💳 Response body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        AppLogger.debug("💳 Decoded response keys: ${data.keys.toList()}");
        AppLogger.debug("💳 Full decoded data: $data");

        // Coba beberapa kemungkinan field name
        final paymentUrl = data['payment_url'] ??
            data['paymentUrl'] ??
            data['url'] ??
            data['checkout_url'] ??
            data['redirect_url'] ??
            data['link'];

        if (paymentUrl != null) {
          AppLogger.debug("💳 ✅ Payment URL found: $paymentUrl");
          return paymentUrl;
        } else {
          AppLogger.debug("💳 ❌ No payment URL field found in response!");
          AppLogger.debug("💳 Available keys: ${data.keys.toList()}");
          AppLogger.debug("💳 Tip: Check backend response format");
          return null;
        }
      } else {
        AppLogger.debug("💳 ❌ Non-200 status code: ${response.statusCode}");
        AppLogger.debug("💳 Error body: ${response.body}");

        // Try to decode error response
        try {
          final errorData = json.decode(response.body);
          AppLogger.debug(
              "💳 Error message: ${errorData['message'] ?? errorData['error'] ?? 'unknown'}");
        } catch (_) {
          AppLogger.debug("💳 Could not decode error response");
        }
      }
    } on SocketException catch (e) {
      AppLogger.debug("💳 ❌ SocketException (no internet/DNS fail): $e");
    } on http.ClientException catch (e) {
      AppLogger.debug("💳 ❌ ClientException: $e");
    } on FormatException catch (e) {
      AppLogger.debug("💳 ❌ FormatException (invalid JSON response): $e");
    } catch (e) {
      AppLogger.debug("💳 ❌ Unexpected error: $e");
      AppLogger.debug("💳 Error type: ${e.runtimeType}");
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
      AppLogger.debug("❌ Error Check Status: $e");
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
      AppLogger.debug("❌ Error Voucher: $e");
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
      AppLogger.debug("Error Upload Photo: $e");
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
      AppLogger.debug("❌ Error Upload Final: $e");
    }
    return null;
  }
}
