import '../models/vaccination_reminder.dart';
import '../models/reminder_follow_up.dart';

class ReminderSummary {
  final int dueToday;
  final int overdue;
  final int upcoming;
  final int unread;
  final List<String> guardianIds;
  final List<ReminderVaccineCount> vaccineCounts;

  const ReminderSummary({
    required this.dueToday,
    required this.overdue,
    required this.upcoming,
    this.unread = 0,
    this.guardianIds = const [],
    this.vaccineCounts = const [],
  });

  factory ReminderSummary.fromItems(Iterable<VaccinationReminder> items) {
    final rows = items.toList(growable: false);
    final grouped = <String, ReminderVaccineCount>{};
    for (final item in rows.where(
      (item) =>
          item.status == VaccinationReminderStatus.dueToday ||
          item.status == VaccinationReminderStatus.overdue,
    )) {
      final current = grouped[item.vaccineId];
      grouped[item.vaccineId] = ReminderVaccineCount(
        vaccineId: item.vaccineId,
        vaccineName: item.vaccineName,
        dueToday:
            (current?.dueToday ?? 0) +
            (item.status == VaccinationReminderStatus.dueToday ? 1 : 0),
        overdue:
            (current?.overdue ?? 0) +
            (item.status == VaccinationReminderStatus.overdue ? 1 : 0),
      );
    }
    return ReminderSummary(
      dueToday: rows
          .where((item) => item.status == VaccinationReminderStatus.dueToday)
          .length,
      overdue: rows
          .where((item) => item.status == VaccinationReminderStatus.overdue)
          .length,
      upcoming: rows
          .where((item) => item.status == VaccinationReminderStatus.upcoming)
          .length,
      unread: rows.where((item) => item.hasUnreadNotification).length,
      guardianIds: rows
          .where(
            (item) =>
                item.status == VaccinationReminderStatus.dueToday ||
                item.status == VaccinationReminderStatus.overdue,
          )
          .map((item) => item.guardianId)
          .toSet()
          .toList(growable: false),
      vaccineCounts: grouped.values.toList(growable: false),
    );
  }
}

class ReminderPage {
  final List<VaccinationReminder> items;
  final bool hasMore;
  final int nextOffset;

  const ReminderPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });
}

abstract class ReminderRepository {
  Future<void> syncGuardianReminders(String guardianId);

  Future<List<VaccinationReminder>> getGuardianReminders(String guardianId);

  Future<ReminderPage> getGuardianRemindersPage(
    String guardianId, {
    VaccinationReminderStatus? status,
    String? childId,
    int limit = 10,
    int offset = 0,
  });

  Future<ReminderSummary> getGuardianReminderSummary(
    String guardianId, {
    String? childId,
  });

  Future<List<VaccinationReminder>> getFacilityFollowUps();

  Future<ReminderPage> getFacilityFollowUpsPage({
    VaccinationReminderStatus? status,
    int limit = 10,
    int offset = 0,
  });

  Future<ReminderSummary> getFacilityFollowUpSummary();

  Future<VaccinationReminder> markAsRead(String reminderId);

  Future<VaccinationReminder> dismiss(String reminderId);

  Future<ReminderPreference> getPreference(String guardianId);

  Future<ReminderPreference> savePreference(ReminderPreference preference);

  Future<List<ReminderFollowUpRecord>> performBatchAction(
    ReminderBatchActionRequest request,
  );

  Future<List<ReminderFollowUpRecord>> getFollowUpHistory(String reminderId);
}
