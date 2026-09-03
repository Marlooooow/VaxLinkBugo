enum PnipDoseStatus { completed, due, upcoming, overdue, notEligible }

class PnipScheduleEntry {
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime scheduledDate;
  final PnipDoseStatus status;
  final DateTime? administeredDate;
  final String? vaccinationRecordId;

  const PnipScheduleEntry({
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.scheduledDate,
    required this.status,
    this.administeredDate,
    this.vaccinationRecordId,
  });

  bool get requiresAction =>
      status == PnipDoseStatus.due || status == PnipDoseStatus.overdue;

  factory PnipScheduleEntry.fromJson(Map<String, dynamic> json) {
    return PnipScheduleEntry(
      vaccineId: json['vaccine_id'] as String,
      vaccineName: json['vaccine_name'] as String,
      doseNumber: json['dose_number'] as int,
      scheduledDate: DateTime.parse(json['scheduled_date'] as String),
      status: PnipDoseStatus.values.byName(json['status'] as String),
      administeredDate: json['administered_date'] == null
          ? null
          : DateTime.parse(json['administered_date'] as String),
      vaccinationRecordId: json['vaccination_record_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'dose_number': doseNumber,
    'scheduled_date': scheduledDate.toIso8601String(),
    'status': status.name,
    'administered_date': administeredDate?.toIso8601String(),
    'vaccination_record_id': vaccinationRecordId,
  };
}
