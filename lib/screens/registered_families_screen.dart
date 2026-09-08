import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/vaccination_schedule_state.dart';
import '../repositories/child_repository.dart';
import '../theme/status_colors.dart';
import 'registered_family_details_screen.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';

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
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  final _searchController = TextEditingController();
  late Future<List<_FamilySummary>> _families;
  VaccinationScheduleState? _filter;
  bool _dashboardSelectionActive = false;

  @override
  void initState() {
    super.initState();
    _dashboardSelectionActive = widget.initialGuardianIds != null;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() => _families = _loadSummaries();

  Future<List<_FamilySummary>> _loadSummaries() async {
    final families = await _repository.getHealthWorkerRegisteredFamilies();
    final vaccinationRepository =
        RepositoryRegistry.instance.vaccinationRepository;
    final summaries = await Future.wait(
      families.map((family) async {
        final states = <String, VaccinationScheduleState>{};
        for (final child in family.children) {
          final schedule = await vaccinationRepository.getVaccinationSchedule(
            child,
          );
          states[child.id] = summarizeSchedule(schedule);
        }
        return _FamilySummary(family: family, childStates: states);
      }),
    );
    summaries.sort(
      (a, b) => b.family.guardian.registeredAt.compareTo(
        a.family.guardian.registeredAt,
      ),
    );
    return summaries;
  }

  Future<void> _refresh() async {
    setState(_load);
    await _families;
  }

  bool _matchesSearch(RegisteredFamily family) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return family.guardian.fullName.toLowerCase().contains(query) ||
        family.guardian.guardianCode.toLowerCase().contains(query) ||
        family.children.any(
          (child) =>
              child.fullName.toLowerCase().contains(query) ||
              child.id.toLowerCase().contains(query),
        );
  }

  bool _matchesDashboardSelection(RegisteredFamily family) =>
      !_dashboardSelectionActive ||
      widget.initialGuardianIds == null ||
      widget.initialGuardianIds!.contains(family.guardian.id);

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
      body: FutureBuilder<List<_FamilySummary>>(
        future: _families,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingView(
              title: 'Loading registered families',
              message: 'Preparing guardians, children, and schedule summaries.',
            );
          }
          final all = snapshot.data ?? const [];
          final visible = all
              .where(
                (summary) =>
                    _matchesDashboardSelection(summary.family) &&
                    _matchesSearch(summary.family) &&
                    (_filter == null ||
                        summary.childStates.values.contains(_filter)),
              )
              .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                if (_dashboardSelectionActive &&
                    widget.initialGuardianIds != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Showing families connected to current due or overdue reminders.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search guardian, child, or ID',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatusFilter(
                        label: 'All',
                        selected: _filter == null && !_dashboardSelectionActive,
                        onSelected: () => setState(() {
                          _filter = null;
                          _dashboardSelectionActive = false;
                        }),
                      ),
                      for (final state in VaccinationScheduleState.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _StatusFilter(
                            label: state.label,
                            selected: _filter == state,
                            onSelected: () => setState(() => _filter = state),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${visible.length} of ${all.length} registration(s)',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const _EmptyFamilies()
                else
                  ...visible.map(
                    (summary) => _FamilyCard(
                      summary: summary,
                      registeredByUserId: widget.healthWorker.id,
                      onChanged: () => setState(_load),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FamilySummary {
  final RegisteredFamily family;
  final Map<String, VaccinationScheduleState> childStates;
  const _FamilySummary({required this.family, required this.childStates});
}

class _FamilyCard extends StatelessWidget {
  final _FamilySummary summary;
  final String registeredByUserId;
  final VoidCallback onChanged;
  const _FamilyCard({
    required this.summary,
    required this.registeredByUserId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final family = summary.family;
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RegisteredFamilyDetailsScreen(
                family: family,
                registeredByUserId: registeredByUserId,
              ),
            ),
          );
          onChanged();
        },
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
                              state: summary.childStates[child.id]!,
                            ),
                          )
                          .toList(),
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

class _StatusFilter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _StatusFilter({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
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
      border: Border.all(color: const Color(0xFFE7EDF4)),
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
