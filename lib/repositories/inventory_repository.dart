import '../models/vaccine_inventory.dart';
import '../models/inventory_transaction.dart';
import '../models/vaccine_batch.dart';

abstract class InventoryRepository {
  Future<List<VaccineInventory>> getInventoryOverview();

  Future<List<VaccineBatch>> getBatches(String vaccineId);

  Future<List<VaccineBatch>> getAllBatches();

  Future<List<InventoryTransaction>> getTransactions(String vaccineId);

  Future<InventoryTransaction> receiveStock(StockReceiptRequest request);

  Future<InventoryTransaction> adjustStock(StockAdjustmentRequest request);

  Future<InventoryTransaction> recordWastage(WastageRequest request);

  Future<VaccineBatch> reviewBatchSafety(BatchSafetyReviewRequest request);

  Future<VaccineInventory?> getVaccineInventory(String vaccineId);

  Future<List<VaccineInventory>> getInventoryForVaccines(
    List<String> vaccineIds,
  );

  Future<void> consumeDoses(Map<String, int> dosesByVaccineId);
}
