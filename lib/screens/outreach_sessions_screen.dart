import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/outreach_session.dart';
import '../models/vaccine_batch.dart';
import '../repositories/outreach_repository.dart';
import '../repositories/repository_registry.dart';
import '../theme/status_colors.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_loading.dart';
import 'qr_scan_screen.dart';

class OutreachSessionsScreen extends StatefulWidget {
  final AppUser user;
  const OutreachSessionsScreen({super.key, required this.user});

  @override
  State<OutreachSessionsScreen> createState() => _OutreachSessionsScreenState();
}

class _OutreachSessionsScreenState extends State<OutreachSessionsScreen> {
  final OutreachRepository _repository =
      RepositoryRegistry.instance.outreachRepository;
  final _searchController = TextEditingController();
  final List<OutreachSession> _loadedSessions = [];
  late Future<List<OutreachSession>> _sessions;
  Timer? _searchDebounce;
  OutreachSessionStatus? _statusFilter;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _nextOffset = 0;
    _hasMore = false;
    _totalCount = 0;
    _sessions = _loadPage(reset: true);
  }

  Future<List<OutreachSession>> _loadPage({required bool reset}) async {
    final page = await _repository.getSessionsPage(
      search: _searchController.text,
      status: _statusFilter,
      limit: 20,
      offset: reset ? 0 : _nextOffset,
    );
    if (reset) _loadedSessions.clear();
    final ids = _loadedSessions.map((session) => session.id).toSet();
    _loadedSessions.addAll(page.items.where((session) => ids.add(session.id)));
    _hasMore = page.hasMore;
    _nextOffset = page.nextOffset;
    _totalCount = page.totalCount;
    return List.unmodifiable(_loadedSessions);
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(_reload);
    });
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _sessions;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final sessions = await _loadPage(reset: false);
      if (mounted) setState(() => _sessions = Future.value(sessions));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _create() async {
    final request = await showDialog<_NewOutreachRequest>(
      context: context,
      builder: (_) => const _CreateOutreachDialog(),
    );
    if (request == null || !mounted) return;
    try {
      final session = await _repository.createSession(
        title: request.title,
        location: request.location,
        scheduledOn: request.date,
        notes: request.notes,
      );
      if (!mounted) return;
      AppFeedback.success(context, message: 'Outreach session created.');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutreachSessionDetailsScreen(
            sessionId: session.id,
            user: widget.user,
          ),
        ),
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.failure(
        context,
        message: UserFacingError.message(
          error,
          fallback: 'The outreach session could not be created.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Outreach Immunization',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add_rounded),
      label: const Text('New session'),
    ),
    body: FutureBuilder<List<OutreachSession>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            title: 'Loading outreach sessions',
            message: 'Retrieving field activities and stock accountability.',
          );
        }
        if (snapshot.hasError) {
          return _MessageState(
            icon: Icons.cloud_off_outlined,
            message: 'Outreach sessions could not be loaded.',
            action: () => setState(_reload),
          );
        }
        final sessions = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search session, location, or ID',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            _searchDebounce?.cancel();
                            setState(_reload);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _statusFilter == null,
                      onSelected: (_) => setState(() {
                        _statusFilter = null;
                        _reload();
                      }),
                    ),
                    for (final status in OutreachSessionStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(_status(status)),
                          selected: _statusFilter == status,
                          onSelected: (_) => setState(() {
                            _statusFilter = status;
                            _reload();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${sessions.length} of $_totalCount session(s)',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: _MessageState(
                    icon: Icons.groups_2_outlined,
                    message: 'No matching outreach sessions were found.',
                  ),
                )
              else
                for (final session in sessions)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const CircleAvatar(
                        child: Icon(Icons.health_and_safety_outlined),
                      ),
                      title: Text(
                        session.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${session.location}\n${_date(session.scheduledOn)} • ${_status(session.status)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OutreachSessionDetailsScreen(
                              sessionId: session.id,
                              user: widget.user,
                            ),
                          ),
                        );
                        if (mounted) setState(_reload);
                      },
                    ),
                  ),
              if (_hasMore)
                OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadMore,
                  icon: _loadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    _loadingMore ? 'Loading more…' : 'Load more sessions',
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class OutreachSessionDetailsScreen extends StatefulWidget {
  final String sessionId;
  final AppUser user;
  const OutreachSessionDetailsScreen({
    super.key,
    required this.sessionId,
    required this.user,
  });

  @override
  State<OutreachSessionDetailsScreen> createState() =>
      _OutreachSessionDetailsScreenState();
}

