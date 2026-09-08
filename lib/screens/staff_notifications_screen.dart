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
import '../theme/status_colors.dart';

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
  late Future<int> _unreadCount;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository =
        widget.repository ??
        RepositoryRegistry.instance.staffNotificationRepository;
    _repository.changes.addListener(_readStateChanged);
    _unreadCount = _repository.unreadCount(widget.user.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _reload();
  }

  void _reload() {
    if (mounted) {
      setState(() => _unreadCount = _repository.unreadCount(widget.user.id));
    }
  }

  void _readStateChanged() {
    _reload();
  }

  void _openInbox() {
    if (!mounted) return;
    final route = MaterialPageRoute(
      builder: (_) =>
          StaffNotificationsScreen(user: widget.user, repository: _repository),
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
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _unreadCount,
    builder: (context, snapshot) {
      final count = snapshot.data ?? 0;
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
  static const _pageSize = 20;
  late Future<StaffNotificationPage> _items;
  final List<StaffNotification> _loadedItems = [];
  bool _unreadOnly = false;
  bool _saving = false;
  bool _loadingMore = false;
  int _overallCount = 0;
  int _totalCount = 0;
  int _unreadCount = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  @override
  void initState() {
    super.initState();
    _items = _fetchPage(reset: true);
  }

  Future<StaffNotificationPage> _fetchPage({required bool reset}) async {
    final page = await widget.repository.loadPage(
      userId: widget.user.id,
      unreadOnly: _unreadOnly,
      limit: _pageSize,
      offset: reset ? 0 : _nextOffset,
    );
    if (reset) _loadedItems.clear();
    final knownIds = _loadedItems.map((item) => item.id).toSet();
    _loadedItems.addAll(
      page.items.where((item) => knownIds.add(item.id)),
    );
    _overallCount = page.overallCount;
    _totalCount = page.totalCount;
    _unreadCount = page.unreadCount;
    _nextOffset = page.nextOffset;
    _hasMore = page.hasMore;
    return StaffNotificationPage(
      items: List.unmodifiable(_loadedItems),
      overallCount: _overallCount,
      totalCount: _totalCount,
      unreadCount: _unreadCount,
      hasMore: _hasMore,
      nextOffset: _nextOffset,
    );
  }

  Future<void> _reload() async {
    final next = _fetchPage(reset: true);
    setState(() {
      _items = next;
    });
    try {
      await next;
    } catch (_) {
      /* Render retry state through FutureBuilder. */
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(reset: false);
      if (!mounted) return;
      setState(() => _items = Future.value(page));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more notifications.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<bool> _read(Iterable<String> ids) async {
    setState(() => _saving = true);
    try {
      await widget.repository.markRead(widget.user.id, ids);
      await _reload();
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
      title: const Text(
        'Notifications',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh notifications',
          onPressed: _saving ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: FutureBuilder<StaffNotificationPage>(
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
              final page = snapshot.data;
              final all = [...page?.items ?? <StaffNotification>[]]
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final unread = all
                  .where((n) => !widget.repository.isRead(widget.user.id, n.id))
                  .toList();
              final visible = all;
              return Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                        children: [
                          const _NotificationIntro(),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _NotificationCountCard(
                                  label: 'Total',
                                  count: page?.overallCount ?? 0,
                                  icon: Icons.notifications_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _NotificationCountCard(
                                  label: 'Unread',
                                  count: page?.unreadCount ?? 0,
                                  icon: Icons.mark_email_unread_outlined,
                                  color: StatusColors.information,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              ChoiceChip(
                                avatar: !_unreadOnly
                                    ? const Icon(Icons.check_rounded, size: 17)
                                    : null,
                                label: const Text('All'),
                                selected: !_unreadOnly,
                                onSelected: (_) {
                                  setState(() => _unreadOnly = false);
                                  _reload();
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                avatar: _unreadOnly
                                    ? const Icon(Icons.check_rounded, size: 17)
                                    : null,
                                label: Text(
                                  'Unread (${page?.unreadCount ?? 0})',
                                ),
                                selected: _unreadOnly,
                                onSelected: (_) {
                                  setState(() => _unreadOnly = true);
                                  _reload();
                                },
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _saving || unread.isEmpty
                                    ? null
                                    : () => _read(unread.map((n) => n.id)),
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.done_all_rounded,
                                        size: 19,
                                      ),
                                label: Text(
                                  (page?.hasMore ?? false)
                                      ? 'Read loaded'
                                      : 'Read all',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (visible.isEmpty)
                            _NotificationEmptyState(unreadOnly: _unreadOnly)
                          else
                            for (final item in visible) ...[
                              _StaffNotificationCard(
                                item: item,
                                read: widget.repository.isRead(
                                  widget.user.id,
                                  item.id,
                                ),
                                enabled: !_saving,
                                onTap: () => _open(item),
                              ),
                              const SizedBox(height: 10),
                            ],
                          if (visible.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Showing ${visible.length} of ${page?.totalCount ?? 0}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_loadingMore)
                              const Center(child: CircularProgressIndicator())
                            else if (page?.hasMore ?? false)
                              OutlinedButton.icon(
                                onPressed: _loadMore,
                                icon: const Icon(Icons.expand_more_rounded),
                                label: const Text('Load 20 more'),
                              )
                            else
                              const Center(
                                child: Text('All notifications are loaded.'),
                              ),
                          ],
                        ],
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

class _NotificationIntro extends StatelessWidget {
  const _NotificationIntro();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Center Notifications',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  'Review requests, appointments, stock alerts, and follow-up tasks. Opening an alert does not automatically resolve it.',
                  style: TextStyle(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _NotificationCountCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StaffNotificationCard extends StatelessWidget {
  final StaffNotification item;
  final bool read;
  final bool enabled;
  final VoidCallback onTap;

  const _StaffNotificationCard({
    required this.item,
    required this.read,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _targetColor(item.target);
    return Card(
      margin: EdgeInsets.zero,
      elevation: read ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: read ? colors.outlineVariant : accent.withValues(alpha: 0.42),
          width: read ? 1 : 1.4,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: read ? 0.08 : 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(_targetIcon(item.target), color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: read
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!read) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.body,
                      style: TextStyle(
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _NotificationTag(
                          label: _targetLabel(item.target),
                          color: accent,
                        ),
                        Text(
                          _notificationDate(context, item.createdAt),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTag extends StatelessWidget {
  final String label;
  final Color color;
  const _NotificationTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _NotificationEmptyState extends StatelessWidget {
  final bool unreadOnly;
  const _NotificationEmptyState({required this.unreadOnly});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      child: Column(
        children: [
          Icon(
            unreadOnly
                ? Icons.mark_email_read_outlined
                : Icons.notifications_none_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            unreadOnly ? 'You’re all caught up' : 'No notifications yet',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            unreadOnly
                ? 'There are no unread notifications.'
                : 'New health-center alerts will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

IconData _targetIcon(StaffNotificationTarget target) => switch (target) {
  StaffNotificationTarget.requests => Icons.person_add_alt_1_outlined,
  StaffNotificationTarget.inventory => Icons.inventory_2_outlined,
  StaffNotificationTarget.appointments => Icons.calendar_month_outlined,
  StaffNotificationTarget.offers => Icons.event_available_outlined,
  StaffNotificationTarget.waitlist => Icons.hourglass_top_rounded,
  StaffNotificationTarget.followUps => Icons.notifications_active_outlined,
  StaffNotificationTarget.insights => Icons.auto_awesome_outlined,
  StaffNotificationTarget.passwordResets => Icons.lock_reset_rounded,
};

Color _targetColor(StaffNotificationTarget target) => switch (target) {
  StaffNotificationTarget.inventory => StatusColors.due,
  StaffNotificationTarget.waitlist => StatusColors.pending,
  StaffNotificationTarget.followUps => StatusColors.overdue,
  StaffNotificationTarget.passwordResets => StatusColors.overdue,
  StaffNotificationTarget.appointments => StatusColors.upcoming,
  StaffNotificationTarget.offers => StatusColors.completed,
  StaffNotificationTarget.requests => StatusColors.information,
  StaffNotificationTarget.insights => const Color(0xFF7C4DFF),
};

String _targetLabel(StaffNotificationTarget target) => switch (target) {
  StaffNotificationTarget.requests => 'CHILD REQUEST',
  StaffNotificationTarget.inventory => 'INVENTORY',
  StaffNotificationTarget.appointments => 'APPOINTMENT',
  StaffNotificationTarget.offers => 'SLOT OFFER',
  StaffNotificationTarget.waitlist => 'WAITLIST',
  StaffNotificationTarget.followUps => 'FOLLOW-UP',
  StaffNotificationTarget.insights => 'ADVISORY',
  StaffNotificationTarget.passwordResets => 'PASSWORD RESET',
};

String _notificationDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatShortDate(local);
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date • $time';
}
