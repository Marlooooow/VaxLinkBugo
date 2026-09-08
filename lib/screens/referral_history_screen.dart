import 'dart:async';

import 'package:flutter/material.dart';

import '../models/referral_group.dart';
import '../repositories/referral_repository.dart';
import '../utils/user_facing_error.dart';
import '../widgets/worker_app_bar_actions.dart';
import 'referral_group_details_screen.dart';
import '../widgets/app_loading.dart';

class ReferralHistoryScreen extends StatefulWidget {
  final ReferralRepository repository;

  const ReferralHistoryScreen({super.key, required this.repository});

  @override
  State<ReferralHistoryScreen> createState() => _ReferralHistoryScreenState();
}

class _ReferralHistoryScreenState extends State<ReferralHistoryScreen> {
  static const _pageSize = 20;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  ReferralGroupStatus? _filter;
  bool _overdueOnly = false;
  List<ReferralGroup> _groups = [];
  ReferralGroupSummaryCounts _summaryCounts =
      const ReferralGroupSummaryCounts();
  Object? _error;
  int _totalCount = 0;
  int _nextOffset = 0;
  int _requestVersion = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadWhenNearBottom);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadWhenNearBottom() {
    if (_scrollController.position.extentAfter < 450) _loadNextPage();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadFirstPage,
    );
    setState(() {});
  }

  Future<ReferralGroupPage> _fetchPage(int offset) async {
    return widget.repository.getReferralGroupsPage(
      query: _searchController.text,
      status: _filter,
      overdueOnly: _overdueOnly,
      limit: _pageSize,
      offset: offset,
    );
  }

  Future<void> _loadFirstPage() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _groups = [];
      _totalCount = 0;
      _nextOffset = 0;
      _hasMore = false;
    });
    try {
      final page = await _fetchPage(0);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _groups = page.items;
        _summaryCounts = page.summary;
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
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

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final version = _requestVersion;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(_nextOffset);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        final existing = _groups
            .map((group) => group.referralGroupId)
            .toSet();
        _groups.addAll(
          page.items.where((group) => existing.add(group.referralGroupId)),
        );
        _summaryCounts = page.summary;
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
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

  Future<void> _open(ReferralGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReferralGroupDetailsScreen(
          referrals: group.referrals,
          repository: widget.repository,
        ),
      ),
    );
    await _loadFirstPage();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Referral History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [WorkerAppBarActions()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summary(),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => _onSearchChanged(),
                    decoration: InputDecoration(
                      hintText: 'Search child, referral ID, or vaccine',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _loadFirstPage();
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip('All', null),
                      _filterChip('Pending', ReferralGroupStatus.pending),
                      _filterChip(
                        'Partially Completed',
                        ReferralGroupStatus.partiallyCompleted,
                      ),
                      _filterChip('Completed', ReferralGroupStatus.completed),
                      _overdueChip(),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, ReferralGroupStatus? value) => ChoiceChip(
    label: Text(label),
    selected: _filter == value && (value != null || !_overdueOnly),
    onSelected: (_) {
      setState(() {
        _filter = value;
        _overdueOnly = false;
      });
      _loadFirstPage();
    },
  );

  Widget _overdueChip() => ChoiceChip(
    label: const Text('Overdue'),
    selected: _overdueOnly,
    onSelected: (_) {
      setState(() {
        _filter = null;
        _overdueOnly = true;
      });
      _loadFirstPage();
    },
  );

  Widget _summary() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _summaryCard(
            'Pending',
            _summaryCounts.pending,
            Colors.blue,
            selected: _filter == ReferralGroupStatus.pending && !_overdueOnly,
            onTap: () => _selectSummary(ReferralGroupStatus.pending),
          ),
          _summaryCard(
            'Partial',
            _summaryCounts.partiallyCompleted,
            Colors.orange,
            selected:
                _filter == ReferralGroupStatus.partiallyCompleted &&
                !_overdueOnly,
            onTap: () => _selectSummary(
              ReferralGroupStatus.partiallyCompleted,
            ),
          ),
          _summaryCard(
            'Completed',
            _summaryCounts.completed,
            Colors.green,
            selected:
                _filter == ReferralGroupStatus.completed && !_overdueOnly,
            onTap: () => _selectSummary(ReferralGroupStatus.completed),
          ),
          _summaryCard(
            'Overdue',
            _summaryCounts.overdue,
            Colors.red,
            selected: _overdueOnly,
            onTap: () => _selectSummary(null, overdue: true),
          ),
        ],
      ),
    );
  }

  void _selectSummary(ReferralGroupStatus? status, {bool overdue = false}) {
    setState(() {
      _filter = status;
      _overdueOnly = overdue;
    });
    _loadFirstPage();
  }

  Widget _summaryCard(
    String label,
    int count,
    Color color, {
    required bool selected,
    required VoidCallback onTap,
  }) => Container(
    width: 105,
    margin: const EdgeInsets.only(right: 9),
    child: Material(
      color: color.withValues(alpha: selected ? 0.15 : 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.70 : 0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11.5)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _results() {
    if (_loading && _groups.isEmpty) {
      return const AppLoadingView(
        title: 'Loading referral history',
        message: 'Fetching the first 20 referral groups.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          if (_error != null && _groups.isEmpty)
            _errorState()
          else if (_groups.isEmpty)
            _emptyState()
          else ...[
            Text(
              'Showing ${_groups.length} of $_totalCount referral group${_totalCount == 1 ? '' : 's'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            ..._groups.map(_groupCard),
            _pageFooter(),
          ],
        ],
      ),
    );
  }

  Widget _pageFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return TextButton.icon(
        onPressed: _loadNextPage,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Could not load more — try again'),
      );
    }
    if (_hasMore) {
      return OutlinedButton.icon(
        onPressed: _loadNextPage,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text('Load 20 more'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'All matching referrals are loaded.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Referral history could not be loaded',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            UserFacingError.message(_error!),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadFirstPage,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Widget _groupCard(ReferralGroup group) {
    final completed = group.referrals.where((item) => item.isCompleted).length;
    final color = group.isCompleted
        ? Colors.green
        : group.isPartiallyCompleted
        ? Colors.orange
        : Colors.blue;
    final label = group.isCompleted
        ? 'Completed'
        : group.isPartiallyCompleted
        ? 'Partially Completed'
        : 'Pending';
    final isOverdue = group.isOverdueOn(DateTime.now());
    final overdueDays = isOverdue
        ? group.pendingReferrals
              .map(
                (item) =>
                    DateTime.now().difference(item.scheduledDueDate).inDays,
              )
              .reduce((a, b) => a > b ? a : b)
        : 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: () => _open(group),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.childName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _badge(label, color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${group.childId}  •  ${group.referralGroupCode}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                group.referrals
                    .map((item) => '${item.vaccineName} ${item.doseNumber}')
                    .join(', '),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (isOverdue) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'PNIP vaccination overdue by $overdueDays day${overdueDays == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Issued ${_date(group.issuedAt)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$completed of ${group.referrals.length} recorded',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No referrals found',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Try another search term or status filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
