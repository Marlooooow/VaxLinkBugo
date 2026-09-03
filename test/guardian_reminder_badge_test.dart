import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/auth_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/reminder_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/guardian_home_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

class _Auth extends Fake implements AuthRepository {}

class _Reminders extends Fake implements ReminderRepository {
  bool read = false;
  final requested = <String>[];
  @override
  Future<List<VaccinationReminder>> getGuardianReminders(String id) async {
    requested.add(id);
    return [
      for (var i = 0; i < (id == 'guardian-a' ? 3 : 1); i++)
        VaccinationReminder(
          id: '$id-$i',
          reminderCode: '$id-$i',
          guardianId: id,
          childId: '$id-child',
          childName: 'Child $id',
          vaccineId: 'bcg',
          vaccineName: 'BCG',
          doseNumber: 1,
          dueDate: DateTime(2026, 8, 1),
          status: VaccinationReminderStatus.overdue,
          channel: VaccinationReminderChannel.inApp,
          isRead: read,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ),
    ];
  }
}

void main() {
  testWidgets(
    'Each guardian gets their own badge and return refreshes from same repository',
    (tester) async {
      final repository = _Reminders();
      final auth = _Auth();
      Widget app(String id) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: GuardianHomeScreen(
          user: AppUser(
            id: id,
            fullName: id,
            role: UserRole.guardian,
            active: true,
          ),
          authRepository: auth,
          reminderRepository: repository,
        ),
      );
      await tester.pumpWidget(app('guardian-a'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Vaccination reminders (3 unread)'),
        findsOneWidget,
      );
      await tester.pumpWidget(app('guardian-b'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Vaccination reminders (1 unread)'),
        findsOneWidget,
      );
      expect(find.byTooltip('Vaccination reminders (3 unread)'), findsNothing);
      await tester.tap(find.byTooltip('Vaccination reminders (1 unread)'));
      await tester.pumpAndSettle();
      repository.read = true;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Vaccination reminders (0 unread)'),
        findsOneWidget,
      );
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      expect(repository.requested.last, 'guardian-b');
      expect(tester.takeException(), isNull);
    },
  );

  test('Completed and dismissed reminders are not unread notifications', () {
    for (final status in VaccinationReminderStatus.values) {
      final item = VaccinationReminder(
        id: 'r',
        reminderCode: 'r',
        guardianId: 'g',
        childId: 'c',
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
      expect(
        item.hasUnreadNotification,
        status != VaccinationReminderStatus.completed &&
            status != VaccinationReminderStatus.dismissed,
      );
      expect(item.copyWith(isRead: true).hasUnreadNotification, isFalse);
    }
  });
}
