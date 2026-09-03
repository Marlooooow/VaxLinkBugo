import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/health_worker_home_screen.dart';

void main() {
  for (final administrator in [true, false]) {
    testWidgets(
      'staff management is ${administrator ? 'visible to administrators' : 'hidden from health workers'}',
      (tester) async {
        final registry = RepositoryRegistry.create(
          const AppEnvironment(
            dataMode: AppDataMode.mock,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: HealthWorkerHomeScreen(
              user: AppUser(
                id: administrator ? 'USR-A-001' : 'USR-H-001',
                fullName: administrator ? 'Administrator' : 'Nurse Maria',
                role: UserRole.healthWorker,
                active: true,
                isAdministrator: administrator,
              ),
              authRepository: registry.authRepository,
              servicesOnly: true,
            ),
          ),
        );
        // Let the notification bell's mock repository reads finish before the
        // widget is disposed. Otherwise those intentional mock delays remain
        // as pending timers and obscure the access-control assertion.
        await tester.pump(const Duration(seconds: 3));
        expect(
          find.text('Staff Management'),
          administrator ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
