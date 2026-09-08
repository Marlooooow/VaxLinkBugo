import '../models/inventory_transaction.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import '../services/mock_identifier_generator.dart';
import 'inventory_repository.dart';
import 'mock_appointment_repository.dart';

class MockInventoryRepository implements InventoryRepository {
  static int usableDosesForOffers(String vaccineId) => _batches
      .where(
        (batch) => batch.vaccineId == vaccineId && _isCurrentlyUsable(batch),
      )
      .fold<int>(0, (sum, batch) => sum + batch.availableDoses);
  MockInventoryRepository() {
    MockIdentifierGenerator.reserve('VBAT', 5);
    MockIdentifierGenerator.reserve('ITXN', 5);
  }

  static const _facilityId = '00000000-0000-4000-8100-000000000001';
  static final _seedUpdatedAt = DateTime(2026, 8, 28, 8, 30);
  static final Map<String, VaccineInventory> _inventory = {
    'pentavalent': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000001',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      facilityId: _facilityId,
      availableDoses: 0,
      updatedAt: _seedUpdatedAt,
    ),
    'opv': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000002',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      facilityId: _facilityId,
      availableDoses: 0,
      updatedAt: _seedUpdatedAt,
    ),
    'bcg': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000003',
      vaccineId: 'bcg',
      vaccineName: 'BCG',
      facilityId: _facilityId,
      availableDoses: 4,
      updatedAt: _seedUpdatedAt,
    ),
    'hepatitis_b': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000004',
      vaccineId: 'hepatitis_b',
      vaccineName: 'Hepatitis B',
      facilityId: _facilityId,
      availableDoses: 1,
      updatedAt: _seedUpdatedAt,
    ),
    'pcv': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000005',
      vaccineId: 'pcv',
      vaccineName: 'PCV',
      facilityId: _facilityId,
      availableDoses: 6,
      updatedAt: _seedUpdatedAt,
    ),
    'ipv': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000006',
      vaccineId: 'ipv',
      vaccineName: 'IPV',
      facilityId: _facilityId,
      availableDoses: 3,
      updatedAt: _seedUpdatedAt,
    ),
    'mmr': VaccineInventory(
      id: '00000000-0000-4000-8200-000000000007',
      vaccineId: 'mmr',
      vaccineName: 'MMR',
      facilityId: _facilityId,
      availableDoses: 4,
      updatedAt: _seedUpdatedAt,
    ),
  };

  static final List<VaccineBatch> _batches = [
    _seedBatch(1, 'bcg', 'BCG', 'BCG-260801', 'DOH Supplier', 4),
    _seedBatch(
      2,
      'hepatitis_b',
      'Hepatitis B',
      'HEPB-260802',
      'DOH Supplier',
      1,
    ),
    _seedBatch(3, 'pcv', 'PCV', 'PCV-260803', 'DOH Supplier', 6),
    _seedBatch(4, 'ipv', 'IPV', 'IPV-260804', 'DOH Supplier', 3),
    _seedBatch(5, 'mmr', 'MMR', 'MMR-260805', 'DOH Supplier', 4),
  ];

  static final List<InventoryTransaction> _transactions = [
    for (var index = 0; index < _batches.length; index++)
      InventoryTransaction(
        id: '00000000-0000-4000-8400-${(index + 1).toString().padLeft(12, '0')}',
        transactionCode: 'ITXN-2026-${(index + 1).toString().padLeft(6, '0')}',
        facilityId: _facilityId,
        vaccineId: _batches[index].vaccineId,
        vaccineName: _batches[index].vaccineName,
        batchId: _batches[index].id,
        type: InventoryTransactionType.received,
        quantityChange: _batches[index].quantityReceived,
        balanceBefore: 0,
        balanceAfter: _batches[index].quantityReceived,
        reason: 'Opening mock inventory',
        referenceNumber: 'SEED-2026',
        recordedAt: _batches[index].receivedAt,
        recordedByUserId: 'USR-H-001',
      ),
  ];

  static VaccineBatch _seedBatch(
    int sequence,
    String vaccineId,
    String vaccineName,
    String lotNumber,
    String manufacturer,
    int quantity,
  ) => VaccineBatch(
    id: '00000000-0000-4000-8300-${sequence.toString().padLeft(12, '0')}',
    batchCode: 'VBAT-2026-${sequence.toString().padLeft(6, '0')}',
    facilityId: _facilityId,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    lotNumber: lotNumber,
    manufacturer: manufacturer,
    expiryDate: DateTime(2027, 8, 31),
    quantityReceived: quantity,
    availableDoses: quantity,
    receivedAt: _seedUpdatedAt,
    receivedByUserId: 'USR-H-001',
    packagingIntact: true,
    coldChainVerified: true,
    vvmStatus: VaccineVvmStatus.acceptable,
    safetyStatus: VaccineBatchSafetyStatus.usable,
    safetyNotes: 'Opening mock batch verified as usable.',
    safetyReviewedAt: _seedUpdatedAt,
    safetyReviewedByUserId: 'USR-H-001',
  );

  @override
  Future<List<VaccineInventory>> getInventoryOverview() async {
    await Future.delayed(const Duration(milliseconds: 450));
    for (final vaccineId in _inventory.keys) {
      _synchronizeUsableBalance(vaccineId);
    }
    final results = _inventory.values.toList(growable: false)
      ..sort((a, b) => a.vaccineName.compareTo(b.vaccineName));
    return results;
  }

  @override
  Future<Map<String, int>> getInventoryAttentionCounts() async {
    final now = DateTime.now();
    final counts = <String, int>{};
    for (final batch in _batches) {
      final needsAttention =
          batch.safetyStatus == VaccineBatchSafetyStatus.quarantined ||
          (batch.availableDoses > 0 &&
              batch.statusAsOf(now) == VaccineBatchStatus.expired);
      if (needsAttention) {
        counts.update(batch.vaccineId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  @override
  Future<List<VaccineBatch>> getBatches(String vaccineId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final results =
        _batches
            .where((batch) => batch.vaccineId == vaccineId)
            .toList(growable: false)
          ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return results;
  }

  @override
  Future<InventoryPage<VaccineBatch>> getBatchesPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  }) async {
    final all = await getBatches(vaccineId);
    final items = all.skip(offset).take(limit).toList(growable: false);
    return InventoryPage(
      items: items,
      hasMore: offset + items.length < all.length,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<List<VaccineBatch>> getAllBatches() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final results = List<VaccineBatch>.of(_batches)
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return List.unmodifiable(results);
  }

  @override
  Future<List<InventoryTransaction>> getTransactions(String vaccineId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final results =
        _transactions
            .where((transaction) => transaction.vaccineId == vaccineId)
            .toList(growable: false)
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return results;
  }

  @override
  Future<InventoryPage<InventoryTransaction>> getTransactionsPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  }) async {
    final all = await getTransactions(vaccineId);
    final items = all.skip(offset).take(limit).toList(growable: false);
    return InventoryPage(
      items: items,
      hasMore: offset + items.length < all.length,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<InventoryTransaction> receiveStock(StockReceiptRequest request) async {
    await Future.delayed(const Duration(milliseconds: 450));
    _synchronizeUsableBalance(request.vaccineId);
    final inventory = _requireInventory(request.vaccineId);
    if (request.quantity <= 0) {
      throw ArgumentError('Received quantity must be greater than zero.');
    }
    if (request.lotNumber.trim().isEmpty ||
        request.referenceNumber.trim().isEmpty) {
      throw ArgumentError('Lot and delivery reference are required.');
    }
    final today = DateTime.now();
    final expiry = DateTime(
      request.expiryDate.year,
      request.expiryDate.month,
      request.expiryDate.day,
    );
    if (!expiry.isAfter(DateTime(today.year, today.month, today.day))) {
      throw ArgumentError('Received stock must have a future expiry date.');
    }
    final duplicateLot = _batches.any(
      (batch) =>
          batch.vaccineId == request.vaccineId &&
          batch.lotNumber.toUpperCase() ==
              request.lotNumber.trim().toUpperCase(),
    );
    if (duplicateLot) {
      throw StateError(
        'This lot number is already registered for the vaccine.',
      );
    }
    final batchIdentity = MockIdentifierGenerator.next(prefix: 'VBAT');
    final safetyStatus =
        request.packagingIntact &&
            request.coldChainVerified &&
            (request.vvmStatus == VaccineVvmStatus.acceptable ||
                request.vvmStatus == VaccineVvmStatus.notApplicable)
        ? VaccineBatchSafetyStatus.usable
        : VaccineBatchSafetyStatus.quarantined;
    if (safetyStatus == VaccineBatchSafetyStatus.quarantined &&
        request.safetyNotes.trim().isEmpty) {
      throw ArgumentError('Safety remarks are required for quarantined stock.');
    }
    final batch = VaccineBatch(
      id: batchIdentity.id,
      batchCode: batchIdentity.code,
      facilityId: inventory.facilityId,
      vaccineId: inventory.vaccineId,
      vaccineName: inventory.vaccineName,
      lotNumber: request.lotNumber.trim(),
      manufacturer: request.manufacturer.trim(),
      expiryDate: expiry,
      quantityReceived: request.quantity,
      availableDoses: request.quantity,
      receivedAt: today,
      receivedByUserId: request.recordedByUserId,
      packagingIntact: request.packagingIntact,
      coldChainVerified: request.coldChainVerified,
      vvmStatus: request.vvmStatus,
      safetyStatus: safetyStatus,
      safetyNotes: request.safetyNotes.trim(),
      safetyReviewedAt: today,
      safetyReviewedByUserId: request.recordedByUserId,
    );
    _batches.add(batch);
    final transaction = _recordChange(
      inventory: inventory,
      batchId: batch.id,
      type: InventoryTransactionType.received,
      quantityChange: safetyStatus == VaccineBatchSafetyStatus.usable
          ? request.quantity
          : 0,
      reason: safetyStatus == VaccineBatchSafetyStatus.usable
          ? 'Stock received and verified as usable'
          : 'Stock received and quarantined for safety review',
      referenceNumber: request.referenceNumber.trim(),
      recordedByUserId: request.recordedByUserId,
    );
    if (safetyStatus == VaccineBatchSafetyStatus.usable) {
      MockAppointmentRepository.createStockAvailabilityOffers(
        vaccineId: request.vaccineId,
        availableSlots: request.quantity,
      );
    }
    return transaction;
  }

  @override
  Future<InventoryTransaction> adjustStock(
    StockAdjustmentRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 450));
    _synchronizeUsableBalance(request.vaccineId);
    if (request.quantityChange == 0) {
      throw ArgumentError('Adjustment quantity cannot be zero.');
    }
    if (request.reason.trim().isEmpty) {
      throw ArgumentError('An adjustment reason is required.');
    }
    final inventory = _requireInventory(request.vaccineId);
    final batchIndex = _requireBatchIndex(request.batchId, request.vaccineId);
    final batch = _batches[batchIndex];
    if (!_isCurrentlyUsable(batch)) {
      throw StateError('Only a usable batch can be adjusted.');
    }
    final batchAfter = batch.availableDoses + request.quantityChange;
    final inventoryAfter = inventory.availableDoses + request.quantityChange;
    if (batchAfter < 0 || inventoryAfter < 0) {
      throw StateError('The adjustment exceeds the available stock.');
    }
    _batches[batchIndex] = batch.copyWith(availableDoses: batchAfter);
    return _recordChange(
      inventory: inventory,
      batchId: batch.id,
      type: request.quantityChange > 0
          ? InventoryTransactionType.adjustmentIncrease
          : InventoryTransactionType.adjustmentDecrease,
      quantityChange: request.quantityChange,
      reason: request.reason.trim(),
      referenceNumber: request.referenceNumber.trim(),
      recordedByUserId: request.recordedByUserId,
    );
  }

  @override
  Future<InventoryTransaction> recordWastage(WastageRequest request) async {
    await Future.delayed(const Duration(milliseconds: 450));
    _synchronizeUsableBalance(request.vaccineId);
    if (request.quantity <= 0 || request.reason.trim().isEmpty) {
      throw ArgumentError('Wastage quantity and reason are required.');
    }
    final inventory = _requireInventory(request.vaccineId);
    final batchIndex = _requireBatchIndex(request.batchId, request.vaccineId);
    final batch = _batches[batchIndex];
    if (!_isCurrentlyUsable(batch)) {
      throw StateError('Only a usable batch can be recorded as wastage.');
    }
    if (request.quantity > batch.availableDoses ||
        request.quantity > inventory.availableDoses) {
      throw StateError('Wastage cannot exceed available stock.');
    }
    _batches[batchIndex] = batch.copyWith(
      availableDoses: batch.availableDoses - request.quantity,
    );
    return _recordChange(
      inventory: inventory,
      batchId: batch.id,
      type: InventoryTransactionType.wastage,
      quantityChange: -request.quantity,
      reason: request.reason.trim(),
      referenceNumber: '',
      recordedByUserId: request.recordedByUserId,
    );
  }

  @override
  Future<VaccineBatch> reviewBatchSafety(
    BatchSafetyReviewRequest request,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _synchronizeUsableBalance(request.vaccineId);
    if (request.notes.trim().isEmpty) {
      throw ArgumentError('Safety review notes are required.');
    }
    final inventory = _requireInventory(request.vaccineId);
    final batchIndex = _requireBatchIndex(request.batchId, request.vaccineId);
    final batch = _batches[batchIndex];
    if (batch.safetyStatus == VaccineBatchSafetyStatus.discarded) {
      throw StateError('A discarded batch cannot be reviewed again.');
    }
    final wasUsable = _isCurrentlyUsable(batch);
    final willBeUsable = request.decision == VaccineBatchSafetyStatus.usable;
    if (willBeUsable &&
        batch.statusAsOf(DateTime.now()) == VaccineBatchStatus.expired) {
      throw StateError('An expired batch cannot be released for use.');
    }
    var quantityChange = 0;
    if (wasUsable && !willBeUsable) quantityChange = -batch.availableDoses;
    if (!wasUsable && willBeUsable) quantityChange = batch.availableDoses;
    final reviewed = batch.copyWith(
      availableDoses: request.decision == VaccineBatchSafetyStatus.discarded
          ? 0
          : batch.availableDoses,
      safetyStatus: request.decision,
      safetyNotes: request.notes.trim(),
      safetyReviewedAt: DateTime.now(),
      safetyReviewedByUserId: request.reviewedByUserId,
    );
    _batches[batchIndex] = reviewed;
    _recordChange(
      inventory: inventory,
      batchId: batch.id,
      type: InventoryTransactionType.batchSafetyReview,
      quantityChange: quantityChange,
      reason:
          'Batch safety decision: ${request.decision.name}. '
          '${request.notes.trim()}',
      referenceNumber: '',
      recordedByUserId: request.reviewedByUserId,
    );
    return reviewed;
  }

  @override
  Future<VaccineInventory?> getVaccineInventory(String vaccineId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _synchronizeUsableBalance(vaccineId);
    return _inventory[vaccineId];
  }

  @override
  Future<List<VaccineInventory>> getInventoryForVaccines(
    List<String> vaccineIds,
  ) async {
    final results = <VaccineInventory>[];

    for (final vaccineId in vaccineIds) {
      final vaccine = await getVaccineInventory(vaccineId);

      if (vaccine != null) {
        results.add(vaccine);
      }
    }

    return results;
  }

  @override
  Future<void> consumeDoses(Map<String, int> dosesByVaccineId) async {
    await Future.delayed(const Duration(milliseconds: 350));
    for (final vaccineId in dosesByVaccineId.keys) {
      _synchronizeUsableBalance(vaccineId);
    }
    for (final entry in dosesByVaccineId.entries) {
      final current = _inventory[entry.key];
      if (current == null || entry.value <= 0) continue;
      if (current.availableDoses < entry.value) {
        throw StateError('${current.vaccineName} has insufficient stock.');
      }
      final usableDoses = _batches
          .where(
            (batch) =>
                batch.vaccineId == entry.key && _isCurrentlyUsable(batch),
          )
          .fold<int>(0, (total, batch) => total + batch.availableDoses);
      if (usableDoses < entry.value) {
        throw StateError('${current.vaccineName} has no usable batch stock.');
      }
    }
    for (final entry in dosesByVaccineId.entries) {
      final current = _inventory[entry.key];
      if (current == null || entry.value <= 0) continue;
      var remaining = entry.value;
      final usableBatchIndexes =
          <int>[
            for (var index = 0; index < _batches.length; index++)
              if (_batches[index].vaccineId == entry.key &&
                  _isCurrentlyUsable(_batches[index]) &&
                  _batches[index].availableDoses > 0)
                index,
          ]..sort(
            (a, b) => _batches[a].expiryDate.compareTo(_batches[b].expiryDate),
          );
      for (final index in usableBatchIndexes) {
        if (remaining == 0) break;
        final batch = _batches[index];
        final used = remaining > batch.availableDoses
            ? batch.availableDoses
            : remaining;
        _batches[index] = batch.copyWith(
          availableDoses: batch.availableDoses - used,
        );
        _recordChange(
          inventory: _requireInventory(entry.key),
          batchId: batch.id,
          type: InventoryTransactionType.administration,
          quantityChange: -used,
          reason: 'Administered through vaccination workflow',
          referenceNumber: '',
          recordedByUserId: 'USR-H-001',
        );
        remaining -= used;
      }
      if (remaining > 0) {
        throw StateError('${current.vaccineName} has no usable batch stock.');
      }
    }
  }

  VaccineInventory _requireInventory(String vaccineId) {
    final inventory = _inventory[vaccineId];
    if (inventory == null) throw StateError('Vaccine inventory was not found.');
    return inventory;
  }

  static bool _isCurrentlyUsable(VaccineBatch batch) =>
      batch.canBeUsed &&
      batch.statusAsOf(DateTime.now()) != VaccineBatchStatus.expired;

  void _synchronizeUsableBalance(String vaccineId) {
    final inventory = _inventory[vaccineId];
    if (inventory == null) return;
    final usableDoses = _batches
        .where(
          (batch) => batch.vaccineId == vaccineId && _isCurrentlyUsable(batch),
        )
        .fold<int>(0, (total, batch) => total + batch.availableDoses);
    if (usableDoses == inventory.availableDoses) return;
    _inventory[vaccineId] = inventory.copyWith(
      availableDoses: usableDoses,
      updatedAt: DateTime.now(),
    );
  }

  int _requireBatchIndex(String batchId, String vaccineId) {
    final index = _batches.indexWhere(
      (batch) => batch.id == batchId && batch.vaccineId == vaccineId,
    );
    if (index < 0) throw StateError('Vaccine batch was not found.');
    return index;
  }

  InventoryTransaction _recordChange({
    required VaccineInventory inventory,
    required String? batchId,
    required InventoryTransactionType type,
    required int quantityChange,
    required String reason,
    required String referenceNumber,
    required String recordedByUserId,
  }) {
    final now = DateTime.now();
    final before = inventory.availableDoses;
    final after = before + quantityChange;
    if (after < 0) throw StateError('Inventory balance cannot be negative.');
    _inventory[inventory.vaccineId] = inventory.copyWith(
      availableDoses: after,
      updatedAt: now,
    );
    final identity = MockIdentifierGenerator.next(prefix: 'ITXN');
    final transaction = InventoryTransaction(
      id: identity.id,
      transactionCode: identity.code,
      facilityId: inventory.facilityId,
      vaccineId: inventory.vaccineId,
      vaccineName: inventory.vaccineName,
      batchId: batchId,
      type: type,
      quantityChange: quantityChange,
      balanceBefore: before,
      balanceAfter: after,
      reason: reason,
      referenceNumber: referenceNumber,
      recordedAt: now,
      recordedByUserId: recordedByUserId,
    );
    _transactions.add(transaction);
    return transaction;
  }
}
