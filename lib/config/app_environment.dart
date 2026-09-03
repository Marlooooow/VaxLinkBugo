import 'dart:convert';

enum AppDataMode { mock, hybrid, live }

class AppEnvironment {
  final AppDataMode dataMode;
  final String supabaseUrl;
  final String supabaseAnonKey;

  const AppEnvironment({
    required this.dataMode,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory AppEnvironment.fromDartDefines() {
    const rawMode = String.fromEnvironment(
      'APP_DATA_MODE',
      defaultValue: 'live',
    );

    return AppEnvironment(
      dataMode: parseDataMode(rawMode),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  factory AppEnvironment.fromPublicConfiguration(
    String contents, {
    AppDataMode dataMode = AppDataMode.live,
  }) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid public Supabase configuration.');
    }
    const permitted = {'APP_DATA_MODE', 'SUPABASE_URL', 'SUPABASE_ANON_KEY'};
    if (decoded.keys.any((key) => !permitted.contains(key))) {
      throw const FormatException(
        'The public configuration contains an unsupported field.',
      );
    }
    final environment = AppEnvironment(
      dataMode: dataMode,
      supabaseUrl: decoded['SUPABASE_URL'] as String? ?? '',
      supabaseAnonKey: decoded['SUPABASE_ANON_KEY'] as String? ?? '',
    );
    environment.validate();
    return environment;
  }

  static AppDataMode parseDataMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'live':
        return AppDataMode.live;
      case 'hybrid':
        return AppDataMode.hybrid;
      case 'mock':
        return AppDataMode.mock;
      default:
        throw const FormatException(
          'APP_DATA_MODE must be live, mock, or hybrid.',
        );
    }
  }

  bool get usesSupabase => dataMode != AppDataMode.mock;
  bool get isLive => dataMode == AppDataMode.live;
  bool get showsDemoControls => !isLive;

  bool get hasSupabaseConfiguration =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  bool get hasAnySupabaseConfiguration =>
      supabaseUrl.trim().isNotEmpty || supabaseAnonKey.trim().isNotEmpty;

  void validate() {
    if (usesSupabase && !hasSupabaseConfiguration) {
      throw const FormatException(
        'SUPABASE_URL and SUPABASE_ANON_KEY are required in hybrid or live mode.',
      );
    }
    if (!usesSupabase) return;
    final uri = Uri.tryParse(supabaseUrl);
    final local = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        !uri.hasAuthority ||
        !(uri.scheme == 'https' || (local && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Use a valid HTTPS Supabase project URL.');
    }
    if (!isPublicSupabaseKey(supabaseAnonKey)) {
      throw const FormatException(
        'Only a Supabase publishable or anon key may be included in the app.',
      );
    }
  }

  static bool isPublicSupabaseKey(String key) {
    if (key.startsWith('sb_publishable_')) {
      return key.length > 'sb_publishable_'.length;
    }
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
