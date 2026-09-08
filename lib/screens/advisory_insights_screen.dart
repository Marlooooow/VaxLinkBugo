import 'package:flutter/material.dart';

import '../models/advisory_insight.dart';
import '../models/app_user.dart';
import '../repositories/advisory_insight_repository.dart';
import '../repositories/repository_registry.dart';
import '../utils/user_facing_error.dart';
import 'vaccine_inventory_details_screen.dart';
import 'vaccination_reminders_screen.dart';
import 'vaccination_appointments_screen.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';

class AdvisoryInsightsScreen extends StatefulWidget {
  final AppUser healthWorker;
  final AdvisoryInsightRepository? repository;
  final String? initialInsightId;

  const AdvisoryInsightsScreen({
    super.key,
    required this.healthWorker,
    this.repository,
    this.initialInsightId,
  });

  @override
  State<AdvisoryInsightsScreen> createState() => _AdvisoryInsightsScreenState();
}

class _AdvisoryInsightsScreenState extends State<AdvisoryInsightsScreen> {
  static const _pageSize = 20;
  late final AdvisoryInsightRepository _repository;
  final Set<String> _saving = {};
  List<AdvisoryInsight> _insights = [];
  AdvisoryInsightSummary _summary = const AdvisoryInsightSummary();
  AdvisoryInsightSeverity? _severity;
  AdvisoryInsightStatus? _status;
  String? _focusedInsightId;
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
    _focusedInsightId = widget.initialInsightId;
    _repository =
        widget.repository ??
        RepositoryRegistry.instance.advisoryInsightRepository;
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _insights = [];
      _totalCount = 0;
      _nextOffset = 0;
      _hasMore = false;
    });
    try {
      final page = await _repository.getFacilityInsightsPage(
        severity: _severity,
        status: _status,
        insightId: _focusedInsightId,
        limit: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _insights = page.items;
        _summary = page.summary;
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
      final page = await _repository.getFacilityInsightsPage(
        severity: _severity,
        status: _status,
        insightId: _focusedInsightId,
        limit: _pageSize,
        offset: _nextOffset,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        final ids = _insights.map((item) => item.id).toSet();
        _insights.addAll(page.items.where((item) => ids.add(item.id)));
        _summary = page.summary;
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
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

  Future<void> _update(
    AdvisoryInsight insight,
    AdvisoryInsightStatus status,
  ) async {
    if (_saving.contains(insight.id)) return;
    setState(() => _saving.add(insight.id));
    try {
      final updated = await _repository.updateStatus(
        insightId: insight.id,
        status: status,
        reviewedByUserId: widget.healthWorker.id,
      );
      if (!mounted) return;
      setState(() {
        final index = _insights.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _insights[index] = updated;
        if (insight.status == AdvisoryInsightStatus.newInsight &&
            updated.status != AdvisoryInsightStatus.newInsight) {
          _summary = AdvisoryInsightSummary(
            high: _summary.high,
            medium: _summary.medium,
            newCount: (_summary.newCount - 1)
                .clamp(0, _summary.newCount)
                .toInt(),
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AdvisoryInsightStatus.reviewed
                ? 'Insight marked as reviewed.'
                : 'Insight dismissed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'The insight could not be updated. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(insight.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Advisory Insights',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh insights',
          onPressed: _saving.isNotEmpty ? null : _loadFirstPage,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const WorkerAppBarActions(),
      ],
    ),
    body: _loading
        ? const AppLoadingView(
            title: 'Loading advisory insights',
            message: 'Reviewing the latest saved indicators.',
          )
        : _error != null && _insights.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    UserFacingError.message(
                      _error!,
                      fallback:
                          'The insights could not be loaded. Please refresh and try again.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: _loadFirstPage,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              if (_focusedInsightId != null) ...[
                const Text('Opened from notification'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(() => _focusedInsightId = null);
                      _loadFirstPage();
                    },
                    child: const Text('View all insights'),
                  ),
                ),
              ] else ...[
                _AdvisoryNotice(
                  provider: _insights.firstOrNull?.analysisProvider,
                ),
                const SizedBox(height: 16),
                _InsightSummary(
                  summary: _summary,
                  onHighTap: () =>
                      _applyFilter(severity: AdvisoryInsightSeverity.high),
                  onMediumTap: () =>
                      _applyFilter(severity: AdvisoryInsightSeverity.medium),
                  onNewTap: () =>
                      _applyFilter(status: AdvisoryInsightStatus.newInsight),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filter('All', null),
                      _filter('High', AdvisoryInsightSeverity.high),
                      _filter('Medium', AdvisoryInsightSeverity.medium),
                      _filter('Low', AdvisoryInsightSeverity.low),
                      _statusFilter(
                        'Unreviewed',
                        AdvisoryInsightStatus.newInsight,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_focusedInsightId == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Showing ${_insights.length} of $_totalCount insight(s)',
                  ),
                ),
              if (_insights.isEmpty)
                _focusedInsightId != null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This insight is no longer available. You can view all insights for current updates.',
                        ),
                      )
                    : const _EmptyInsights()
              else
                ..._insights.map(
                  (insight) => _InsightCard(
                    key: ValueKey(insight.id),
                    insight: insight,
                    initiallyExpanded: _focusedInsightId == insight.id,
                    saving: _saving.contains(insight.id),
                    onReviewed: () =>
                        _update(insight, AdvisoryInsightStatus.reviewed),
                    onDismissed: () =>
                        _update(insight, AdvisoryInsightStatus.dismissed),
                  ),
                ),
              if (_hasMore)
                OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadNextPage,
                  icon: _loadingMore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? 'Loading…' : 'Load 20 more'),
                )
              else if (_insights.isNotEmpty && _focusedInsightId == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'All matching insights are displayed.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
  );

  void _applyFilter({
    AdvisoryInsightSeverity? severity,
    AdvisoryInsightStatus? status,
  }) {
    setState(() {
      _severity = severity;
      _status = status;
    });
    _loadFirstPage();
  }

  Widget _filter(String label, AdvisoryInsightSeverity? severity) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _status == null && _severity == severity,
      onSelected: (_) => _applyFilter(severity: severity),
    ),
  );

  Widget _statusFilter(String label, AdvisoryInsightStatus status) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _status == status,
      onSelected: (_) => _applyFilter(status: status),
    ),
  );
}

