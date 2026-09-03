import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../services/session_context.dart';
import '../widgets/app_logo.dart';
import '../widgets/family_care_banner.dart';
import '../widgets/app_loading.dart';
import 'app_shell.dart';

import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  final AuthRepository authRepository;

  const SplashScreen({super.key, required this.authRepository});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (mounted) setState(() => _failed = false);
    AppUser? user;
    try {
      final results = await Future.wait<Object?>([
        widget.authRepository.getCurrentUser(),
        // Avoid a flash on fast devices without delaying a slower connection.
        Future<void>.delayed(const Duration(milliseconds: 650)),
      ]);
      user = results.first as AppUser?;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    if (!mounted) return;

    if (user == null || !user.active) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(authRepository: widget.authRepository),
        ),
      );
      return;
    }

    _goToDashboard(user);
  }

  void _goToDashboard(AppUser user) {
    SessionContext.setUser(user);
    final screen = AppShell(user: user, authRepository: widget.authRepository);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final green = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              primary.withValues(alpha: 0.035),
              green.withValues(alpha: 0.045),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppLogo(size: 96),
                  const SizedBox(height: 26),
                  const FamilyCareBanner(),
                  const SizedBox(height: 20),
                  Text(
                    'Vaccination Tracking\n& Reminder System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 42),
                  if (_failed) ...[
                    const Text(
                      'Unable to verify your session. Check your connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _initializeApp,
                      child: const Text('Retry'),
                    ),
                  ] else ...[
                    const AppLoadingIndicator(size: 42),
                    const SizedBox(height: 14),
                    Text(
                      'Preparing your secure session...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
