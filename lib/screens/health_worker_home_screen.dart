import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

import '../models/app_user.dart';
import '../models/vaccination_reminder.dart';
import '../repositories/auth_repository.dart';
import '../repositories/reminder_repository.dart';
import '../services/session_context.dart';
import '../repositories/repository_registry.dart';
import '../widgets/bugo_brand_title.dart';
import '../widgets/dashboard_appointments.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/dashboard_stat_grid.dart';
import 'external_vaccination_screen.dart';
import 'account_profile_screen.dart';
import 'guardian_patient_registration_screen.dart';
import 'login_screen.dart';
import 'registered_families_screen.dart';
import 'vaccine_inventory_screen.dart';
import 'vaccination_reminders_screen.dart';
import 'vaccination_appointments_screen.dart';
import 'child_link_requests_screen.dart';
import 'advisory_insights_screen.dart';
import 'staff_notifications_screen.dart';
import 'staff_management_screen.dart';
import 'vaccination_records_screen.dart';
import '../widgets/app_loading.dart';
import '../utils/user_facing_error.dart';

class HealthWorkerHomeScreen extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;
  final bool servicesOnly;
  final int revision;
  final ValueChanged<Set<String>?>? onOpenFamilies;

  const HealthWorkerHomeScreen({
    super.key,
    required this.user,
    required this.authRepository,
    this.servicesOnly = false,
    this.revision = 0,
    this.onOpenFamilies,
  });

  @override
  State<HealthWorkerHomeScreen> createState() => _HealthWorkerHomeScreenState();
}

