import 'package:flutter/services.dart';

import '../config/app_environment.dart';

/// Loads public mobile configuration without ever reading `.env` at runtime.
/// Compile-time values take precedence. A partially supplied compile-time
/// configuration is rejected rather than mixed with another source.
class AppConfigurationLoader {
  const AppConfigurationLoader._();

  static const publicAsset = 'assets/config/supabase.public.json';

  static Future<AppEnvironment> load({AssetBundle? bundle}) async {
    final defined = AppEnvironment.fromDartDefines();
    if (!defined.usesSupabase) return defined;
    if (defined.hasAnySupabaseConfiguration) {
      defined.validate();
      return defined;
    }

    final contents = await (bundle ?? rootBundle).loadString(publicAsset);
    return AppEnvironment.fromPublicConfiguration(
      contents,
      dataMode: defined.dataMode,
    );
  }
}
