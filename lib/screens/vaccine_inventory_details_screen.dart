import 'package:flutter/material.dart';

import '../models/inventory_transaction.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import '../services/session_context.dart';
import '../utils/user_facing_error.dart';
import '../repositories/inventory_repository.dart';
import '../utils/number_formatter.dart';
import 'inventory_stock_action_screen.dart';
import '../widgets/app_loading.dart';

class VaccineInventoryDetailsScreen extends StatefulWidget {
  final String vaccineId;
  final InventoryRepository repository;

  const VaccineInventoryDetailsScreen({
    super.key,
    required this.vaccineId,
    required this.repository,
  });

  @override
  State<VaccineInventoryDetailsScreen> createState() =>
      _VaccineInventoryDetailsScreenState();
}

class _VaccineInventoryDetailsScreenState
    extends State<VaccineInventoryDetailsScreen> {
  late Future<_InventoryDetailsData> _details;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _details = _loadDetails();

  Future<_InventoryDetailsData> _loadDetails() async {
    final inventory = await widget.repository.getVaccineInventory(
      widget.vaccineId,
    );

    if (inventory == null) {
      throw StateError('Vaccine inventory was not found.');
    }

    final results = await Future.wait([
      widget.repository.getBatches(widget.vaccineId),
      widget.repository.getTransactions(widget.vaccineId),
    ]);

    return _InventoryDetailsData(
      inventory: inventory,
      batches: results[0] as List<VaccineBatch>,
      transactions: results[1] as List<InventoryTransaction>,
    );
  }

  Future<void> _openAction(
    InventoryStockAction action,
    _InventoryDetailsData data,
  ) async {
    final transaction = await Navigator.push<InventoryTransaction>(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryStockActionScreen(
          action: action,
          inventory: data.inventory,
          batches: data.batches,
          repository: widget.repository,
        ),
      ),
    );

    if (transaction == null || !mounted) return;

    final previousBatch = transaction.batchId == null
        ? null
        : data.batches
              .where((batch) => batch.id == transaction.batchId)
              .firstOrNull;
    final expectedBatchQuantity = previousBatch == null
        ? null
        : previousBatch.availableDoses + transaction.quantityChange;

    // Update the visible cards immediately from the committed transaction.
    // This prevents a short-lived stale read from making a successful stock
    // action look as if it did nothing.
    if (previousBatch != null &&
        transaction.type != InventoryTransactionType.received) {
      final updatedBatches = data.batches
          .map(
            (batch) => batch.id == previousBatch.id
                ? batch.copyWith(availableDoses: expectedBatchQuantity)
                : batch,
          )
          .toList(growable: false);
      setState(
        () => _details = Future.value(
          _InventoryDetailsData(
            inventory: data.inventory.copyWith(
              availableDoses:
                  data.inventory.availableDoses + transaction.quantityChange,
            ),
            batches: updatedBatches,
            transactions: [
              transaction,
              ...data.transactions.where((item) => item.id != transaction.id),
            ],
          ),
        ),
      );
    }

    // Confirm the same values against Supabase before replacing the local
    // update. The app may briefly read an older snapshot after an RPC.
    await _refreshAfterStockWrite(
      batchId: transaction.batchId,
      expectedBatchQuantity: expectedBatchQuantity,
    );

    final message = switch (transaction.type) {
      InventoryTransactionType.received when transaction.quantityChange > 0 =>
        '${formatWholeNumber(transaction.quantityChange)} doses received and added to usable stock.',
      InventoryTransactionType.received =>
        'Stock received but quarantined. Usable doses were not increased.',
      InventoryTransactionType.adjustmentIncrease =>
        '${formatWholeNumber(transaction.quantityChange)} doses added through stock adjustment.',
      InventoryTransactionType.adjustmentDecrease =>
        '${formatWholeNumber(transaction.quantityChange.abs())} doses removed through stock adjustment.',
      InventoryTransactionType.wastage =>
        '${formatWholeNumber(transaction.quantityChange.abs())} wasted doses recorded.',
      _ => 'Stock updated successfully.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshAfterStockWrite({
    String? batchId,
    int? expectedBatchQuantity,
  }) async {
    const delays = <Duration>[
      Duration(milliseconds: 300),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1500),
    ];
    for (var attempt = 0; attempt < delays.length; attempt++) {
      if (!mounted) return;
      await Future<void>.delayed(delays[attempt]);
      if (!mounted) return;
      final nextDetails = _loadDetails();
      try {
        final loaded = await nextDetails;
        final loadedBatch = batchId == null
            ? null
            : loaded.batches.where((batch) => batch.id == batchId).firstOrNull;
        final isCurrent = expectedBatchQuantity == null ||
            loadedBatch?.availableDoses == expectedBatchQuantity;
        if (isCurrent && expectedBatchQuantity != null) {
          setState(() => _details = Future.value(loaded));
          return;
        }
        if (isCurrent) setState(() => _details = Future.value(loaded));
      } catch (_) {
        if (attempt == delays.length - 1) return;
      }
    }
  }

  Future<void> _reviewBatch(VaccineBatch batch) async {
    var decision = batch.safetyStatus == VaccineBatchSafetyStatus.quarantined
        ? VaccineBatchSafetyStatus.usable
        : VaccineBatchSafetyStatus.quarantined;

    final notes = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Review Batch Safety'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lot ${batch.lotNumber}'),
                const SizedBox(height: 14),
                DropdownButtonFormField<VaccineBatchSafetyStatus>(
                  initialValue: decision,
                  decoration: const InputDecoration(labelText: 'Decision'),
                  items: VaccineBatchSafetyStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_safetyLabel(status)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => decision = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Review notes',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (notes.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter the review notes.')),
                  );
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save Decision'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      notes.dispose();
      return;
    }

    try {
      await widget.repository.reviewBatchSafety(
        BatchSafetyReviewRequest(
          vaccineId: batch.vaccineId,
          batchId: batch.id,
          decision: decision,
          notes: notes.text.trim(),
          reviewedByUserId: SessionContext.userId,
        ),
      );

      if (!mounted) return;

      setState(_reload);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The batch safety review could not be saved. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Stock Details',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: FutureBuilder<_InventoryDetailsData>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            title: 'Loading stock details',
            message: 'Retrieving batches and transaction history.',
          );
        }

        if (!snapshot.hasData) {
          return _DetailsError(
            message:
                snapshot.error?.toString() ?? 'Unable to load stock details.',
            onRetry: () => setState(_reload),
          );
        }

        final data = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            _StockSummary(inventory: data.inventory),
            const SizedBox(height: 16),
            Text(
              'Stock Actions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _StockActions(
              onReceive: () => _openAction(InventoryStockAction.receive, data),
              onAdjust:
                  data.batches.any(
                    (batch) =>
                        batch.canBeUsed &&
                        batch.statusAsOf(DateTime.now()) !=
                            VaccineBatchStatus.expired,
                  )
                  ? () => _openAction(InventoryStockAction.adjust, data)
                  : null,
              onWastage:
                  data.batches.any(
                    (batch) =>
                        batch.canBeUsed &&
                        batch.statusAsOf(DateTime.now()) !=
                            VaccineBatchStatus.expired,
                  )
                  ? () => _openAction(InventoryStockAction.wastage, data)
                  : null,
            ),
            const SizedBox(height: 22),
            const _SectionTitle(
              title: 'Batches and Expiry',
              subtitle:
                  'Stock is issued from the earliest-expiring usable batch.',
            ),
            const SizedBox(height: 10),
            if (data.batches.isEmpty)
              const _EmptyCard(
                text: 'No batches recorded. Receive stock to create a batch.',
              )
            else
              ...data.batches.map(
                (batch) => _BatchCard(
                  batch,
                  onReview:
                      batch.safetyStatus == VaccineBatchSafetyStatus.discarded
                      ? null
                      : () => _reviewBatch(batch),
                ),
              ),
            const SizedBox(height: 18),
            const _SectionTitle(
              title: 'Transaction History',
              subtitle: 'Every stock increase or decrease is recorded.',
            ),
            const SizedBox(height: 10),
            if (data.transactions.isEmpty)
              const _EmptyCard(text: 'No stock transactions recorded.')
            else
              ...data.transactions.map(
                (transaction) => _TransactionCard(
                  transaction: transaction,
                  batches: data.batches,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _InventoryDetailsData {
  final VaccineInventory inventory;
  final List<VaccineBatch> batches;
  final List<InventoryTransaction> transactions;

  const _InventoryDetailsData({
    required this.inventory,
    required this.batches,
    required this.transactions,
  });
}

class _StockSummary extends StatelessWidget {
  final VaccineInventory inventory;

  const _StockSummary({required this.inventory});

  @override
  Widget build(BuildContext context) {
    final (label, color) = inventory.isUnavailable
        ? ('Unavailable', Colors.red)
        : inventory.isLowStock
        ? ('Low stock', Colors.orange)
        : ('Available', Colors.green);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(Icons.vaccines_outlined, color: color, size: 29),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inventory.vaccineName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$label • ${formatWholeNumber(inventory.availableDoses)} doses',
                ),
                const SizedBox(height: 3),
                Text(
                  'Updated ${_dateTime(inventory.updatedAt)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockActions extends StatelessWidget {
  final VoidCallback onReceive;
  final VoidCallback? onAdjust;
  final VoidCallback? onWastage;

  const _StockActions({
    required this.onReceive,
    required this.onAdjust,
    required this.onWastage,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 500 ? 3 : 2;
      final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ActionButton(
            width: width,
            icon: Icons.add_box_outlined,
            label: 'Receive stock',
            onPressed: onReceive,
          ),
          _ActionButton(
            width: width,
            icon: Icons.tune_rounded,
            label: 'Adjust stock',
            onPressed: onAdjust,
          ),
          _ActionButton(
            width: width,
            icon: Icons.delete_outline_rounded,
            label: 'Record wastage',
            onPressed: onWastage,
          ),
        ],
      );
    },
  );
}

class _ActionButton extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.width,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 72,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12.5,
        ),
      ),
    ],
  );
}

