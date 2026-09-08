import '../models/vaccine_inventory.dart';
import '../models/inventory_transaction.dart';
import '../models/vaccine_batch.dart';

class InventoryPage<T> {
  final List<T> items;
  final bool hasMore;
  final int nextOffset;

  const InventoryPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });
}

abstract class InventoryRepository {
  Future<List<VaccineInventory>> getInventoryOverview();

  Future<Map<String, int>> getInventoryAttentionCounts();

  Future<List<VaccineBatch>> getBatches(String vaccineId);

  Future<InventoryPage<VaccineBatch>> getBatchesPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  });

  Future<List<VaccineBatch>> getAllBatches();

  Future<List<InventoryTransaction>> getTransactions(String vaccineId);

  Future<InventoryPage<InventoryTransaction>> getTransactionsPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  });

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
