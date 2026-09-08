import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/vaccination_reminder.dart';
import '../repositories/auth_repository.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/repository_registry.dart';
import '../screens/login_screen.dart';
import '../screens/account_profile_screen.dart';
import '../screens/vaccination_reminders_screen.dart';
import '../services/session_context.dart';
import '../theme/theme_controller.dart';
import 'app_loading.dart';
import '../utils/user_facing_error.dart';

/// Shared header actions for every guardian bottom-navigation feature.
class GuardianAppBarActions extends StatefulWidget {
  final AppUser? user;
  final AuthRepository? authRepository;
  final ReminderRepository? reminderRepository;

  const GuardianAppBarActions({
    super.key,
    this.user,
    this.authRepository,
    this.reminderRepository,
  });

  @override
  State<GuardianAppBarActions> createState() => _GuardianAppBarActionsState();
}

class _GuardianAppBarActionsState extends State<GuardianAppBarActions> {
  late ReminderRepository _reminders;
  late Future<List<VaccinationReminder>> _reminderRows;

  AppUser? get _user => widget.user ?? SessionContext.user;

  @override
  void initState() {
    super.initState();
    _reminders =
        widget.reminderRepository ??
        RepositoryRegistry.instance.reminderRepository;
    _reminderRows = _loadReminders();
  }

  Future<List<VaccinationReminder>> _loadReminders() async {
    final user = _user;
    if (user == null) return const <VaccinationReminder>[];
    await _reminders.syncGuardianReminders(user.id);
    return _reminders.getGuardianReminders(user.id);
  }

  void _reload() {
    setState(() => _reminderRows = _loadReminders());
  }

  Future<void> _openReminders() async {
    final user = _user;
    if (user == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaccinationRemindersScreen.guardian(
          guardianId: user.id,
          repository: _reminders,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _logout() async {
    final auth =
        widget.authRepository ?? RepositoryRegistry.instance.authRepository;
    try {
      await runWithAppLoading(
        context,
        title: 'Signing you out',
        message: 'Closing your secure session safely.',
        operation: auth.logout,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'Sign-out could not be completed. Please try again.',
            ),
          ),
        ),
      );
      return;
    }
    SessionContext.clear();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(authRepository: auth)),
      (route) => false,
    );
  }

  Future<void> _openProfile() async {
    final user = _user;
    if (user == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountProfileScreen(
          user: user,
          authRepository:
              widget.authRepository ??
              RepositoryRegistry.instance.authRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ThemeModeButton(),
        FutureBuilder<List<VaccinationReminder>>(
          future: _reminderRows,
          builder: (context, snapshot) {
            final ready =
                snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError;
            final unread = (snapshot.data ?? const <VaccinationReminder>[])
                .where((reminder) => reminder.hasUnreadNotification)
                .length;
            return IconButton(
              tooltip: snapshot.hasError
                  ? 'Reminders unavailable — tap to retry'
                  : !ready
                  ? 'Loading vaccination reminders'
                  : 'Vaccination reminders ($unread unread)',
              onPressed: snapshot.hasError ? _reload : _openReminders,
              icon: Badge(
                isLabelVisible: ready && unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                child: const Icon(Icons.notifications_outlined),
              ),
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu_rounded),
          onSelected: (value) {
            if (value == 'profile') _openProfile();
            if (value == 'logout') _logout();
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
