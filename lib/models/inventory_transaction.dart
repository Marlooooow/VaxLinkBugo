import 'vaccine_batch.dart';

enum InventoryTransactionType {
  received,
  adjustmentIncrease,
  adjustmentDecrease,
  administration,
  wastage,
  batchSafetyReview,
}

class InventoryTransaction {
  final String id;
  final String transactionCode;
  final String facilityId;
  final String vaccineId;
  final String vaccineName;
  final String? batchId;
  final InventoryTransactionType type;
  final int quantityChange;
  final int balanceBefore;
  final int balanceAfter;
  final String reason;
  final String referenceNumber;
  final DateTime recordedAt;
  final String recordedByUserId;

  const InventoryTransaction({
    required this.id,
    required this.transactionCode,
    required this.facilityId,
    required this.vaccineId,
    required this.vaccineName,
    required this.batchId,
    required this.type,
    required this.quantityChange,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.reason,
    required this.referenceNumber,
    required this.recordedAt,
    required this.recordedByUserId,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) =>
      InventoryTransaction(
        id: json['id'] as String,
        transactionCode: json['transaction_code'] as String,
        facilityId: json['facility_id'] as String,
        vaccineId: json['vaccine_id'] as String,
        vaccineName: json['vaccine_name'] as String,
        batchId: json['batch_id'] as String?,
        type: InventoryTransactionType.values.byName(json['type'] as String),
        quantityChange: json['quantity_change'] as int,
        balanceBefore: json['balance_before'] as int,
        balanceAfter: json['balance_after'] as int,
        reason: json['reason'] as String,
        referenceNumber: json['reference_number'] as String? ?? '',
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        recordedByUserId: json['recorded_by_user_id'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'transaction_code': transactionCode,
    'facility_id': facilityId,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'batch_id': batchId,
    'type': type.name,
    'quantity_change': quantityChange,
    'balance_before': balanceBefore,
    'balance_after': balanceAfter,
    'reason': reason,
    'reference_number': referenceNumber,
    'recorded_at': recordedAt.toIso8601String(),
    'recorded_by_user_id': recordedByUserId,
  };
}

class StockReceiptRequest {
  final String vaccineId;
  final int quantity;
  final String lotNumber;
  final String manufacturer;
  final DateTime expiryDate;
  final String referenceNumber;
  final String recordedByUserId;
  final bool packagingIntact;
  final bool coldChainVerified;
  final VaccineVvmStatus vvmStatus;
  final String safetyNotes;

  const StockReceiptRequest({
    required this.vaccineId,
    required this.quantity,
    required this.lotNumber,
    required this.manufacturer,
    required this.expiryDate,
    required this.referenceNumber,
    required this.recordedByUserId,
    required this.packagingIntact,
    required this.coldChainVerified,
    required this.vvmStatus,
    required this.safetyNotes,
  });
}

class BatchSafetyReviewRequest {
  final String vaccineId;
  final String batchId;
  final VaccineBatchSafetyStatus decision;
  final String notes;
  final String reviewedByUserId;

  const BatchSafetyReviewRequest({
    required this.vaccineId,
    required this.batchId,
    required this.decision,
    required this.notes,
    required this.reviewedByUserId,
  });
}

class StockAdjustmentRequest {
  final String vaccineId;
  final String batchId;
  final int quantityChange;
  final String reason;
  final String referenceNumber;
  final String recordedByUserId;

  const StockAdjustmentRequest({
    required this.vaccineId,
    required this.batchId,
    required this.quantityChange,
    required this.reason,
    required this.referenceNumber,
    required this.recordedByUserId,
  });
}

class WastageRequest {
  final String vaccineId;
  final String batchId;
  final int quantity;
  final String reason;
  final String recordedByUserId;

  const WastageRequest({
    required this.vaccineId,
    required this.batchId,
    required this.quantity,
    required this.reason,
    required this.recordedByUserId,
  });
}
