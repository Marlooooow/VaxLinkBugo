import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/services/app_configuration_loader.dart';

class _PublicConfigurationBundle extends CachingAssetBundle {
  final Map<String, Object?> values;
  _PublicConfigurationBundle(this.values);

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(jsonEncode(values));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  test(
    'plain live launch loads the bundled public Supabase settings',
    () async {
      final environment = await AppConfigurationLoader.load(
        bundle: _PublicConfigurationBundle({
          'APP_DATA_MODE': 'live',
          'SUPABASE_URL': 'https://example.supabase.co',
          'SUPABASE_ANON_KEY': 'sb_publishable_example',
        }),
      );
      expect(environment.dataMode, AppDataMode.live);
      expect(environment.supabaseUrl, 'https://example.supabase.co');
    },
  );

  test('plain launch rejects a private field in the bundled asset', () async {
    await expectLater(
      AppConfigurationLoader.load(
        bundle: _PublicConfigurationBundle({
          'SUPABASE_URL': 'https://example.supabase.co',
          'SUPABASE_ANON_KEY': 'sb_publishable_example',
          'AI_API_KEY': 'must-not-be-bundled',
        }),
      ),
      throwsFormatException,
    );
  });
}
