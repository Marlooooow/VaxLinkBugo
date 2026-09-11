enum VaccinationSource { bugo, externalReferral, previousRecord, outreach }

class VaccinationRecord {
  final String id;
  final String recordCode;
  final String childId;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime dateAdministered;
  final String administeringFacility;
  final String healthWorkerName;
  final String? healthWorkerId;
  final VaccinationSource source;
  final String? referralId;
  final String? externalVisitId;
  final String notes;
  final DateTime recordedAt;
  final String? recordedByUserId;
  final String? screeningId;
  final String? evidenceType;

  const VaccinationRecord({
    required this.id,
    required this.recordCode,
    required this.childId,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.dateAdministered,
    required this.administeringFacility,
    required this.healthWorkerName,
    required this.source,
    required this.notes,
    required this.recordedAt,
    this.healthWorkerId,
    this.referralId,
    this.externalVisitId,
    this.recordedByUserId,
    this.screeningId,
    this.evidenceType,
  });

  String get vaccine => vaccineName;
  String get dose => 'Dose $doseNumber';
  DateTime get dateGiven => dateAdministered;
  String get healthCenter => administeringFacility;

  VaccinationRecord copyWith({
    DateTime? dateAdministered,
    String? administeringFacility,
    String? healthWorkerName,
    String? notes,
  }) => VaccinationRecord(
    id: id,
    recordCode: recordCode,
    childId: childId,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    doseNumber: doseNumber,
    dateAdministered: dateAdministered ?? this.dateAdministered,
    administeringFacility: administeringFacility ?? this.administeringFacility,
    healthWorkerName: healthWorkerName ?? this.healthWorkerName,
    healthWorkerId: healthWorkerId,
    source: source,
    referralId: referralId,
    externalVisitId: externalVisitId,
    notes: notes ?? this.notes,
    recordedAt: recordedAt,
    recordedByUserId: recordedByUserId,
    screeningId: screeningId,
    evidenceType: evidenceType,
  );

  factory VaccinationRecord.fromJson(Map<String, dynamic> json) {
    return VaccinationRecord(
      id: json['id'] as String,
      recordCode: json['record_code'] as String,
      childId: json['child_id'] as String,
      vaccineId: json['vaccine_id'] as String,
      vaccineName: json['vaccine_name'] as String,
      doseNumber: json['dose_number'] as int,
      dateAdministered: DateTime.parse(json['date_administered'] as String),
      administeringFacility: json['administering_facility'] as String,
      healthWorkerName: json['health_worker_name'] as String,
      healthWorkerId: json['health_worker_id'] as String?,
      source: VaccinationSource.values.byName(json['source'] as String),
      referralId: json['referral_id'] as String?,
      externalVisitId: json['external_visit_id'] as String?,
      notes: json['notes'] as String? ?? '',
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      recordedByUserId: json['recorded_by_user_id'] as String?,
      screeningId: json['screening_id'] as String?,
      evidenceType: json['evidence_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'record_code': recordCode,
    'child_id': childId,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'dose_number': doseNumber,
    'date_administered': dateAdministered.toIso8601String(),
    'administering_facility': administeringFacility,
    'health_worker_name': healthWorkerName,
    'health_worker_id': healthWorkerId,
    'source': source.name,
    'referral_id': referralId,
    'external_visit_id': externalVisitId,
    'notes': notes,
    'recorded_at': recordedAt.toIso8601String(),
    'recorded_by_user_id': recordedByUserId,
    'screening_id': screeningId,
    'evidence_type': evidenceType,
  };
}
