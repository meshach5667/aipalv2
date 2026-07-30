import 'package:aipal/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig production URL validation', () {
    test('rejects localhost API URLs in production', () {
      expect(
        () => AppConfig.normalizeApiBase(
          'http://127.0.0.1:8102',
          environment: 'production',
        ),
        throwsStateError,
      );
    });

    test('rejects insecure API URLs in production', () {
      expect(
        () => AppConfig.normalizeApiBase(
          'http://api.example.com',
          environment: 'production',
        ),
        throwsStateError,
      );
    });

    test('accepts HTTPS API URLs in production and appends API prefix', () {
      expect(
        AppConfig.normalizeApiBase(
          'https://api.example.com',
          environment: 'production',
        ),
        'https://api.example.com/api/v2',
      );
    });

    test('rejects insecure WebSocket URLs in production', () {
      expect(
        () => AppConfig.normalizeServiceBase(
          'ws://api.example.com',
          environment: 'production',
          expectedSecureScheme: 'wss',
          productionName: 'WS_BASE_URL',
        ),
        throwsStateError,
      );
    });

    test('accepts WSS URLs in production', () {
      expect(
        AppConfig.normalizeServiceBase(
          'wss://api.example.com/api/v2',
          environment: 'production',
          expectedSecureScheme: 'wss',
          productionName: 'WS_BASE_URL',
        ),
        'wss://api.example.com/api/v2',
      );
    });
  });
}
