import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_transaction.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import 'inventory_repository.dart';

class SupabaseInventoryRepository implements InventoryRepository {
  final SupabaseClient _client;

  SupabaseInventoryRepository(this._client);

  static const _inventorySelect =
      'id, facility_id, reorder_level, updated_at, '
      'vaccine_definitions!inner(id, name), vaccine_batches(quantity, expiry_date, '
      'safety_status, packaging_intact, cold_chain_verified, vvm_status)';
  static const _batchSelect =
      'id, batch_code, lot_number, manufacturer, expiry_date, '
      'quantity_received, quantity, received_at, received_by, packaging_intact, '
      'cold_chain_verified, vvm_status, safety_status, safety_notes, '
      'safety_reviewed_at, safety_reviewed_by, '
      'vaccine_inventory!inner(facility_id, vaccine_id, vaccine_definitions!inner(name))';
  static const _transactionSelect =
      'id, transaction_code, batch_id, transaction_type, quantity_delta, '
      'balance_before, balance_after, reason, reference_number, created_at, '
      'performed_by, vaccine_inventory!inner(facility_id, vaccine_id, '
      'vaccine_definitions!inner(name))';

  @override
  Future<List<VaccineInventory>> getInventoryOverview() async {
    final rows = await _client
        .from('vaccine_inventory')
        .select(_inventorySelect);
    return rows
        .map<VaccineInventory>(_inventoryFromRow)
        .toList(growable: false);
  }

  @override
  Future<Map<String, int>> getInventoryAttentionCounts() async {
    final rows = await _client.rpc('get_inventory_attention_counts') as List;
    return {
      for (final raw in rows)
        (raw as Map)['vaccine_id'] as String:
            ((raw)['attention_count'] as num).toInt(),
    };
  }

  @override
  Future<VaccineInventory?> getVaccineInventory(String vaccineId) async {
    final row = await _client
        .from('vaccine_inventory')
        .select(_inventorySelect)
        .eq('vaccine_id', vaccineId)
        .maybeSingle();
    return row == null ? null : _inventoryFromRow(row);
  }

  @override
  Future<List<VaccineInventory>> getInventoryForVaccines(
    List<String> vaccineIds,
  ) async {
    if (vaccineIds.isEmpty) return const [];
    final rows = await _client
        .from('vaccine_inventory')
        .select(_inventorySelect)
        .inFilter('vaccine_id', vaccineIds);
    return rows
        .map<VaccineInventory>(_inventoryFromRow)
        .toList(growable: false);
  }

  @override
  Future<List<VaccineBatch>> getBatches(String vaccineId) async {
    final inventory = await _client
        .from('vaccine_inventory')
        .select('id')
        .eq('vaccine_id', vaccineId)
        .maybeSingle();
    if (inventory == null) return const [];
    final rows = await _client
        .from('vaccine_batches')
        .select(_batchSelect)
        .eq('inventory_id', inventory['id'])
        .order('expiry_date');
    return rows.map<VaccineBatch>(_batchFromRow).toList(growable: false);
  }

