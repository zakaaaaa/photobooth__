import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:photobooth_app/services/app_logger.dart';

import 'config_service.dart';

class ApiService {
  static const Set<String> _allowedPaymentMethods = {'qris', 'voucher'};

  String get baseUrl => "${ConfigService().baseUrl}/api";

  Future<Map<String, dynamic>?> fetchBootstrap(String hwid) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/bootstrap?hwid=$hwid");
      final response = await http.get(
        uri,
        headers: {"Accept": "application/json"},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.debug("Bootstrap error: $e");
    }
    return null;
  }

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
      AppLogger.debug("License error: $e");
      return false;
    }
  }

  Future<bool> startSession(
    String uuid, {
    required String hwid,
    String paymentMethod = 'qris',
    String transactionType = 'session',
    int extraPrintCount = 0,
    String? voucherCode,
  }) async {
    if (!_allowedPaymentMethods.contains(paymentMethod)) {
      AppLogger.warn(
          "Rejected unsupported payment method: $paymentMethod (uuid: $uuid)");
      return false;
    }

    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/start");
      final body = <String, dynamic>{
        'hwid': hwid,
        'transaction_code': uuid,
        'payment_method': paymentMethod,
        'transaction_type': transactionType,
      };

      if (extraPrintCount > 0) {
        body['extra_print_count'] = extraPrintCount;
      }
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
          "Start session response: ${response.statusCode} - ${response.body}");
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      AppLogger.debug("Error Start Session: $e");
      return false;
    }
  }

  Future<String?> generatePaymentLink(String sessionUuid, {required String hwid}) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/generate");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: jsonEncode({'session_uuid': sessionUuid, 'hwid': hwid}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['payment_url'] ??
            data['paymentUrl'] ??
            data['url'] ??
            data['checkout_url'] ??
            data['redirect_url'] ??
            data['link'];
      }
    } on SocketException catch (e) {
      AppLogger.debug("Payment link socket error: $e");
    } on http.ClientException catch (e) {
      AppLogger.debug("Payment link client error: $e");
    } on FormatException catch (e) {
      AppLogger.debug("Payment link format error: $e");
    } catch (e) {
      AppLogger.debug("Payment link unexpected error: $e");
    }
    return null;
  }

  Future<bool> checkPaymentStatus(String sessionUuid, {required String hwid}) async {
    try {
      final uri = Uri.parse("$baseUrl/payment/check-status");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: jsonEncode({'session_uuid': sessionUuid, 'hwid': hwid}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'paid' || data['status'] == 'free';
      }
    } catch (e) {
      AppLogger.debug("Check payment error: $e");
    }
    return false;
  }

  Future<bool> uploadPhoto(
    String uuid,
    String filePath, {
    String? hwid,
    int? photoOrder,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/upload");
      final request = http.MultipartRequest('POST', uri);
      request.fields['session_uuid'] = uuid;
      if (hwid != null && hwid.isNotEmpty) {
        request.fields['hwid'] = hwid;
      }
      if (photoOrder != null && photoOrder > 0) {
        request.fields['photo_order'] = photoOrder.toString();
      }
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));
      final response = await request.send();
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      AppLogger.debug("Upload photo error: $e");
      return false;
    }
  }

  Future<String?> uploadFinalResult(String sessionUuid, String filePath, {String? hwid}) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/upload/final");
      final request = http.MultipartRequest('POST', uri);
      request.fields['session_uuid'] = sessionUuid;
      if (hwid != null && hwid.isNotEmpty) {
        request.fields['hwid'] = hwid;
      }
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['url'];
      }
    } catch (e) {
      AppLogger.debug("Upload final error: $e");
    }
    return null;
  }

  Future<bool> attachFrameToSession({
    required String sessionUuid,
    required String frameId,
    required String hwid,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/session/attach-frame");
      final response = await http.patch(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          'session_uuid': sessionUuid,
          'frame_id': frameId,
          'hwid': hwid,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.debug("Attach frame error: $e");
      return false;
    }
  }

  Future<bool> sendResultEmail({
    required String hwid,
    required String recipientEmail,
    required String resultUrl,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/photobooth/email/send-result");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: jsonEncode({
          'hwid': hwid,
          'recipient_email': recipientEmail,
          'result_url': resultUrl,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.debug("Send email error: $e");
      return false;
    }
  }
}