class _BatchCard extends StatelessWidget {
  final VaccineBatch batch;
  final VoidCallback? onReview;

  const _BatchCard(this.batch, {required this.onReview});

  @override
  Widget build(BuildContext context) {
    final status = batch.statusAsOf(DateTime.now());

    final statusLabel = switch (status) {
      VaccineBatchStatus.usable => 'Usable',
      VaccineBatchStatus.expiringSoon => 'Expiring soon',
      VaccineBatchStatus.expired => 'Expired',
      VaccineBatchStatus.depleted => 'Depleted',
    };

    final safetyColor = switch (batch.safetyStatus) {
      VaccineBatchSafetyStatus.usable => Colors.green,
      VaccineBatchSafetyStatus.quarantined => Colors.orange,
      VaccineBatchSafetyStatus.discarded => Colors.red,
    };

    return Card(
      key: ValueKey(batch.id),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
        title: Text(
          batch.lotNumber,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 8,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${formatWholeNumber(batch.availableDoses)} '
                'dose${batch.availableDoses == 1 ? '' : 's'} • '
                'Expires ${_date(batch.expiryDate)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              _StatusLabel(
                label: _safetyLabel(batch.safetyStatus),
                color: safetyColor,
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Batch quantity',
                value: batch.safetyStatus == VaccineBatchSafetyStatus.usable
                    ? '${formatWholeNumber(batch.availableDoses)} '
                          'usable doses'
                    : '${formatWholeNumber(batch.availableDoses)} '
                          'doses excluded from usable stock',
              ),
              _DetailRow(label: 'Expiry', value: _date(batch.expiryDate)),
              _DetailRow(label: 'Expiry status', value: statusLabel),
              _DetailRow(
                label: 'Safety check',
                value:
                    '${batch.packagingIntact ? 'Package intact' : 'Package issue'} • '
                    '${batch.coldChainVerified ? 'Condition verified' : 'Not verified'} • '
                    'VVM ${_vvmLabel(batch.vvmStatus)}',
              ),
              if (batch.safetyNotes.isNotEmpty)
                _DetailRow(label: 'Safety notes', value: batch.safetyNotes),
              if (batch.manufacturer.isNotEmpty)
                _DetailRow(label: 'Manufacturer', value: batch.manufacturer),
              _DetailRow(label: 'Batch ID', value: batch.batchCode),
              if (onReview != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(
                      batch.safetyStatus == VaccineBatchSafetyStatus.quarantined
                          ? 'Review quarantined batch'
                          : 'Update safety status',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final InventoryTransaction transaction;
  final List<VaccineBatch> batches;

  const _TransactionCard({required this.transaction, required this.batches});

  @override
  Widget build(BuildContext context) {
    final color = _transactionColor(transaction);

    final batch = transaction.batchId == null
        ? null
        : batches.where((item) => item.id == transaction.batchId).firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 16),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _transactionIcon(transaction.type),
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          _transactionLabel(transaction.type),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _transactionQuantityLabel(transaction),
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _dateTime(transaction.recordedAt),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 5),
          _DetailRow(label: 'Vaccine', value: transaction.vaccineName),
          _DetailRow(
            label: 'Stock movement',
            value: _transactionQuantityLabel(transaction),
          ),
          _DetailRow(
            label: 'Previous balance',
            value: '${formatWholeNumber(transaction.balanceBefore)} doses',
          ),
          _DetailRow(
            label: 'New balance',
            value: '${formatWholeNumber(transaction.balanceAfter)} doses',
          ),
          if (batch != null) ...[
            _DetailRow(label: 'Lot number', value: batch.lotNumber),
            _DetailRow(label: 'Batch ID', value: batch.batchCode),
          ],
          _DetailRow(label: 'Reason', value: transaction.reason),
          _DetailRow(
            label: 'Reference',
            value: transaction.referenceNumber.isEmpty
                ? 'Not provided'
                : transaction.referenceNumber,
          ),
          _DetailRow(
            label: 'Recorded at',
            value: _dateTime(transaction.recordedAt),
          ),
          _DetailRow(label: 'Recorded by', value: transaction.recordedByUserId),
          _DetailRow(
            label: 'Transaction ID',
            value: transaction.transactionCode,
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 390;

      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text),
  );
}

class _DetailsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DetailsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Unable to load stock details.',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

String _transactionLabel(InventoryTransactionType type) => switch (type) {
  InventoryTransactionType.received => 'Stock received',
  InventoryTransactionType.adjustmentIncrease => 'Stock adjustment',
  InventoryTransactionType.adjustmentDecrease => 'Stock adjustment',
  InventoryTransactionType.administration => 'Dose administered',
  InventoryTransactionType.wastage => 'Wastage recorded',
  InventoryTransactionType.batchSafetyReview => 'Batch safety reviewed',
};

IconData _transactionIcon(InventoryTransactionType type) => switch (type) {
  InventoryTransactionType.received => Icons.inventory_2_outlined,
  InventoryTransactionType.adjustmentIncrease => Icons.add_circle_outline,
  InventoryTransactionType.adjustmentDecrease => Icons.remove_circle_outline,
  InventoryTransactionType.administration => Icons.vaccines_outlined,
  InventoryTransactionType.wastage => Icons.delete_outline,
  InventoryTransactionType.batchSafetyReview => Icons.verified_user_outlined,
};

Color _transactionColor(InventoryTransaction transaction) =>
    switch (transaction.type) {
      InventoryTransactionType.received =>
        transaction.quantityChange > 0 ? Colors.green : Colors.orange,
      InventoryTransactionType.adjustmentIncrease => Colors.green,
      InventoryTransactionType.adjustmentDecrease => Colors.red,
      InventoryTransactionType.administration => Colors.blue,
      InventoryTransactionType.wastage => Colors.deepOrange,
      InventoryTransactionType.batchSafetyReview =>
        transaction.quantityChange == 0
            ? Colors.orange
            : transaction.quantityChange > 0
            ? Colors.green
            : Colors.red,
    };

String _transactionQuantityLabel(InventoryTransaction transaction) {
  final quantity = formatWholeNumber(transaction.quantityChange.abs());
  final doses =
      '$quantity dose${transaction.quantityChange.abs() == 1 ? '' : 's'}';
  return switch (transaction.type) {
    InventoryTransactionType.received when transaction.quantityChange > 0 =>
      '$doses added',
    InventoryTransactionType.received => 'Received — awaiting safety clearance',
    InventoryTransactionType.adjustmentIncrease => '$doses added',
    InventoryTransactionType.adjustmentDecrease => '$doses removed',
    InventoryTransactionType.administration => '$doses administered',
    InventoryTransactionType.wastage => '$doses recorded as wastage',
    InventoryTransactionType.batchSafetyReview
        when transaction.quantityChange > 0 =>
      '$doses released to usable stock',
    InventoryTransactionType.batchSafetyReview
        when transaction.quantityChange < 0 =>
      '$doses removed from usable stock',
    InventoryTransactionType.batchSafetyReview => 'No stock balance change',
  };
}

String _safetyLabel(VaccineBatchSafetyStatus status) => switch (status) {
  VaccineBatchSafetyStatus.usable => 'Usable',
  VaccineBatchSafetyStatus.quarantined => 'Quarantined',
  VaccineBatchSafetyStatus.discarded => 'Discarded',
};

String _vvmLabel(VaccineVvmStatus status) => switch (status) {
  VaccineVvmStatus.notApplicable => 'not applicable',
  VaccineVvmStatus.acceptable => 'acceptable',
  VaccineVvmStatus.notAcceptable => 'not acceptable',
  VaccineVvmStatus.unknown => 'unknown',
};

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.year}';

String _dateTime(DateTime value) =>
    '${_date(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