class _AdvisoryNotice extends StatelessWidget {
  final String? provider;
  const _AdvisoryNotice({required this.provider});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.insights_rounded),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Decision support only',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Insights summarize existing PNIP schedules, reminders, appointments, and stock. A health worker must verify every recommendation.',
                style: TextStyle(height: 1.4, fontSize: 12.5),
              ),
              const SizedBox(height: 5),
              Text(
                'Source: ${provider ?? 'schedule and facility records'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InsightSummary extends StatelessWidget {
  final AdvisoryInsightSummary summary;
  final VoidCallback onHighTap;
  final VoidCallback onMediumTap;
  final VoidCallback onNewTap;
  const _InsightSummary({
    required this.summary,
    required this.onHighTap,
    required this.onMediumTap,
    required this.onNewTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _count('${summary.high}', 'High', Colors.red, onHighTap),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _count(
            '${summary.medium}',
            'Medium',
            Colors.orange,
            onMediumTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _count(
            '${summary.newCount}',
            'Unreviewed',
            Colors.blue,
            onNewTap,
          ),
        ),
      ],
    );
  }

  Widget _count(String value, String label, Color color, VoidCallback onTap) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: .18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: const TextStyle(fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );
}

class _InsightCard extends StatelessWidget {
  final bool initiallyExpanded;
  final bool saving;
  final AdvisoryInsight insight;
  final VoidCallback onReviewed;
  final VoidCallback onDismissed;