class _OutreachSessionDetailsScreenState
    extends State<OutreachSessionDetailsScreen> {
  final OutreachRepository _repository =
      RepositoryRegistry.instance.outreachRepository;
  OutreachSession? _session;
  List<OutreachStockAllocation> _allocations = const [];
  _OutreachStockView _stockView = _OutreachStockView.allocated;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessionRequest = _repository.getSession(widget.sessionId);
      final allocationRequest = _repository.getAllocations(widget.sessionId);
      final session = await sessionRequest;
      final allocations = await allocationRequest;
      if (!mounted) return;
      setState(() {
        _session = session;
        _allocations = allocations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.failure(
        context,
        message: UserFacingError.message(
          error,
          fallback: 'The outreach session could not be loaded.',
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      await _load();
      if (!mounted) return;
      AppFeedback.success(context, message: success);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.failure(
        context,
        message: UserFacingError.message(
          error,
          fallback: 'The outreach action could not be completed.',
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _releaseStock() async {
    final request = await showDialog<_StockReleaseRequest>(
      context: context,
      builder: (_) => _ReleaseStockDialog(repository: _repository),
    );
    if (request == null) return;
    await _run(
      () => _repository.releaseStock(
        sessionId: widget.sessionId,
        batchId: request.batch.id,
        quantity: request.quantity,
      ),
      'Stock released to the outreach session.',
    );
  }

  Future<void> _start() async {
    final safety = await showDialog<_SafetyCheck>(
      context: context,
      builder: (_) => const _SafetyCheckDialog(),
    );
    if (safety == null) return;
    await _run(() async {
      await _repository.startSession(
        sessionId: widget.sessionId,
        packagingIntact: safety.packagingIntact,
        coldChainVerified: safety.coldChainVerified,
        vvmStatus: safety.vvmStatus,
        notes: safety.notes,
      );
    }, 'Outreach session started.');
  }

  Future<void> _disposeStock(OutreachStockAllocation allocation) async {
    final request = await showDialog<_DispositionRequest>(
      context: context,
      builder: (_) => _DispositionDialog(allocation: allocation),
    );
    if (request == null) return;
    await _run(
      () => _repository.recordDisposition(
        sessionId: widget.sessionId,
        allocationId: allocation.id,
        disposition: request.disposition,
        quantity: request.quantity,
        reason: request.reason,
      ),
      'Outreach stock updated.',
    );
  }

  Future<void> _showAllocationDetails(
    OutreachStockAllocation allocation,
  ) async {
    final shouldReconcile = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _AllocationDetailsSheet(
        allocation: allocation,
        canReconcile:
            _session?.status == OutreachSessionStatus.active &&
            allocation.remaining > 0 &&
            !_working,
      ),
    );
    if (shouldReconcile == true && mounted) {
      await _disposeStock(allocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Outreach Session')),
        body: const AppLoadingView(
          title: 'Loading session',
          message: 'Checking stock custody and reconciliation.',
        ),
      );
    }
    final session = _session!;
    final totalAllocated = _allocations.fold<int>(
      0,
      (sum, a) => sum + a.allocated,
    );
    final totalAdministered = _allocations.fold<int>(
      0,
      (sum, a) => sum + a.administered,
    );
    final totalRemaining = _allocations.fold<int>(
      0,
      (sum, a) => sum + a.remaining,
    );
    final visibleAllocations = switch (_stockView) {
      _OutreachStockView.allocated => _allocations,
      _OutreachStockView.administered =>
        _allocations
            .where((allocation) => allocation.administered > 0)
            .toList(growable: false),
      _OutreachStockView.unaccounted =>
        _allocations
            .where((allocation) => allocation.remaining > 0)
            .toList(growable: false),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Outreach Session',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${session.sessionCode}\n${session.location}\n${_date(session.scheduledOn)}',
                  ),
                  const SizedBox(height: 10),
                  Chip(label: Text(_status(session.status))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Allocated',
                  value: totalAllocated,
                  selected: _stockView == _OutreachStockView.allocated,
                  onTap: () =>
                      setState(() => _stockView = _OutreachStockView.allocated),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Metric(
                  label: 'Administered',
                  value: totalAdministered,
                  selected: _stockView == _OutreachStockView.administered,
                  onTap: () => setState(
                    () => _stockView = _OutreachStockView.administered,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Metric(
                  label: 'Unaccounted',
                  value: totalRemaining,
                  selected: _stockView == _OutreachStockView.unaccounted,
                  onTap: () => setState(
                    () => _stockView = _OutreachStockView.unaccounted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outreach stock',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _stockView.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (session.status == OutreachSessionStatus.draft)
                TextButton.icon(
                  onPressed: _working ? null : _releaseStock,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Release stock'),
                ),
            ],
          ),
          if (visibleAllocations.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_stockView.emptyMessage),
              ),
            )
          else
            for (final allocation in visibleAllocations)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  title: Text(
                    allocation.vaccineName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lot: ${allocation.lotNumber} • Expires ${_date(allocation.expiryDate)}',
                        ),
                        const SizedBox(height: 3),
                        Text(_allocationActivitySummary(allocation)),
                        const SizedBox(height: 8),
                        _AllocationStatusPill(allocation: allocation),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _working
                      ? null
                      : () => _showAllocationDetails(allocation),
                ),
              ),
          const SizedBox(height: 18),
          if (session.status == OutreachSessionStatus.draft)
            FilledButton.icon(
              onPressed: _working || _allocations.isEmpty ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Complete safety check and start'),
            ),
          if (session.status == OutreachSessionStatus.active) ...[
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrScanScreen(
                            outreachSessionId: session.id,
                            outreachTitle: session.title,
                          ),
                        ),
                      );
                      if (mounted) _load();
                    },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan child for outreach vaccination'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _working || totalRemaining != 0
                  ? null
                  : () => _run(() async {
                      await _repository.submitSession(session.id);
                    }, 'Session submitted for administrator approval.'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Submit reconciliation'),
            ),
            if (totalRemaining != 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Account for every remaining dose before submitting.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
          if (session.status == OutreachSessionStatus.reconciliation)
            widget.user.isAdministrator
                ? FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _run(() async {
                            await _repository.completeSession(session.id);
                          }, 'Outreach session completed.'),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Approve and complete'),
                  )
                : const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Submitted for administrator review.'),
                    ),
                  ),
        ],
      ),
    );
  }
}

