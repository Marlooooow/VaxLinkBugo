import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/account_profile_screen.dart';
import '../screens/staff_notifications_screen.dart';
import '../services/session_context.dart';
import '../theme/theme_controller.dart';
import 'app_loading.dart';
import '../repositories/repository_registry.dart';

/// Shared actions for every health-worker feature header.
class WorkerAppBarActions extends StatelessWidget {
  final bool showNotifications;

  const WorkerAppBarActions({super.key, this.showNotifications = true});

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

  Future<void> _openProfile(BuildContext context) async {
    final user = SessionContext.user;
    if (user == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountProfileScreen(
          user: user,
          authRepository: RepositoryRegistry.instance.authRepository,
        ),
      ),
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
        if (showNotifications)
          StaffNotificationBell(user: user, repository: repository),
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu_rounded),
          onSelected: (value) {
            if (value == 'profile') _openProfile(context);
            if (value == 'logout') _logout(context);
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded),
                  SizedBox(width: 12),
                  Text('My Profile'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout_rounded),
                  SizedBox(width: 12),
                  Text('Log out'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
