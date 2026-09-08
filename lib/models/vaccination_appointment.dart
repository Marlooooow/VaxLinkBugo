enum VaccinationAppointmentStatus {
  scheduled,
  confirmed,
  checkedIn,
  completed,
  cancelled,
  noShow,
  rescheduled,
  waitlisted,
  referred,
}

enum VaccinationAppointmentSource {
  pnipReminder,
  stockDeferral,
  healthWorker,
  guardianRequest,
}

class VaccinationAppointment {
  final String id;
  final String appointmentCode;
  final String guardianId;
  final String? reminderId;
  final String childId;
  final String childName;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime pnipDueDate;
  final DateTime appointmentDate;
  final String facilityId;
  final String facilityName;
  final VaccinationAppointmentStatus status;
  final VaccinationAppointmentSource source;
  final String reason;
  final String? previousAppointmentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdByUserId;
  final int clinicalPriority;
  final DateTime? eligibleFrom;

  const VaccinationAppointment({
    this.clinicalPriority = 0,
    this.eligibleFrom,
    required this.id,
    required this.appointmentCode,
    required this.guardianId,
    required this.reminderId,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.pnipDueDate,
    required this.appointmentDate,
    required this.facilityId,
    required this.facilityName,
    required this.status,
    required this.source,
    required this.reason,
    required this.previousAppointmentId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByUserId,
  });

  VaccinationAppointment copyWith({
    VaccinationAppointmentStatus? status,
    DateTime? updatedAt,
  }) => VaccinationAppointment(
    clinicalPriority: clinicalPriority,
    eligibleFrom: eligibleFrom,
    id: id,
    appointmentCode: appointmentCode,
    guardianId: guardianId,
    reminderId: reminderId,
    childId: childId,
    childName: childName,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    doseNumber: doseNumber,
    pnipDueDate: pnipDueDate,
    appointmentDate: appointmentDate,
    facilityId: facilityId,
    facilityName: facilityName,
    status: status ?? this.status,
    source: source,
    reason: reason,
    previousAppointmentId: previousAppointmentId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByUserId: createdByUserId,
  );

  factory VaccinationAppointment.fromJson(Map<String, dynamic> json) =>
      VaccinationAppointment(
        clinicalPriority: json['clinical_priority'] as int? ?? 0,
        eligibleFrom: json['eligible_from'] == null
            ? null
            : DateTime.parse(json['eligible_from'] as String),
        id: json['id'] as String,
        appointmentCode: json['appointment_code'] as String,
        guardianId: json['guardian_id'] as String,
        reminderId: json['reminder_id'] as String?,
        childId: json['child_id'] as String,
        childName: json['child_name'] as String,
        vaccineId: json['vaccine_id'] as String,
        vaccineName: json['vaccine_name'] as String,
        doseNumber: json['dose_number'] as int,
        pnipDueDate: DateTime.parse(json['pnip_due_date'] as String),
        appointmentDate: DateTime.parse(json['appointment_date'] as String),
        facilityId: json['facility_id'] as String,
        facilityName: json['facility_name'] as String,
        status: VaccinationAppointmentStatus.values.byName(
          json['status'] as String,
        ),
        source: VaccinationAppointmentSource.values.byName(
          json['source'] as String,
        ),
        reason: json['reason'] as String? ?? '',
        previousAppointmentId: json['previous_appointment_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        createdByUserId: json['created_by_user_id'] as String,
      );

  Map<String, dynamic> toJson() => {
    'clinical_priority': clinicalPriority,
    'eligible_from': eligibleFrom?.toIso8601String(),
    'id': id,
    'appointment_code': appointmentCode,
    'guardian_id': guardianId,
    'reminder_id': reminderId,
    'child_id': childId,
    'child_name': childName,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'dose_number': doseNumber,
    'pnip_due_date': pnipDueDate.toIso8601String(),
    'appointment_date': appointmentDate.toIso8601String(),
    'facility_id': facilityId,
    'facility_name': facilityName,
    'status': status.name,
    'source': source.name,
    'reason': reason,
    'previous_appointment_id': previousAppointmentId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'created_by_user_id': createdByUserId,
  };
}

class AppointmentPage {
  final List<VaccinationAppointment> items;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;

  const AppointmentPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
  });
}

class AppointmentRequest {
  final int clinicalPriority;
  final DateTime? eligibleFrom;
  final String guardianId;
  final String? reminderId;
  final String childId;
  final String childName;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime pnipDueDate;
  final DateTime appointmentDate;
  final VaccinationAppointmentSource source;
  final String reason;
  final String createdByUserId;

  const AppointmentRequest({
    this.clinicalPriority = 0,
    this.eligibleFrom,
    required this.guardianId,
    required this.reminderId,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.pnipDueDate,
    required this.appointmentDate,
    required this.source,
    required this.reason,
    required this.createdByUserId,
  });
}

class RescheduleAppointmentRequest {
  final String appointmentId;
  final DateTime newAppointmentDate;
  final String reason;
  final String rescheduledByUserId;

  const RescheduleAppointmentRequest({
    required this.appointmentId,
    required this.newAppointmentDate,
    required this.reason,
    required this.rescheduledByUserId,
  });
}
