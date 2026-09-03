import 'package:flutter/material.dart';

import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/repository_registry.dart';
import '../utils/number_formatter.dart';
import 'vaccine_inventory_details_screen.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';

enum _InventoryFilter { all, available, lowStock, unavailable }

class VaccineInventoryScreen extends StatefulWidget {
  const VaccineInventoryScreen({super.key});

  @override
  State<VaccineInventoryScreen> createState() => _VaccineInventoryScreenState();
}

class _VaccineInventoryScreenState extends State<VaccineInventoryScreen> {
  final InventoryRepository _repository =
      RepositoryRegistry.instance.inventoryRepository;
  late Future<_InventoryOverviewData> _inventory;
  _InventoryFilter _filter = _InventoryFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _inventory = _loadOverview();

  Future<_InventoryOverviewData> _loadOverview() async {
    final results = await Future.wait([
      _repository.getInventoryOverview(),
      _repository.getAllBatches(),
    ]);
    return _InventoryOverviewData(
      inventory: results[0] as List<VaccineInventory>,
      batches: results[1] as List<VaccineBatch>,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _inventory;
  }

  List<VaccineInventory> _filtered(List<VaccineInventory> items) =>
      switch (_filter) {
        _InventoryFilter.all => items,
        _InventoryFilter.available =>
          items
              .where((item) => item.isAvailable && !item.isLowStock)
              .toList(growable: false),
        _InventoryFilter.lowStock =>
          items.where((item) => item.isLowStock).toList(growable: false),
        _InventoryFilter.unavailable =>
          items.where((item) => item.isUnavailable).toList(growable: false),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Vaccine Inventory',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: const [WorkerAppBarActions()],
    ),
    body: FutureBuilder<_InventoryOverviewData>(
      future: _inventory,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            title: 'Loading vaccine inventory',
            message: 'Checking usable stock and batch availability.',
          );
        }
        if (snapshot.hasError) {
          return _InventoryError(onRetry: () => setState(_reload));
        }
        final data = snapshot.data ?? const _InventoryOverviewData();
        final inventory = data.inventory;
        final visible = _filtered(inventory);
        final attentionBatches = data.batches
            .where(
              (batch) =>
                  batch.safetyStatus == VaccineBatchSafetyStatus.quarantined ||
                  (batch.availableDoses > 0 &&
                      batch.statusAsOf(DateTime.now()) ==
                          VaccineBatchStatus.expired),
            )
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              const _FacilityHeader(),
              const SizedBox(height: 16),
              _SummaryGrid(
                items: inventory,
                attentionCount: attentionBatches.length,
              ),
              if (attentionBatches.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AttentionBanner(count: attentionBatches.length),
              ],
              const SizedBox(height: 18),
              Text(
                'Stock Status',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                'Monitor the current dose availability used by the vaccination workflow.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _InventoryFilter.values
                    .map(
                      (filter) => FilterChip(
                        selected: _filter == filter,
                        label: Text(_filterLabel(filter)),
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const _EmptyInventoryFilter()
              else
                ...visible.map(
                  (inventory) => _InventoryCard(
                    inventory,
                    attentionCount: data.batches
                        .where(
                          (batch) =>
                              batch.vaccineId == inventory.vaccineId &&
                              (batch.safetyStatus ==
                                      VaccineBatchSafetyStatus.quarantined ||
                                  (batch.availableDoses > 0 &&
                                      batch.statusAsOf(DateTime.now()) ==
                                          VaccineBatchStatus.expired)),
                        )
                        .length,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VaccineInventoryDetailsScreen(
                            vaccineId: inventory.vaccineId,
                            repository: _repository,
                          ),
                        ),
                      );
                      if (!mounted) return;
                      await _refreshAfterStockAction();
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Inventory is shared with vaccination, referral, batch, and stock-history workflows.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  String _filterLabel(_InventoryFilter filter) => switch (filter) {
    _InventoryFilter.all => 'All',
    _InventoryFilter.available => 'Available',
    _InventoryFilter.lowStock => 'Low stock',
    _InventoryFilter.unavailable => 'Unavailable',
  };

  Future<void> _refreshAfterStockAction() async {
    const delays = <Duration>[
      Duration(milliseconds: 300),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1500),
    ];
    for (var attempt = 0; attempt < delays.length; attempt++) {
      if (!mounted) return;
      await Future<void>.delayed(delays[attempt]);
      if (!mounted) return;
      final nextInventory = _loadOverview();
      setState(() => _inventory = nextInventory);
      try {
        await nextInventory;
      } catch (_) {
        if (attempt == delays.length - 1) return;
      }
    }
  }
}

class _FacilityHeader extends StatelessWidget {
  const _FacilityHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
      ),
    ),
    child: const Row(
      children: [
        Icon(Icons.local_hospital_outlined),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barangay Bugo Health Center',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'Current facility inventory',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  final List<VaccineInventory> items;
  final int attentionCount;

  const _SummaryGrid({required this.items, required this.attentionCount});

  @override
  Widget build(BuildContext context) {
    final available = items
        .where((item) => item.isAvailable && !item.isLowStock)
        .length;
    final low = items.where((item) => item.isLowStock).length;
    final unavailable = items.where((item) => item.isUnavailable).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 620
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: width,
              value: '$available',
              label: 'Available',
              color: Colors.green,
            ),
            _SummaryCard(
              width: width,
              value: '$low',
              label: 'Low stock',
              color: Colors.orange,
            ),
            _SummaryCard(
              width: width,
              value: '$unavailable',
              label: 'Unavailable',
              color: Colors.red,
            ),
            _SummaryCard(
              width: width,
              value: '$attentionCount',
              label: 'Needs review',
              color: Colors.deepOrange,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double width;
  final String value;
  final String label;
  final Color color;

  const _SummaryCard({
    required this.width,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    ),
  );
}

class _InventoryCard extends StatelessWidget {
  final VaccineInventory inventory;
  final int attentionCount;
  final VoidCallback onTap;

  const _InventoryCard(
    this.inventory, {
    required this.attentionCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = inventory.isUnavailable
        ? ('Unavailable', Colors.red)
        : inventory.isLowStock
        ? ('Low stock', Colors.orange)
        : ('Available', Colors.green);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.vaccines_outlined, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inventory.vaccineName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (attentionCount > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '$attentionCount batch${attentionCount == 1 ? '' : 'es'} needs review',
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${formatWholeNumber(inventory.availableDoses)} dose${inventory.availableDoses == 1 ? '' : 's'} available',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryOverviewData {
  final List<VaccineInventory> inventory;
  final List<VaccineBatch> batches;

  const _InventoryOverviewData({
    this.inventory = const [],
    this.batches = const [],
  });
}

class _AttentionBanner extends StatelessWidget {
  final int count;

  const _AttentionBanner({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.deepOrange.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.20)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$count batch${count == 1 ? '' : 'es'} ${count == 1 ? 'requires' : 'require'} safety or expiry review. Open the vaccine stock details to take action.',
            style: const TextStyle(height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _EmptyInventoryFilter extends StatelessWidget {
  const _EmptyInventoryFilter();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Center(child: Text('No vaccines match this stock status.')),
  );
}

class _InventoryError extends StatelessWidget {
  final VoidCallback onRetry;

  const _InventoryError({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 12),
          const Text('Unable to load vaccine inventory.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
