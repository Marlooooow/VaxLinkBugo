import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian_invitation.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/person_name.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_child_repository.dart';

const _guardianId = '10000000-0000-4000-8000-000000000001';
const _childId = '10000000-0000-4000-8000-000000000002';
const _workerId = '10000000-0000-4000-8000-000000000003';

Map<String, dynamic> _guardian() => {
  'id': _guardianId,
  'guardian_code': 'GRD-2026-000001',
  'full_name': 'Database Guardian',
  'sex': 'female',
  'phone': null,
  'email': null,
  'address': 'Bugo',
  'profile_id': null,
  'access_status': 'offline',
  'created_at': '2026-08-01T00:00:00Z',
  'registered_by': _workerId,
};
Map<String, dynamic> _child() => {
  'id': _childId,
  'child_code': 'CH-2026-000001',
  'full_name': 'Database Child',
  'sex': 'male',
  'birth_date': '2025-02-03',
};
Map<String, dynamic> _link({String status = 'approved'}) => {
  'id': 'link-uuid',
  'guardian_id': _guardianId,
  'child_id': _childId,
  'relationship': 'aunt',
  'is_primary': false,
  'status': status,
  'created_at': '2026-08-01T00:00:00Z',
  'reviewed_by': _workerId,
  'children': _child(),
};
Map<String, dynamic> _invitation({bool withCode = true}) => {
  'id': 'invitation-uuid',
  'guardian_id': _guardianId,
  'created_at': '2026-08-01T00:00:00Z',
  'expires_at': '2099-08-08T00:00:00Z',
  'status': 'pending',
  'issued_by': _workerId,
  if (withCode) 'activation_code': 'ACT-0123456789ABCDEF0123456789ABCDEF',
};

