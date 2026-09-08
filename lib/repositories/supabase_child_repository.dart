import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_link_request.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';
import '../models/vaccination_schedule_state.dart';
import 'child_repository.dart';
import 'guardian_invitation_repository.dart';
import 'live_data_access.dart';

/// Database IDs stay UUIDs. Display codes are identifiers, not foreign keys.
class SupabaseChildRepository
    implements ChildRepository, GuardianInvitationIssuer {
  final SupabaseClient _client;
  late final _access = LiveDataAccess(_client);
  SupabaseChildRepository(this._client);

  static const _familySelect =
      '*, guardian_child_links(*, children(*)), '
      'guardian_invitations(id, guardian_id, expires_at, status, issued_by, used_at, created_at)';
  static const _requestSelect =
      '*, guardians!inner(full_name, sex, facility_id)';

  @override
  Future<List<ChildProfile>> getChildrenForGuardian(String guardianId) async {
    final id = await _access.guardianId(guardianId);
    final row = await _client
        .from('guardians')
        .select(_familySelect)
        .eq('id', id)
        .single();
    return familyFromRow(row).children;
  }

  @override
  Future<List<RegisteredFamily>> getHealthWorkerRegisteredFamilies() async {
    final facility = await _access.staffFacilityId();
    final rows = await _client
        .from('guardians')
        .select(_familySelect)
        .eq('facility_id', facility)
        .order('created_at', ascending: false);
    return rows.map(familyFromRow).toList(growable: false);
  }

  @override
  Future<RegisteredFamilyPage> getHealthWorkerRegisteredFamiliesPage({
    String search = '',
    VaccinationScheduleState? status,
    Set<String>? guardianIds,
    int pageSize = 20,
    DateTime? cursorCreatedAt,
    String? cursorGuardianId,
  }) async {
    final safePageSize = pageSize.clamp(10, 50).toInt();
    final response = await _client.rpc(
      'get_registered_family_summary_page',
      params: {
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_status': switch (status) {
          VaccinationScheduleState.dueNow => 'due_now',
          VaccinationScheduleState.completed => 'completed',
          VaccinationScheduleState.upcoming => 'upcoming',
          VaccinationScheduleState.overdue => 'overdue',
          null => null,
        },
        'p_guardian_ids': guardianIds?.toList(growable: false),
        'p_page_size': safePageSize,
        'p_cursor_created_at': cursorCreatedAt?.toUtc().toIso8601String(),
        'p_cursor_guardian_id': cursorGuardianId,
      },
    );
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final hasMore = rows.length > safePageSize;
    final pageRows = hasMore ? rows.take(safePageSize) : rows;
    final items = pageRows
        .map((row) {
          final guardian = guardianFromRow(
            Map<String, dynamic>.from(row['guardian'] as Map),
          );
          final children = <ChildProfile>[];
          final states = <String, VaccinationScheduleState>{};
          for (final raw in row['child_summaries'] as List? ?? const []) {
            final summary = Map<String, dynamic>.from(raw as Map);
            final child = childFromRow(
              Map<String, dynamic>.from(summary['child'] as Map),
              relationship: LiveDataAccess.relationship(
                summary['relationship'] as String,
                guardian.sex,
              ),
            );
            children.add(child);
            states[child.id] = switch (summary['schedule_state']) {
              'completed' => VaccinationScheduleState.completed,
              'due_now' => VaccinationScheduleState.dueNow,
              'overdue' => VaccinationScheduleState.overdue,
              _ => VaccinationScheduleState.upcoming,
            };
          }
          return RegisteredFamilySummary(
            family: RegisteredFamily(
              guardian: guardian,
              children: children,
              links: const [],
            ),
            childStates: states,
          );
        })
        .toList(growable: false);
    return RegisteredFamilyPage(
      items: items,
      totalCount: rows.isEmpty
          ? 0
          : (rows.first['total_count'] as num?)?.toInt() ?? items.length,
      hasMore: hasMore,
      nextCreatedAt: items.isEmpty
          ? null
          : items.last.family.guardian.registeredAt,
      nextGuardianId: items.isEmpty ? null : items.last.family.guardian.id,
    );
  }

  @override
  Future<RegisteredFamily?> getHealthWorkerRegisteredFamily(
    String guardianId,
  ) async {
    await _access.staffFacilityId();
    final row = await _client
        .from('guardians')
        .select(_familySelect)
        .eq('id', guardianId)
        .maybeSingle();
    return row == null ? null : familyFromRow(row);
  }

  @override
  Future<GuardianProfile?> findGuardianById(String guardianId) async {
    final row = await _client
        .from('guardians')
        .select()
        .eq('id', guardianId)
        .maybeSingle();
    return row == null ? null : guardianFromRow(row);
  }

  @override
  Future<ChildProfile?> findChildByIdentifier(String identifier) async {
    _access.userId;
    final value = identifier.trim();
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
    // Do not interpolate the identifier into an OR/filter expression.
    final row = await _client
        .from('children')
        .select()
        .eq(isUuid ? 'id' : 'child_code', isUuid ? value : value.toUpperCase())
        .maybeSingle();
    return row == null ? null : childFromRow(row);
  }

  @override
  Future<List<ChildLinkRequest>> getGuardianChildLinkRequests(
    String guardianUserId,
  ) async {
    final id = await _access.guardianId(guardianUserId);
    final rows = await _client
        .from('child_link_requests')
        .select(_requestSelect)
        .eq('guardian_id', id)
        .order('created_at', ascending: false);
    return rows.map(requestFromRow).toList(growable: false);
  }

  @override
  Future<List<ChildLinkRequest>> getPendingChildLinkRequests() async {
    final facility = await _access.staffFacilityId();
    final rows = await _client
        .from('child_link_requests')
        .select(_requestSelect)
        .eq('guardians.facility_id', facility)
        .eq('status', 'pending')
        .order('created_at');
    return rows.map(requestFromRow).toList(growable: false);
  }

  @override
  Future<ChildLinkRequestPage> getPendingChildLinkRequestsPage({
    String query = '',
    String? initialRequestId,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_pending_child_link_request_page',
            params: {
              'p_search': query.trim().isEmpty ? null : query.trim(),
              'p_request_id': initialRequestId,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final items = (payload['items'] as List? ?? const [])
        .map((row) => requestFromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return ChildLinkRequestPage(
      items: items,
      totalCount: (payload['total_count'] as num?)?.toInt() ?? items.length,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
    );
  }

  @override
  Future<GuardianRegistrationResult> registerGuardianAndChild(
    GuardianRegistrationRequest request,
  ) async {
    if (request.createUserAccount &&
        request.invitationChannel != GuardianInvitationChannel.printedSlip) {
      throw ArgumentError(
        'Use a printed activation code. Live SMS and email delivery are not configured.',
      );
    }
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'register_family_with_access',
            params: {
              'guardian_details': {
                'full_name': request.guardianName.trim(),
                'first_name': request.guardianFirstName?.trim(),
                'middle_name': request.guardianMiddleName?.trim(),
                'last_name': request.guardianLastName?.trim(),
                'suffix': request.guardianSuffix?.trim(),
                'birth_date': request.guardianBirthDate == null
                    ? null
                    : LiveDataAccess.date(request.guardianBirthDate!),
                'sex': request.guardianSex.toLowerCase(),
                'phone': request.phoneNumber,
                'email': request.emailAddress,
                'address': request.address.trim(),
              },
              'child_details': request.children.map(_childInput).toList(),
              'authorization_confirmed': request.authorizationConfirmed,
              'request_online_access': request.createUserAccount,
            },
          )
          as Map,
    );
    final family = familyFromRow(row);
    return GuardianRegistrationResult(
      guardian: family.guardian,
      children: family.children,
      links: family.links,
      invitation: family.invitation,
    );
  }

  @override
  Future<ExistingGuardianChildResult> addChildToExistingGuardian(
    ExistingGuardianChildRequest request,
  ) async {
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'add_family_child',
            params: {
              'target_guardian_id': request.guardianId,
              'child_details': _childInput(request.child),
              'authorization_confirmed': request.authorizationConfirmed,
            },
          )
          as Map,
    );
    final guardian = row['guardian'] as Map<String, dynamic>;
    final link = linkFromRow(
      row['link'] as Map<String, dynamic>,
      guardian['sex'] as String,
    );
    return ExistingGuardianChildResult(
      child: childFromRow(
        row['child'] as Map<String, dynamic>,
        relationship: link.relationship,
      ),
      link: link,
    );
  }

  @override
  Future<ChildLinkRequest> submitChildLinkRequest(
    SubmitChildLinkRequest request,
  ) async {
    await _access.guardianId(request.guardianUserId);
    final id = await _client.rpc(
      'submit_family_child_request',
      params: {
        'child_details': {
          'full_name': request.childName.trim(),
          'first_name': request.childFirstName?.trim(),
          'middle_name': request.childMiddleName?.trim(),
          'last_name': request.childLastName?.trim(),
          'suffix': request.childSuffix?.trim(),
          'birth_date': LiveDataAccess.date(request.birthDate),
          'sex': request.sex.toLowerCase(),
          'relationship': LiveDataAccess.relationshipValue(
            request.relationship,
          ),
        },
      },
    );
    return requestFromRow(
      await _client
          .from('child_link_requests')
          .select(_requestSelect)
          .eq('id', id)
          .single(),
    );
  }

  @override
  Future<ChildLinkRequest> reviewChildLinkRequest({
    required String requestId,
    required bool approve,
    required String reviewedByUserId,
    required String reviewNotes,
  }) async {
    final id = await _client.rpc(
      'review_family_child_request',
      params: {
        'target_request_id': requestId,
        'approve_request': approve,
        'notes': reviewNotes.trim(),
      },
    );
    return requestFromRow(
      await _client
          .from('child_link_requests')
          .select(_requestSelect)
          .eq('id', id)
          .single(),
    );
  }

  @override
  Future<GuardianInvitationIssueResult> issueGuardianInvitation(
    String guardianId,
  ) async {
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'issue_guardian_invitation',
            params: {'target_guardian_id': guardianId},
          )
          as Map,
    );
    final invitation = invitationFromRow(
      row['invitation'] as Map<String, dynamic>,
    );
    return GuardianInvitationIssueResult(
      guardian: guardianFromRow(row['guardian'] as Map<String, dynamic>)
          .copyWith(
            invitationCode: invitation.invitationCode,
            invitationExpiresAt: invitation.expiresAt,
          ),
      invitation: invitation,
    );
  }

  @override
  Future<GuardianCorrectionResult> correctGuardian(
    GuardianCorrectionRequest request,
  ) async {
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'correct_guardian_details',
            params: {
              'target_guardian_id': request.guardianId,
              'changes': {
                'full_name': request.fullName.trim(),
                'first_name': request.firstName?.trim(),
                'middle_name': request.middleName?.trim(),
                'last_name': request.lastName?.trim(),
                'suffix': request.suffix?.trim(),
                'birth_date': request.birthDate
                    ?.toIso8601String()
                    .split('T')
                    .first,
                'sex': request.sex.toLowerCase(),
                'phone': request.phoneNumber?.trim(),
                'email': request.emailAddress?.trim(),
                'address': request.address.trim(),
              },
              'correction_reason': request.reason.trim(),
            },
          )
          as Map,
    );
    final correction = row['correction'] as Map<String, dynamic>;
    return GuardianCorrectionResult(
      guardian: guardianFromRow(row['guardian'] as Map<String, dynamic>),
      correction: GuardianCorrection(
        id: correction['id'] as String,
        correctionCode: correction['correction_code'] as String,
        guardianId: correction['guardian_id'] as String,
        previousValues: Map<String, Object?>.from(
          correction['previous_values'] as Map,
        ),
        updatedValues: Map<String, Object?>.from(
          correction['updated_values'] as Map,
        ),
        reason: correction['reason'] as String,
        correctedAt: DateTime.parse(correction['corrected_at'] as String),
        correctedByUserId: correction['corrected_by'] as String,
      ),
    );
  }

  @override
  Future<ChildCorrectionResult> correctChild(
    ChildCorrectionRequest request,
  ) async {
    if (request.guardianId == null) {
      throw ArgumentError(
        'Select the guardian-child relationship before correcting this record.',
      );
    }
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'correct_child_details',
            params: {
              'target_child_id': request.childId,
              'target_guardian_id': request.guardianId,
              'changes': {
                'full_name': request.fullName.trim(),
                'sex': request.sex.toLowerCase(),
                'birth_date': LiveDataAccess.date(request.birthDate),
                'relationship': LiveDataAccess.relationshipValue(
                  request.relationship,
                ),
              },
              'correction_reason': request.reason.trim(),
            },
          )
          as Map,
    );
    final correction = row['correction'] as Map<String, dynamic>;
    final link = linkFromRow(
      row['link'] as Map<String, dynamic>,
      row['guardian_sex'] as String,
    );
    return ChildCorrectionResult(
      child: childFromRow(
        row['child'] as Map<String, dynamic>,
        relationship: link.relationship,
      ),
      correction: ChildCorrection(
        id: correction['id'] as String,
        correctionCode: correction['correction_code'] as String,
        childId: correction['child_id'] as String,
        previousValues: Map<String, Object?>.from(
          correction['previous_values'] as Map,
        ),
        updatedValues: Map<String, Object?>.from(
          correction['updated_values'] as Map,
        ),
        reason: correction['reason'] as String,
        correctedAt: DateTime.parse(correction['corrected_at'] as String),
        correctedByUserId: correction['corrected_by'] as String,
      ),
    );
  }

  static Map<String, Object?> _childInput(ChildRegistrationInput child) => {
    'full_name': child.fullName.trim(),
    'first_name': child.firstName?.trim(),
    'middle_name': child.middleName?.trim(),
    'last_name': child.lastName?.trim(),
    'suffix': child.suffix?.trim(),
    'birth_date': LiveDataAccess.date(child.birthDate),
    'sex': child.sex.toLowerCase(),
    'relationship': LiveDataAccess.relationshipValue(child.relationship),
  };

  static ChildProfile childFromRow(
    Map<String, dynamic> row, {
    String relationship = 'Other',
  }) => ChildProfile(
    id: row['id'] as String,
    fullName: row['full_name'] as String,
    firstName: row['first_name'] as String?,
    middleName: row['middle_name'] as String?,
    lastName: row['last_name'] as String?,
    suffix: row['suffix'] as String?,
    birthDate: DateTime.parse(row['birth_date'] as String),
    sex: LiveDataAccess.title(row['sex'] as String),
    qrIdentifier: row['child_code'] as String,
    relationship: relationship,
  );

  static GuardianProfile guardianFromRow(Map<String, dynamic> row) =>
      GuardianProfile(
        id: row['id'] as String,
        guardianCode: row['guardian_code'] as String,
        fullName: row['full_name'] as String,
        firstName: row['first_name'] as String?,
        middleName: row['middle_name'] as String?,
        lastName: row['last_name'] as String?,
        suffix: row['suffix'] as String?,
        birthDate: row['birth_date'] == null
            ? null
            : DateTime.parse(row['birth_date'] as String),
        sex: LiveDataAccess.title(row['sex'] as String),
        phoneNumber: row['phone'] as String?,
        emailAddress: row['email'] as String?,
        address: row['address'] as String? ?? '',
        hasUserAccount: row['profile_id'] != null,
        userId: row['profile_id'] as String?,
        accessStatus: switch (row['access_status']) {
          'active' => GuardianAccessStatus.activeGuardianAccount,
          'invitation_pending' => GuardianAccessStatus.invitationPending,
          'disabled' => GuardianAccessStatus.accessDisabled,
          _ => GuardianAccessStatus.healthWorkerManaged,
        },
        registeredAt: DateTime.parse(row['created_at'] as String),
        registeredByUserId: row['registered_by'] as String? ?? '',
      );

  static GuardianChildLink linkFromRow(
    Map<String, dynamic> row,
    String guardianSex,
  ) => GuardianChildLink(
    id: row['id'] as String,
    guardianId: row['guardian_id'] as String,
    childId: row['child_id'] as String,
    relationship: LiveDataAccess.relationship(
      row['relationship'] as String,
      guardianSex,
    ),
    isPrimaryGuardian: row['is_primary'] as bool,
    authorizationConfirmed: row['status'] == 'approved',
    linkedAt: DateTime.parse(row['created_at'] as String),
    linkedByUserId:
        row['reviewed_by'] as String? ?? row['requested_by'] as String? ?? '',
  );

  static RegisteredFamily familyFromRow(Map<String, dynamic> row) {
    final links = <GuardianChildLink>[];
    final children = <ChildProfile>[];
    for (final link in (row['guardian_child_links'] as List? ?? const [])) {
      if (link['status'] != 'approved' || link['children'] == null) continue;
      final mapped = linkFromRow(
        Map<String, dynamic>.from(link as Map),
        row['sex'] as String,
      );
      links.add(mapped);
      children.add(
        childFromRow(
          Map<String, dynamic>.from(link['children'] as Map),
          relationship: mapped.relationship,
        ),
      );
    }
    final issued = row['issued_invitation'] as Map<String, dynamic>?;
    final history = List<Map<String, dynamic>>.from(
      row['guardian_invitations'] as List? ?? const [],
    );
    history.sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
    final invitation = issued != null
        ? invitationFromRow(issued)
        : history.isEmpty
        ? null
        : invitationFromRow(history.first);
    return RegisteredFamily(
      guardian: guardianFromRow(row).copyWith(
        invitationCode: issued?['activation_code'] as String?,
        invitationExpiresAt: invitation?.expiresAt,
        accessStatus:
            invitation?.status == GuardianInvitationStatus.expired &&
                row['access_status'] == 'invitation_pending'
            ? GuardianAccessStatus.invitationExpired
            : null,
      ),
      children: children,
      links: links,
      invitation: invitation,
    );
  }

  static GuardianInvitation invitationFromRow(Map<String, dynamic> row) {
    final expiry = DateTime.parse(row['expires_at'] as String);
    return GuardianInvitation(
      id: row['id'] as String,
      invitationCode: row['activation_code'] as String? ?? '',
      guardianId: row['guardian_id'] as String,
      channel: GuardianInvitationChannel.printedSlip,
      destination: 'Hand to guardian',
      maskedDestination: 'Hand to guardian',
      status: switch (row['status']) {
        'used' => GuardianInvitationStatus.accepted,
        'revoked' => GuardianInvitationStatus.revoked,
        'expired' => GuardianInvitationStatus.expired,
        _ =>
          expiry.isAfter(DateTime.now())
              ? GuardianInvitationStatus.pendingDelivery
              : GuardianInvitationStatus.expired,
      },
      createdAt: DateTime.parse(row['created_at'] as String),
      deliveredAt: null,
      expiresAt: expiry,
      acceptedAt: row['used_at'] == null
          ? null
          : DateTime.parse(row['used_at'] as String),
      createdByUserId: row['issued_by'] as String,
    );
  }

  static ChildLinkRequest requestFromRow(Map<String, dynamic> row) {
    final guardian = row['guardians'] as Map<String, dynamic>;
    return ChildLinkRequest(
      id: row['id'] as String,
      requestCode: row['request_code'] as String,
      guardianId: row['guardian_id'] as String,
      guardianName: guardian['full_name'] as String,
      childName: row['child_name'] as String,
      childFirstName: row['first_name'] as String?,
      childMiddleName: row['middle_name'] as String?,
      childLastName: row['last_name'] as String?,
      childSuffix: row['suffix'] as String?,
      birthDate: DateTime.parse(row['birth_date'] as String),
      sex: LiveDataAccess.title(row['sex'] as String),
      relationship: LiveDataAccess.relationship(
        row['relationship'] as String,
        guardian['sex'] as String,
      ),
      status: ChildLinkRequestStatus.values.byName(row['status'] as String),
      submittedAt: DateTime.parse(row['created_at'] as String),
      reviewedAt: row['reviewed_at'] == null
          ? null
          : DateTime.parse(row['reviewed_at'] as String),
      reviewedByUserId: row['reviewed_by'] as String?,
      reviewNotes: row['review_notes'] as String?,
      linkedChildId: row['linked_child_id'] as String?,
    );
  }
}