class _CreateOutreachDialog extends StatefulWidget {
  const _CreateOutreachDialog();
  @override
  State<_CreateOutreachDialog> createState() => _CreateOutreachDialogState();
}

class _CreateOutreachDialogState extends State<_CreateOutreachDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  DateTime _dateValue = DateTime.now();
  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New outreach session'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Activity name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Outreach location'),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Session date'),
            subtitle: Text(_date(_dateValue)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: _dateValue,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (selected != null) setState(() => _dateValue = selected);
            },
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Preparation notes (optional)',
            ),
            maxLines: 2,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().length < 3 ||
              _location.text.trim().length < 3) {
            return;
          }
          Navigator.pop(
            context,
            _NewOutreachRequest(
              _title.text.trim(),
              _location.text.trim(),
              _dateValue,
              _notes.text.trim(),
            ),
          );
        },
        child: const Text('Create'),
      ),
    ],
  );
}

class _ReleaseStockDialog extends StatefulWidget {
  final OutreachRepository repository;
  const _ReleaseStockDialog({required this.repository});
  @override
  State<_ReleaseStockDialog> createState() => _ReleaseStockDialogState();
}

class _ReleaseStockDialogState extends State<_ReleaseStockDialog> {
  final _search = TextEditingController();
  final List<VaccineBatch> _batches = [];
  VaccineBatch? _batch;
  final _quantity = TextEditingController(text: '1');
  late Future<List<VaccineBatch>> _results;
  Timer? _debounce;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _nextOffset = 0;
    _hasMore = false;
    _totalCount = 0;
    _results = _loadPage(reset: true);
  }

  Future<List<VaccineBatch>> _loadPage({required bool reset}) async {
    final page = await widget.repository.getEligibleBatchesPage(
      search: _search.text,
      limit: 15,
      offset: reset ? 0 : _nextOffset,
    );
    if (reset) _batches.clear();
    final ids = _batches.map((batch) => batch.id).toSet();
    _batches.addAll(page.items.where((batch) => ids.add(batch.id)));
    _hasMore = page.hasMore;
    _nextOffset = page.nextOffset;
    _totalCount = page.totalCount;
    if (_batch != null && !_batches.any((item) => item.id == _batch!.id)) {
      _batch = null;
    }
    return List.unmodifiable(_batches);
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(_reload);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final batches = await _loadPage(reset: false);
      if (mounted) setState(() => _results = Future.value(batches));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Release outreach stock'),
    content: SizedBox(
      width: double.maxFinite,
      height: MediaQuery.sizeOf(context).height * .58,
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'Find vaccine or batch',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        _debounce?.cancel();
                        setState(_reload);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<VaccineBatch>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Batches could not be loaded'),
                    ),
                  );
                }
                final batches = snapshot.data ?? const [];
                if (batches.isEmpty) {
                  return const Center(
                    child: Text('No matching usable batches are available.'),
                  );
                }
                return RadioGroup<String>(
                  groupValue: _batch?.id,
                  onChanged: (batchId) => setState(() {
                    _batch = batches
                        .where((batch) => batch.id == batchId)
                        .firstOrNull;
                  }),
                  child: ListView(
                    children: [
                      Text(
                        '${batches.length} of $_totalCount available batch(es)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final batch in batches)
                        RadioListTile<String>(
                          value: batch.id,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${batch.vaccineName} • ${batch.lotNumber}',
                          ),
                          subtitle: Text(
                            '${batch.availableDoses} dose(s) • Expires ${_date(batch.expiryDate)}',
                          ),
                        ),
                      if (_hasMore)
                        TextButton.icon(
                          onPressed: _loadingMore ? null : _loadMore,
                          icon: _loadingMore
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(
                            _loadingMore ? 'Loading…' : 'Load more batches',
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _batch == null
                  ? 'Number of doses'
                  : 'Number of doses (maximum ${_batch!.availableDoses})',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final quantity = int.tryParse(_quantity.text);
          if (_batch == null ||
              quantity == null ||
              quantity <= 0 ||
              quantity > _batch!.availableDoses) {
            return;
          }
          Navigator.pop(context, _StockReleaseRequest(_batch!, quantity));
        },
        child: const Text('Release'),
      ),
    ],
  );
}

