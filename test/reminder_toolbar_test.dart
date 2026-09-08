import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/reminder_follow_up.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/reminder_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccination_reminders_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

class _Reminders extends Fake implements ReminderRepository {
  @override
  Future<List<ReminderFollowUpRecord>> getFollowUpHistory(
    String reminderId,
  ) async => [];

  @override
  Future<List<VaccinationReminder>> getFacilityFollowUps() async => [
    for (var i = 0; i < 24; i++)
      VaccinationReminder(
        id: 'reminder-$i',
        reminderCode: 'R-$i',
        guardianId: 'guardian',
        childId: 'child-$i',
        childName: 'Child $i',
        vaccineId: 'opv',
        vaccineName: 'OPV',
        doseNumber: 1,
        dueDate: DateTime(2026, 8, 1),
        status: VaccinationReminderStatus.overdue,
        channel: VaccinationReminderChannel.inApp,
        isRead: true,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      ),
  ];
}

void main() {
  testWidgets('summary cards control the reminder status filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: VaccinationRemindersScreen.healthWorker(repository: _Reminders()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel(RegExp(r'Overdue reminders:')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Overdue'))
          .selected,
      isTrue,
    );

    await tester.tap(
      find.bySemanticsLabel(RegExp(r'Upcoming reminders:')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Upcoming'))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'Full-screen actions keep selection header fixed and cancel preserves selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: VaccinationRemindersScreen.healthWorker(
            repository: _Reminders(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batch action'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Follow-up actions'), findsOneWidget);
      final header = find.byKey(
        const ValueKey('batch-action-selection-summary'),
      );
      expect(find.textContaining('24 reminders selected.'), findsOneWidget);
      final before = tester.getTopLeft(header);
      await tester.drag(
        find.byKey(const ValueKey('batch-action-options')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header), before);
      await tester.ensureVisible(find.text('Record no answer'));
      await tester.tap(find.text('Record no answer'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm action'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('24 selected'), findsOneWidget);
      await tester.tap(find.text('Batch action'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('24 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('batch action remains fixed when reminders scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: VaccinationRemindersScreen.healthWorker(repository: _Reminders()),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('Batch action');
    final before = tester.getTopLeft(button);
    await tester.drag(
      find.byKey(const PageStorageKey('vaccination-reminders-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(button), before);
    expect(tester.takeException(), isNull);
  });
}