  const _InsightCard({
    super.key,
    this.initiallyExpanded = false,
    required this.saving,
    required this.insight,
    required this.onReviewed,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (insight.severity) {
      AdvisoryInsightSeverity.high => Colors.red,
      AdvisoryInsightSeverity.medium => Colors.orange,
      AdvisoryInsightSeverity.low => Colors.blue,
    };
    final pending = insight.status == AdvisoryInsightStatus.newInsight;
    final statusColor = switch (insight.status) {
      AdvisoryInsightStatus.newInsight => color,
      AdvisoryInsightStatus.reviewed => const Color(0xFF237A3B),
      AdvisoryInsightStatus.actioned => const Color(0xFF237A3B),
      AdvisoryInsightStatus.dismissed => const Color(0xFF526174),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: initiallyExpanded,
        key: PageStorageKey('insight-${insight.id}'),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .10),
          child: Icon(_typeIcon(insight.type), color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                insight.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            _StatusBadge(insight: insight, color: statusColor),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(insight.summary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          _section('Why this appeared', insight.rationale),
          _section('Recommended next step', insight.recommendedAction),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(switch (insight.type) {
                AdvisoryInsightType.stockRisk => 'View stock details',
                AdvisoryInsightType.delayedVaccination => 'View follow-ups',
                AdvisoryInsightType.waitlistPressure => 'Review waitlist',
              }),
              onPressed: () {
                if (insight.type == AdvisoryInsightType.stockRisk &&
                    (insight.vaccineId == null || insight.vaccineId!.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This insight has no linked vaccine record.',
                      ),
                    ),
                  );
                  return;
                }
                final Widget destination = switch (insight.type) {
                  AdvisoryInsightType.stockRisk =>
                    VaccineInventoryDetailsScreen(
                      vaccineId: insight.vaccineId!,
                      repository:
                          RepositoryRegistry.instance.inventoryRepository,
                    ),
                  AdvisoryInsightType.delayedVaccination =>
                    VaccinationRemindersScreen.healthWorker(
                      childId: insight.childId,
                    ),
                  AdvisoryInsightType.waitlistPressure =>
                    VaccinationAppointmentsScreen.healthWorker(
                      waitlistOnly: true,
                      waitlistVaccineId: insight.vaccineId,
                    ),
                };
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => destination),
                );
              },
            ),
          ),
          _section(
            'Evidence',
            insight.sourceSnapshot.entries
                .map((entry) => '${_label(entry.key)}: ${entry.value}')
                .join('\n'),
          ),
          _section(
            'Audit',
            '${insight.insightCode}\n${insight.analysisProvider} • ${insight.analysisVersion}',
          ),
          if (!pending)
            _section(
              'Review status',
              insight.status == AdvisoryInsightStatus.dismissed
                  ? 'Dismissed. Retained here for audit history.'
                  : 'Reviewed. Your review has been saved.',
              valueColor: statusColor,
            ),
          if (pending) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : onReviewed,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(saving ? 'Saving...' : 'Mark as reviewed'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: saving ? null : onDismissed,
                child: const Text('Dismiss insight'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(top: 11),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(height: 1.4, color: valueColor)),
        ],
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final AdvisoryInsight insight;
  final Color color;
  const _StatusBadge({required this.insight, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      insight.status == AdvisoryInsightStatus.newInsight
          ? insight.severity.name.toUpperCase()
          : insight.status.name.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _EmptyInsights extends StatelessWidget {
  const _EmptyInsights();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(30),
    child: Center(child: Text('No advisory insights match this filter.')),
  );
}

IconData _typeIcon(AdvisoryInsightType type) => switch (type) {
  AdvisoryInsightType.delayedVaccination =>
    Icons.notification_important_outlined,
  AdvisoryInsightType.stockRisk => Icons.inventory_2_outlined,
  AdvisoryInsightType.waitlistPressure => Icons.event_busy_outlined,
};

String _label(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
