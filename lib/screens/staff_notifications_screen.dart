import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/staff_notification.dart';
import '../repositories/staff_notification_repository.dart';
import '../repositories/repository_registry.dart';
import 'child_link_requests_screen.dart';
import 'vaccine_inventory_details_screen.dart';
import 'vaccination_appointments_screen.dart';
import 'vaccination_reminders_screen.dart';
import 'advisory_insights_screen.dart';
import 'earlier_appointment_offers_screen.dart';
import '../widgets/app_loading.dart';
import 'guardian_password_reset_screen.dart';

class StaffNotificationBell extends StatefulWidget {
  final AppUser user;
  final StaffNotificationRepository? repository;
  const StaffNotificationBell({super.key, required this.user, this.repository});
  @override
  State<StaffNotificationBell> createState() => _StaffNotificationBellState();
}

class _StaffNotificationBellState extends State<StaffNotificationBell>
    with WidgetsBindingObserver {
  late final StaffNotificationRepository _repository;
  late Future<List<StaffNotification>> _items;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository =
        widget.repository ??
        RepositoryRegistry.instance.staffNotificationRepository;
    _repository.changes.addListener(_readStateChanged);
    _items = _repository.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _reload();
  }

  void _reload() {
    if (mounted) setState(() => _items = _repository.load());
  }

  void _readStateChanged() {
    if (mounted) setState(() {});
  }

  void _openInbox() {
    if (!mounted) return;
    final route = MaterialPageRoute(
      builder: (_) => StaffNotificationsScreen(
        user: widget.user,
        repository: _repository,
      ),
    );
    Navigator.of(context, rootNavigator: true).push(route).then((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.changes.removeListener(_readStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StaffNotification>>(
    future: _items,
    builder: (context, snapshot) {
      final count = (snapshot.data ?? [])
          .where((n) => !_repository.isRead(widget.user.id, n.id))
          .length;
      return IconButton(
        tooltip: snapshot.hasError
            ? 'Notifications — tap to retry'
            : 'Notifications ($count unread)',
        icon: Badge(
          label: Text(count > 99 ? '99+' : '$count'),
          isLabelVisible: count > 0,
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: _openInbox,
      );
    },
  );
}

class StaffNotificationsScreen extends StatefulWidget {
  final AppUser user;
  final StaffNotificationRepository repository;
  const StaffNotificationsScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  late Future<List<StaffNotification>> _items;
  bool _unreadOnly = false;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _items = widget.repository.load();
  }

  Future<void> _reload() async {
    final next = widget.repository.load();
    setState(() {
      _items = next;
    });
    try {
      await next;
    } catch (_) {
      /* Render retry state through FutureBuilder. */
    }
  }

  Future<bool> _read(Iterable<String> ids) async {
    setState(() => _saving = true);
    try {
      await widget.repository.markRead(widget.user.id, ids);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not mark notifications as read. Please try again.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(StaffNotification item) async {
    if (item.target != StaffNotificationTarget.followUps &&
        (item.entityId == null || item.entityId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This notification has no linked record. Please refresh notifications.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    await _read([item.id]);

    if (!mounted) return;
    final Widget destination = switch (item.target) {
      StaffNotificationTarget.requests => ChildLinkRequestsScreen(
        healthWorker: widget.user,
        initialRequestId: item.entityId,
      ),
      StaffNotificationTarget.inventory => VaccineInventoryDetailsScreen(
        vaccineId: item.entityId!,
        repository: RepositoryRegistry.instance.inventoryRepository,
      ),
      StaffNotificationTarget.appointments =>
        VaccinationAppointmentsScreen.healthWorker(
          initialAppointmentId: item.entityId,
        ),
      StaffNotificationTarget.offers => EarlierAppointmentOffersScreen(
        healthWorkerMode: true,
        initialOfferId: item.entityId,
      ),
      StaffNotificationTarget.waitlist =>
        VaccinationAppointmentsScreen.healthWorker(
          waitlistVaccineId: item.entityId,
        ),
      StaffNotificationTarget.followUps =>
        const VaccinationRemindersScreen.healthWorker(),
      StaffNotificationTarget.insights => AdvisoryInsightsScreen(
        healthWorker: widget.user,
        initialInsightId: item.entityId,
      ),
      StaffNotificationTarget.passwordResets => GuardianPasswordResetScreen(
        notification: item,
        repository: widget.repository,
      ),
    };
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Refresh notifications',
          onPressed: _saving ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: FutureBuilder<List<StaffNotification>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingView(
                  title: 'Loading notifications',
                  message: 'Checking requests, stock alerts, and follow-ups.',
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Notifications could not be loaded.'),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                );
              }
              final all = snapshot.data ?? [];
              final unread = all
                  .where((n) => !widget.repository.isRead(widget.user.id, n.id))
                  .toList();
              final visible = _unreadOnly ? unread : all;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reading an alert does not resolve its underlying task.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: !_unreadOnly,
                              onSelected: (_) =>
                                  setState(() => _unreadOnly = false),
                            ),
                            ChoiceChip(
                              label: Text('Unread (${unread.length})'),
                              selected: _unreadOnly,
                              onSelected: (_) =>
                                  setState(() => _unreadOnly = true),
                            ),
                            TextButton(
                              onPressed: _saving || unread.isEmpty
                                  ? null
                                  : () => _read(unread.map((n) => n.id)),
                              child: Text(
                                _saving ? 'Saving…' : 'Mark all as read',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: visible.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    _unreadOnly
                                        ? 'You’re all caught up. No unread notifications.'
                                        : 'No current notifications.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ]
                            : visible.map((item) {
                                final read = widget.repository.isRead(
                                  widget.user.id,
                                  item.id,
                                );
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    onTap: _saving ? null : () => _open(item),
                                    title: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: read
                                            ? FontWeight.w500
                                            : FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 6),
                                        Text(item.body),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${read ? "Read" : "Unread"} • ${MaterialLocalizations.of(context).formatShortDate(item.createdAt)}',
                                          style: TextStyle(
                                            color: read
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onSurfaceVariant
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                  ),
                                );
                              }).toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