void main() {
  test(
    'family mapping excludes unapproved links and never uses codes as foreign keys',
    () {
      final family = SupabaseChildRepository.familyFromRow({
        ..._guardian(),
        'guardian_child_links': [
          _link(),
          _link(status: 'pending'),
          _link(status: 'revoked'),
        ],
      });
      expect(family.children, hasLength(1));
      expect(family.children.single.id, _childId);
      expect(family.children.single.qrIdentifier, 'CH-2026-000001');
      expect(family.children.single.relationship, 'Aunt');
      expect(family.links.single.isPrimaryGuardian, isFalse);
    },
  );
  test(
    'invitation code is shown only in issuance response; delivery is not fabricated',
    () {
      final issued = SupabaseChildRepository.familyFromRow({
        ..._guardian(),
        'access_status': 'invitation_pending',
        'issued_invitation': _invitation(),
      });
      expect(issued.guardian.invitationCode, startsWith('ACT-'));
      expect(
        issued.invitation!.status,
        GuardianInvitationStatus.pendingDelivery,
      );
      expect(issued.invitation!.deliveredAt, isNull);
      final reloaded = SupabaseChildRepository.familyFromRow({
        ..._guardian(),
        'access_status': 'invitation_pending',
        'guardian_invitations': [_invitation(withCode: false)],
      });
      expect(reloaded.guardian.invitationCode, isNull);
      expect(reloaded.invitation!.invitationCode, isEmpty);
    },
  );
  test(
    'registration calls one live transaction with two children; no mock actor or SMS',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://unit-test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              ..._guardian(),
              'access_status': 'invitation_pending',
              'guardian_child_links': [_link()],
              'issued_invitation': _invitation(),
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseChildRepository(client);
      GuardianRegistrationRequest registration(
        GuardianInvitationChannel channel,
      ) => GuardianRegistrationRequest(
        guardianName: 'Database Guardian',
        guardianSex: 'Female',
        phoneNumber: null,
        emailAddress: null,
        address: 'Bugo',
        createUserAccount: true,
        invitationChannel: channel,
        authorizationConfirmed: true,
        registeredByUserId: 'FORGED-USER',
        children: [
          for (final name in ['Child A', 'Child B'])
            ChildRegistrationInput(
              fullName: name,
              birthDate: DateTime(2025, 2, 3),
              sex: 'Male',
              relationship: 'Aunt',
            ),
        ],
      );
      await repository.registerGuardianAndChild(
        registration(GuardianInvitationChannel.printedSlip),
      );
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/register_family_with_access',
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['child_details'], hasLength(2));
      expect(body['request_online_access'], true);
      expect(requests.single.body, isNot(contains('FORGED-USER')));
      await expectLater(
        repository.registerGuardianAndChild(
          registration(GuardianInvitationChannel.sms),
        ),
        throwsArgumentError,
      );
      expect(requests, hasLength(1));
    },
  );
  test('structured registration sends names and guardian birth date', () async {
    late Map<String, dynamic> body;
    final client = SupabaseClient(
      'https://unit-test.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            ..._guardian(),
            'first_name': 'Elena',
            'middle_name': 'Reyes',
            'last_name': 'Dela Cruz',
            'birth_date': '1992-06-15',
            'guardian_child_links': [_link()],
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    await SupabaseChildRepository(client).registerGuardianAndChild(
      GuardianRegistrationRequest.structured(
        guardianName: const PersonName(
          firstName: 'Elena',
          middleName: 'Reyes',
          lastName: 'Dela Cruz',
        ),
        guardianBirthDate: DateTime(1992, 6, 15),
        phoneNumber: '09123456789',
        emailAddress: null,
        address: 'Bugo',
        createUserAccount: false,
        invitationChannel: null,
        authorizationConfirmed: true,
        registeredByUserId: 'FORGED-USER',
        children: [
          ChildRegistrationInput.structured(
            name: const PersonName(
              firstName: 'Carlo',
              lastName: 'Dela Cruz',
              suffix: 'Jr.',
            ),
            birthDate: DateTime(2025, 2, 3),
            sex: 'Male',
            relationship: 'Mother',
          ),
        ],
      ),
    );

    final guardian = Map<String, dynamic>.from(body['guardian_details'] as Map);
    final children = body['child_details'] as List<dynamic>;
    final child = Map<String, dynamic>.from(children.single as Map);
    expect(guardian['first_name'], 'Elena');
    expect(guardian['middle_name'], 'Reyes');
    expect(guardian['last_name'], 'Dela Cruz');
    expect(guardian['birth_date'], '1992-06-15');
    expect(child['first_name'], 'Carlo');
    expect(child['last_name'], 'Dela Cruz');
    expect(child['suffix'], 'Jr.');
    expect(body.toString(), isNot(contains('FORGED-USER')));
  });
  test(
    'corrections use explicit guardian-child context and server actor/audit IDs',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://unit-test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final correction = {
            'id': 'audit-uuid',
            'correction_code': 'CCOR-2026-000001',
            'child_id': _childId,
            'guardian_id': _guardianId,
            'previous_values': {'full_name': 'Before'},
            'updated_values': {'full_name': 'After'},
            'reason': 'Test reason',
            'corrected_at': '2026-08-01T00:00:00Z',
            'corrected_by': _workerId,
          };
          return http.Response(
            jsonEncode({
              'guardian': _guardian(),
              'child': _child(),
              'link': _link(),
              'guardian_sex': 'female',
              'correction': correction,
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseChildRepository(client);
      final childResult = await repository.correctChild(
        ChildCorrectionRequest(
          childId: _childId,
          guardianId: _guardianId,
          fullName: 'After',
          birthDate: DateTime(2025, 2, 3),
          sex: 'Male',
          relationship: 'Aunt',
          reason: 'Test reason',
          correctedByUserId: 'FORGED-USER',
        ),
      );
      expect(
        jsonDecode(requests.single.body)['target_guardian_id'],
        _guardianId,
      );
      expect(childResult.correction.correctedByUserId, _workerId);
      final guardianResult = await repository.correctGuardian(
        const GuardianCorrectionRequest(
          guardianId: _guardianId,
          fullName: 'After',
          sex: 'Female',
          phoneNumber: null,
          address: 'Bugo',
          hasUserAccount: true,
          reason: 'Test reason',
          correctedByUserId: 'FORGED-USER',
        ),
      );
      expect(guardianResult.correction.correctedByUserId, _workerId);
      expect(
        jsonDecode(requests.last.body)['changes'].keys,
        isNot(contains('has_user_account')),
      );
      expect(requests.every((r) => !r.body.contains('FORGED-USER')), isTrue);
    },
  );
  test(
    'database failures are surfaced; registration never falls back to demo data',
    () async {
      final client = SupabaseClient(
        'https://unit-test.supabase.co',
        'test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            '{"code":"42501","message":"permission denied"}',
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseChildRepository(client).addChildToExistingGuardian(
          ExistingGuardianChildRequest(
            guardianId: _guardianId,
            authorizationConfirmed: true,
            registeredByUserId: _workerId,
            child: ChildRegistrationInput(
              fullName: 'Blocked',
              birthDate: DateTime(2025, 2, 3),
              sex: 'Male',
              relationship: 'Aunt',
            ),
          ),
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
