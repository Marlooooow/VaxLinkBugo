import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_child_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_vaccination_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_schedule_state.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_assessment.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_qr_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_auth_repository.dart';

void main() {
  test('registers a health-worker-managed guardian and child', () async {
    final result = await MockChildRepository().registerGuardianAndChild(
      GuardianRegistrationRequest(
        guardianName: 'Test Guardian',
        phoneNumber: null,
        emailAddress: null,
        address: 'Barangay Bugo',
        createUserAccount: false,
        invitationChannel: null,
        children: [
          ChildRegistrationInput(
            fullName: 'Test Child',
            birthDate: DateTime(2026, 1, 1),
            sex: 'Female',
            relationship: 'Aunt',
          ),
          ChildRegistrationInput(
            fullName: 'Second Child',
            birthDate: DateTime(2024, 1, 1),
            sex: 'Male',
            relationship: 'Aunt',
          ),
        ],
        authorizationConfirmed: true,
        registeredByUserId: 'health-worker-1',
      ),
    );

    expect(result.guardian.hasUserAccount, isFalse);
    expect(result.guardian.userId, isNull);
    expect(result.child.id, startsWith('CH-'));
    expect(result.child.qrIdentifier, startsWith('QR-CH-'));
    expect(result.link.relationship, 'Aunt');
    expect(result.link.authorizationConfirmed, isTrue);
    expect(result.children, hasLength(2));
  });

  test('rejects a future child birth date', () async {
    final future = DateTime.now().add(const Duration(days: 1));

    await expectLater(
      MockChildRepository().registerGuardianAndChild(
        GuardianRegistrationRequest(
          guardianName: 'Test Guardian',
          phoneNumber: null,
          emailAddress: null,
          address: 'Barangay Bugo',
          createUserAccount: false,
          invitationChannel: null,
          children: [
            ChildRegistrationInput(
              fullName: 'Future Child',
              birthDate: future,
              sex: 'Male',
              relationship: 'Mother',
            ),
          ],
          authorizationConfirmed: true,
          registeredByUserId: 'health-worker-1',
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'online access starts as an invitation without a password account',
    () async {
      final result = await MockChildRepository().registerGuardianAndChild(
        GuardianRegistrationRequest(
          guardianName: 'Invited Guardian',
          phoneNumber: '09170000000',
          emailAddress: null,
          address: 'Barangay Bugo',
          createUserAccount: true,
          invitationChannel: GuardianInvitationChannel.sms,
          children: [
            ChildRegistrationInput(
              fullName: 'Invitation Child',
              birthDate: DateTime(2025, 6, 1),
              sex: 'Female',
              relationship: 'Mother',
            ),
          ],
          authorizationConfirmed: true,
          registeredByUserId: 'USR-H-001',
        ),
      );

      expect(
        result.guardian.accessStatus,
        GuardianAccessStatus.invitationPending,
      );
      expect(result.guardian.hasUserAccount, isFalse);
      expect(result.guardian.userId, isNull);
      expect(result.guardian.invitationCode, isNotNull);
      expect(result.guardian.invitationExpiresAt, isNotNull);
      expect(result.invitation, isNotNull);
      expect(result.invitation!.channel, GuardianInvitationChannel.sms);
      expect(result.invitation!.status, GuardianInvitationStatus.delivered);
      expect(result.invitation!.maskedDestination, isNot('09170000000'));
    },
  );

  test(
    'guardian activates an invitation and signs in to linked records',
    () async {
      final childRepository = MockChildRepository();

      final registration = await childRepository.registerGuardianAndChild(
        GuardianRegistrationRequest(
          guardianName: 'Activation Guardian',
          phoneNumber: null,
          emailAddress: 'activation@example.test',
          address: 'Barangay Bugo',
          createUserAccount: true,
          invitationChannel: GuardianInvitationChannel.email,
          children: [
            ChildRegistrationInput(
              fullName: 'Activation Child',
              birthDate: DateTime(2025, 7, 1),
              sex: 'Male',
              relationship: 'Father',
            ),
          ],
          authorizationConfirmed: true,
          registeredByUserId: 'USR-H-001',
        ),
      );

      final authRepository = MockAuthRepository();

      final activation = await authRepository.activateGuardianInvitation(
        activationCode: registration.guardian.invitationCode!,
      );

      final signedIn = await authRepository.login(
        username: activation.username,
        password: activation.temporaryPassword,
      );

      final children = await childRepository.getChildrenForGuardian(
        activation.user.id,
      );

      final family = (await childRepository.getHealthWorkerRegisteredFamilies())
          .firstWhere((item) => item.guardian.id == registration.guardian.id);

      expect(signedIn?.id, activation.user.id);
      expect(signedIn?.fullName, 'Activation Guardian');

      expect(children, hasLength(1));
      expect(children.single.fullName, 'Activation Child');

      expect(family.invitation?.status, GuardianInvitationStatus.accepted);
    },
  );

  test('adds another child without creating another guardian', () async {
    final repository = MockChildRepository();
    final family = (await repository.getHealthWorkerRegisteredFamilies()).first;
    final beforeCount = family.children.length;

    final result = await repository.addChildToExistingGuardian(
      ExistingGuardianChildRequest(
        guardianId: family.guardian.id,
        child: ChildRegistrationInput(
          fullName: 'Unique Linked Child',
          birthDate: DateTime(2025, 5, 1),
          sex: 'Female',
          relationship: 'Mother',
        ),
        authorizationConfirmed: true,
        registeredByUserId: 'health-worker-1',
      ),
    );

    final refreshed = (await repository.getHealthWorkerRegisteredFamilies())
        .firstWhere((item) => item.guardian.id == family.guardian.id);
    expect(result.link.guardianId, family.guardian.id);
    expect(refreshed.children, hasLength(beforeCount + 1));
  });

  test(
    'registered family scenarios cover each calculated PNIP state',
    () async {
      final families = await MockChildRepository()
          .getHealthWorkerRegisteredFamilies();
      final vaccinationRepository = MockVaccinationRepository();
      final states = <VaccinationScheduleState>{};
      for (final family in families) {
        for (final child in family.children) {
          final schedule = await vaccinationRepository.getVaccinationSchedule(
            child,
          );
          states.add(summarizeSchedule(schedule));
        }
      }

      expect(states, containsAll(VaccinationScheduleState.values));
    },
  );

  test('finds a health-worker registered child by child or QR ID', () async {
    final repository = MockChildRepository();
    final family = (await repository.getHealthWorkerRegisteredFamilies()).first;
    final child = family.children.first;

    expect((await repository.findChildByIdentifier(child.id))?.id, child.id);
    expect(
      (await repository.findChildByIdentifier(child.qrIdentifier))?.id,
      child.id,
    );
  });

  test('resolves the versioned printed child QR payload', () async {
    final result = await MockQrRepository().findByIdentifier(
      '{"type":"child_identity","version":1,"child_id":"CH-2026-000101","qr_identifier":"QR-CH-2026-000101"}',
    );

    expect(result?.child.id, 'CH-2026-000101');
  });

  test('Maria Santos appears as an account-linked registered family', () async {
    final repository = MockChildRepository();
    final families = await repository.getHealthWorkerRegisteredFamilies();
    final maria = families.firstWhere(
      (family) => family.guardian.fullName == 'Maria Santos',
    );
    final guardianViewChildren = await repository.getChildrenForGuardian(
      'USR-G-001',
    );

    expect(maria.guardian.hasUserAccount, isTrue);
    expect(maria.guardian.userId, 'USR-G-001');
    expect(maria.children, hasLength(5));
    expect(
      guardianViewChildren.map((child) => child.id).toSet(),
      maria.children.map((child) => child.id).toSet(),
    );
  });

  test('first-visit mock child opens the Phase 6 intake state', () async {
    final child = await MockChildRepository().findChildByIdentifier(
      'CH-2026-000105',
    );
    final assessment = await MockVaccinationRepository().assessChild(child!);

    expect(child.fullName, 'Isabella Navarro');
    expect(assessment.history, isEmpty);
    expect(assessment.status, VaccinationAssessmentStatus.firstVaccination);
  });
}
