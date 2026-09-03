import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/staff_notifications_screen.dart';
import '../services/session_context.dart';
import '../theme/theme_controller.dart';
import 'app_loading.dart';
import '../repositories/repository_registry.dart';

/// Shared actions for every health-worker feature header.
class WorkerAppBarActions extends StatelessWidget {
  const WorkerAppBarActions({super.key});

  Future<void> _logout(BuildContext context) async {
    final user = SessionContext.user;
    if (user == null) return;
    await runWithAppLoading(
      context,
      title: 'Signing you out',
      message: 'Closing your secure session safely.',
      operation: RepositoryRegistry.instance.authRepository.logout,
    );
    SessionContext.clear();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authRepository: RepositoryRegistry.instance.authRepository,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionContext.user;
    if (user == null) return const SizedBox.shrink();
    final repository = RepositoryRegistry.instance.staffNotificationRepository;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ThemeModeButton(),
        StaffNotificationBell(user: user, repository: repository),
        IconButton(
          tooltip: 'Logout',
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout_rounded),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
