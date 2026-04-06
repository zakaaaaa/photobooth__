import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:photobooth_app/services/app_logger.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  // Backend URLs
  static const String localUrl = String.fromEnvironment(
    'LOCAL_BACKEND_URL',
    defaultValue: 'http://localhost:3001',
  );
  static const String remoteUrl = String.fromEnvironment(
    'PROD_BACKEND_URL',
    defaultValue: 'https://api.amandya.tech',
  );

  // Frontend URLs (untuk QR download)
  static const String localFrontendUrl = String.fromEnvironment(
    'LOCAL_FRONTEND_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const String remoteFrontendUrl = String.fromEnvironment(
    'PROD_FRONTEND_URL',
    defaultValue: 'https://app.amandya.tech',
  );

  String _baseUrl = localUrl;
  String get baseUrl => _baseUrl;

  bool get _isDevelopment => !kReleaseMode;
  String get frontendUrl =>
      _isDevelopment ? localFrontendUrl : remoteFrontendUrl;

  /// Development: force localhost (tanpa fallback ke production).
  /// Release: gunakan production URL.
  Future<void> init() async {
    if (_isDevelopment) {
      _baseUrl = localUrl;
      AppLogger.debug(
        'ConfigService: Development mode -> force local backend: $_baseUrl',
      );

      // Health-check hanya untuk log (tidak mengubah URL aktif)
      try {
        final uri = Uri.parse('$_baseUrl/api/photobooth/license/check');
        await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: '{"hwid":"ping"}',
            )
            .timeout(const Duration(seconds: 2));
        AppLogger.debug('ConfigService: Local backend reachable.');
      } catch (e) {
        AppLogger.debug('ConfigService: Local backend belum reachable: $e');
      }
      return;
    }

    _baseUrl = remoteUrl;
    AppLogger.debug(
      'ConfigService: Release mode -> production backend: $_baseUrl',
    );
  }
}
