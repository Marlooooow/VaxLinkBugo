import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_auth_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_child_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_vaccination_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_referral_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_qr_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_inventory_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_reminder_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_advisory_insight_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';

void main() {
  test('demo selects only mock repositories without initializing Supabase', () {
    final registry = RepositoryRegistry.create(
      const AppEnvironment(
        dataMode: AppDataMode.mock,
        supabaseUrl: '',
        supabaseAnonKey: '',
      ),
    );
    expect(registry.environment.usesSupabase, isFalse);
    expect(registry.authRepository, isA<MockAuthRepository>());
    expect(registry.childRepository, isA<MockChildRepository>());
    expect(registry.vaccinationRepository, isA<MockVaccinationRepository>());
    expect(registry.appointmentRepository, isA<MockAppointmentRepository>());
    expect(registry.referralRepository, isA<MockReferralRepository>());
    expect(registry.qrRepository, isA<MockQrRepository>());
    expect(registry.inventoryRepository, isA<MockInventoryRepository>());
    expect(registry.reminderRepository, isA<MockReminderRepository>());
    expect(
      registry.advisoryInsightRepository,
      isA<MockAdvisoryInsightRepository>(),
    );
  });

  test('all demo accounts sign in; guardian records stay connected', () async {
    final registry = RepositoryRegistry.create(
      const AppEnvironment(
        dataMode: AppDataMode.mock,
        supabaseUrl: '',
        supabaseAnonKey: '',
      ),
    );
    for (final username in ['guardian', 'paolo.guardian', 'grace.guardian']) {
      final user = await registry.authRepository.login(
        username: username,
        password: 'guardian123',
      );
      expect(user, isNotNull, reason: username);
      final children = await registry.childRepository.getChildrenForGuardian(
        user!.id,
      );
      expect(children, isNotEmpty, reason: username);
      final reminders = await registry.reminderRepository.getGuardianReminders(
        user.id,
      );
      expect(reminders, isNotEmpty, reason: username);
      expect(
        reminders.every(
          (reminder) => children.any((child) => child.id == reminder.childId),
        ),
        isTrue,
      );
      await registry.authRepository.logout();
    }
    final worker = await registry.authRepository.login(
      username: 'healthworker',
      password: 'health123',
    );
    expect(worker, isNotNull);
    expect(
      await registry.childRepository.getHealthWorkerRegisteredFamilies(),
      isNotEmpty,
    );
    expect(
      await registry.inventoryRepository.getInventoryOverview(),
      isNotEmpty,
    );
  });
}
