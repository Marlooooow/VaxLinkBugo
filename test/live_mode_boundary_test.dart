import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/reminder_follow_up.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/live_data_access.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_child_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_auth_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_inventory_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_vaccination_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_reminder_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_advisory_insight_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/live_qr_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/pending_live_referral_repository.dart';

void main() {
  test(
    'live mode selects database adapters and never substitutes simulated writes',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'https://local-test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests++;
          throw StateError(
            'A blocked operation must not make a network request',
          );
        }),
      );
      addTearDown(client.dispose);
      final saved = RepositoryRegistry.instance;
      addTearDown(() => RepositoryRegistry.instance = saved);
      final registry = RepositoryRegistry.create(
        const AppEnvironment(
          dataMode: AppDataMode.live,
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
        client: client,
      );
      expect(registry.childRepository, isA<SupabaseChildRepository>());
      expect(registry.authRepository, isA<SupabaseAuthRepository>());
      expect(registry.inventoryRepository, isA<SupabaseInventoryRepository>());
      expect(
        registry.vaccinationRepository,
        isA<SupabaseVaccinationRepository>(),
      );
      expect(
        registry.appointmentRepository,
        isA<SupabaseAppointmentRepository>(),
      );
      expect(registry.reminderRepository, isA<SupabaseReminderRepository>());
      expect(
        registry.advisoryInsightRepository,
        isA<SupabaseAdvisoryInsightRepository>(),
      );
      expect(registry.qrRepository, isA<LiveQrRepository>());
      expect(registry.referralRepository, isA<PendingLiveReferralRepository>());
      final unavailable = throwsA(isA<LiveOperationUnavailable>());
      await expectLater(
        registry.inventoryRepository.consumeDoses({'bcg': 1}),
        unavailable,
      );
      await expectLater(
        registry.vaccinationRepository.recordVaccinations([]),
        unavailable,
      );
      await expectLater(registry.qrRepository.simulateScan(), unavailable);
      await expectLater(
        registry.referralRepository.simulateReferralScan(),
        unavailable,
      );
      for (final action in [
        ReminderFollowUpAction.mockSms,
        ReminderFollowUpAction.printedList,
      ]) {
        await expectLater(
          registry.reminderRepository.performBatchAction(
            ReminderBatchActionRequest(
              reminderIds: ['real-id'],
              action: action,
              outcome: ReminderFollowUpOutcome.reminderSent,
              assignedToUserId: null,
              notes: '',
              performedByUserId: 'ignored',
            ),
          ),
          unavailable,
        );
      }
      expect(requests, 0);
    },
  );

  test(
    'live inventory counts only non-expired, verified, usable stock',
    () async {
      final client = SupabaseClient(
        'https://local-test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          Map<String, Object?> batch(
            int quantity, [
            Map<String, Object?> changes = const {},
          ]) => {
            'quantity': quantity,
            'expiry_date': '2099-01-01',
            'safety_status': 'usable',
            'packaging_intact': true,
            'cold_chain_verified': true,
            'vvm_status': 'acceptable',
            ...changes,
          };
          return http.Response(
            jsonEncode([
              {
                'id': 'inventory-uuid',
                'facility_id': 'facility-uuid',
                'reorder_level': 5,
                'updated_at': '2026-08-01T00:00:00Z',
                'vaccine_definitions': {'id': 'bcg', 'name': 'BCG'},
                'vaccine_batches': [
                  batch(7),
                  batch(5, {'vvm_status': 'not_applicable'}),
                  batch(100, {'expiry_date': '2020-01-01'}),
                  batch(100, {'safety_status': 'quarantined'}),
                  batch(100, {'packaging_intact': false}),
                  batch(100, {'cold_chain_verified': false}),
                  batch(100, {'vvm_status': 'unknown'}),
                  batch(100, {'vvm_status': 'not_acceptable'}),
                  batch(100, {'safety_status': 'discarded'}),
                ],
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final inventory = await SupabaseInventoryRepository(
        client,
      ).getInventoryOverview();
      expect(inventory.single.availableDoses, 12);
    },
  );
}
