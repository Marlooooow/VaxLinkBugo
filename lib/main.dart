import 'package:flutter/material.dart';
import 'app.dart';
import 'repositories/repository_registry.dart';
import 'services/app_bootstrap.dart';
import 'services/app_configuration_loader.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.initialize();
  try {
    final environment = await AppConfigurationLoader.load();
    await AppBootstrap.initialize(environment);
    final repositories = RepositoryRegistry.create(environment);
    runApp(QRPediatricVaccinationApp(repositories: repositories));
  } catch (_) {
    // Configuration errors must never silently start a demo session.
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'VaxLink could not start its live connection.\n\n'
                  'Fully restart the application. If this continues, regenerate '
                  'the bundled public Supabase configuration. Demo mode remains '
                  'available as a separate launch.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
