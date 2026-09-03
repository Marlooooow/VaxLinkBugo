import 'dart:convert';
import 'dart:io';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';

/// Whitelist only public mobile configuration. Never export the entire .env:
/// it can also contain AI keys, management tokens, and service-role secrets.
Map<String, String> publicLiveConfiguration(String contents) {
  final values = <String, String>{};
  const allowed = {'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_KEY'};
  for (final line in const LineSplitter().convert(contents)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator < 1) continue;
    final name = trimmed.substring(0, separator).trim();
    if (!allowed.contains(name)) continue;
    var value = trimmed.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (values.containsKey(name)) {
      throw const FormatException('Duplicate public configuration key.');
    }
    values[name] = value;
  }
  final key = values['SUPABASE_ANON_KEY'] ?? values['SUPABASE_KEY'] ?? '';
  final environment = AppEnvironment(
    dataMode: AppDataMode.live,
    supabaseUrl: values['SUPABASE_URL'] ?? '',
    supabaseAnonKey: key,
  );
  environment.validate();
  return {
    'APP_DATA_MODE': 'live',
    'SUPABASE_URL': environment.supabaseUrl,
    'SUPABASE_ANON_KEY': key,
  };
}

void main(List<String> args) {
  final output = File('.dart_tool/vaxlink.public.json');
  final bundledOutput = File('assets/config/supabase.public.json');
  try {
    final values = publicLiveConfiguration(File('.env').readAsStringSync());
    final encoded = '${const JsonEncoder.withIndent('  ').convert(values)}\n';
    for (final target in [output, bundledOutput]) {
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(encoded, flush: true);
    }
    stdout.writeln(
      'Live public configuration prepared for launch and app bundling. '
      'Private credentials were excluded.',
    );
  } catch (_) {
    // Do not leave a stale project's configuration available after validation fails.
    if (output.existsSync()) output.deleteSync();
    if (bundledOutput.existsSync()) bundledOutput.deleteSync();
    stderr.writeln(
      'Live configuration could not be prepared. Check .env: use the project URL and a publishable/anon key.',
    );
    exitCode = 1;
  }
}