  @override
  Future<InventoryPage<VaccineBatch>> getBatchesPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  }) async {
    final inventory = await _client
        .from('vaccine_inventory')
        .select('id')
        .eq('vaccine_id', vaccineId)
        .maybeSingle();
    if (inventory == null) {
      return const InventoryPage(items: [], hasMore: false, nextOffset: 0);
    }
    final rows = await _client
        .from('vaccine_batches')
        .select(_batchSelect)
        .eq('inventory_id', inventory['id'])
        .order('expiry_date')
        .range(offset, offset + limit);
    final parsed = rows.map<VaccineBatch>(_batchFromRow).toList();
    final hasMore = parsed.length > limit;
    final items = parsed.take(limit).toList(growable: false);
    return InventoryPage(
      items: items,
      hasMore: hasMore,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<List<VaccineBatch>> getAllBatches() async {
    final rows = await _client
        .from('vaccine_batches')
        .select(_batchSelect)
        .order('expiry_date');
    return rows.map<VaccineBatch>(_batchFromRow).toList(growable: false);
  }

  @override
  Future<List<InventoryTransaction>> getTransactions(String vaccineId) async {
    final inventory = await _inventoryId(vaccineId);
    if (inventory == null) return const [];
    final rows = await _client
        .from('inventory_transactions')
        .select(_transactionSelect)
        .eq('inventory_id', inventory)
        .order('created_at', ascending: false);
    return rows
        .map<InventoryTransaction>(_transactionFromRow)
        .toList(growable: false);
  }

  @override
  Future<InventoryPage<InventoryTransaction>> getTransactionsPage(
    String vaccineId, {
    int limit = 10,
    int offset = 0,
  }) async {
    final inventory = await _inventoryId(vaccineId);
    if (inventory == null) {
      return const InventoryPage(items: [], hasMore: false, nextOffset: 0);
    }
    final rows = await _client
        .from('inventory_transactions')
        .select(_transactionSelect)
        .eq('inventory_id', inventory)
        .order('created_at', ascending: false)
        .range(offset, offset + limit);
    final parsed = rows.map<InventoryTransaction>(_transactionFromRow).toList();
    final hasMore = parsed.length > limit;
    final items = parsed.take(limit).toList(growable: false);
    return InventoryPage(
      items: items,
      hasMore: hasMore,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<InventoryTransaction> receiveStock(StockReceiptRequest request) async {
    final inventoryId = await _requiredInventoryId(request.vaccineId);
    final row = await _client.rpc(
      'receive_vaccine_stock',
      params: {
        'target_inventory_id': inventoryId,
        'lot': request.lotNumber,
        'manufacturer_name': request.manufacturer,
        'expiry': _date(request.expiryDate),
        'received_quantity': request.quantity,
        'delivery_ref': request.referenceNumber,
        'package_ok': request.packagingIntact,
        'cold_chain_ok': request.coldChainVerified,
        'vvm': _snake(request.vvmStatus.name),
        'review_notes': request.safetyNotes,
      },
    );
    return _loadTransaction((row as Map<String, dynamic>)['id'] as String);
  }

  @override
  Future<InventoryTransaction> adjustStock(StockAdjustmentRequest request) =>
      _move(
        batchId: request.batchId,
        type: request.quantityChange >= 0
            ? 'adjustment_increase'
            : 'adjustment_decrease',
        quantity: request.quantityChange,
        reason: request.reason,
        reference: request.referenceNumber,
      );

  @override
  Future<InventoryTransaction> recordWastage(WastageRequest request) => _move(
    batchId: request.batchId,
    type: 'wastage',
    quantity: -request.quantity.abs(),
    reason: request.reason,
    reference: '',
  );

  @override
  Future<void> consumeDoses(Map<String, int> dosesByVaccineId) async {
    for (final entry in dosesByVaccineId.entries) {
      var remaining = entry.value;
      if (remaining <= 0) continue;
      final batches = await getBatches(entry.key);
      for (final batch in batches) {
        if (remaining == 0) break;
        if (!batch.canBeUsed || batch.expiryDate.isBefore(DateTime.now())) {
          continue;
        }
        final take = remaining > batch.availableDoses
            ? batch.availableDoses
            : remaining;
        await _move(
          batchId: batch.id,
          type: 'administration',
          quantity: take,
          reason: 'Vaccine administered through child vaccination workflow',
          reference: entry.key,
        );
        remaining -= take;
      }
      if (remaining > 0) {
        throw StateError('Insufficient usable stock for ${entry.key}.');
      }
    }
  }

  @override
  Future<VaccineBatch> reviewBatchSafety(
    BatchSafetyReviewRequest request,
  ) async {
    final row = await _client
        .from('vaccine_batches')
        .update({
          'safety_status': _snake(request.decision.name),
          'safety_notes': request.notes,
          'safety_reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'safety_reviewed_by': _client.auth.currentUser!.id,
        })
        .eq('id', request.batchId)
        .select(_batchSelect)
        .single();
    return _batchFromRow(row);
  }

  Future<InventoryTransaction> _move({
    required String batchId,
    required String type,
    required int quantity,
    required String reason,
    required String reference,
  }) async {
    final row = await _client.rpc(
      'record_inventory_movement',
      params: {
        'target_batch_id': batchId,
        'movement_type': type,
        'movement_quantity': quantity,
        'movement_reason': reason,
        'movement_reference': reference,
      },
    );
    return _loadTransaction((row as Map<String, dynamic>)['id'] as String);
  }

  Future<InventoryTransaction> _loadTransaction(String id) async {
    final row = await _client
        .from('inventory_transactions')
        .select(_transactionSelect)
        .eq('id', id)
        .single();
    return _transactionFromRow(row);
  }

  Future<String?> _inventoryId(String vaccineId) async {
    final row = await _client
        .from('vaccine_inventory')
        .select('id')
        .eq('vaccine_id', vaccineId)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<String> _requiredInventoryId(String vaccineId) async =>
      await _inventoryId(vaccineId) ??
      (throw StateError('No inventory record exists for this vaccine.'));

  VaccineInventory _inventoryFromRow(Map<String, dynamic> row) {
    final vaccine = row['vaccine_definitions'] as Map<String, dynamic>;
    final batches = (row['vaccine_batches'] as List? ?? const []);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final available = batches.fold<int>(0, (sum, item) {
      final batch = item as Map;
      final expiry = DateTime.parse(batch['expiry_date'] as String);
      final quantity = batch['quantity'] as int;
      final usable =
          quantity > 0 &&
          !expiry.isBefore(today) &&
          batch['safety_status'] == 'usable' &&
          batch['packaging_intact'] == true &&
          batch['cold_chain_verified'] == true &&
          ['acceptable', 'not_applicable'].contains(batch['vvm_status']);
      return sum + (usable ? quantity : 0);
    });
    return VaccineInventory(
      id: row['id'] as String,
      vaccineId: vaccine['id'] as String,
      vaccineName: vaccine['name'] as String,
      facilityId: row['facility_id'] as String,
      availableDoses: available,
      lowStockThreshold: row['reorder_level'] as int? ?? 0,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  VaccineBatch _batchFromRow(Map<String, dynamic> row) {
    final inventory = row['vaccine_inventory'] as Map<String, dynamic>;
    final vaccine = inventory['vaccine_definitions'] as Map<String, dynamic>;
    return VaccineBatch(
      id: row['id'] as String,
      batchCode: row['batch_code'] as String,
      facilityId: inventory['facility_id'] as String,
      vaccineId: inventory['vaccine_id'] as String,
      vaccineName: vaccine['name'] as String,
      lotNumber: row['lot_number'] as String,
      manufacturer: row['manufacturer'] as String? ?? '',
      expiryDate: DateTime.parse(row['expiry_date'] as String),
      quantityReceived: row['quantity_received'] as int,
      availableDoses: row['quantity'] as int,
      receivedAt: DateTime.parse(row['received_at'] as String),
      receivedByUserId: row['received_by'] as String,
      packagingIntact: row['packaging_intact'] as bool,
      coldChainVerified: row['cold_chain_verified'] as bool,
      vvmStatus: VaccineVvmStatus.values.byName(
        _camel(row['vvm_status'] as String),
      ),
      safetyStatus: VaccineBatchSafetyStatus.values.byName(
        _camel(row['safety_status'] as String),
      ),
      safetyNotes: row['safety_notes'] as String? ?? '',
      safetyReviewedAt: DateTime.parse(row['safety_reviewed_at'] as String),
      safetyReviewedByUserId: row['safety_reviewed_by'] as String,
    );
  }

  InventoryTransaction _transactionFromRow(Map<String, dynamic> row) {
    final inventory = row['vaccine_inventory'] as Map<String, dynamic>;
    final vaccine = inventory['vaccine_definitions'] as Map<String, dynamic>;
    return InventoryTransaction(
      id: row['id'] as String,
      transactionCode: row['transaction_code'] as String,
      facilityId: inventory['facility_id'] as String,
      vaccineId: inventory['vaccine_id'] as String,
      vaccineName: vaccine['name'] as String,
      batchId: row['batch_id'] as String?,
      type: InventoryTransactionType.values.byName(
        _camel(row['transaction_type'] as String),
      ),
      quantityChange: row['quantity_delta'] as int,
      balanceBefore: row['balance_before'] as int,
      balanceAfter: row['balance_after'] as int,
      reason: row['reason'] as String,
      referenceNumber: row['reference_number'] as String? ?? '',
      recordedAt: DateTime.parse(row['created_at'] as String),
      recordedByUserId: row['performed_by'] as String,
    );
  }

  static String _date(DateTime value) =>
      value.toIso8601String().split('T').first;
  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
  static String _camel(String value) => value.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}
