import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/guardian_home_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/health_worker_home_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/child_profile_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/dashboard_charts.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

void main() {
  Future<void> load(
    WidgetTester tester, {
    required bool guardian,
    double scale = 1,
  }) async {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
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
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets(
    'Guardian dashboard shows linked children before actions and services',
    (tester) async {
      await load(tester, guardian: true);
      expect(find.text('Guardian dashboard'), findsNothing);
      expect(
        find.text('Your children, their progress, and what comes next.'),
        findsNothing,
      );
      expect(find.byType(ChildCompletionChart), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items,
        hasLength(5),
      );
      final childrenY = tester
          .getTopLeft(find.text('Vaccination Statistics'))
          .dy;
      final nextY = tester.getTopLeft(find.text('Next steps')).dy;
      expect(childrenY, lessThan(nextY));
      expect(find.text('All services'), findsNothing);
      final record = find.text('View Sofia’s record');
      await tester.ensureVisible(record);
      await tester.pumpAndSettle();
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(find.byType(ChildProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final guardian in [true, false]) {
    testWidgets(
      '${guardian ? 'Guardian' : 'Worker'} dashboard supports large text',
      (tester) async {
        await load(tester, guardian: guardian, scale: 1.5);
        expect(
          find.text(
            guardian ? 'Guardian dashboard' : 'Health-worker dashboard',
          ),
          findsNothing,
        );
        if (!guardian) {
          expect(
            tester.getTopLeft(find.text('Vaccination Statistics')).dy,
            lessThan(
              tester.getTopLeft(find.text('Appointments & quick actions')).dy,
            ),
          );
        }
        await tester.ensureVisible(find.text('Next appointments'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
