import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_environment.dart';
import 'advisory_insight_repository.dart';
import 'auth_repository.dart';
import 'inventory_repository.dart';
import 'mock_auth_repository.dart';
import 'mock_advisory_insight_repository.dart';
import 'mock_inventory_repository.dart';
import 'mock_reminder_repository.dart';
import 'reminder_repository.dart';
import 'supabase_auth_repository.dart';
import 'supabase_advisory_insight_repository.dart';
import 'supabase_inventory_repository.dart';
import 'supabase_reminder_repository.dart';
import 'child_repository.dart';
import 'vaccination_repository.dart';
import 'appointment_repository.dart';
import 'referral_repository.dart';
import 'qr_repository.dart';
import 'mock_child_repository.dart';
import 'mock_vaccination_repository.dart';
import 'mock_appointment_repository.dart';
import 'mock_referral_repository.dart';
import 'mock_qr_repository.dart';
import 'supabase_child_repository.dart';
import 'supabase_vaccination_repository.dart';
import 'supabase_appointment_repository.dart';
import 'live_qr_repository.dart';
import 'pending_live_referral_repository.dart';
import 'supabase_referral_repository.dart';
import 'staff_repository.dart';
import 'supabase_staff_repository.dart';
import 'unavailable_staff_repository.dart';
import 'staff_notification_repository.dart';

class RepositoryRegistry {
  static late RepositoryRegistry instance;

  final AppEnvironment environment;
  final AuthRepository authRepository;
  final AdvisoryInsightRepository advisoryInsightRepository;
  final InventoryRepository inventoryRepository;
  final ReminderRepository reminderRepository;
  final ChildRepository childRepository;
  final VaccinationRepository vaccinationRepository;
  final AppointmentRepository appointmentRepository;
  final ReferralRepository referralRepository;
  final QrRepository qrRepository;
  final StaffRepository staffRepository;
  StaffNotificationRepository staffNotificationRepository;

  RepositoryRegistry._({
    required this.environment,
    required this.authRepository,
    required this.advisoryInsightRepository,
    required this.inventoryRepository,
    required this.reminderRepository,
    required this.childRepository,
    required this.vaccinationRepository,
    required this.appointmentRepository,
    required this.referralRepository,
    required this.qrRepository,
    required this.staffRepository,
    required this.staffNotificationRepository,
  });

  factory RepositoryRegistry.create(
    AppEnvironment environment, {
    SupabaseClient? client,
  }) {
    final live = environment.dataMode == AppDataMode.live;
    final database = live ? (client ?? Supabase.instance.client) : null;
    final children = live
        ? SupabaseChildRepository(database!)
        : MockChildRepository();
    // Only an explicitly selected mock/legacy-hybrid launch uses local fixtures.
    // Database demo accounts use the live Auth adapter, just like real accounts.
    final authRepository = environment.dataMode == AppDataMode.live
        ? SupabaseAuthRepository(database!)
        : MockAuthRepository();

    final registry = RepositoryRegistry._(
      environment: environment,
      authRepository: authRepository,
      childRepository: children,
      vaccinationRepository: live
          ? SupabaseVaccinationRepository(database!)
          : MockVaccinationRepository(),
      appointmentRepository: live
          ? SupabaseAppointmentRepository(database!)
          : MockAppointmentRepository(),
      referralRepository: live
          ? SupabaseReferralRepository(database!)
          : MockReferralRepository(),
      qrRepository: live ? LiveQrRepository(children) : MockQrRepository(),
      staffRepository: live
          ? SupabaseStaffRepository(database!)
          : const UnavailableStaffRepository(),
      staffNotificationRepository: const UnavailableStaffNotificationRepository(),
      advisoryInsightRepository: environment.dataMode == AppDataMode.live
          ? SupabaseAdvisoryInsightRepository(database!)
          : MockAdvisoryInsightRepository(),
      inventoryRepository: environment.dataMode == AppDataMode.live
          ? SupabaseInventoryRepository(database!)
          : MockInventoryRepository(),
      reminderRepository: environment.dataMode == AppDataMode.live
          ? SupabaseReminderRepository(database!)
          : MockReminderRepository(),
    );
    registry.staffNotificationRepository = live
        ? SupabaseStaffNotificationRepository(database!, registry)
        : MockStaffNotificationRepository(registry);
    instance = registry;
    return registry;
  }
}
