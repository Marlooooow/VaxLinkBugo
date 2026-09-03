import '../models/child_profile.dart';
import '../models/guardian_profile.dart';
import '../models/guardian_correction.dart';
import '../models/child_correction.dart';
import '../models/guardian_registration.dart';
import '../models/guardian_invitation.dart';
import '../models/child_link_request.dart';
import '../services/mock_identifier_generator.dart';
import '../services/mock_scenario_clock.dart';
import 'child_repository.dart';

class MockChildRepository implements ChildRepository {
  static final List<ChildProfile> _guardianAccountChildren = [
    ChildProfile(
      id: 'CH-001',
      fullName: 'Sofia Santos',
      birthDate: DateTime(2025, 9, 14),
      sex: 'Female',
      qrIdentifier: 'QR-CH-001',
      relationship: 'Mother',
    ),
    ChildProfile(
      id: 'CH-002',
      fullName: 'Princess Santos',
      birthDate: DateTime(2023, 12, 24),
      sex: 'Female',
      qrIdentifier: 'QR-CH-002',
      relationship: 'Mother',
    ),
    ChildProfile(
      id: 'CH-003',
      fullName: 'Mateo Santos',
      birthDate: DateTime(2025, 12, 20),
      sex: 'Male',
      qrIdentifier: 'QR-CH-003',
      relationship: 'Mother',
    ),
    ChildProfile(
      id: 'CH-004',
      fullName: 'Miguel Reyes',
      birthDate: DateTime(2026, 4, 1),
      sex: 'Male',
      qrIdentifier: 'QR-CH-004',
      relationship: 'Aunt',
    ),
    ChildProfile(
      id: 'CH-005',
      fullName: 'Ana Cruz',
      birthDate: DateTime(2026, 3, 26),
      sex: 'Female',
      qrIdentifier: 'QR-CH-005',
      relationship: 'Aunt',
    ),
  ];
  static final List<ChildProfile> _registeredChildren = [
    ChildProfile(
      id: 'CH-2026-000101',
      fullName: 'Carlo Dela Cruz',
      birthDate: DateTime(2025, 1, 10),
      sex: 'Male',
      qrIdentifier: 'QR-CH-2026-000101',
      relationship: 'Mother',
    ),
    ChildProfile(
      id: 'CH-2026-000102',
      fullName: 'Lia Mendoza',
      birthDate: MockScenarioClock.daysAgo(42),
      sex: 'Female',
      qrIdentifier: 'QR-CH-2026-000102',
      relationship: 'Father',
    ),
    ChildProfile(
      id: 'CH-2026-000103',
      fullName: 'Noah Villanueva',
      birthDate: MockScenarioClock.daysAgo(16),
      sex: 'Male',
      qrIdentifier: 'QR-CH-2026-000103',
      relationship: 'Mother',
    ),
    ChildProfile(
      id: 'CH-2026-000104',
      fullName: 'Mia Fernandez',
      birthDate: MockScenarioClock.daysAgo(100),
      sex: 'Female',
      qrIdentifier: 'QR-CH-2026-000104',
      relationship: 'Grandmother',
    ),
    ChildProfile(
      id: 'CH-2026-000105',
      fullName: 'Isabella Navarro',
      birthDate: DateTime(2025, 11, 18),
      sex: 'Female',
      qrIdentifier: 'QR-CH-2026-000105',
      relationship: 'Mother',
    ),
  ];
  static final List<GuardianProfile> _registeredGuardians = [
    for (final data in const [
      (
        '00000000-0000-4000-8000-000000001101',
        'GRD-2026-000101',
        'Elena Dela Cruz',
      ),
      (
        '00000000-0000-4000-8000-000000001102',
        'GRD-2026-000102',
        'Paolo Mendoza',
      ),
      (
        '00000000-0000-4000-8000-000000001103',
        'GRD-2026-000103',
        'Grace Villanueva',
      ),
      (
        '00000000-0000-4000-8000-000000001104',
        'GRD-2026-000104',
        'Rosa Fernandez',
      ),
    ])
      GuardianProfile(
        id: data.$1,
        guardianCode: data.$2,
        fullName: data.$3,
        sex: data.$3 == 'Paolo Mendoza' ? 'Male' : 'Female',
        phoneNumber: switch (data.$3) {
          'Elena Dela Cruz' => '0917 000 0101',
          'Paolo Mendoza' => '0917 000 0102',
          'Grace Villanueva' => '0917 000 0103',
          _ => null,
        },
        address: 'Barangay Bugo, Cagayan de Oro City',
        hasUserAccount:
            data.$3 == 'Paolo Mendoza' || data.$3 == 'Grace Villanueva',
        userId: switch (data.$3) {
          'Paolo Mendoza' => 'USR-G-002',
          'Grace Villanueva' => 'USR-G-003',
          _ => null,
        },
        accessStatus: data.$3 == 'Elena Dela Cruz'
            ? GuardianAccessStatus.invitationPending
            : null,
        invitationCode: data.$3 == 'Elena Dela Cruz' ? 'ACT-000101' : null,
        invitationExpiresAt: data.$3 == 'Elena Dela Cruz'
            ? DateTime(2027, 1, 31)
            : null,
        registeredAt: DateTime(2026, 8, 20),
        registeredByUserId: '00000000-0000-4000-8000-000000000201',
      ),
    GuardianProfile(
      id: '00000000-0000-4000-8000-000000001100',
      guardianCode: 'GRD-2026-000100',
      fullName: 'Maria Santos',
      phoneNumber: '0917 000 0100',
      address: 'Barangay Bugo, Cagayan de Oro City',
      hasUserAccount: true,
      userId: 'USR-G-001',
      registeredAt: DateTime(2026, 7, 1),
      registeredByUserId: 'SELF-REGISTRATION',
    ),
    GuardianProfile(
      id: '00000000-0000-4000-8000-000000001105',
      guardianCode: 'GRD-2026-000105',
      fullName: 'Camille Navarro',
      phoneNumber: null,
      address: 'Barangay Bugo, Cagayan de Oro City',
      hasUserAccount: false,
      userId: null,
      registeredAt: DateTime(2026, 8, 25),
      registeredByUserId: 'USR-H-001',
    ),
  ];
  static final List<GuardianChildLink> _guardianLinks = [
    for (var index = 0; index < 4; index++)
      GuardianChildLink(
        id: '00000000-0000-4000-8000-${(1201 + index).toString().padLeft(12, '0')}',
        guardianId: _registeredGuardians[index].id,
        childId: _registeredChildren[index].id,
        relationship: _registeredChildren[index].relationship,
        isPrimaryGuardian: index != 3,
        authorizationConfirmed: true,
        linkedAt: DateTime(2026, 8, 20),
        linkedByUserId: '00000000-0000-4000-8000-000000000201',
      ),
    for (var index = 0; index < 5; index++)
      GuardianChildLink(
        id: '00000000-0000-4000-8000-${(1210 + index).toString().padLeft(12, '0')}',
        guardianId: '00000000-0000-4000-8000-000000001100',
        childId: _guardianAccountChildren[index].id,
        relationship: _guardianAccountChildren[index].relationship,
        isPrimaryGuardian: index < 3,
        authorizationConfirmed: true,
        linkedAt: DateTime(2026, 7, 1),
        linkedByUserId: 'SELF-REGISTRATION',
      ),
    GuardianChildLink(
      id: '00000000-0000-4000-8000-000000001220',
      guardianId: '00000000-0000-4000-8000-000000001105',
      childId: 'CH-2026-000105',
      relationship: 'Mother',
      isPrimaryGuardian: true,
      authorizationConfirmed: true,
      linkedAt: DateTime(2026, 8, 25),
      linkedByUserId: 'USR-H-001',
    ),
  ];
  static final List<GuardianCorrection> _guardianCorrections = [];
  static final List<ChildCorrection> _childCorrections = [];
  static final Map<String, GuardianInvitation> _guardianInvitations = {
    'ACT-000101': GuardianInvitation(
      id: '00000000-0000-4000-8300-000000000101',
      invitationCode: 'ACT-000101',
      guardianId: '00000000-0000-4000-8000-000000001101',
      channel: GuardianInvitationChannel.sms,
      destination: '0917 000 0101',
      maskedDestination: '09••••••101',
      status: GuardianInvitationStatus.delivered,
      createdAt: DateTime(2026, 8, 29, 8),
      deliveredAt: DateTime(2026, 8, 29, 8, 1),
      expiresAt: DateTime(2027, 1, 31),
      acceptedAt: null,
      createdByUserId: 'USR-H-001',
    ),
  };
  static final List<ChildLinkRequest> _childLinkRequests = [];

