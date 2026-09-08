import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/app_user.dart';
import '../models/vaccination_record_summary.dart';
import '../repositories/repository_registry.dart';
import '../repositories/vaccination_records_repository.dart';
import '../theme/status_colors.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';
import 'child_profile_screen.dart';

class VaccinationRecordsScreen extends StatefulWidget {
  final AppUser healthWorker;

  const VaccinationRecordsScreen({super.key, required this.healthWorker});

  @override
  State<VaccinationRecordsScreen> createState() =>
      _VaccinationRecordsScreenState();
}

class _VaccinationRecordsScreenState extends State<VaccinationRecordsScreen> {
  static const _pageSize = 20;
  final VaccinationRecordsRepository _repository =
      RepositoryRegistry.instance.vaccinationRecordsRepository;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<VaccinationRecordSummary> _records = [];
  VaccinationRecordSummaryFilter _filter = VaccinationRecordSummaryFilter.all;
  VaccinationRecordSummaryCursor? _cursor;
  Timer? _searchDebounce;
  Object? _error;
  int _totalCount = 0;
  int _requestVersion = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadWhenNearBottom);
    _fetchFirstPage();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadWhenNearBottom() {
    if (_scrollController.position.extentAfter < 450) _fetchNextPage();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _fetchFirstPage);
    setState(() {});
  }

  Future<void> _fetchFirstPage() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _cursor = null;
      _totalCount = 0;
      _hasMore = false;
      _records.clear();
    });
    try {
      final page = await _repository.getSummaries(
        search: _searchController.text,
        filter: _filter,
        pageSize: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _records
          ..clear()
          ..addAll(page.items);
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_loading || _loadingMore || !_hasMore || _cursor == null) return;
    final version = _requestVersion;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.getSummaries(
        search: _searchController.text,
        filter: _filter,
        pageSize: _pageSize,
        cursor: _cursor,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        final existingIds = _records.map((record) => record.child.id).toSet();
        _records.addAll(
          page.items.where((record) => existingIds.add(record.child.id)),
        );
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _error = null;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  void _selectFilter(VaccinationRecordSummaryFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _fetchFirstPage();
  }

  void _openHistory(ChildProfile child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(
          child: child,
          initialSection: ChildProfileSection.history,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vaccination Records',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [WorkerAppBarActions()],
      ),
      body: _loading && _records.isEmpty
          ? const AppLoadingView(
              title: 'Loading vaccination records',
              message: 'Fetching the first 20 child summaries.',
            )
          : RefreshIndicator(
              onRefresh: _fetchFirstPage,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => _onSearchChanged(),
                    decoration: InputDecoration(
                      hintText: 'Search child, guardian, ID, or vaccine',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _fetchFirstPage();
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterBar(selected: _filter, onSelected: _selectFilter),
                  const SizedBox(height: 14),
                  _OverviewBar(loaded: _records.length, total: _totalCount),
                  const SizedBox(height: 14),
                  if (_error != null && _records.isEmpty)
                    _RecordsError(error: _error!, onRetry: _fetchFirstPage)
                  else if (_records.isEmpty)
                    const _EmptyRecords()
                  else ...[
                    ..._records.map(
                      (summary) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ChildRecordCard(
                          summary: summary,
                          onTap: () => _openHistory(summary.child),
                        ),
                      ),
                    ),
                    _PageFooter(
                      loading: _loadingMore,
                      hasMore: _hasMore,
                      error: _error,
                      onLoadMore: _fetchNextPage,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final VaccinationRecordSummaryFilter selected;
  final ValueChanged<VaccinationRecordSummaryFilter> onSelected;

  const _FilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const labels = {
      VaccinationRecordSummaryFilter.all: 'All',
      VaccinationRecordSummaryFilter.recorded: 'Has records',
      VaccinationRecordSummaryFilter.dueNow: 'Due now',
      VaccinationRecordSummaryFilter.overdue: 'Overdue',
      VaccinationRecordSummaryFilter.upcoming: 'Upcoming',
      VaccinationRecordSummaryFilter.completed: 'Completed',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value),
                selected: selected == entry.key,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewBar extends StatelessWidget {
  final int loaded;
  final int total;

  const _OverviewBar({required this.loaded, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.assignment_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Showing $loaded of $total child record(s)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildRecordCard extends StatelessWidget {
  final VaccinationRecordSummary summary;
  final VoidCallback onTap;

  const _ChildRecordCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _status(summary);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: status.$2.withValues(alpha: 0.13),
                foregroundColor: status.$2,
                child: const Icon(Icons.child_care_rounded, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.child.fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _StatusBadge(label: status.$1, color: status.$2),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${summary.guardianName} · ${summary.guardianCode}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _Metric(
                          icon: Icons.verified_outlined,
                          text: '${summary.recordedCount} recorded',
                        ),
                        if (summary.dueCount > 0)
                          _Metric(
                            icon: Icons.today_outlined,
                            text: '${summary.dueCount} due',
                            color: StatusColors.due,
                          ),
                        if (summary.overdueCount > 0)
                          _Metric(
                            icon: Icons.notification_important_outlined,
                            text: '${summary.overdueCount} overdue',
                            color: StatusColors.overdue,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _latestDescription(summary),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 38),
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _status(VaccinationRecordSummary value) {
    if (value.isCompleted) return ('Completed', StatusColors.completed);
    if (value.overdueCount > 0) return ('Overdue', StatusColors.overdue);
    if (value.dueCount > 0) return ('Due now', StatusColors.due);
    return ('Upcoming', StatusColors.upcoming);
  }

  String _latestDescription(VaccinationRecordSummary value) {
    final date = value.latestAdministeredOn;
    if (date == null || value.latestVaccineName == null) {
      return 'No administered vaccination recorded yet';
    }
    return 'Latest: ${value.latestVaccineName} Dose '
        '${value.latestDoseNumber ?? 1} · ${_date(date)}';
  }

  String _date(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _Metric({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: effectiveColor),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PageFooter extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final Object? error;
  final VoidCallback onLoadMore;

  const _PageFooter({
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return TextButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Could not load more — try again'),
      );
    }
    if (hasMore) {
      return TextButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text('Load 20 more'),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: Text('All matching records are displayed.')),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 46,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        const Text(
          'No matching vaccination records',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text('Try another search or status filter.'),
      ],
    ),
  );
}

class _RecordsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _RecordsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44),
    child: Column(
      children: [
        const Icon(Icons.error_outline_rounded, size: 42),
        const SizedBox(height: 12),
        Text(
          UserFacingError.message(
            error,
            fallback: 'Vaccination records could not be loaded.',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    ),
  );
}
