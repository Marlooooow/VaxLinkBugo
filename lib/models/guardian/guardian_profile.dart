enum GuardianAccessStatus {
  healthWorkerManaged,
  invitationPending,
  activeGuardianAccount,
  invitationExpired,
  accessDeclined,
  accessDisabled,
}

class GuardianProfile {
  final String id;
  final String guardianCode;
  final String fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final DateTime? birthDate;
  final String sex;
  final String? phoneNumber;
  final String? emailAddress;
  final String address;
  final bool hasUserAccount;
  final GuardianAccessStatus accessStatus;
  final String? invitationCode;
  final DateTime? invitationExpiresAt;
  final String? userId;
  final DateTime registeredAt;
  final String registeredByUserId;
  final String? registeredByName;

  const GuardianProfile({
    required this.id,
    required this.guardianCode,
    required this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.birthDate,
    this.sex = 'Female',
    required this.phoneNumber,
    this.emailAddress,
    required this.address,
    required this.hasUserAccount,
    GuardianAccessStatus? accessStatus,
    this.invitationCode,
    this.invitationExpiresAt,
    required this.userId,
    required this.registeredAt,
    required this.registeredByUserId,
    this.registeredByName,
  }) : accessStatus =
           accessStatus ??
           (hasUserAccount
               ? GuardianAccessStatus.activeGuardianAccount
               : GuardianAccessStatus.healthWorkerManaged);

  String get accessLabel => switch (accessStatus) {
    GuardianAccessStatus.healthWorkerManaged => 'Health-worker managed',
    GuardianAccessStatus.invitationPending => 'Invitation pending',
    GuardianAccessStatus.activeGuardianAccount => 'Guardian account',
    GuardianAccessStatus.invitationExpired => 'Invitation expired',
    GuardianAccessStatus.accessDeclined => 'Online access declined',
    GuardianAccessStatus.accessDisabled => 'Online access disabled',
  };

  GuardianProfile copyWith({
    String? fullName,
    String? firstName,
    String? middleName,
    String? lastName,
    String? suffix,
    DateTime? birthDate,
    String? sex,
    String? phoneNumber,
    bool clearPhoneNumber = false,
    String? emailAddress,
    bool clearEmailAddress = false,
    String? address,
    bool? hasUserAccount,
    GuardianAccessStatus? accessStatus,
    String? invitationCode,
    bool clearInvitationCode = false,
    DateTime? invitationExpiresAt,
    bool clearInvitationExpiry = false,
    String? userId,
    bool clearUserId = false,
    String? registeredByName,
  }) => GuardianProfile(
    id: id,
    guardianCode: guardianCode,
    fullName: fullName ?? this.fullName,
    firstName: firstName ?? this.firstName,
    middleName: middleName ?? this.middleName,
    lastName: lastName ?? this.lastName,
    suffix: suffix ?? this.suffix,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
    phoneNumber: clearPhoneNumber ? null : phoneNumber ?? this.phoneNumber,
    emailAddress: clearEmailAddress ? null : emailAddress ?? this.emailAddress,
    address: address ?? this.address,
    hasUserAccount: hasUserAccount ?? this.hasUserAccount,
    accessStatus: accessStatus ?? this.accessStatus,
    invitationCode: clearInvitationCode
        ? null
        : invitationCode ?? this.invitationCode,
    invitationExpiresAt: clearInvitationExpiry
        ? null
        : invitationExpiresAt ?? this.invitationExpiresAt,
    userId: clearUserId ? null : userId ?? this.userId,
    registeredAt: registeredAt,
    registeredByUserId: registeredByUserId,
    registeredByName: registeredByName ?? this.registeredByName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'guardian_code': guardianCode,
    'full_name': fullName,
    'first_name': firstName,
    'middle_name': middleName,
    'last_name': lastName,
    'suffix': suffix,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'sex': sex,
    'phone_number': phoneNumber,
    'email_address': emailAddress,
    'address': address,
    'has_user_account': hasUserAccount,
    'access_status': accessStatus.name,
    'invitation_code': invitationCode,
    'invitation_expires_at': invitationExpiresAt?.toIso8601String(),
    'user_id': userId,
    'registered_at': registeredAt.toIso8601String(),
    'registered_by_user_id': registeredByUserId,
    'registered_by_name': registeredByName,
  };
}

class GuardianChildLink {
  final String id;
  final String guardianId;
  final String childId;
  final String relationship;
  final bool isPrimaryGuardian;
  final bool authorizationConfirmed;
  final DateTime linkedAt;
  final String linkedByUserId;

  const GuardianChildLink({
    required this.id,
    required this.guardianId,
    required this.childId,
    required this.relationship,
    required this.isPrimaryGuardian,
    required this.authorizationConfirmed,
    required this.linkedAt,
    required this.linkedByUserId,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'guardian_id': guardianId,
    'child_id': childId,
    'relationship': relationship,
    'is_primary_guardian': isPrimaryGuardian,
    'authorization_confirmed': authorizationConfirmed,
    'linked_at': linkedAt.toIso8601String(),
    'linked_by_user_id': linkedByUserId,
  };
}
