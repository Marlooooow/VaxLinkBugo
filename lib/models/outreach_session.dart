enum OutreachSessionStatus {
  draft,
  active,
  reconciliation,
  completed,
  cancelled,
}

enum OutreachStockDisposition { wastage, returned, quarantine }

class OutreachSession {
  final String id;
  final String sessionCode;
  final String facilityId;
  final String title;
  final String location;
  final DateTime scheduledOn;
  final OutreachSessionStatus status;
  final bool packagingIntact;
  final bool coldChainVerified;
  final String vvmStatus;
  final String safetyNotes;
  final String closureNotes;
  final DateTime createdAt;

  const OutreachSession({
    required this.id,
    required this.sessionCode,
    required this.facilityId,
    required this.title,
    required this.location,
    required this.scheduledOn,
    required this.status,
    required this.packagingIntact,
    required this.coldChainVerified,
    required this.vvmStatus,
    required this.safetyNotes,
    required this.closureNotes,
    required this.createdAt,
  });

  factory OutreachSession.fromJson(Map<String, dynamic> json) =>
      OutreachSession(
        id: json['id'] as String,
        sessionCode: json['session_code'] as String,
        facilityId: json['facility_id'] as String,
        title: json['title'] as String,
        location: json['location'] as String,
        scheduledOn: DateTime.parse(json['scheduled_on'] as String),
        status: OutreachSessionStatus.values.byName(json['status'] as String),
        packagingIntact: json['packaging_intact'] as bool? ?? false,
        coldChainVerified: json['cold_chain_verified'] as bool? ?? false,
        vvmStatus: json['vvm_status'] as String? ?? 'unknown',
        safetyNotes: json['safety_notes'] as String? ?? '',
        closureNotes: json['closure_notes'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class OutreachStockAllocation {
  final String id;
  final String sessionId;
  final String batchId;
  final String batchCode;
  final String lotNumber;
  final String vaccineId;
  final String vaccineName;
  final DateTime expiryDate;
  final int allocated;
  final int administered;
  final int wasted;
  final int returned;
  final int quarantined;

  const OutreachStockAllocation({
    required this.id,
    required this.sessionId,
    required this.batchId,
    required this.batchCode,
    required this.lotNumber,
    required this.vaccineId,
    required this.vaccineName,
    required this.expiryDate,
    required this.allocated,
    required this.administered,
    required this.wasted,
    required this.returned,
    required this.quarantined,
  });

  int get remaining =>
      allocated - administered - wasted - returned - quarantined;

  factory OutreachStockAllocation.fromJson(Map<String, dynamic> json) {
    final batch = json['vaccine_batches'] as Map;
    final inventory = batch['vaccine_inventory'] as Map;
    final vaccine = inventory['vaccine_definitions'] as Map;
    return OutreachStockAllocation(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      batchId: json['batch_id'] as String,
      batchCode: batch['batch_code'] as String,
      lotNumber: batch['lot_number'] as String,
      vaccineId: inventory['vaccine_id'] as String,
      vaccineName: vaccine['name'] as String,
      expiryDate: DateTime.parse(batch['expiry_date'] as String),
      allocated: json['allocated_quantity'] as int,
      administered: json['administered_quantity'] as int,
      wasted: json['wasted_quantity'] as int,
      returned: json['returned_quantity'] as int,
      quarantined: json['quarantined_quantity'] as int,
    );
  }
}
