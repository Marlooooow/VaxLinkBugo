import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/pnip_schedule_entry.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/dashboard_charts.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('Completion ring uses recorded doses and full schedule', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ChildCompletionChart(
          schedule: [
            PnipScheduleEntry(
              vaccineId: 'bcg',
              vaccineName: 'BCG',
              doseNumber: 1,
              scheduledDate: DateTime(2020),
              status: PnipDoseStatus.completed,
              administeredDate: DateTime(2020),
            ),
            PnipScheduleEntry(
              vaccineId: 'mmr',
              vaccineName: 'MMR',
              doseNumber: 1,
              scheduledDate: DateTime(2099),
              status: PnipDoseStatus.upcoming,
            ),
          ],
        ),
      ),
    );
    expect(find.text('1 of 2 doses recorded'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      .5,
    );
    expect(find.textContaining('Overdue: 0'), findsOneWidget);
  });

  testWidgets('Bars aggregate only due and overdue with shared scale', (
    tester,
  ) async {
    VaccinationReminder reminder(String id, VaccinationReminderStatus status) =>
        VaccinationReminder(
          id: id,
          reminderCode: id,
          guardianId: 'g',
          childId: id,
          childName: 'Child',
          vaccineId: 'bcg',
          vaccineName: 'BCG',
          doseNumber: 1,
          dueDate: DateTime(2026),
          status: status,
          channel: VaccinationReminderChannel.inApp,
          isRead: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
    await tester.pumpWidget(
      app(
        FollowUpVaccineChart(
          reminders: [
            reminder('1', VaccinationReminderStatus.dueToday),
            reminder('2', VaccinationReminderStatus.overdue),
            reminder('3', VaccinationReminderStatus.completed),
            reminder('4', VaccinationReminderStatus.upcoming),
          ],
        ),
      ),
    );
    expect(find.text('1 due today · 1 overdue'), findsOneWidget);
    expect(find.text('Common scale: 0–2 doses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty chart does not invent statistical values', (tester) async {
    await tester.pumpWidget(app(const FollowUpVaccineChart(reminders: [])));
    expect(find.text('No due or overdue doses to display.'), findsOneWidget);
    expect(find.textContaining('Common scale'), findsNothing);
  });
}