  static void _ensureSeededChildLinkRequests() {
    const requestId = '00000000-0000-4000-8700-000000000001';
    if (_childLinkRequests.any((request) => request.id == requestId)) return;
    _childLinkRequests.add(
      ChildLinkRequest(
        id: requestId,
        requestCode: 'CLR-2026-000001',
        guardianId: '00000000-0000-4000-8000-000000001103',
        guardianName: 'Grace Villanueva',
        childName: 'Lucas Villanueva',
        birthDate: DateTime(2026, 2, 12),
        sex: 'Male',
        relationship: 'Mother',
        status: ChildLinkRequestStatus.pending,
        submittedAt: DateTime(2026, 8, 29, 9, 15),
      ),
    );
  }

  static void _ensurePrototypeGuardianInvitation() {
    final index = _registeredGuardians.indexWhere(
      (guardian) => guardian.guardianCode == 'GRD-2026-000101',
    );
    if (index < 0) return;
    final guardian = _registeredGuardians[index];
    if (guardian.accessStatus == GuardianAccessStatus.healthWorkerManaged) {
      _registeredGuardians[index] = guardian.copyWith(
        phoneNumber: '0917 000 0101',
        hasUserAccount: false,
        accessStatus: GuardianAccessStatus.invitationPending,
        invitationCode: 'ACT-000101',
        invitationExpiresAt: DateTime(2027, 1, 31),
      );
    }
    if (_registeredGuardians[index].accessStatus ==
        GuardianAccessStatus.invitationPending) {
      _guardianInvitations.putIfAbsent(
        'ACT-000101',
        () => GuardianInvitation(
          id: '00000000-0000-4000-8300-000000000101',
          invitationCode: 'ACT-000101',
          guardianId: '00000000-0000-4000-8000-000000001101',
          channel: GuardianInvitationChannel.sms,
          destination: '0917 000 0101',
          maskedDestination: '09••••••101',
          status: GuardianInvitationStatus.delivered,
          createdAt: DateTime(2026, 8, 29, 8),
          deliveredAt: DateTime(2026, 8, 29, 8, 1),
          expiresAt: DateTime(2027, 1, 31),
          acceptedAt: null,
          createdByUserId: 'USR-H-001',
        ),
      );
    }
  }

