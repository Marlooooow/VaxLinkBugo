enum AppointmentSlotOfferStatus { pending, accepted, declined, expired }

class AppointmentSlotOffer {
  final String id;
  final String offerCode;
  final String appointmentId;
  final String guardianId;
  final String childId;
  final String childName;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime currentAppointmentDate;
  final DateTime offeredAppointmentDate;
  final AppointmentSlotOfferStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final String? respondedByUserId;
  final String responseChannel;
  final String queueReason;

  const AppointmentSlotOffer({
    this.respondedByUserId,
    this.responseChannel = 'guardian_online',
    this.queueReason = 'Earliest eligible waiting-list entry',
    required this.id,
    required this.offerCode,
    required this.appointmentId,
    required this.guardianId,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.currentAppointmentDate,
    required this.offeredAppointmentDate,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.respondedAt,
  });

  AppointmentSlotOffer copyWith({
    AppointmentSlotOfferStatus? status,
    DateTime? respondedAt,
    String? respondedByUserId,
    String? responseChannel,
  }) => AppointmentSlotOffer(
    respondedByUserId: respondedByUserId ?? this.respondedByUserId,
    responseChannel: responseChannel ?? this.responseChannel,
    queueReason: queueReason,
    id: id,
    offerCode: offerCode,
    appointmentId: appointmentId,
    guardianId: guardianId,
    childId: childId,
    childName: childName,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    doseNumber: doseNumber,
    currentAppointmentDate: currentAppointmentDate,
    offeredAppointmentDate: offeredAppointmentDate,
    status: status ?? this.status,
    createdAt: createdAt,
    expiresAt: expiresAt,
    respondedAt: respondedAt ?? this.respondedAt,
  );

  factory AppointmentSlotOffer.fromJson(
    Map<String, dynamic> json,
  ) => AppointmentSlotOffer(
    respondedByUserId: json['responded_by_user_id'] as String?,
    responseChannel: json['response_channel'] as String? ?? 'guardian_online',
    queueReason:
        json['queue_reason'] as String? ??
        'Earliest eligible waiting-list entry',
    id: json['id'] as String,
    offerCode: json['offer_code'] as String,
    appointmentId: json['appointment_id'] as String,
    guardianId: json['guardian_id'] as String,
    childId: json['child_id'] as String,
    childName: json['child_name'] as String,
    vaccineId: json['vaccine_id'] as String,
    vaccineName: json['vaccine_name'] as String,
    doseNumber: json['dose_number'] as int,
    currentAppointmentDate: DateTime.parse(
      json['current_appointment_date'] as String,
    ),
    offeredAppointmentDate: DateTime.parse(
      json['offered_appointment_date'] as String,
    ),
    status: AppointmentSlotOfferStatus.values.byName(json['status'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    respondedAt: json['responded_at'] == null
        ? null
        : DateTime.parse(json['responded_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'responded_by_user_id': respondedByUserId,
    'response_channel': responseChannel,
    'queue_reason': queueReason,
    'id': id,
    'offer_code': offerCode,
    'appointment_id': appointmentId,
    'guardian_id': guardianId,
    'child_id': childId,
    'child_name': childName,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'dose_number': doseNumber,
    'current_appointment_date': currentAppointmentDate.toIso8601String(),
    'offered_appointment_date': offeredAppointmentDate.toIso8601String(),
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'responded_at': respondedAt?.toIso8601String(),
  };
}
