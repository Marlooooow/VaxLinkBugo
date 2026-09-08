import 'guardian_profile.dart';

class GuardianCorrectionRequest {
  final String guardianId;
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
  final String reason;
  final String correctedByUserId;

  const GuardianCorrectionRequest({
    required this.guardianId,
    required this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    this.birthDate,
    required this.sex,
    required this.phoneNumber,
    this.emailAddress,
    required this.address,
    required this.hasUserAccount,
    required this.reason,
    required this.correctedByUserId,
  });
}

class GuardianCorrection {
  final String id;
  final String correctionCode;
  final String guardianId;
  final Map<String, Object?> previousValues;
  final Map<String, Object?> updatedValues;
  final String reason;
  final DateTime correctedAt;
  final String correctedByUserId;

  const GuardianCorrection({
    required this.id,
    required this.correctionCode,
    required this.guardianId,
    required this.previousValues,
    required this.updatedValues,
    required this.reason,
    required this.correctedAt,
    required this.correctedByUserId,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'correction_code': correctionCode,
    'guardian_id': guardianId,
    'previous_values': previousValues,
    'updated_values': updatedValues,
    'reason': reason,
    'corrected_at': correctedAt.toIso8601String(),
    'corrected_by_user_id': correctedByUserId,
  };
}

class GuardianCorrectionResult {
  final GuardianProfile guardian;
  final GuardianCorrection correction;

  const GuardianCorrectionResult({
    required this.guardian,
    required this.correction,
  });
}
