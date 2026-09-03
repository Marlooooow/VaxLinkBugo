// Explicit opt-in hosted smoke test. Normal test runs never open credentials
// or access the network. Reads records through the same adapters as the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_SUPABASE_DEMO_CHECKS');
  for (final key in ['staff', 'maria', 'paolo', 'grace']) {
    test(
      'hosted demo $key: live sign-in and linked screen data',
      () async {
        final environment = AppEnvironment.fromPublicConfiguration(
          File('assets/config/supabase.public.json').readAsStringSync(),
        );
        environment.validate();
        expect(environment.isLive, isTrue);
        expect(
          Uri.parse(environment.supabaseUrl).host,
          'oytdqiavxqowrzqpowvr.supabase.co',
        );
        final state =
            jsonDecode(
                  File('.env.supabase-demo-accounts.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(state['project'], 'oytdqiavxqowrzqpowvr');
        final account = state['accounts'][key] as Map<String, dynamic>;
        final client = SupabaseClient(
          environment.supabaseUrl,
          environment.supabaseAnonKey,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        final previous = RepositoryRegistry.instance;
        final repositories = RepositoryRegistry.create(
          environment,
          client: client,
        );
        var operation = 'sign-in';
        try {
          final user = await repositories.authRepository.login(
            username: account['username'] as String,
            password: account['password'] as String,
          );
          expect(user?.id, account['id']);
          if (user == null) fail('Demo sign-in failed; credentials omitted.');
          if (key == 'staff') {
            expect(user.role, UserRole.healthWorker);
            operation = 'Registered Families';
            final families = await repositories.childRepository
                .getHealthWorkerRegisteredFamilies();
            expect(families.length, greaterThanOrEqualTo(4));
            expect(
              families.expand((family) => family.children).length,
              greaterThanOrEqualTo(8),
            );
            operation = 'inventory and stock details';
            final inventory = await repositories.inventoryRepository
                .getInventoryOverview();
            expect(inventory.length, 7);
            expect(
              await repositories.inventoryRepository.getAllBatches(),
              isNotEmpty,
            );
            expect(
              await repositories.inventoryRepository.getTransactions('bcg'),
              isNotEmpty,
            );
            operation = 'staff reminders, appointments, offers and requests';
            expect(
              await repositories.reminderRepository.getFacilityFollowUps(),
              isNotEmpty,
            );
            expect(
              await repositories.appointmentRepository
                  .getFacilityAppointments(),
              isNotEmpty,
            );
            expect(
              await repositories.appointmentRepository.getFacilitySlotOffers(),
              isNotEmpty,
            );
            expect(
              await repositories.childRepository.getPendingChildLinkRequests(),
              isNotEmpty,
            );
            operation = 'advisory insights';
            expect(
              await repositories.advisoryInsightRepository
                  .getFacilityInsights(),
              isNotEmpty,
            );
          } else {
            expect(user.role, UserRole.guardian);
            operation = 'guardian children and relationship labels';
            final children = await repositories.childRepository
                .getChildrenForGuardian(user.id);
            expect(
              children.length,
              greaterThanOrEqualTo(key == 'maria' ? 5 : 1),
            );
            expect(
              children.every((child) => child.relationship != 'Other'),
              isTrue,
            );
            operation = 'guardian vaccination histories and statistics';
            for (final child in children) {
              expect(
                await repositories.vaccinationRepository.getVaccinationHistory(
                  child.id,
                ),
                isNotEmpty,
              );
              expect(
                await repositories.vaccinationRepository.getVaccinationSchedule(
                  child,
                ),
                hasLength(15),
              );
              expect(
                await repositories.vaccinationRepository.getFirstVisitReview(
                  child.id,
                ),
                isNotNull,
              );
            }
            operation = 'guardian reminders and preferences';
            expect(
              await repositories.reminderRepository.getGuardianReminders(
                user.id,
              ),
              isNotEmpty,
            );
            expect(
              (await repositories.reminderRepository.getPreference(
                user.id,
              )).smsEnabled,
              isFalse,
            );
            operation = 'guardian appointments, offers and requests';
            final appointments = await repositories.appointmentRepository
                .getGuardianAppointments(user.id);
            if (key != 'grace') expect(appointments, isNotEmpty);
            final offers = await repositories.appointmentRepository
                .getGuardianSlotOffers(user.id);
            if (key == 'maria') expect(offers, isNotEmpty);
            await repositories.childRepository.getGuardianChildLinkRequests(
              user.id,
            );
          }
        } on PostgrestException catch (error) {
          fail('$operation failed: ${error.code} ${error.message}');
        } on AuthException {
          fail(
            '$operation failed: authentication error; credential details omitted.',
          );
        } finally {
          await client.auth.signOut(scope: SignOutScope.local);
          await client.dispose();
          RepositoryRegistry.instance = previous;
        }
      },
      skip: enabled
          ? false
          : 'Hosted checks require explicit opt-in and private demo logins.',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
