import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/reminder_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccination_reminders_screen.dart';

class _Reminders extends Fake implements ReminderRepository {
  String? guardianRequested;
  @override
  Future<List<VaccinationReminder>> getGuardianReminders(
    String guardianId,
  ) async {
    guardianRequested = guardianId;
    return [
      for (final (child, status, vaccine) in [
        ('selected', VaccinationReminderStatus.overdue, 'Matching vaccine'),
        ('selected', VaccinationReminderStatus.upcoming, 'Future vaccine'),
        ('other', VaccinationReminderStatus.overdue, 'Other child vaccine'),
      ])
        VaccinationReminder(
          id: vaccine,
          reminderCode: vaccine,
          guardianId: guardianId,
          childId: child,
          childName: child,
          vaccineId: vaccine,
          vaccineName: vaccine,
          doseNumber: 1,
          dueDate: DateTime(2026, 8, 1),
          status: status,
          channel: VaccinationReminderChannel.inApp,
          isRead: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
    ];
  }
}

void main() {
  for (final empty in [false, true]) {
    testWidgets('Child/status filter preserves guardian scope; empty=$empty', (
      tester,
    ) async {
      final repository = _Reminders();
      await tester.pumpWidget(
        MaterialApp(
          home: VaccinationRemindersScreen.guardian(
            guardianId: 'guardian-test',
            childId: 'selected',
            repository: repository,
            initialFilter: empty
                ? VaccinationReminderStatus.dueToday
                : VaccinationReminderStatus.overdue,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.guardianRequested, 'guardian-test');
      expect(find.textContaining('Other child vaccine'), findsNothing);
      expect(find.textContaining('Future vaccine'), findsNothing);
      expect(
        find.textContaining('Matching vaccine'),
        empty ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('No reminders in this category.'),
        empty ? findsOneWidget : findsNothing,
      );
      final selected = find.widgetWithText(
        ChoiceChip,
        empty ? 'Due today' : 'Overdue',
      );
      expect(tester.widget<ChoiceChip>(selected).selected, isTrue);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Matching vaccine'), findsOneWidget);
      expect(find.textContaining('Future vaccine'), findsOneWidget);
      expect(find.textContaining('Other child vaccine'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
