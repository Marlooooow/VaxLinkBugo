import 'package:qr_code_based_pediatric_vaccination/models/person_name.dart';

enum StaffType { nurse, midwife, barangayHealthWorker, physician }

extension StaffTypeDisplay on StaffType {
  String get label => switch (this) {
    StaffType.nurse => 'Nurse',
    StaffType.midwife => 'Midwife',
    StaffType.barangayHealthWorker => 'Barangay Health Worker',
    StaffType.physician => 'Physician',
  };
}

enum StaffAccessStatus { invitationPending, active, disabled }

class StaffPage {
  final List<StaffMember> items;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;

  const StaffPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
  });
}

class StaffMember {
  final String id;
  final String staffCode;
  final String? profileId;
  final String fullName;
  final StaffType staffType;
  final String? licenseNumber;
  final String? phone;
  final String? email;
  final StaffAccessStatus status;
  final DateTime createdAt;

  const StaffMember({
    required this.id,
    required this.staffCode,
    required this.profileId,
    required this.fullName,
    required this.staffType,
    required this.licenseNumber,
    required this.phone,
    required this.email,
    required this.status,
    required this.createdAt,
  });

  String get typeLabel => staffType.label;

  String get statusLabel => switch (status) {
    StaffAccessStatus.invitationPending => 'Invitation pending',
    StaffAccessStatus.active => 'Active',
    StaffAccessStatus.disabled => 'Disabled',
  };
}

class StaffRegistrationRequest {
  final PersonName name;
  final StaffType staffType;
  final String? licenseNumber;
  final String? phone;
  final String? email;

  const StaffRegistrationRequest({
    required this.name,
    required this.staffType,
    this.licenseNumber,
    this.phone,
    this.email,
  });
}

class StaffInvitationResult {
  final StaffMember staff;
  final String activationCode;
  final DateTime expiresAt;

  const StaffInvitationResult({
    required this.staff,
    required this.activationCode,
    required this.expiresAt,
  });
}
