import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/models/reminder_follow_up.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_reminder_repository.dart';

void main() {
  test('guardian reminders are synchronized before reading the dashboard count', () async {
    final repository = MockReminderRepository();
    await repository.syncGuardianReminders('USR-G-001');
    final reminders = await repository.getGuardianReminders('USR-G-001');

    expect(reminders, isNotEmpty);
    expect(reminders.every((item) => item.guardianId == 'USR-G-001'), isTrue);
    expect(
      reminders.where((item) => item.status == VaccinationReminderStatus.overdue),
      isNotEmpty,
    );
  });

  test('health-worker queue contains only actionable reminders', () async {
    final repository = MockReminderRepository();
    final reminders = await repository.getFacilityFollowUps();

    expect(
      reminders.every(
        (item) =>
            item.status == VaccinationReminderStatus.dueToday ||
            item.status == VaccinationReminderStatus.overdue,
      ),
      isTrue,
    );
  });

  test('reminder JSON preserves backend fields', () async {
    final repository = MockReminderRepository();
    final reminder = (await repository.getGuardianReminders('USR-G-001')).first;
    final restored = VaccinationReminder.fromJson(reminder.toJson());

    expect(restored.id, reminder.id);
    expect(restored.childId, reminder.childId);
    expect(restored.status, reminder.status);
    expect(restored.dueDate, reminder.dueDate);
  });

  test('batch follow-up creates one auditable record per reminder', () async {
    final repository = MockReminderRepository();
    final reminders = await repository.getFacilityFollowUps();
    expect(reminders, isNotEmpty);
    final selected = reminders.take(2).toList(growable: false);

    final records = await repository.performBatchAction(
      ReminderBatchActionRequest(
        reminderIds: selected.map((item) => item.id).toList(growable: false),
        action: ReminderFollowUpAction.mockSms,
        outcome: ReminderFollowUpOutcome.reminderSent,
        assignedToUserId: null,
        notes: 'Mock batch reminder.',
        performedByUserId: 'USR-H-001',
      ),
    );

    expect(records, hasLength(selected.length));
    if (selected.isNotEmpty) {
      final history = await repository.getFollowUpHistory(selected.first.id);
      expect(history.first.outcome, ReminderFollowUpOutcome.reminderSent);
      expect(
        ReminderFollowUpRecord.fromJson(history.first.toJson()).reminderId,
        selected.first.id,
      );
    }
  });
}
