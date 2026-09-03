class VaccineInventory {
  final String id;
  final String vaccineId;
  final String vaccineName;
  final String facilityId;
  final int availableDoses;
  final int lowStockThreshold;
  final DateTime updatedAt;

  VaccineInventory({
    required this.id,
    required this.vaccineId,
    required this.vaccineName,
    required this.facilityId,
    required this.availableDoses,
    this.lowStockThreshold = 5,
    required this.updatedAt,
  });

  bool get isAvailable => availableDoses > 0;

  bool get isLowStock =>
      availableDoses > 0 && availableDoses <= lowStockThreshold;

  bool get isUnavailable => availableDoses <= 0;

  VaccineInventory copyWith({int? availableDoses, DateTime? updatedAt}) =>
      VaccineInventory(
        id: id,
        vaccineId: vaccineId,
        vaccineName: vaccineName,
        facilityId: facilityId,
        availableDoses: availableDoses ?? this.availableDoses,
        lowStockThreshold: lowStockThreshold,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory VaccineInventory.fromJson(Map<String, dynamic> json) =>
      VaccineInventory(
        id: json['id'] as String,
        vaccineId: json['vaccine_id'] as String,
        vaccineName: json['vaccine_name'] as String,
        facilityId: json['facility_id'] as String,
        availableDoses: json['available_doses'] as int,
        lowStockThreshold: json['low_stock_threshold'] as int? ?? 5,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'facility_id': facilityId,
    'available_doses': availableDoses,
    'low_stock_threshold': lowStockThreshold,
    'updated_at': updatedAt.toIso8601String(),
  };
}
