import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/child_profile.dart';
import '../models/vaccination_schedule_state.dart';
import '../repositories/child_repository.dart';
import '../repositories/repository_registry.dart';
import '../theme/status_colors.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';
import 'registered_family_details_screen.dart';

class RegisteredFamiliesScreen extends StatefulWidget {
  final AppUser healthWorker;
  final Set<String>? initialGuardianIds;

  const RegisteredFamiliesScreen({
    super.key,
    required this.healthWorker,
    this.initialGuardianIds,
  });

  @override
  State<RegisteredFamiliesScreen> createState() =>
      _RegisteredFamiliesScreenState();
}

class _RegisteredFamiliesScreenState extends State<RegisteredFamiliesScreen> {
  static const _pageSize = 20;
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<RegisteredFamilySummary> _families = [];
  VaccinationScheduleState? _filter;
  DateTime? _cursorCreatedAt;
  String? _cursorGuardianId;
  Timer? _searchDebounce;
  Object? _error;
  int _requestVersion = 0;
  int _totalCount = 0;
  bool _dashboardSelectionActive = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _dashboardSelectionActive = widget.initialGuardianIds != null;
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

  void _searchChanged() {
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
      _hasMore = false;
      _totalCount = 0;
      _cursorCreatedAt = null;
      _cursorGuardianId = null;
      _families.clear();
    });
    try {
      final page = await _repository.getHealthWorkerRegisteredFamiliesPage(
        search: _searchController.text,
        status: _filter,
        guardianIds:
            _dashboardSelectionActive ? widget.initialGuardianIds : null,
        pageSize: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _families.addAll(page.items);
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _cursorCreatedAt = page.nextCreatedAt;
        _cursorGuardianId = page.nextGuardianId;
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
    if (_loading || _loadingMore || !_hasMore) return;
    final version = _requestVersion;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.getHealthWorkerRegisteredFamiliesPage(
        search: _searchController.text,
        status: _filter,
        guardianIds:
            _dashboardSelectionActive ? widget.initialGuardianIds : null,
        pageSize: _pageSize,
        cursorCreatedAt: _cursorCreatedAt,
        cursorGuardianId: _cursorGuardianId,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        final ids = _families
            .map((summary) => summary.family.guardian.id)
            .toSet();
        _families.addAll(
          page.items.where((item) => ids.add(item.family.guardian.id)),
        );
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _cursorCreatedAt = page.nextCreatedAt;
        _cursorGuardianId = page.nextGuardianId;
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

  void _selectStatus(VaccinationScheduleState? status) {
    _filter = status;
    if (status == null) _dashboardSelectionActive = false;
    _fetchFirstPage();
  }

  Future<void> _openFamily(RegisteredFamilySummary summary) async {
    RegisteredFamily? family;
    try {
      await runWithAppLoading(
        context,
        title: 'Loading family details',
        message: 'Fetching the latest guardian and child information.',
        operation: () async {
          family = await _repository.getHealthWorkerRegisteredFamily(
            summary.family.guardian.id,
          );
        },
      );
      if (!mounted) return;
      if (family == null) throw StateError('The family record was not found.');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RegisteredFamilyDetailsScreen(
            family: family!,
            registeredByUserId: widget.healthWorker.id,
          ),
        ),
      );
      if (mounted) await _fetchFirstPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'Family details could not be loaded.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Registered Families',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [WorkerAppBarActions()],
      ),
      body: _loading && _families.isEmpty
          ? const AppLoadingView(
              title: 'Loading registered families',
              message: 'Fetching the first 20 family summaries.',
            )
          : RefreshIndicator(
              onRefresh: _fetchFirstPage,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                children: [
                  if (_dashboardSelectionActive) ...[
                    const _DashboardFilterNotice(),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => _searchChanged(),
                    decoration: InputDecoration(
                      hintText: 'Search guardian, child, or ID',
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
                  _StatusFilters(
                    selected: _filter,
                    dashboardSelectionActive: _dashboardSelectionActive,
                    onSelected: _selectStatus,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Showing ${_families.length} of $_totalCount registration(s)',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null && _families.isEmpty)
                    _FamiliesError(error: _error!, onRetry: _fetchFirstPage)
                  else if (_families.isEmpty)
                    const _EmptyFamilies()
                  else ...[
                    ..._families.map(
                      (summary) => _FamilyCard(
                        summary: summary,
                        onTap: () => _openFamily(summary),
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

class _FamilyCard extends StatelessWidget {
  final RegisteredFamilySummary summary;
  final VoidCallback onTap;

  const _FamilyCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final family = summary.family;
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: primary.withValues(alpha: 0.10),
                child: Icon(Icons.family_restroom_rounded, color: primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.guardian.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${family.guardian.guardianCode} • ${family.children.length} child(ren)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: family.children
                          .map(
                            (child) => _ChildStatusChip(
                              child: child,
                              state: summary.childStates[child.id] ??
                                  VaccinationScheduleState.upcoming,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildStatusChip extends StatelessWidget {
  final ChildProfile child;
  final VaccinationScheduleState state;

  const _ChildStatusChip({required this.child, required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      VaccinationScheduleState.completed => StatusColors.completed,
      VaccinationScheduleState.dueNow => StatusColors.due,
      VaccinationScheduleState.upcoming => StatusColors.upcoming,
      VaccinationScheduleState.overdue => StatusColors.overdue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${child.fullName.split(' ').first}: ${state.label}',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  final VaccinationScheduleState? selected;
  final bool dashboardSelectionActive;
  final ValueChanged<VaccinationScheduleState?> onSelected;

  const _StatusFilters({
    required this.selected,
    required this.dashboardSelectionActive,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: selected == null && !dashboardSelectionActive,
              onSelected: (_) => onSelected(null),
            ),
            for (final state in VaccinationScheduleState.values)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(state.label),
                  selected: selected == state,
                  onSelected: (_) => onSelected(state),
                ),
              ),
          ],
        ),
      );
}

class _DashboardFilterNotice extends StatelessWidget {
  const _DashboardFilterNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.filter_alt_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Showing families connected to current due or overdue reminders.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
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
      child: Center(child: Text('All matching families are displayed.')),
    );
  }
}

class _FamiliesError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _FamiliesError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              UserFacingError.message(
                error,
                fallback: 'Registered families could not be loaded.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
}

class _EmptyFamilies extends StatelessWidget {
  const _EmptyFamilies();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Column(
          children: [
            Icon(Icons.person_search_rounded, size: 42),
            SizedBox(height: 10),
            Text(
              'No matching registered families.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5),
            Text(
              'Try another search term or status filter.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
