import '../models/vaccination_reminder.dart';
import '../models/reminder_follow_up.dart';

class ReminderSummary {
  final int dueToday;
  final int overdue;
  final int upcoming;

  const ReminderSummary({
    required this.dueToday,
    required this.overdue,
    required this.upcoming,
  });

  factory ReminderSummary.fromItems(Iterable<VaccinationReminder> items) {
    return ReminderSummary(
      dueToday: items
          .where((item) => item.status == VaccinationReminderStatus.dueToday)
          .length,
      overdue: items
          .where((item) => item.status == VaccinationReminderStatus.overdue)
          .length,
      upcoming: items
          .where((item) => item.status == VaccinationReminderStatus.upcoming)
          .length,
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

  Future<List<VaccinationReminder>> getFacilityFollowUps();

  Future<ReminderPage> getFacilityFollowUpsPage({
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
