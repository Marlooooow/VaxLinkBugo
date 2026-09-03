import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/health_worker_home_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/guardian_home_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/child_profile_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/dashboard_stat_grid.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/registered_families_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccination_reminders_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/app_shell.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

void main() {
  for (final section in ChildProfileSection.values) {
    testWidgets('Parent overview opens selected child $section directly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = RepositoryRegistry.create(
        const AppEnvironment(
          dataMode: AppDataMode.mock,
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: GuardianHomeScreen(
            user: const AppUser(
              id: 'USR-G-001',
              fullName: 'Maria Santos',
              role: UserRole.guardian,
              active: true,
            ),
            authRepository: registry.authRepository,
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      await settle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      final childId = dropdown.items!.last.value;
      dropdown.onChanged!(childId);
      await tester.pumpAndSettle();
      final history = section == ChildProfileSection.history;
      final stats = tester
          .widget<DashboardStatGrid>(find.byType(DashboardStatGrid))
          .stats;
      final count = stats
          .firstWhere(
            (stat) => stat.label == (history ? 'Recorded doses' : 'Upcoming'),
          )
          .value;
      final action = find.text(history ? 'View history' : 'View upcoming');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await settle();
      final screen = tester.widget<ChildProfileScreen>(
        find.byType(ChildProfileScreen),
      );
      expect(screen.child.id, childId);
      expect(screen.initialSection, section);
      final heading = find.text(
        history ? 'Vaccination History ($count)' : 'Upcoming Schedule ($count)',
      );
      expect(heading.hitTestable(), findsOneWidget);
      final expansion = tester.widget<ExpansionTile>(
        find.ancestor(of: heading, matching: find.byType(ExpansionTile)),
      );
      expect(expansion.initiallyExpanded, isTrue);
      await tester.pageBack();
      await settle();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        childId,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'QR shortcut opens without scrolling on a small phone; dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final registry = RepositoryRegistry.create(
          const AppEnvironment(
            dataMode: AppDataMode.mock,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: HealthWorkerHomeScreen(
              user: const AppUser(
                id: 'USR-H-001',
                fullName: 'Nurse Maria Reyes',
                role: UserRole.healthWorker,
                active: true,
              ),
              authRepository: registry.authRepository,
            ),
          ),
        );
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        // QR access belongs to the fixed worker shell, not a dashboard button.
        expect(
          find.widgetWithText(FilledButton, 'Scan Child QR'),
          findsNothing,
        );
        expect(find.text('Vaccination Statistics'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final guardian in [true, false]) {
    for (final status in [
      VaccinationReminderStatus.dueToday,
      VaccinationReminderStatus.overdue,
    ]) {
      testWidgets(
        '${guardian ? 'Guardian' : 'Worker'} statistics open $status reminders',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final registry = RepositoryRegistry.create(
            const AppEnvironment(
              dataMode: AppDataMode.mock,
              supabaseUrl: '',
              supabaseAnonKey: '',
            ),
          );
          final user = AppUser(
            id: guardian ? 'USR-G-001' : 'USR-H-001',
            fullName: guardian ? 'Maria Santos' : 'Nurse Maria Reyes',
            role: guardian ? UserRole.guardian : UserRole.healthWorker,
            active: true,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: guardian
                  ? GuardianHomeScreen(
                      user: user,
                      authRepository: registry.authRepository,
                    )
                  : HealthWorkerHomeScreen(
                      user: user,
                      authRepository: registry.authRepository,
                    ),
            ),
          );
          Future<void> settle() async {
            for (var i = 0; i < 30; i++) {
              await tester.pump(const Duration(milliseconds: 500));
            }
          }

          await settle();
          String? selectedChild;
          if (guardian) {
            final dropdown = tester.widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>),
            );
            // Use a non-default child to catch accidental hard-coded navigation.
            selectedChild = dropdown.items!.last.value;
            dropdown.onChanged!(selectedChild);
            await tester.pumpAndSettle();
          }
          final isDue = status == VaccinationReminderStatus.dueToday;
          final action = find.text(isDue ? 'View due today' : 'View overdue');
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
          await settle();
          final screen = tester.widget<VaccinationRemindersScreen>(
            find.byType(VaccinationRemindersScreen),
          );
          expect(screen.initialFilter, status);
          expect(screen.healthWorkerMode, !guardian);
          expect(screen.childId, selectedChild);
          expect(screen.guardianId, guardian ? user.id : null);
          if (guardian) {
            expect(screen.repository, same(registry.reminderRepository));
          }
          final chip = find.widgetWithText(
            ChoiceChip,
            isDue ? 'Due today' : 'Overdue',
          );
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
          await tester.pageBack();
          await settle();
          expect(find.text('Vaccination Statistics'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final destination in ['View families', 'View reminders']) {
    testWidgets('dashboard $destination card opens its destination', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = RepositoryRegistry.create(
        const AppEnvironment(
          dataMode: AppDataMode.mock,
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: HealthWorkerHomeScreen(
            user: const AppUser(
              id: 'USR-H-001',
              fullName: 'Nurse Maria Reyes',
              role: UserRole.healthWorker,
              active: true,
            ),
            authRepository: registry.authRepository,
          ),
        ),
      );
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final card = find.text(destination);
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        find.byType(
          destination == 'View families'
              ? RegisteredFamiliesScreen
              : VaccinationRemindersScreen,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'worker dashboard family statistic selects and filters the Families tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = RepositoryRegistry.create(
        const AppEnvironment(
          dataMode: AppDataMode.mock,
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
      );
      const user = AppUser(
        id: 'USR-H-001',
        fullName: 'Nurse Maria Reyes',
        role: UserRole.healthWorker,
        active: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AppShell(user: user, authRepository: registry.authRepository),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final action = find.text('View families');
      await tester.ensureVisible(action);
      await tester.tap(action);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(RegisteredFamiliesScreen), findsOneWidget);
      expect(
        find.text(
          'Showing families connected to current due or overdue reminders.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
