import 'package:photobooth_app/services/app_logger.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  // URLs
  static const String localUrl = "http://localhost:3001";
  static const String remoteUrl = "https://api.amandya.tech";

  // Current active URL
  String _baseUrl = localUrl;
  String get baseUrl => _baseUrl;

  /// Initialize the configuration by discovering the best backend URL.
  Future<void> init() async {
    AppLogger.debug("🌐 ConfigService: Discovering backend...");

    try {
      // Try to "ping" local server with a short timeout
      final uri = Uri.parse("$localUrl/api/photobooth/license/check");

      // We use a dummy POST to see if the server responds at all
      final response = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: '{"hwid": "ping"}',
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppLogger.debug("✅ ConfigService: Local server found at $localUrl");
        _baseUrl = localUrl;
      } else {
        AppLogger.debug(
            "⚠️ ConfigService: Local server returned error ${response.statusCode}. Falling back to $remoteUrl");
        _baseUrl = remoteUrl;
      }
    } catch (e) {
      AppLogger.debug(
          "⚠️ ConfigService: Local server NOT found ($e). Falling back to $remoteUrl");
      _baseUrl = remoteUrl;
    }

    AppLogger.debug("🚀 ConfigService: Active Base URL -> $_baseUrl");
  }
}