class _HealthWorkerHomeScreenState extends State<HealthWorkerHomeScreen> {
  AppUser get user => widget.user;
  AuthRepository get authRepository => widget.authRepository;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant HealthWorkerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _revision++;
  }

  Future<T?> _open<T>(BuildContext context, Route<T> route) async {
    final result = await Navigator.push(context, route);
    if (mounted) setState(() => _revision++);
    return result;
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
          StaffNotificationBell(
            user: user,
            repository: RepositoryRegistry.instance.staffNotificationRepository,
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.servicesOnly) ...[
                    Text(
                      'Welcome back,',
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
                    const SizedBox(height: 16),
                    const SizedBox(height: 18),
                    const Text(
                      'Vaccination Statistics',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TodayAtGlance(
                      key: ValueKey(_revision),
                      onViewFamilies: (guardianIds) {
                        final openTab = widget.onOpenFamilies;
                        if (openTab != null) {
                          openTab(guardianIds);
                          return;
                        }
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RegisteredFamiliesScreen(
                              healthWorker: user,
                              initialGuardianIds: guardianIds,
                            ),
                          ),
                        );
                      },
                      primary: primary,
                      green: green,
                      onViewStatus: (status) => _open(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VaccinationRemindersScreen.healthWorker(
                                initialFilter: status,
                              ),
                        ),
                      ),
                      onViewAll: () => _open(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const VaccinationRemindersScreen.healthWorker(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Appointments & quick actions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DashboardAppointments(
                      revision: _revision,
                      onChanged: () => setState(() => _revision++),
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (widget.servicesOnly) ...[
                    const Text(
                      'All services',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (user.isAdministrator) ...[
                      _WorkerCard(
                        icon: Icons.admin_panel_settings_outlined,
                        color: Colors.deepPurple,
                        title: 'Staff Management',
                        subtitle:
                            'Add nurses and health workers with an auditable activation invitation.',
                        onTap: () {
                          _open(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StaffManagementScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    _WorkerCard(
                      icon: Icons.person_add_alt_1_rounded,
                      color: green,
                      title: 'Register Guardian & Child',
                      subtitle:
                          'Create records for families with or without phone access.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GuardianPatientRegistrationScreen(
                              healthWorker: user,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.family_restroom_rounded,
                      color: primary,
                      title: 'Registered Families',
                      subtitle:
                          'View guardians and children registered by health workers.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RegisteredFamiliesScreen(healthWorker: user),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.how_to_reg_outlined,
                      color: Colors.orange,
                      title: 'Child Link Requests',
                      subtitle:
                          'Approve or reject children submitted by guardian accounts.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChildLinkRequestsScreen(healthWorker: user),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.insights_rounded,
                      color: Colors.deepPurple,
                      title: 'Advisory Insights',
                      subtitle:
                          'Review evidence-based follow-up, stock, and waitlist insights.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AdvisoryInsightsScreen(healthWorker: user),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.assignment_rounded,
                      color: primary,
                      title: 'Vaccination Records',
                      subtitle: 'Review vaccination history and schedules.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                VaccinationRecordsScreen(healthWorker: user),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.notification_important_outlined,
                      color: Colors.orange,
                      title: 'Follow-up Reminders',
                      subtitle:
                          'Review children with due or overdue vaccinations.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const VaccinationRemindersScreen.healthWorker(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.event_note_outlined,
                      color: primary,
                      title: 'Vaccination Appointments',
                      subtitle:
                          'Review scheduled, waitlisted, and rescheduled visits.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const VaccinationAppointmentsScreen.healthWorker(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.inventory_2_outlined,
                      color: green,
                      title: 'Vaccine Inventory',
                      subtitle: 'Monitor vaccine availability and stock.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VaccineInventoryScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _WorkerCard(
                      icon: Icons.qr_code_2_rounded,
                      color: primary,
                      title: 'QR Referrals',
                      subtitle: 'Verify and record external vaccinations.',
                      onTap: () {
                        _open(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExternalVaccinationScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    _InfoBox(
                      text:
                          'QR Referrals is available for verifying signed referrals and recording vaccinations received at external facilities.',
                      color: primary,
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

class _TodayAtGlance extends StatefulWidget {
  final Color primary;
  final Color green;
  final VoidCallback onViewAll;
  final ValueChanged<Set<String>> onViewFamilies;
  final ValueChanged<VaccinationReminderStatus> onViewStatus;

  const _TodayAtGlance({
    super.key,
    required this.primary,
    required this.green,
    required this.onViewAll,
    required this.onViewFamilies,
    required this.onViewStatus,
  });

  @override
  State<_TodayAtGlance> createState() => _TodayAtGlanceState();
}

class _TodayAtGlanceData {
  final ReminderSummary summary;
  final List<VaccinationReminder> preview;

  const _TodayAtGlanceData({required this.summary, required this.preview});
}

class _TodayAtGlanceState extends State<_TodayAtGlance> {
  late Future<_TodayAtGlanceData> _followUps;

  void _refresh() => setState(() {
    _followUps = _load();
  });

  Future<_TodayAtGlanceData> _load() async {
    final repository = RepositoryRegistry.instance.reminderRepository;
    final results = await Future.wait<Object>([
      repository.getFacilityFollowUpSummary(),
      repository.getFacilityFollowUpsPage(limit: 3),
    ]);
    return _TodayAtGlanceData(
      summary: results[0] as ReminderSummary,
      preview: (results[1] as ReminderPage).items,
    );
  }

  @override
  void initState() {
    super.initState();
    _followUps = _load();
  }

  String _doseLabel(VaccinationReminder item) =>
      '${item.vaccineName} Dose ${item.doseNumber}';

  @override
  Widget build(BuildContext context) => FutureBuilder<_TodayAtGlanceData>(
    future: _followUps,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 138,
          child: AppLoadingView(
            title: 'Loading follow-up summary',
            message: 'Counting children and vaccinations needing attention.',
            padding: EdgeInsets.all(12),
          ),
        );
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            const Text('The follow-up summary could not be loaded.'),
            TextButton(onPressed: _refresh, child: const Text('Try again')),
          ],
        );
      }
      final data = snapshot.data!;
      final followUps = data.preview
          .where(
            (item) =>
                item.status == VaccinationReminderStatus.dueToday ||
                item.status == VaccinationReminderStatus.overdue,
          )
          .toList();
      final guardianIds = data.summary.guardianIds.toSet();
      final preview = followUps.take(3).toList(growable: false);
      return Column(
        children: [
          DashboardStatGrid(
            stats: [
              DashboardStat(
                'Families due',
                guardianIds.length,
                Icons.groups_rounded,
                widget.primary,
                actionLabel: 'View families',
                onTap: () => widget.onViewFamilies(guardianIds),
              ),
              DashboardStat(
                'Vaccines due',
                data.summary.dueToday + data.summary.overdue,
                Icons.vaccines_outlined,
                widget.green,
                actionLabel: 'View reminders',
                onTap: widget.onViewAll,
              ),
              DashboardStat(
                'Due today',
                data.summary.dueToday,
                Icons.today_outlined,
                const Color(0xFF946000),
                actionLabel: 'View due today',
                onTap: () =>
                    widget.onViewStatus(VaccinationReminderStatus.dueToday),
              ),
              DashboardStat(
                'Overdue',
                data.summary.overdue,
                Icons.notification_important_outlined,
                const Color(0xFFB42335),
                actionLabel: 'View overdue',
                onTap: () =>
                    widget.onViewStatus(VaccinationReminderStatus.overdue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FollowUpVaccineChart(summary: data.summary.vaccineCounts),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Children needing follow-up',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onViewAll,
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  if (preview.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No due or overdue vaccines today.'),
                    )
                  else
                    for (final item in preview)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor:
                              (item.status == VaccinationReminderStatus.overdue
                                      ? Colors.red
                                      : widget.primary)
                                  .withValues(alpha: .1),
                          child: Icon(
                            Icons.child_care_rounded,
                            color:
                                item.status == VaccinationReminderStatus.overdue
                                ? Colors.red
                                : widget.primary,
                          ),
                        ),
                        title: Text(
                          item.childName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(_doseLabel(item)),
                        trailing: Text(
                          item.status == VaccinationReminderStatus.overdue
                              ? 'Overdue'
                              : 'Due',
                          style: TextStyle(
                            color:
                                item.status == VaccinationReminderStatus.overdue
                                ? Colors.red
                                : widget.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VaccinationRemindersScreen.healthWorker(
                                    childId: item.childId,
                                  ),
                            ),
                          );
                          if (mounted) _refresh();
                        },
                      ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _WorkerCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _WorkerCard({
    required this.icon,
    required this.color,
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
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color),
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
              if (onTap != null)
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
