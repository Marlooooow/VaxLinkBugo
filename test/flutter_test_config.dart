import 'dart:async';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';

/// Match app bootstrap for widget tests without opening a database connection.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RepositoryRegistry.create(
    const AppEnvironment(
      dataMode: AppDataMode.mock,
      supabaseUrl: '',
      supabaseAnonKey: '',
    ),
  );
  await testMain();
}
