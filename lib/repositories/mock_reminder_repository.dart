import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/reminder_follow_up.dart';
import '../models/vaccination_reminder.dart';
import '../services/mock_scenario_clock.dart';
import '../services/mock_identifier_generator.dart';
import 'child_repository.dart';
import 'mock_child_repository.dart';
import 'mock_vaccination_repository.dart';
import 'reminder_repository.dart';
import 'vaccination_repository.dart';

class MockReminderRepository implements ReminderRepository {
  final ChildRepository childRepository;
  final VaccinationRepository vaccinationRepository;

  MockReminderRepository({
    ChildRepository? childRepository,
    VaccinationRepository? vaccinationRepository,
  }) : childRepository = childRepository ?? MockChildRepository(),
       vaccinationRepository =
           vaccinationRepository ?? MockVaccinationRepository();

  static final Map<String, bool> _readState = {};
  static final Set<String> _dismissed = {};
  static final Map<String, ReminderPreference> _preferences = {};
  static final Map<String, VaccinationReminder> _latest = {};
  static final List<ReminderFollowUpRecord> _followUps = [];

  @override
  Future<void> syncGuardianReminders(String guardianId) async {
    final children = await childRepository.getChildrenForGuardian(guardianId);
    final reminders = await _buildForChildren(children, guardianId: guardianId);
    final ids = reminders.map((item) => item.id).toSet();
    for (final reminder in reminders) {
      _latest[reminder.id] = reminder;
    }
    _latest.removeWhere(
      (id, reminder) => reminder.guardianId == guardianId && !ids.contains(id),
    );
  }

  @override
  Future<List<VaccinationReminder>> getGuardianReminders(
    String guardianId,
  ) async {
    await syncGuardianReminders(guardianId);
    final children = await childRepository.getChildrenForGuardian(guardianId);
    final reminders = await _buildForChildren(children, guardianId: guardianId);
    final ids = reminders.map((item) => item.id).toSet();
    _latest.removeWhere(
      (id, reminder) => reminder.guardianId == guardianId && !ids.contains(id),
    );
    for (final reminder in reminders) {
      _latest[reminder.id] = reminder;
    }
    return _sort(reminders);
  }

  @override
  Future<ReminderPage> getGuardianRemindersPage(
    String guardianId, {
    VaccinationReminderStatus? status,
    String? childId,
    int limit = 10,
    int offset = 0,
  }) async {
    final all = (await getGuardianReminders(guardianId))
        .where(
          (reminder) =>
              _isInActionableWindow(reminder) &&
              (status == null || reminder.status == status) &&
              (childId == null || reminder.childId == childId),
        )
        .toList(growable: false);
    final remindersByChild = <String, List<VaccinationReminder>>{};
    for (final reminder in all) {
      remindersByChild.putIfAbsent(reminder.childId, () => []).add(reminder);
    }
    final childIds = remindersByChild.keys.toList(growable: false);
    final start = offset.clamp(0, childIds.length);
    final end = (start + limit.clamp(1, 100)).clamp(0, childIds.length);
    return ReminderPage(
      items: [
        for (final id in childIds.sublist(start, end)) ...remindersByChild[id]!,
      ],
      hasMore: end < childIds.length,
      nextOffset: end,
    );
  }

  @override
  Future<ReminderSummary> getGuardianReminderSummary(
    String guardianId, {
    String? childId,
  }) async => ReminderSummary.fromItems(
    (await getGuardianReminders(guardianId)).where(
      (reminder) =>
          _isInActionableWindow(reminder) &&
          (childId == null || reminder.childId == childId),
    ),
  );

  @override
  Future<List<VaccinationReminder>> getFacilityFollowUps() async {
    final families = await childRepository.getHealthWorkerRegisteredFamilies();
    final reminders = <VaccinationReminder>[];
    for (final family in families) {
      reminders.addAll(
        await _buildForChildren(
          family.children,
          guardianId: family.guardian.id,
          followUpOnly: true,
        ),
      );
    }
    return _sort(reminders);
  }

