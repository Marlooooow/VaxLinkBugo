import 'external_vaccination_record.dart';

class ExternalVaccinationVisit {
  final String externalVisitId;
  final String visitCode;
  final String referralGroupId;
  final String childId;
  final DateTime dateAdministered;
  final String administeringFacility;
  final String healthWorkerName;
  final String notes;
  final DateTime recordedAt;
  final String? recordedBy;
  final bool documentVerified;
  final String? verifiedByUserId;
  final DateTime? verifiedAt;
  final String? verificationMethod;
  final String? signedDocumentPath;
  final List<ExternalVaccinationRecord> records;

  const ExternalVaccinationVisit({
    required this.externalVisitId,
    required this.visitCode,
    required this.referralGroupId,
    required this.childId,
    required this.dateAdministered,
    required this.administeringFacility,
    required this.healthWorkerName,
    required this.notes,
    required this.recordedAt,
    required this.records,
    this.recordedBy,
    this.documentVerified = false,
    this.verifiedByUserId,
    this.verifiedAt,
    this.verificationMethod,
    this.signedDocumentPath,
  });

  ExternalVaccinationVisit copyWith({
    DateTime? dateAdministered,
    String? administeringFacility,
    String? healthWorkerName,
    String? notes,
    List<ExternalVaccinationRecord>? records,
  }) {
    return ExternalVaccinationVisit(
      externalVisitId: externalVisitId,
      visitCode: visitCode,
      referralGroupId: referralGroupId,
      childId: childId,
      dateAdministered: dateAdministered ?? this.dateAdministered,
      administeringFacility:
          administeringFacility ?? this.administeringFacility,
      healthWorkerName: healthWorkerName ?? this.healthWorkerName,
      notes: notes ?? this.notes,
      recordedAt: recordedAt,
      recordedBy: recordedBy,
      documentVerified: documentVerified,
      verifiedByUserId: verifiedByUserId,
      verifiedAt: verifiedAt,
      verificationMethod: verificationMethod,
      signedDocumentPath: signedDocumentPath,
      records: records ?? this.records,
    );
  }

  factory ExternalVaccinationVisit.fromJson(
    Map<String, dynamic> json, {
    List<ExternalVaccinationRecord> records = const [],
  }) {
    return ExternalVaccinationVisit(
      externalVisitId: json['external_visit_id'] as String,
      visitCode: json['visit_code'] as String,
      referralGroupId: json['referral_group_id'] as String,
      childId: json['child_id'] as String,
      dateAdministered: DateTime.parse(json['date_administered'] as String),
      administeringFacility: json['administering_facility'] as String,
      healthWorkerName: json['health_worker_name'] as String,
      notes: json['notes'] as String? ?? '',
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      recordedBy: json['recorded_by'] as String?,
      documentVerified: json['document_verified'] as bool? ?? false,
      verifiedByUserId: json['verified_by_user_id'] as String?,
      verifiedAt: json['verified_at'] == null
          ? null
          : DateTime.parse(json['verified_at'] as String),
      verificationMethod: json['verification_method'] as String?,
      signedDocumentPath: json['signed_document_path'] as String?,
      records: records,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'external_visit_id': externalVisitId,
      'visit_code': visitCode,
      'referral_group_id': referralGroupId,
      'child_id': childId,
      'date_administered': dateAdministered.toIso8601String(),
      'administering_facility': administeringFacility,
      'health_worker_name': healthWorkerName,
      'notes': notes,
      'recorded_at': recordedAt.toIso8601String(),
      'recorded_by': recordedBy,
      'document_verified': documentVerified,
      'verified_by_user_id': verifiedByUserId,
      'verified_at': verifiedAt?.toIso8601String(),
      'verification_method': verificationMethod,
      'signed_document_path': signedDocumentPath,
    };
  }
}
