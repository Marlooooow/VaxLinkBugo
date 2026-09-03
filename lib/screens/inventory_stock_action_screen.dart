import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_transaction.dart';
import '../services/session_context.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import '../repositories/inventory_repository.dart';
import '../utils/number_formatter.dart';

enum InventoryStockAction { receive, adjust, wastage }

class InventoryStockActionScreen extends StatefulWidget {
  final InventoryStockAction action;
  final VaccineInventory inventory;
  final List<VaccineBatch> batches;
  final InventoryRepository repository;

  const InventoryStockActionScreen({
    super.key,
    required this.action,
    required this.inventory,
    required this.batches,
    required this.repository,
  });

  @override
  State<InventoryStockActionScreen> createState() =>
      _InventoryStockActionScreenState();
}

class _InventoryStockActionScreenState
    extends State<InventoryStockActionScreen> {
  final _quantity = TextEditingController();
  final _lotNumber = TextEditingController();
  final _manufacturer = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  DateTime? _expiryDate;
  String? _batchId;
  bool _adjustmentIncrease = true;
  bool _packagingIntact = true;
  bool _coldChainVerified = true;
  VaccineVvmStatus _vvmStatus = VaccineVvmStatus.acceptable;
  String? _quantityError;
  String? _lotNumberError;
  String? _expiryDateError;
  String? _referenceError;
  bool _saving = false;

  List<VaccineBatch> get _selectableBatches => widget.batches
      .where(
        (batch) =>
            batch.canBeUsed &&
            batch.statusAsOf(DateTime.now()) != VaccineBatchStatus.expired,
      )
      .toList(growable: false);

  VaccineBatch? get _selectedBatch {
    if (_batchId == null) return null;
    return _selectableBatches
        .where((batch) => batch.id == _batchId)
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    if (_selectableBatches.isNotEmpty) {
      _batchId = _selectableBatches.first.id;
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _lotNumber.dispose();
    _manufacturer.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _title => switch (widget.action) {
    InventoryStockAction.receive => 'Receive Stock',
    InventoryStockAction.adjust => 'Adjust Stock',
    InventoryStockAction.wastage => 'Record Wastage',
  };

  Future<void> _selectExpiry() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today.add(const Duration(days: 365)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'SELECT BATCH EXPIRY DATE',
    );
    if (selected != null) {
      setState(() {
        _expiryDate = selected;
        _expiryDateError = null;
      });
    }
  }

  Future<void> _submit() async {
    final quantityText = _quantity.text.trim();
    final quantity = int.tryParse(quantityText);
    if (quantityText.isEmpty) {
      setState(() => _quantityError = 'Enter the number of doses.');
      return;
    }
    if (quantity == null) {
      setState(
        () => _quantityError =
            'Enter a whole number of doses. Decimal values are not allowed.',
      );
      return;
    }
    if (quantity <= 0) {
      setState(
        () => _quantityError = 'The quantity must be greater than zero.',
      );
      return;
    }
    setState(() => _quantityError = null);
    if (widget.action == InventoryStockAction.receive) {
      final lotNumberMissing = _lotNumber.text.trim().isEmpty;
      final expiryDateMissing = _expiryDate == null;
      final referenceMissing = _reference.text.trim().isEmpty;
      setState(() {
        _lotNumberError = lotNumberMissing
            ? 'Enter the lot / batch number.'
            : null;
        _expiryDateError = expiryDateMissing ? 'Select the expiry date.' : null;
        _referenceError = referenceMissing
            ? 'Enter the delivery reference number.'
            : null;
      });
      if (lotNumberMissing || expiryDateMissing || referenceMissing) return;
    }
    if (widget.action == InventoryStockAction.receive &&
        !_receiptIsUsable &&
        _reason.text.trim().isEmpty) {
      _message('Enter safety remarks explaining why the batch is uncertain.');
      return;
    }
    if (widget.action != InventoryStockAction.receive && _batchId == null) {
      _message('Select a vaccine batch first.');
      return;
    }
    final selectedBatch = _selectedBatch;
    final removesFromBatch =
        widget.action == InventoryStockAction.wastage ||
        (widget.action == InventoryStockAction.adjust && !_adjustmentIncrease);
    if (removesFromBatch &&
        selectedBatch != null &&
        quantity > selectedBatch.availableDoses) {
      setState(
        () => _quantityError =
            'This batch has only ${formatWholeNumber(selectedBatch.availableDoses)} doses. Enter ${formatWholeNumber(selectedBatch.availableDoses)} or fewer.',
      );
      return;
    }
    if (widget.action != InventoryStockAction.receive &&
        _reason.text.trim().isEmpty) {
      _message('Enter the reason for this stock change.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Confirm $_title'),
        content: Text(
          '${widget.inventory.vaccineName}: ${_adjustedQuantityLabel(quantity)}. '
          'This will update inventory and create an audit transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back to edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      late final InventoryTransaction transaction;
      switch (widget.action) {
        case InventoryStockAction.receive:
          transaction = await widget.repository.receiveStock(
            StockReceiptRequest(
              vaccineId: widget.inventory.vaccineId,
              quantity: quantity,
              lotNumber: _lotNumber.text.trim(),
              manufacturer: _manufacturer.text.trim(),
              expiryDate: _expiryDate!,
              referenceNumber: _reference.text.trim(),
              recordedByUserId: SessionContext.userId,
              packagingIntact: _packagingIntact,
              coldChainVerified: _coldChainVerified,
              vvmStatus: _vvmStatus,
              safetyNotes: _reason.text.trim(),
            ),
          );
        case InventoryStockAction.adjust:
          transaction = await widget.repository.adjustStock(
            StockAdjustmentRequest(
              vaccineId: widget.inventory.vaccineId,
              batchId: _batchId!,
              quantityChange: _adjustmentIncrease ? quantity : -quantity,
              reason: _reason.text.trim(),
              referenceNumber: _reference.text.trim(),
              recordedByUserId: SessionContext.userId,
            ),
          );
        case InventoryStockAction.wastage:
          transaction = await widget.repository.recordWastage(
            WastageRequest(
              vaccineId: widget.inventory.vaccineId,
              batchId: _batchId!,
              quantity: quantity,
              reason: _reason.text.trim(),
              recordedByUserId: SessionContext.userId,
            ),
          );
      }
      if (!mounted) return;
      Navigator.pop(context, transaction);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(
        error
            .toString()
            .replaceFirst('Invalid argument(s): ', '')
            .replaceFirst('Bad state: ', ''),
      );
    }
  }

  String _adjustedQuantityLabel(int quantity) => switch (widget.action) {
    InventoryStockAction.receive =>
      '+${formatWholeNumber(quantity)} received doses',
    InventoryStockAction.adjust =>
      '${_adjustmentIncrease ? '+' : '-'}${formatWholeNumber(quantity)} adjusted doses',
    InventoryStockAction.wastage =>
      '-${formatWholeNumber(quantity)} wasted doses',
  };

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        _ActionHeader(inventory: widget.inventory, action: widget.action),
        const SizedBox(height: 18),
        if (widget.action == InventoryStockAction.receive) ...[
          TextField(
            controller: _lotNumber,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) {
              if (_lotNumberError != null) {
                setState(() => _lotNumberError = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Lot / batch number',
              errorText: _lotNumberError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manufacturer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Manufacturer (optional)',
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectExpiry,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Expiry date',
                suffixIcon: const Icon(Icons.calendar_month_outlined),
                errorText: _expiryDateError,
              ),
              child: Text(
                _expiryDate == null
                    ? 'Select expiry date'
                    : _formatDate(_expiryDate!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vaccine Safety Check',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  'No temperature or sensor data is required.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _packagingIntact,
                  title: const Text('Packaging is intact'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) =>
                      setState(() => _packagingIntact = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _coldChainVerified,
                  title: const Text('Cold-chain condition verified on receipt'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) =>
                      setState(() => _coldChainVerified = value ?? false),
                ),
                DropdownButtonFormField<VaccineVvmStatus>(
                  initialValue: _vvmStatus,
                  decoration: const InputDecoration(labelText: 'VVM status'),
                  items: VaccineVvmStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_vvmLabel(status)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _vvmStatus = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _receiptIsUsable
                        ? 'Safety remarks (optional)'
                        : 'Safety remarks',
                    alignLabelWithHint: true,
                  ),
                ),
                if (!_receiptIsUsable) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'This batch will be quarantined and excluded from available stock.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          DropdownButtonFormField<String>(
            initialValue: _batchId,
            decoration: const InputDecoration(labelText: 'Vaccine batch'),
            items: _selectableBatches
                .map(
                  (batch) => DropdownMenuItem(
                    value: batch.id,
                    child: Text(
                      '${batch.lotNumber} • ${formatWholeNumber(batch.availableDoses)} doses',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() {
              _batchId = value;
              _quantityError = null;
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.action == InventoryStockAction.adjust) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.add_rounded),
                label: Text('Increase'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.remove_rounded),
                label: Text('Decrease'),
              ),
            ],
            selected: {_adjustmentIncrease},
            onSelectionChanged: (value) => setState(() {
              _adjustmentIncrease = value.first;
              _quantityError = null;
            }),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _quantity,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: false,
            signed: false,
          ),
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              if (newValue.text.isEmpty ||
                  RegExp(r'^\d+$').hasMatch(newValue.text)) {
                return newValue;
              }
              return oldValue;
            }),
          ],
          onChanged: (_) {
            if (_quantityError != null) {
              setState(() => _quantityError = null);
            }
          },
          decoration: InputDecoration(
            labelText: 'Number of doses',
            helperText: 'Whole doses only',
            errorText: _quantityError,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.action != InventoryStockAction.receive) ...[
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.action == InventoryStockAction.wastage
                  ? 'Wastage reason'
                  : 'Adjustment reason',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.action != InventoryStockAction.wastage)
          TextField(
            controller: _reference,
            onChanged: (_) {
              if (_referenceError != null) {
                setState(() => _referenceError = null);
              }
            },
            decoration: InputDecoration(
              labelText: widget.action == InventoryStockAction.receive
                  ? 'Delivery reference number'
                  : 'Reference number (optional)',
              errorText: widget.action == InventoryStockAction.receive
                  ? _referenceError
                  : null,
            ),
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_saving ? 'Saving...' : 'Review and confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    ),
  );

  String _formatDate(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  bool get _receiptIsUsable =>
      _packagingIntact &&
      _coldChainVerified &&
      (_vvmStatus == VaccineVvmStatus.acceptable ||
          _vvmStatus == VaccineVvmStatus.notApplicable);

  String _vvmLabel(VaccineVvmStatus status) => switch (status) {
    VaccineVvmStatus.notApplicable => 'Not applicable',
    VaccineVvmStatus.acceptable => 'Acceptable',
    VaccineVvmStatus.notAcceptable => 'Not acceptable',
    VaccineVvmStatus.unknown => 'Unknown',
  };
}

class _ActionHeader extends StatelessWidget {
  final VaccineInventory inventory;
  final InventoryStockAction action;

  const _ActionHeader({required this.inventory, required this.action});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.vaccines_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inventory.vaccineName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${formatWholeNumber(inventory.availableDoses)} current doses',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
