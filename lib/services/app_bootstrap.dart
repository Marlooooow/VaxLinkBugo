import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize(AppEnvironment environment) async {
    environment.validate();
    if (!environment.usesSupabase) return;

    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.supabaseAnonKey,
    );
  }
}
