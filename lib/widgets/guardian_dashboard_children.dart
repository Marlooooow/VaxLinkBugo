import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';
import '../models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../repositories/child_repository.dart';
import '../repositories/vaccination_repository.dart';
import '../screens/child_profile_screen.dart';
import '../models/vaccination_progress.dart';
import '../models/vaccination_reminder.dart';
import '../repositories/reminder_repository.dart';
import '../screens/vaccination_reminders_screen.dart';
import 'dashboard_stat_grid.dart';
import 'dashboard_charts.dart';

/// Loads from the same repositories as My Children and Child Profile.
class GuardianDashboardChildren extends StatefulWidget {
  final String guardianId;
  final ChildRepository? children;
  final VaccinationRepository? vaccinations;
  final ReminderRepository? reminders;
  final VoidCallback onChanged;
  final int revision;
  const GuardianDashboardChildren({
    super.key,
    required this.guardianId,
    required this.onChanged,
    this.children,
    this.vaccinations,
    this.reminders,
    this.revision = 0,
  });

  @override
  State<GuardianDashboardChildren> createState() =>
      _GuardianDashboardChildrenState();
}

class _GuardianDashboardChildrenState extends State<GuardianDashboardChildren> {
  String? _selectedChildId;
  late Future<List<(ChildProfile, List<PnipScheduleEntry>, List<VaccinationReminder>)>> _rows;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant GuardianDashboardChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guardianId != widget.guardianId ||
        oldWidget.children != widget.children ||
        oldWidget.vaccinations != widget.vaccinations ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    _rows = _load();
  }

  Future<void> _openChild(
    ChildProfile child, {
    ChildProfileSection? section,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(
          child: child,
          initialSection: section,
          repository: widget.vaccinations,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
    widget.onChanged();
  }

  Future<void> _openReminders(
    String childId,
    VaccinationReminderStatus status,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaccinationRemindersScreen.guardian(
          guardianId: widget.guardianId,
          childId: childId,
          initialFilter: status,
          repository: widget.reminders,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
    widget.onChanged();
  }

  Future<List<(ChildProfile, List<PnipScheduleEntry>, List<VaccinationReminder>)>> _load() async {
    final children = await (widget.children ?? RepositoryRegistry.instance.childRepository)
        .getChildrenForGuardian(widget.guardianId);
    final vaccinations = widget.vaccinations ?? RepositoryRegistry.instance.vaccinationRepository;
    final reminders = widget.reminders ?? RepositoryRegistry.instance.reminderRepository;
    final reminderRows = await reminders.getGuardianReminders(widget.guardianId);
    final scheduleByChild = <String, List<PnipScheduleEntry>>{};
    for (final child in children) {
      scheduleByChild[child.id] = await vaccinations.getVaccinationSchedule(child);
    }
    return Future.wait(
      children.map((child) async {
        final schedule = scheduleByChild[child.id] ?? const <PnipScheduleEntry>[];
        final childReminders = reminderRows.where((item) => item.childId == child.id).toList();
        final mappedSchedule = schedule.map((entry) {
            final matchingReminder = childReminders.firstWhere(
              (reminder) => reminder.vaccineId == entry.vaccineId && reminder.doseNumber == entry.doseNumber,
              orElse: () => VaccinationReminder(
                id: '',
                reminderCode: '',
                guardianId: '',
                childId: '',
                childName: '',
                vaccineId: '',
                vaccineName: '',
                doseNumber: 0,
                dueDate: DateTime(1970),
                status: VaccinationReminderStatus.upcoming,
                channel: VaccinationReminderChannel.inApp,
                isRead: false,
                createdAt: DateTime(1970),
                updatedAt: DateTime(1970),
              ),
            );
            if (matchingReminder.id.isEmpty) return entry;
            return PnipScheduleEntry(
              vaccineId: entry.vaccineId,
              vaccineName: entry.vaccineName,
              doseNumber: entry.doseNumber,
              scheduledDate: entry.scheduledDate,
              status: switch (matchingReminder.status) {
                VaccinationReminderStatus.completed => PnipDoseStatus.completed,
                VaccinationReminderStatus.overdue => PnipDoseStatus.overdue,
                VaccinationReminderStatus.dueToday => PnipDoseStatus.due,
                VaccinationReminderStatus.upcoming => PnipDoseStatus.upcoming,
                VaccinationReminderStatus.dismissed => PnipDoseStatus.completed,
              },
            );
          }).toList();
        return (child, mappedSchedule, childReminders);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _rows,
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Loading your children’s progress…'),
        );
      }
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry child overview'),
        );
      }
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No linked children yet. Use Manage Children to submit a request.',
            ),
          ),
        );
      }
      final selected = rows.firstWhere(
        (row) => row.$1.id == _selectedChildId,
        orElse: () => rows.first,
      );
      final progress = VaccinationProgress.fromSchedule(selected.$2);
      final databaseReminders = selected.$3;
      final dueToday = databaseReminders
          .where((item) => item.status == VaccinationReminderStatus.dueToday)
          .length;
      final overdue = databaseReminders
          .where((item) => item.status == VaccinationReminderStatus.overdue)
          .length;
      final upcoming = databaseReminders
          .where((item) => item.status == VaccinationReminderStatus.upcoming)
          .length;
      return Column(
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Child summary',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _ChildRelationshipBadge(child: selected.$1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Select child',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selected.$1.id,
                        isExpanded: true,
                        items: [
                          for (final row in rows)
                            DropdownMenuItem(
                              value: row.$1.id,
                              child: Text(
                                row.$1.fullName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) =>
                            setState(() => _selectedChildId = id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${rows.length} linked children · Overview for the selected child',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  DashboardStatGrid(
                    stats: [
                      DashboardStat(
                        'Recorded doses',
                        progress.completed,
                        Icons.verified_outlined,
                        const Color(0xFF087F83),
                        actionLabel: 'View history',
                        onTap: () => _openChild(
                          selected.$1,
                          section: ChildProfileSection.history,
                        ),
                      ),
                      DashboardStat(
                        'Due today',
                        dueToday,
                        Icons.today_outlined,
                        const Color(0xFF946000),
                        actionLabel: 'View due today',
                        onTap: () => _openReminders(
                          selected.$1.id,
                          VaccinationReminderStatus.dueToday,
                        ),
                      ),
                      DashboardStat(
                        'Overdue',
                        overdue,
                        Icons.notification_important_outlined,
                        const Color(0xFFB42335),
                        actionLabel: 'View overdue',
                        onTap: () => _openReminders(
                          selected.$1.id,
                          VaccinationReminderStatus.overdue,
                        ),
                      ),
                      DashboardStat(
                        'Upcoming',
                        upcoming,
                        Icons.event_outlined,
                        const Color(0xFF5065A1),
                        actionLabel: 'View upcoming',
                        onTap: () => _openReminders(
                          selected.$1.id,
                          VaccinationReminderStatus.upcoming,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ChildCompletionChart(schedule: selected.$2),
                ],
              ),
            ),
          ),
          for (final row in [selected])
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: const Icon(Icons.child_care_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.$1.fullName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                row.$1.isParentRelationship
                                    ? 'My child'
                                    : 'Under my care',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _openChild(row.$1),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          'View ${row.$1.fullName.split(' ').first}’s record',
                        ),
                      ),
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

class _ChildRelationshipBadge extends StatelessWidget {
  final ChildProfile child;
  const _ChildRelationshipBadge({required this.child});

  String get _label {
    // Invert the stored guardian role for a child-facing display label only.
    final labels = switch (child.relationship.trim().toLowerCase()) {
      'mother' || 'father' => ('Son', 'Daughter', 'My child'),
      'aunt' || 'uncle' => ('Nephew', 'Niece', 'Under your care'),
      'grandmother' ||
      'grandfather' => ('Grandson', 'Granddaughter', 'Grandchild'),
      'brother' || 'sister' => ('Brother', 'Sister', 'Sibling'),
      _ => ('Under your care', 'Under your care', 'Under your care'),
    };
    return switch (child.sex.trim().toLowerCase()) {
      'male' => labels.$1,
      'female' => labels.$2,
      _ => labels.$3,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message:
          'Your relationship to ${child.fullName}: ${child.relationship.trim().isEmpty ? 'Guardian' : child.relationship}',
      child: Container(
        key: const ValueKey('selected-child-relationship'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.onPrimaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
