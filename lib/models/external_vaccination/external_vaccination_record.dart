class ExternalVaccinationRecord {
  final String recordId;
  final String recordCode;
  final String referralId;
  final String externalVisitId;
  final String externalVisitCode;
  final String childId;
  final String vaccineId;
  final String vaccineAdministered;
  final DateTime dateAdministered;
  final String administeringFacility;
  final String healthWorkerName;
  final String notes;
  final DateTime recordedAt;
  final DateTime? updatedAt;
  final String? correctionReason;

  const ExternalVaccinationRecord({
    required this.recordId,
    required this.recordCode,
    required this.referralId,
    required this.externalVisitId,
    required this.externalVisitCode,
    required this.childId,
    required this.vaccineId,
    required this.vaccineAdministered,
    required this.dateAdministered,
    required this.administeringFacility,
    required this.healthWorkerName,
    required this.notes,
    required this.recordedAt,
    this.updatedAt,
    this.correctionReason,
  });

  factory ExternalVaccinationRecord.fromJson(Map<String, dynamic> json) {
    return ExternalVaccinationRecord(
      recordId: json['record_id'] as String,
      recordCode: json['record_code'] as String,
      referralId: json['referral_id'] as String,
      externalVisitId: json['external_visit_id'] as String,
      externalVisitCode: json['external_visit_code'] as String,
      childId: json['child_id'] as String,
      vaccineId: json['vaccine_id'] as String,
      vaccineAdministered: json['vaccine_administered'] as String,
      dateAdministered: DateTime.parse(json['date_administered'] as String),
      administeringFacility: json['administering_facility'] as String,
      healthWorkerName: json['health_worker_name'] as String,
      notes: json['notes'] as String? ?? '',
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      correctionReason: json['correction_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'record_id': recordId,
      'record_code': recordCode,
      'referral_id': referralId,
      'external_visit_id': externalVisitId,
      'external_visit_code': externalVisitCode,
      'child_id': childId,
      'vaccine_id': vaccineId,
      'vaccine_administered': vaccineAdministered,
      'date_administered': dateAdministered.toIso8601String(),
      'administering_facility': administeringFacility,
      'health_worker_name': healthWorkerName,
      'notes': notes,
      'recorded_at': recordedAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'correction_reason': correctionReason,
    };
  }
}