class _SafetyCheckDialog extends StatefulWidget {
  const _SafetyCheckDialog();
  @override
  State<_SafetyCheckDialog> createState() => _SafetyCheckDialogState();
}

class _SafetyCheckDialogState extends State<_SafetyCheckDialog> {
  bool _packaging = false;
  bool _coldChain = false;
  String _vvm = 'acceptable';
  final _notes = TextEditingController();
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Departure safety check'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          value: _packaging,
          onChanged: (v) => setState(() => _packaging = v ?? false),
          title: const Text('Packaging is intact'),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _coldChain,
          onChanged: (v) => setState(() => _coldChain = v ?? false),
          title: const Text('Cold chain verified'),
          contentPadding: EdgeInsets.zero,
        ),
        DropdownButtonFormField<String>(
          initialValue: _vvm,
          decoration: const InputDecoration(labelText: 'VVM status'),
          items: const [
            DropdownMenuItem(value: 'acceptable', child: Text('Acceptable')),
            DropdownMenuItem(
              value: 'not_applicable',
              child: Text('Not applicable'),
            ),
            DropdownMenuItem(
              value: 'not_acceptable',
              child: Text('Not acceptable'),
            ),
          ],
          onChanged: (v) => setState(() => _vvm = v ?? 'acceptable'),
        ),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Safety remarks (optional)',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_packaging || !_coldChain || _vvm == 'not_acceptable'
            ? null
            : () => Navigator.pop(
                context,
                _SafetyCheck(_packaging, _coldChain, _vvm, _notes.text.trim()),
              ),
        child: const Text('Start session'),
      ),
    ],
  );
}

class _DispositionDialog extends StatefulWidget {
  final OutreachStockAllocation allocation;
  const _DispositionDialog({required this.allocation});
  @override
  State<_DispositionDialog> createState() => _DispositionDialogState();
}