  @override
  Future<ReminderPage> getFacilityFollowUpsPage({
    VaccinationReminderStatus? status,
    int limit = 10,
    int offset = 0,
  }) async {
    final all = (await getFacilityFollowUps())
        .where(
          (reminder) =>
              _isInActionableWindow(reminder) &&
              (status == null || reminder.status == status),
        )
        .toList(growable: false);
    final remindersByChild = <String, List<VaccinationReminder>>{};
    for (final reminder in all) {
      remindersByChild.putIfAbsent(reminder.childId, () => []).add(reminder);
    }
    final childIds = remindersByChild.keys.toList(growable: false);
    final start = offset < 0
        ? 0
        : offset > childIds.length
        ? childIds.length
        : offset;
    final requestedEnd = start + (limit < 1 ? 1 : limit);
    final end = requestedEnd > childIds.length ? childIds.length : requestedEnd;
    final items = <VaccinationReminder>[
      for (final childId in childIds.sublist(start, end))
        ...remindersByChild[childId]!,
    ];
    return ReminderPage(
      items: items,
      hasMore: end < childIds.length,
      nextOffset: end,
    );
  }

  @override
  Future<ReminderSummary> getFacilityFollowUpSummary() async =>
      ReminderSummary.fromItems(
        (await getFacilityFollowUps()).where(_isInActionableWindow),
      );

  bool _isInActionableWindow(VaccinationReminder reminder) {
    if (reminder.status != VaccinationReminderStatus.overdue &&
        reminder.status != VaccinationReminderStatus.dueToday &&
        reminder.status != VaccinationReminderStatus.upcoming) {
      return false;
    }
    final lastUpcomingDate = MockScenarioClock.today.add(
      const Duration(days: 30),
    );
    return !reminder.dueDate.isAfter(lastUpcomingDate);
  }

  Future<List<VaccinationReminder>> _buildForChildren(
    List<ChildProfile> children, {
    required String guardianId,
    bool followUpOnly = false,
  }) async {
    final reminders = <VaccinationReminder>[];
    for (final child in children) {
      final schedule = await vaccinationRepository.getVaccinationSchedule(
        child,
      );
      final selected = _selectReminderEntries(
        schedule,
        followUpOnly: followUpOnly,
      );
      for (final entry in selected) {
        final reminder = _fromSchedule(guardianId, child, entry);
        _latest[reminder.id] = reminder;
        reminders.add(reminder);
      }
    }
    return _sort(reminders);
  }

  List<PnipScheduleEntry> _selectReminderEntries(
    List<PnipScheduleEntry> schedule, {
    required bool followUpOnly,
  }) {
    if (followUpOnly) {
      return schedule
          .where(
            (entry) =>
                entry.status == PnipDoseStatus.due ||
                entry.status == PnipDoseStatus.overdue,
          )
          .toList(growable: false);
    }
    final active = schedule
        .where(
          (entry) =>
              entry.status == PnipDoseStatus.due ||
              entry.status == PnipDoseStatus.overdue,
        )
        .toList();
    final upcoming =
        schedule
            .where((entry) => entry.status == PnipDoseStatus.upcoming)
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    if (upcoming.isNotEmpty) active.add(upcoming.first);
    final completed =
        schedule
            .where((entry) => entry.status == PnipDoseStatus.completed)
            .toList()
          ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
    if (completed.isNotEmpty) active.add(completed.first);
    return active;
  }

