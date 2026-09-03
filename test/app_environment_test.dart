import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('rejects unknown modes instead of silently selecting mock', () {
      expect(
        () => AppEnvironment.parseDataMode('unknown'),
        throwsFormatException,
      );
    });

    test('parses hybrid and live without case sensitivity', () {
      expect(AppEnvironment.parseDataMode(' Hybrid '), AppDataMode.hybrid);
      expect(AppEnvironment.parseDataMode('LIVE'), AppDataMode.live);
    });

    test('mock mode does not require Supabase credentials', () {
      const environment = AppEnvironment(
        dataMode: AppDataMode.mock,
        supabaseUrl: '',
        supabaseAnonKey: '',
      );
      expect(environment.validate, returnsNormally);
    });

    test('live mode rejects missing Supabase credentials', () {
      const environment = AppEnvironment(
        dataMode: AppDataMode.live,
        supabaseUrl: '',
        supabaseAnonKey: '',
      );
      expect(environment.validate, throwsFormatException);
    });

    test('accepts a bundled public-only live configuration', () {
      final environment = AppEnvironment.fromPublicConfiguration('''
        {
          "APP_DATA_MODE": "live",
          "SUPABASE_URL": "https://example.supabase.co",
          "SUPABASE_ANON_KEY": "sb_publishable_example"
        }
      ''');
      expect(environment.dataMode, AppDataMode.live);
      expect(environment.hasSupabaseConfiguration, isTrue);
    });

    test('bundled configuration refuses private or unsupported fields', () {
      expect(
        () => AppEnvironment.fromPublicConfiguration('''
          {
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_ANON_KEY": "sb_publishable_example",
            "SUPABASE_SERVICE_ROLE_KEY": "must-not-be-bundled"
          }
        '''),
        throwsFormatException,
      );
    });
  });
}