  @override
  Future<List<ChildProfile>> getChildrenForGuardian(String guardianId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final guardian = _registeredGuardians.cast<GuardianProfile?>().firstWhere(
      (item) => item!.id == guardianId || item.userId == guardianId,
      orElse: () => null,
    );
    if (guardian == null) return const [];
    final childIds = _guardianLinks
        .where((link) => link.guardianId == guardian.id)
        .map((link) => link.childId)
        .toSet();
    return List.unmodifiable(
      [
        ..._guardianAccountChildren,
        ..._registeredChildren,
      ].where((child) => childIds.contains(child.id)),
    );
  }

  @override
  Future<ChildProfile?> findChildByIdentifier(String identifier) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final normalized = identifier.trim().toUpperCase();
    for (final child in [..._guardianAccountChildren, ..._registeredChildren]) {
      if (child.id.toUpperCase() == normalized ||
          child.qrIdentifier.toUpperCase() == normalized) {
        return child;
      }
    }
    return null;
  }

  @override
  Future<GuardianRegistrationResult> registerGuardianAndChild(
    GuardianRegistrationRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 650));
    if (request.children.isEmpty) {
      throw ArgumentError('At least one child is required.');
    }
    if (request.children.any(
      (child) => child.birthDate.isAfter(DateTime.now()),
    )) {
      throw ArgumentError('A child birth date cannot be in the future.');
    }
    final requestedChannel =
        request.invitationChannel ?? GuardianInvitationChannel.sms;
    if (request.createUserAccount &&
        requestedChannel == GuardianInvitationChannel.sms &&
        (request.phoneNumber == null || request.phoneNumber!.trim().isEmpty)) {
      throw ArgumentError('A mobile number is required for SMS delivery.');
    }
    if (request.createUserAccount &&
        requestedChannel == GuardianInvitationChannel.email &&
        (request.emailAddress == null ||
            request.emailAddress!.trim().isEmpty)) {
      throw ArgumentError('An email address is required for email delivery.');
    }
    final now = DateTime.now();
    final guardianIdentity = MockIdentifierGenerator.next(prefix: 'GRD');
    final invitationCode = request.createUserAccount
        ? 'ACT-${guardianIdentity.code.substring(guardianIdentity.code.length - 6)}'
        : null;
    final guardian = GuardianProfile(
      id: guardianIdentity.id,
      guardianCode: guardianIdentity.code,
      fullName: request.guardianName.trim(),
      firstName: request.guardianFirstName,
      middleName: request.guardianMiddleName,
      lastName: request.guardianLastName,
      suffix: request.guardianSuffix,
      birthDate: request.guardianBirthDate,
      sex: request.guardianSex,
      phoneNumber: request.phoneNumber?.trim().isEmpty == true
          ? null
          : request.phoneNumber?.trim(),
      emailAddress: request.emailAddress?.trim().isEmpty == true
          ? null
          : request.emailAddress?.trim(),
      address: request.address.trim(),
      hasUserAccount: false,
      accessStatus: request.createUserAccount
          ? GuardianAccessStatus.invitationPending
          : GuardianAccessStatus.healthWorkerManaged,
      invitationCode: invitationCode,
      invitationExpiresAt: request.createUserAccount
          ? now.add(const Duration(days: 7))
          : null,
      userId: null,
      registeredAt: now,
      registeredByUserId: request.registeredByUserId,
    );
    final children = <ChildProfile>[];
    final links = <GuardianChildLink>[];
    for (final input in request.children) {
      final childIdentity = MockIdentifierGenerator.next(prefix: 'CH');
      final linkIdentity = MockIdentifierGenerator.next(prefix: 'GCL');
      final child = ChildProfile(
        id: childIdentity.code,
        fullName: input.fullName.trim(),
        firstName: input.firstName,
        middleName: input.middleName,
        lastName: input.lastName,
        suffix: input.suffix,
        birthDate: input.birthDate,
        sex: input.sex,
        qrIdentifier: 'QR-${childIdentity.code}',
        relationship: input.relationship,
      );
      final link = GuardianChildLink(
        id: linkIdentity.id,
        guardianId: guardian.id,
        childId: child.id,
        relationship: input.relationship,
        isPrimaryGuardian:
            input.relationship == 'Mother' ||
            input.relationship == 'Father' ||
            input.relationship == 'Legal Guardian',
        authorizationConfirmed: request.authorizationConfirmed,
        linkedAt: now,
        linkedByUserId: request.registeredByUserId,
      );
      children.add(child);
      links.add(link);
    }
    _registeredGuardians.add(guardian);
    _registeredChildren.addAll(children);
    _guardianLinks.addAll(links);
    GuardianInvitation? invitation;
    if (request.createUserAccount) {
      final channel = requestedChannel;
      final destination = switch (channel) {
        GuardianInvitationChannel.sms => guardian.phoneNumber ?? '',
        GuardianInvitationChannel.email => guardian.emailAddress ?? '',
        GuardianInvitationChannel.printedSlip => 'Printed activation slip',
      };
      if (destination.isEmpty) {
        throw ArgumentError(
          channel == GuardianInvitationChannel.sms
              ? 'A mobile number is required for SMS delivery.'
              : 'An email address is required for email delivery.',
        );
      }
      final invitationIdentity = MockIdentifierGenerator.next(prefix: 'GINV');
      invitation = GuardianInvitation(
        id: invitationIdentity.id,
        invitationCode: invitationCode!,
        guardianId: guardian.id,
        channel: channel,
        destination: destination,
        maskedDestination: _maskDestination(channel, destination),
        status: GuardianInvitationStatus.delivered,
        createdAt: now,
        deliveredAt: now,
        expiresAt: guardian.invitationExpiresAt!,
        acceptedAt: null,
        createdByUserId: request.registeredByUserId,
      );
      _guardianInvitations[invitation.invitationCode] = invitation;
    }
    return GuardianRegistrationResult(
      guardian: guardian,
      children: List.unmodifiable(children),
      links: List.unmodifiable(links),
      invitation: invitation,
    );
  }

  @override
  Future<List<RegisteredFamily>> getHealthWorkerRegisteredFamilies() async {
    await Future.delayed(const Duration(milliseconds: 350));
    _ensurePrototypeGuardianInvitation();
    return _registeredGuardians.reversed
        .map((guardian) {
          final links = _guardianLinks
              .where((link) => link.guardianId == guardian.id)
              .toList(growable: false);
          final childIds = links.map((link) => link.childId).toSet();
          final children = [..._guardianAccountChildren, ..._registeredChildren]
              .where((child) => childIds.contains(child.id))
              .toList(growable: false);
          return RegisteredFamily(
            guardian: guardian,
            children: children,
            links: links,
            invitation: _guardianInvitations.values
                .where((item) => item.guardianId == guardian.id)
                .lastOrNull,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<ExistingGuardianChildResult> addChildToExistingGuardian(
    ExistingGuardianChildRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 550));
    if (!_registeredGuardians.any((item) => item.id == request.guardianId)) {
      throw StateError('The guardian record was not found.');
    }
    if (!request.authorizationConfirmed) {
      throw StateError('Guardian authorization must be confirmed.');
    }
    if (request.child.birthDate.isAfter(DateTime.now())) {
      throw ArgumentError('A child birth date cannot be in the future.');
    }
    final duplicate = _registeredChildren.any(
      (item) =>
          item.fullName.toLowerCase() == request.child.fullName.toLowerCase() &&
          item.birthDate.year == request.child.birthDate.year &&
          item.birthDate.month == request.child.birthDate.month &&
          item.birthDate.day == request.child.birthDate.day,
    );
    if (duplicate) {
      throw StateError('A matching child record already exists.');
    }
    final childIdentity = MockIdentifierGenerator.next(prefix: 'CH');
    final linkIdentity = MockIdentifierGenerator.next(prefix: 'GCL');
    final child = ChildProfile(
      id: childIdentity.code,
      fullName: request.child.fullName.trim(),
      birthDate: request.child.birthDate,
      sex: request.child.sex,
      qrIdentifier: 'QR-${childIdentity.code}',
      relationship: request.child.relationship,
    );
    final link = GuardianChildLink(
      id: linkIdentity.id,
      guardianId: request.guardianId,
      childId: child.id,
      relationship: request.child.relationship,
      isPrimaryGuardian:
          request.child.relationship == 'Mother' ||
          request.child.relationship == 'Father' ||
          request.child.relationship == 'Legal Guardian',
      authorizationConfirmed: true,
      linkedAt: DateTime.now(),
      linkedByUserId: request.registeredByUserId,
    );
    _registeredChildren.add(child);
    _guardianLinks.add(link);
    return ExistingGuardianChildResult(child: child, link: link);
  }

  GuardianProfile? _guardianForUser(String userId) =>
      _registeredGuardians.cast<GuardianProfile?>().firstWhere(
        (guardian) => guardian!.userId == userId || guardian.id == userId,
        orElse: () => null,
      );

  @override
  Future<GuardianProfile?> findGuardianById(String guardianId) async =>
      _registeredGuardians.cast<GuardianProfile?>().firstWhere(
        (guardian) =>
            guardian!.id == guardianId || guardian.userId == guardianId,
        orElse: () => null,
      );

  @override
  Future<List<ChildLinkRequest>> getGuardianChildLinkRequests(
    String guardianUserId,
  ) async {
    _ensureSeededChildLinkRequests();
    final guardian = _guardianForUser(guardianUserId);
    if (guardian == null) return const [];
    return _childLinkRequests
        .where((request) => request.guardianId == guardian.id)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  @override
  Future<List<ChildLinkRequest>> getPendingChildLinkRequests() async {
    _ensureSeededChildLinkRequests();
    return _childLinkRequests
        .where((request) => request.status == ChildLinkRequestStatus.pending)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  @override
  Future<ChildLinkRequest> submitChildLinkRequest(
    SubmitChildLinkRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 450));
    final guardian = _guardianForUser(request.guardianUserId);
    if (guardian == null) throw StateError('Guardian account was not found.');
    if (request.childName.trim().isEmpty) {
      throw ArgumentError('Child name is required.');
    }
    if (request.birthDate.isAfter(DateTime.now())) {
      throw ArgumentError('Birth date cannot be in the future.');
    }
    final duplicatePending = _childLinkRequests.any(
      (item) =>
          item.guardianId == guardian.id &&
          item.status == ChildLinkRequestStatus.pending &&
          item.childName.toLowerCase() ==
              request.childName.trim().toLowerCase() &&
          item.birthDate.year == request.birthDate.year &&
          item.birthDate.month == request.birthDate.month &&
          item.birthDate.day == request.birthDate.day,
    );
    if (duplicatePending) {
      throw StateError('A matching request is already pending review.');
    }
    final identity = MockIdentifierGenerator.next(prefix: 'CLR');
    final result = ChildLinkRequest(
      id: identity.id,
      requestCode: identity.code,
      guardianId: guardian.id,
      guardianName: guardian.fullName,
      childName: request.childName.trim(),
      birthDate: request.birthDate,
      sex: request.sex,
      relationship: request.relationship,
      status: ChildLinkRequestStatus.pending,
      submittedAt: DateTime.now(),
    );
    _childLinkRequests.add(result);
    return result;
  }

  @override
  Future<ChildLinkRequest> reviewChildLinkRequest({
    required String requestId,
    required bool approve,
    required String reviewedByUserId,
    required String reviewNotes,
  }) async {
    _ensureSeededChildLinkRequests();
    final index = _childLinkRequests.indexWhere((item) => item.id == requestId);
    if (index < 0) throw StateError('Child request was not found.');
    final current = _childLinkRequests[index];
    if (current.status != ChildLinkRequestStatus.pending) {
      throw StateError('This request has already been reviewed.');
    }
    String? linkedChildId;
    if (approve) {
      final result = await addChildToExistingGuardian(
        ExistingGuardianChildRequest(
          guardianId: current.guardianId,
          child: ChildRegistrationInput(
            fullName: current.childName,
            birthDate: current.birthDate,
            sex: current.sex,
            relationship: current.relationship,
          ),
          authorizationConfirmed: true,
          registeredByUserId: reviewedByUserId,
        ),
      );
      linkedChildId = result.child.id;
    } else if (reviewNotes.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }
    final reviewed = current.copyWith(
      status: approve
          ? ChildLinkRequestStatus.approved
          : ChildLinkRequestStatus.rejected,
      reviewedAt: DateTime.now(),
      reviewedByUserId: reviewedByUserId,
      reviewNotes: reviewNotes.trim(),
      linkedChildId: linkedChildId,
    );
    _childLinkRequests[index] = reviewed;
    return reviewed;
  }

  @override
  Future<GuardianCorrectionResult> correctGuardian(
    GuardianCorrectionRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _registeredGuardians.indexWhere(
      (item) => item.id == request.guardianId,
    );
    if (index < 0) throw StateError('The guardian record was not found.');
    if (request.reason.trim().isEmpty) {
      throw ArgumentError('A correction reason is required.');
    }
    final current = _registeredGuardians[index];
    final normalizedPhone = request.phoneNumber?.trim();
    final requestingOnlineAccess = request.hasUserAccount;
    final remainsActive =
        current.accessStatus == GuardianAccessStatus.activeGuardianAccount &&
        requestingOnlineAccess;
    final updated = current.copyWith(
      fullName: request.fullName.trim(),
      firstName: request.firstName,
      middleName: request.middleName,
      lastName: request.lastName,
      suffix: request.suffix,
      birthDate: request.birthDate,
      sex: request.sex,
      phoneNumber: normalizedPhone,
      clearPhoneNumber: normalizedPhone == null || normalizedPhone.isEmpty,
      address: request.address.trim(),
      hasUserAccount: remainsActive,
      accessStatus: requestingOnlineAccess
          ? remainsActive
                ? GuardianAccessStatus.activeGuardianAccount
                : GuardianAccessStatus.invitationPending
          : GuardianAccessStatus.healthWorkerManaged,
      invitationCode: requestingOnlineAccess && !remainsActive
          ? current.invitationCode ??
                'ACT-${current.guardianCode.substring(current.guardianCode.length - 6)}'
          : null,
      clearInvitationCode: !requestingOnlineAccess || remainsActive,
      invitationExpiresAt: requestingOnlineAccess && !remainsActive
          ? DateTime.now().add(const Duration(days: 7))
          : null,
      clearInvitationExpiry: !requestingOnlineAccess || remainsActive,
      userId: remainsActive ? current.userId : null,
      clearUserId: !remainsActive,
    );
    final identity = MockIdentifierGenerator.next(prefix: 'GCOR');
    final correction = GuardianCorrection(
      id: identity.id,
      correctionCode: identity.code,
      guardianId: current.id,
      previousValues: current.toJson(),
      updatedValues: updated.toJson(),
      reason: request.reason.trim(),
      correctedAt: DateTime.now(),
      correctedByUserId: request.correctedByUserId,
    );
    _registeredGuardians[index] = updated;
    _guardianCorrections.add(correction);
    return GuardianCorrectionResult(guardian: updated, correction: correction);
  }

  @override
  Future<ChildCorrectionResult> correctChild(
    ChildCorrectionRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    var target = _registeredChildren;
    var index = target.indexWhere((item) => item.id == request.childId);
    if (index < 0) {
      target = _guardianAccountChildren;
      index = target.indexWhere((item) => item.id == request.childId);
    }
    if (index < 0) throw StateError('The child record was not found.');
    if (request.birthDate.isAfter(DateTime.now())) {
      throw ArgumentError('A child birth date cannot be in the future.');
    }
    if (request.reason.trim().isEmpty) {
      throw ArgumentError('A correction reason is required.');
    }
    final current = target[index];
    final updated = current.copyWith(
      fullName: request.fullName.trim(),
      birthDate: request.birthDate,
      sex: request.sex,
      relationship: request.relationship,
    );
    final identity = MockIdentifierGenerator.next(prefix: 'CCOR');
    final correction = ChildCorrection(
      id: identity.id,
      correctionCode: identity.code,
      childId: current.id,
      previousValues: current.toJson(),
      updatedValues: updated.toJson(),
      reason: request.reason.trim(),
      correctedAt: DateTime.now(),
      correctedByUserId: request.correctedByUserId,
    );
    target[index] = updated;
    final linkIndex = _guardianLinks.indexWhere(
      (link) => link.childId == current.id,
    );
    if (linkIndex >= 0 &&
        _guardianLinks[linkIndex].relationship != request.relationship) {
      final link = _guardianLinks[linkIndex];
      _guardianLinks[linkIndex] = GuardianChildLink(
        id: link.id,
        guardianId: link.guardianId,
        childId: link.childId,
        relationship: request.relationship,
        isPrimaryGuardian:
            request.relationship == 'Mother' ||
            request.relationship == 'Father' ||
            request.relationship == 'Legal Guardian',
        authorizationConfirmed: link.authorizationConfirmed,
        linkedAt: link.linkedAt,
        linkedByUserId: link.linkedByUserId,
      );
    }
    _childCorrections.add(correction);
    return ChildCorrectionResult(child: updated, correction: correction);
  }

  @override
  Future<GuardianProfile> activateGuardianInvitation({
    required String invitationCode,
    required String userId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 450));
    _ensurePrototypeGuardianInvitation();
    final index = _registeredGuardians.indexWhere(
      (guardian) =>
          guardian.invitationCode?.toUpperCase() ==
          invitationCode.trim().toUpperCase(),
    );
    if (index < 0) throw StateError('The activation code is invalid.');
    final guardian = _registeredGuardians[index];
    if (guardian.accessStatus != GuardianAccessStatus.invitationPending) {
      throw StateError('This invitation is no longer pending.');
    }
    if (guardian.invitationExpiresAt == null ||
        guardian.invitationExpiresAt!.isBefore(DateTime.now())) {
      _registeredGuardians[index] = guardian.copyWith(
        hasUserAccount: false,
        accessStatus: GuardianAccessStatus.invitationExpired,
        clearInvitationCode: true,
        clearInvitationExpiry: true,
      );
      final expiredInvitation =
          _guardianInvitations[invitationCode.trim().toUpperCase()];
      if (expiredInvitation != null) {
        _guardianInvitations[expiredInvitation.invitationCode] =
            expiredInvitation.copyWith(
              status: GuardianInvitationStatus.expired,
            );
      }
      throw StateError('The activation invitation has expired.');
    }
    final activated = guardian.copyWith(
      hasUserAccount: true,
      accessStatus: GuardianAccessStatus.activeGuardianAccount,
      userId: userId,
      clearInvitationCode: true,
      clearInvitationExpiry: true,
    );
    _registeredGuardians[index] = activated;
    final invitation =
        _guardianInvitations[invitationCode.trim().toUpperCase()];
    if (invitation != null) {
      _guardianInvitations[invitation.invitationCode] = invitation.copyWith(
        status: GuardianInvitationStatus.accepted,
        acceptedAt: DateTime.now(),
      );
    }
    return activated;
  }

  static String _maskDestination(
    GuardianInvitationChannel channel,
    String destination,
  ) {
    if (channel == GuardianInvitationChannel.printedSlip) return destination;
    if (channel == GuardianInvitationChannel.email) {
      final parts = destination.split('@');
      if (parts.length != 2) return '••••';
      final local = parts.first;
      final visible = local.isEmpty ? '' : local.substring(0, 1);
      return '$visible•••@${parts.last}';
    }
    final compact = destination.replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 4) return '••••';
    return '${compact.substring(0, 2)}••••••${compact.substring(compact.length - 3)}';
  }
}