  VaccinationReminder _fromSchedule(
    String guardianId,
    ChildProfile child,
    PnipScheduleEntry entry,
  ) {
    final stableKey =
        '$guardianId-${child.id}-${entry.vaccineId}-${entry.doseNumber}'
            .toUpperCase();
    final id = 'REM-$stableKey';
    final today = MockScenarioClock.today;
    final calculatedStatus = switch (entry.status) {
      PnipDoseStatus.completed => VaccinationReminderStatus.completed,
      PnipDoseStatus.overdue => VaccinationReminderStatus.overdue,
      PnipDoseStatus.due =>
        _dateOnly(entry.scheduledDate) == today
            ? VaccinationReminderStatus.dueToday
            : VaccinationReminderStatus.overdue,
      PnipDoseStatus.upcoming ||
      PnipDoseStatus.notEligible => VaccinationReminderStatus.upcoming,
    };
    final status = _dismissed.contains(id)
        ? VaccinationReminderStatus.dismissed
        : calculatedStatus;
    final createdAt = entry.scheduledDate.subtract(const Duration(days: 7));
    return VaccinationReminder(
      id: id,
      reminderCode: stableKey,
      guardianId: guardianId,
      childId: child.id,
      childName: child.fullName,
      vaccineId: entry.vaccineId,
      vaccineName: entry.vaccineName,
      doseNumber: entry.doseNumber,
      dueDate: entry.scheduledDate,
      status: status,
      channel: VaccinationReminderChannel.inApp,
      isRead: _readState[id] ?? false,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<VaccinationReminder> markAsRead(String reminderId) async {
    _readState[reminderId] = true;
    return _require(
      reminderId,
    ).copyWith(isRead: true, updatedAt: DateTime.now());
  }

  @override
  Future<VaccinationReminder> dismiss(String reminderId) async {
    final current = _require(reminderId);
    if (current.status == VaccinationReminderStatus.overdue ||
        current.status == VaccinationReminderStatus.dueToday) {
      throw StateError('Due and overdue reminders cannot be dismissed.');
    }
    _dismissed.add(reminderId);
    return current.copyWith(
      status: VaccinationReminderStatus.dismissed,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<ReminderPreference> getPreference(String guardianId) async =>
      _preferences.putIfAbsent(
        guardianId,
        () => ReminderPreference(
          guardianId: guardianId,
          inAppEnabled: true,
          smsEnabled: false,
          emailEnabled: false,
          advanceNoticeDays: 7,
          updatedAt: DateTime.now(),
        ),
      );

  @override
  Future<ReminderPreference> savePreference(
    ReminderPreference preference,
  ) async {
    _preferences[preference.guardianId] = preference;
    return preference;
  }

  @override
  Future<List<ReminderFollowUpRecord>> performBatchAction(
    ReminderBatchActionRequest request,
  ) async {
    if (request.reminderIds.isEmpty) {
      throw ArgumentError('Select at least one reminder.');
    }
    final now = DateTime.now();
    final records = <ReminderFollowUpRecord>[];
    for (final reminderId in request.reminderIds.toSet()) {
      final reminder = _require(reminderId);
      final identity = MockIdentifierGenerator.next(prefix: 'FUP');
      final record = ReminderFollowUpRecord(
        id: identity.id,
        followUpCode: identity.code,
        reminderId: reminder.id,
        childId: reminder.childId,
        action: request.action,
        outcome: request.outcome,
        assignedToUserId: request.assignedToUserId,
        notes: request.notes.trim(),
        performedAt: now,
        performedByUserId: request.performedByUserId,
      );
      _followUps.add(record);
      _readState[reminder.id] = true;
      records.add(record);
    }
    return List.unmodifiable(records);
  }

  @override
  Future<List<ReminderFollowUpRecord>> getFollowUpHistory(
    String reminderId,
  ) async {
    final results =
        _followUps
            .where((item) => item.reminderId == reminderId)
            .toList(growable: false)
          ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
    return List.unmodifiable(results);
  }

  VaccinationReminder _require(String id) {
    final reminder = _latest[id];
    if (reminder == null) throw StateError('Reminder record was not found.');
    return reminder;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static List<VaccinationReminder> _sort(List<VaccinationReminder> items) {
    final result = List<VaccinationReminder>.of(items);
    result.sort((a, b) {
      final created = a.createdAt.compareTo(b.createdAt);
      return created != 0 ? created : a.id.compareTo(b.id);
    });
    return List.unmodifiable(result);
  }
}
