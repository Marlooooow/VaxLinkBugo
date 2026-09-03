import 'package:flutter/material.dart';
import 'repositories/repository_registry.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class QRPediatricVaccinationApp extends StatelessWidget {
  final RepositoryRegistry repositories;

  const QRPediatricVaccinationApp({super.key, required this.repositories});

  @override
  Widget build(BuildContext context) {
    final authRepository = repositories.authRepository;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'QR Pediatric Vaccination',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: SplashScreen(authRepository: authRepository),
        routes: {'/login': (_) => LoginScreen(authRepository: authRepository)},
      ),
    );
  }
}
