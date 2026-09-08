import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/repository_registry.dart';
import '../models/vaccination_reminder.dart';
import '../services/session_context.dart';
import '../widgets/bugo_brand_title.dart';
import '../widgets/guardian_dashboard_children.dart';
import '../widgets/dashboard_appointments.dart';
import '../widgets/app_loading.dart';
import '../utils/user_facing_error.dart';
import 'guardian_children_screen.dart';
import 'account_profile_screen.dart';
import 'login_screen.dart';
import 'vaccination_reminders_screen.dart';
import 'vaccination_appointments_screen.dart';

class GuardianHomeScreen extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;
  final bool servicesOnly;
  final int revision;
  final ReminderRepository? reminderRepository;

  const GuardianHomeScreen({
    super.key,
    required this.user,
    required this.authRepository,
    this.servicesOnly = false,
    this.revision = 0,
    this.reminderRepository,
  });

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen>
    with WidgetsBindingObserver {
  AppUser get user => widget.user;
  AuthRepository get authRepository => widget.authRepository;
  late ReminderRepository _reminders;
  late Future<List<VaccinationReminder>> _reminderRows;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders =
        widget.reminderRepository ??
        RepositoryRegistry.instance.reminderRepository;
    _reminderRows = Future.value(const <VaccinationReminder>[]);
    _reloadReminders();
  }

  void _reloadReminders() {
    _revision++;
    _reminderRows = () async {
      try {
        await _reminders.syncGuardianReminders(user.id);
        return _reminders.getGuardianReminders(user.id);
      } catch (error) {
        return Future<List<VaccinationReminder>>.error(error);
      }
    }();
  }

  @override
  void didUpdateWidget(covariant GuardianHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _reloadReminders();
    if (oldWidget.user.id != user.id ||
        oldWidget.reminderRepository != widget.reminderRepository) {
      _reminders =
          widget.reminderRepository ??
          RepositoryRegistry.instance.reminderRepository;
      _reloadReminders();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_reloadReminders);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openReminders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaccinationRemindersScreen.guardian(
          guardianId: user.id,
          repository: _reminders,
        ),
      ),
    );
    if (mounted) setState(_reloadReminders);
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await runWithAppLoading(
        context,
        title: 'Signing you out',
        message: 'Closing your secure session safely.',
        operation: authRepository.logout,
      );
    } catch (error) {
      if (!context.mounted) return;
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
    if (!context.mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authRepository: authRepository),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final green = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const BugoBrandTitle(),
        actions: [
          const ThemeModeButton(),
          FutureBuilder<List<VaccinationReminder>>(
            key: ValueKey(user.id),
            future: _reminderRows,
            builder: (context, snapshot) {
              final ready =
                  snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError;
              final unread = (snapshot.data ?? <VaccinationReminder>[])
                  .where((r) => r.hasUnreadNotification)
                  .length;
              return IconButton(
                tooltip: snapshot.hasError
                    ? 'Reminders unavailable — tap to retry'
                    : !ready
                    ? 'Loading vaccination reminders'
                    : 'Vaccination reminders ($unread unread)',
                onPressed: _openReminders,
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
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountProfileScreen(
                      user: user,
                      authRepository: authRepository,
                    ),
                  ),
                );
              }
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.servicesOnly) ...[
                Text(
                  'Good day,',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.fullName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Vaccination Statistics',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                GuardianDashboardChildren(
                  key: ValueKey('children-${user.id}'),
                  revision: _revision,
                  guardianId: user.id,
                  reminders: _reminders,
                  onChanged: () => setState(_reloadReminders),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Next steps',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<VaccinationReminder>>(
                  future: _reminderRows,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Text('Loading reminders…');
                    }
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () => setState(_reloadReminders),
                        child: const Text('Retry reminder summary'),
                      );
                    }
                    final rows = snapshot.data ?? [];
                    final due = rows
                        .where(
                          (r) => r.status == VaccinationReminderStatus.dueToday,
                        )
                        .length;
                    final overdue = rows
                        .where(
                          (r) => r.status == VaccinationReminderStatus.overdue,
                        )
                        .length;
                    return _FeatureCard(
                      icon: Icons.notifications_active_outlined,
                      iconColor: overdue > 0 ? Colors.red.shade700 : primary,
                      title: '$due due today · $overdue overdue',
                      subtitle:
                          'Review vaccination reminders for your children.',
                      onTap: _openReminders,
                    );
                  },
                ),
                const SizedBox(height: 12),
                DashboardAppointments(
                  key: ValueKey('appointments-${user.id}'),
                  revision: _revision,
                  guardianId: user.id,
                  onChanged: () => setState(_reloadReminders),
                ),
                const SizedBox(height: 22),
              ],
              if (widget.servicesOnly) ...[
                const Text(
                  'All services',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _FeatureCard(
                  icon: Icons.child_friendly_rounded,
                  iconColor: primary,
                  title: 'Manage Children',
                  subtitle: 'View your children and vaccination records.',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GuardianChildrenScreen(
                          user: user,
                          authRepository: authRepository,
                        ),
                      ),
                    );
                    if (mounted) setState(_reloadReminders);
                  },
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.notifications_active_outlined,
                  iconColor: green,
                  title: 'Vaccination Reminders',
                  subtitle: 'Check upcoming, due, and overdue vaccinations.',
                  onTap: _openReminders,
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.event_note_outlined,
                  iconColor: primary,
                  title: 'Vaccination Appointments',
                  subtitle:
                      'View scheduled visits and priority waitlist entries.',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VaccinationAppointmentsScreen.guardian(
                          guardianId: user.id,
                        ),
                      ),
                    );
                    if (mounted) setState(_reloadReminders);
                  },
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.qr_code_2_rounded,
                  iconColor: primary,
                  title: 'Child QR',
                  subtitle: 'Access the QR identifier for your child.',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GuardianChildrenScreen(
                          user: user,
                          authRepository: authRepository,
                        ),
                      ),
                    );
                    if (mounted) setState(_reloadReminders);
                  },
                ),
                const SizedBox(height: 22),
                _InfoBox(
                  text:
                      'Select a child to view their current schedule, vaccination history, and identification details.',
                  color: primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  final Color color;

  const _InfoBox({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
