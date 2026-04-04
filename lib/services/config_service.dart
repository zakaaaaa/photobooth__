import 'dart:async';
import 'package:http/http.dart' as http;

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  // URLs
  static const String localUrl = "http://localhost:3001";
  static const String remoteUrl = "http://168.231.125.203:8181";

  // Current active URL
  String _baseUrl = localUrl;
  String get baseUrl => _baseUrl;

  /// Initialize the configuration by discovering the best backend URL.
  Future<void> init() async {
    print("🌐 ConfigService: Discovering backend...");
    
    try {
      // Try to "ping" local server with a short timeout
      final uri = Uri.parse("$localUrl/api/photobooth/license/check");
      
      // We use a dummy POST to see if the server responds at all
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: '{"hwid": "ping"}',
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode != 0) {
        print("✅ ConfigService: Local server found at $localUrl");
        _baseUrl = localUrl;
      }
    } catch (e) {
      print("⚠️ ConfigService: Local server NOT found ($e). Falling back to $remoteUrl");
      _baseUrl = remoteUrl;
    }
    
    print("🚀 ConfigService: Active Base URL -> $_baseUrl");
  }
}
