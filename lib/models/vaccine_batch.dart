enum VaccineBatchStatus { usable, expiringSoon, expired, depleted }

enum VaccineBatchSafetyStatus { usable, quarantined, discarded }

enum VaccineVvmStatus { notApplicable, acceptable, notAcceptable, unknown }

class VaccineBatch {
  final String id;
  final String batchCode;
  final String facilityId;
  final String vaccineId;
  final String vaccineName;
  final String lotNumber;
  final String manufacturer;
  final DateTime expiryDate;
  final int quantityReceived;
  final int availableDoses;
  final DateTime receivedAt;
  final String receivedByUserId;
  final bool packagingIntact;
  final bool coldChainVerified;
  final VaccineVvmStatus vvmStatus;
  final VaccineBatchSafetyStatus safetyStatus;
  final String safetyNotes;
  final DateTime safetyReviewedAt;
  final String safetyReviewedByUserId;

  const VaccineBatch({
    required this.id,
    required this.batchCode,
    required this.facilityId,
    required this.vaccineId,
    required this.vaccineName,
    required this.lotNumber,
    required this.manufacturer,
    required this.expiryDate,
    required this.quantityReceived,
    required this.availableDoses,
    required this.receivedAt,
    required this.receivedByUserId,
    required this.packagingIntact,
    required this.coldChainVerified,
    required this.vvmStatus,
    required this.safetyStatus,
    required this.safetyNotes,
    required this.safetyReviewedAt,
    required this.safetyReviewedByUserId,
  });

  VaccineBatchStatus statusAsOf(DateTime value) {
    final today = DateTime(value.year, value.month, value.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    if (availableDoses <= 0 ||
        safetyStatus == VaccineBatchSafetyStatus.discarded) {
      return VaccineBatchStatus.depleted;
    }
    if (expiry.isBefore(today)) return VaccineBatchStatus.expired;
    if (!expiry.isAfter(today.add(const Duration(days: 90)))) {
      return VaccineBatchStatus.expiringSoon;
    }
    return VaccineBatchStatus.usable;
  }

  bool get canBeUsed =>
      safetyStatus == VaccineBatchSafetyStatus.usable && availableDoses > 0;

  VaccineBatch copyWith({
    int? availableDoses,
    VaccineBatchSafetyStatus? safetyStatus,
    String? safetyNotes,
    DateTime? safetyReviewedAt,
    String? safetyReviewedByUserId,
  }) => VaccineBatch(
    id: id,
    batchCode: batchCode,
    facilityId: facilityId,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    lotNumber: lotNumber,
    manufacturer: manufacturer,
    expiryDate: expiryDate,
    quantityReceived: quantityReceived,
    availableDoses: availableDoses ?? this.availableDoses,
    receivedAt: receivedAt,
    receivedByUserId: receivedByUserId,
    packagingIntact: packagingIntact,
    coldChainVerified: coldChainVerified,
    vvmStatus: vvmStatus,
    safetyStatus: safetyStatus ?? this.safetyStatus,
    safetyNotes: safetyNotes ?? this.safetyNotes,
    safetyReviewedAt: safetyReviewedAt ?? this.safetyReviewedAt,
    safetyReviewedByUserId:
        safetyReviewedByUserId ?? this.safetyReviewedByUserId,
  );

  factory VaccineBatch.fromJson(Map<String, dynamic> json) => VaccineBatch(
    id: json['id'] as String,
    batchCode: json['batch_code'] as String,
    facilityId: json['facility_id'] as String,
    vaccineId: json['vaccine_id'] as String,
    vaccineName: json['vaccine_name'] as String,
    lotNumber: json['lot_number'] as String,
    manufacturer: json['manufacturer'] as String? ?? '',
    expiryDate: DateTime.parse(json['expiry_date'] as String),
    quantityReceived: json['quantity_received'] as int,
    availableDoses: json['available_doses'] as int,
    receivedAt: DateTime.parse(json['received_at'] as String),
    receivedByUserId: json['received_by_user_id'] as String,
    packagingIntact: json['packaging_intact'] as bool,
    coldChainVerified: json['cold_chain_verified'] as bool,
    vvmStatus: VaccineVvmStatus.values.byName(json['vvm_status'] as String),
    safetyStatus: VaccineBatchSafetyStatus.values.byName(
      json['safety_status'] as String,
    ),
    safetyNotes: json['safety_notes'] as String? ?? '',
    safetyReviewedAt: DateTime.parse(json['safety_reviewed_at'] as String),
    safetyReviewedByUserId: json['safety_reviewed_by_user_id'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_code': batchCode,
    'facility_id': facilityId,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'lot_number': lotNumber,
    'manufacturer': manufacturer,
    'expiry_date': expiryDate.toIso8601String(),
    'quantity_received': quantityReceived,
    'available_doses': availableDoses,
    'received_at': receivedAt.toIso8601String(),
    'received_by_user_id': receivedByUserId,
    'packaging_intact': packagingIntact,
    'cold_chain_verified': coldChainVerified,
    'vvm_status': vvmStatus.name,
    'safety_status': safetyStatus.name,
    'safety_notes': safetyNotes,
    'safety_reviewed_at': safetyReviewedAt.toIso8601String(),
    'safety_reviewed_by_user_id': safetyReviewedByUserId,
  };
}
