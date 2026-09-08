import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';

class ChildCorrectionRequest {
  final String childId;
  final String? guardianId;
  final String fullName;
  final DateTime birthDate;
  final String sex;
  final String relationship;
  final String reason;
  final String correctedByUserId;

  const ChildCorrectionRequest({
    required this.childId,
    this.guardianId,
    required this.fullName,
    required this.birthDate,
    required this.sex,
    required this.relationship,
    required this.reason,
    required this.correctedByUserId,
  });
}

class ChildCorrection {
  final String id;
  final String correctionCode;
  final String childId;
  final Map<String, Object?> previousValues;
  final Map<String, Object?> updatedValues;
  final String reason;
  final DateTime correctedAt;
  final String correctedByUserId;

  const ChildCorrection({
    required this.id,
    required this.correctionCode,
    required this.childId,
    required this.previousValues,
    required this.updatedValues,
    required this.reason,
    required this.correctedAt,
    required this.correctedByUserId,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'correction_code': correctionCode,
    'child_id': childId,
    'previous_values': previousValues,
    'updated_values': updatedValues,
    'reason': reason,
    'corrected_at': correctedAt.toIso8601String(),
    'corrected_by_user_id': correctedByUserId,
  };
}

class ChildCorrectionResult {
  final ChildProfile child;
  final ChildCorrection correction;

  const ChildCorrectionResult({required this.child, required this.correction});
}
