import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/inventory_transaction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccine_batch.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_inventory_repository.dart';

void main() {
  test('receiving, adjustment, and wastage share one stock balance', () async {
    final repository = MockInventoryRepository();
    final before = await repository.getVaccineInventory('pentavalent');

    final receipt = await repository.receiveStock(
      StockReceiptRequest(
        vaccineId: 'pentavalent',
        quantity: 5,
        lotNumber: 'TEST-PENTA-001',
        manufacturer: 'Test Supplier',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        referenceNumber: 'DR-TEST-001',
        recordedByUserId: 'USR-H-001',
        packagingIntact: true,
        coldChainVerified: true,
        vvmStatus: VaccineVvmStatus.acceptable,
        safetyNotes: 'Verified in test.',
      ),
    );
    final batch = (await repository.getBatches(
      'pentavalent',
    )).firstWhere((item) => item.lotNumber == 'TEST-PENTA-001');
    await repository.adjustStock(
      StockAdjustmentRequest(
        vaccineId: 'pentavalent',
        batchId: batch.id,
        quantityChange: 2,
        reason: 'Physical count correction',
        referenceNumber: 'COUNT-001',
        recordedByUserId: 'USR-H-001',
      ),
    );
    await repository.recordWastage(
      WastageRequest(
        vaccineId: 'pentavalent',
        batchId: batch.id,
        quantity: 1,
        reason: 'Damaged vial',
        recordedByUserId: 'USR-H-001',
      ),
    );
    final after = await repository.getVaccineInventory('pentavalent');
    final transactions = await repository.getTransactions('pentavalent');

    expect(receipt.type, InventoryTransactionType.received);
    expect(after!.availableDoses, before!.availableDoses + 6);
    expect(
      transactions.map((item) => item.type),
      containsAll([
        InventoryTransactionType.received,
        InventoryTransactionType.adjustmentIncrease,
        InventoryTransactionType.wastage,
      ]),
    );
  });

  test(
    'normal administration deducts a batch and records a transaction',
    () async {
      final repository = MockInventoryRepository();
      final before = await repository.getVaccineInventory('bcg');
      final batchesBefore = await repository.getBatches('bcg');
      final batchBalanceBefore = batchesBefore
          .map((item) => item.availableDoses)
          .fold<int>(0, (total, quantity) => total + quantity);

      await repository.consumeDoses({'bcg': 1});

      final after = await repository.getVaccineInventory('bcg');
      final batchesAfter = await repository.getBatches('bcg');
      final batchBalanceAfter = batchesAfter
          .map((item) => item.availableDoses)
          .fold<int>(0, (total, quantity) => total + quantity);
      final transactions = await repository.getTransactions('bcg');

      expect(after!.availableDoses, before!.availableDoses - 1);
      expect(batchBalanceAfter, batchBalanceBefore - 1);
      expect(transactions.first.type, InventoryTransactionType.administration);
    },
  );

  test('an uncertain receipt is quarantined until safety review', () async {
    final repository = MockInventoryRepository();
    final before = await repository.getVaccineInventory('opv');
    await repository.receiveStock(
      StockReceiptRequest(
        vaccineId: 'opv',
        quantity: 4,
        lotNumber: 'TEST-OPV-QUARANTINE-001',
        manufacturer: 'Test Supplier',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        referenceNumber: 'DR-TEST-QUARANTINE',
        recordedByUserId: 'USR-H-001',
        packagingIntact: false,
        coldChainVerified: true,
        vvmStatus: VaccineVvmStatus.acceptable,
        safetyNotes: 'Package requires review.',
      ),
    );
    final quarantined = (await repository.getBatches(
      'opv',
    )).firstWhere((batch) => batch.lotNumber == 'TEST-OPV-QUARANTINE-001');
    final whileQuarantined = await repository.getVaccineInventory('opv');

    expect(quarantined.safetyStatus, VaccineBatchSafetyStatus.quarantined);
    expect(whileQuarantined!.availableDoses, before!.availableDoses);

    await repository.reviewBatchSafety(
      BatchSafetyReviewRequest(
        vaccineId: 'opv',
        batchId: quarantined.id,
        decision: VaccineBatchSafetyStatus.usable,
        notes: 'Reviewed and cleared for use.',
        reviewedByUserId: 'USR-H-001',
      ),
    );
    final afterRelease = await repository.getVaccineInventory('opv');
    final transactions = await repository.getTransactions('opv');
    final released = (await repository.getBatches(
      'opv',
    )).firstWhere((batch) => batch.id == quarantined.id);

    expect(afterRelease!.availableDoses, before.availableDoses + 4);
    expect(transactions.first.type, InventoryTransactionType.batchSafetyReview);
    expect(
      VaccineBatch.fromJson(released.toJson()).safetyStatus,
      VaccineBatchSafetyStatus.usable,
    );
    expect(
      InventoryTransaction.fromJson(transactions.first.toJson()).type,
      InventoryTransactionType.batchSafetyReview,
    );
  });
}