class _DispositionDialogState extends State<_DispositionDialog> {
  OutreachStockDisposition _type = OutreachStockDisposition.returned;
  final _quantity = TextEditingController(text: '1');
  final _reason = TextEditingController();
  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Account for remaining stock'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<OutreachStockDisposition>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Disposition'),
          items: const [
            DropdownMenuItem(
              value: OutreachStockDisposition.returned,
              child: Text('Return usable stock'),
            ),
            DropdownMenuItem(
              value: OutreachStockDisposition.wastage,
              child: Text('Record wastage'),
            ),
            DropdownMenuItem(
              value: OutreachStockDisposition.quarantine,
              child: Text('Quarantine'),
            ),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        TextField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantity (remaining ${widget.allocation.remaining})',
          ),
        ),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(
            labelText: 'Reason / safety remarks',
          ),
          maxLines: 2,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final q = int.tryParse(_quantity.text);
          if (q == null ||
              q <= 0 ||
              q > widget.allocation.remaining ||
              _reason.text.trim().length < 3) {
            return;
          }
          Navigator.pop(
            context,
            _DispositionRequest(_type, q, _reason.text.trim()),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

enum _OutreachStockView { allocated, administered, unaccounted }

extension on _OutreachStockView {
  String get label => switch (this) {
    _OutreachStockView.allocated => 'Showing all allocated batches',
    _OutreachStockView.administered =>
      'Showing batches with administered doses',
    _OutreachStockView.unaccounted =>
      'Showing batches that still require reconciliation',
  };

  String get emptyMessage => switch (this) {
    _OutreachStockView.allocated => 'No vaccine stock has been released.',
    _OutreachStockView.administered =>
      'No doses have been administered in this session.',
    _OutreachStockView.unaccounted =>
      'All released doses have been accounted for.',
  };
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _Metric({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(18);
    return Card(
      color: selected ? colors.primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllocationDetailsSheet extends StatelessWidget {
  final OutreachStockAllocation allocation;
  final bool canReconcile;

  const _AllocationDetailsSheet({
    required this.allocation,
    required this.canReconcile,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  allocation.vaccineName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close stock details',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Lot ${allocation.lotNumber} • Batch ${allocation.batchCode}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _AllocationDetailRow(
            label: 'Expiry date',
            value: _date(allocation.expiryDate),
          ),
          _AllocationDetailRow(
            label: 'Allocated',
            value: '${allocation.allocated}',
          ),
          _AllocationDetailRow(
            label: 'Administered',
            value: '${allocation.administered}',
          ),
          _AllocationDetailRow(
            label: 'Returned',
            value: '${allocation.returned}',
          ),
          _AllocationDetailRow(label: 'Wasted', value: '${allocation.wasted}'),
          _AllocationDetailRow(
            label: 'Quarantined',
            value: '${allocation.quarantined}',
          ),
          const Divider(height: 26),
          _AllocationDetailRow(
            label: 'Unaccounted',
            value: '${allocation.remaining}',
            emphasized: true,
          ),
          if (canReconcile) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.rule_rounded),
              label: const Text('Reconcile remaining stock'),
            ),
          ],
        ],
      ),
    ),
  );
}

String _allocationActivitySummary(OutreachStockAllocation allocation) {
  final parts = <String>['${allocation.allocated} allocated'];
  if (allocation.administered > 0) {
    parts.add('${allocation.administered} administered');
  }
  if (allocation.returned > 0) {
    parts.add('${allocation.returned} returned');
  }
  if (allocation.wasted > 0) {
    parts.add('${allocation.wasted} wasted');
  }
  if (allocation.quarantined > 0) {
    parts.add('${allocation.quarantined} quarantined');
  }
  return parts.join(' • ');
}

class _AllocationStatusPill extends StatelessWidget {
  final OutreachStockAllocation allocation;

  const _AllocationStatusPill({required this.allocation});

  @override
  Widget build(BuildContext context) {
    final requiresReconciliation = allocation.remaining > 0;
    final color = requiresReconciliation
        ? StatusColors.due
        : StatusColors.completed;
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? color
        : requiresReconciliation
        ? const Color(0xFF805400)
        : const Color(0xFF1F7738);
    final label = requiresReconciliation
        ? '${allocation.remaining} remaining — reconciliation needed'
        : 'Fully accounted';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AllocationDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _AllocationDetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? action;
  const _MessageState({required this.icon, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null)
            TextButton(onPressed: action, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _NewOutreachRequest {
  final String title;
  final String location;
  final DateTime date;
  final String notes;
  const _NewOutreachRequest(this.title, this.location, this.date, this.notes);
}

class _StockReleaseRequest {
  final VaccineBatch batch;
  final int quantity;
  const _StockReleaseRequest(this.batch, this.quantity);
}

class _SafetyCheck {
  final bool packagingIntact;
  final bool coldChainVerified;
  final String vvmStatus;
  final String notes;
  const _SafetyCheck(
    this.packagingIntact,
    this.coldChainVerified,
    this.vvmStatus,
    this.notes,
  );
}

class _DispositionRequest {
  final OutreachStockDisposition disposition;
  final int quantity;
  final String reason;
  const _DispositionRequest(this.disposition, this.quantity, this.reason);
}

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';
String _status(OutreachSessionStatus value) => switch (value) {
  OutreachSessionStatus.draft => 'Draft',
  OutreachSessionStatus.active => 'Active',
  OutreachSessionStatus.reconciliation => 'Awaiting approval',
  OutreachSessionStatus.completed => 'Completed',
  OutreachSessionStatus.cancelled => 'Cancelled',
};
