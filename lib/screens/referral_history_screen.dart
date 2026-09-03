import 'package:flutter/material.dart';

import '../models/referral_group.dart';
import '../repositories/referral_repository.dart';
import 'referral_group_details_screen.dart';
import '../widgets/app_loading.dart';

class ReferralHistoryScreen extends StatefulWidget {
  final ReferralRepository repository;

  const ReferralHistoryScreen({super.key, required this.repository});

  @override
  State<ReferralHistoryScreen> createState() => _ReferralHistoryScreenState();
}

class _ReferralHistoryScreenState extends State<ReferralHistoryScreen> {
  final _searchController = TextEditingController();
  ReferralGroupStatus? _filter;
  bool _overdueOnly = false;
  List<ReferralGroup> _groups = [];
  List<ReferralGroup> _summaryGroups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groups = await widget.repository.getReferralGroups(
      query: _searchController.text,
      status: _filter,
      overdueOnly: _overdueOnly,
    );
    final summaryGroups = await widget.repository.getReferralGroups(
      limit: 1000,
    );
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _summaryGroups = summaryGroups;
      _loading = false;
    });
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
    await _load();
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
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Referral History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
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
                    onChanged: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Search child, referral ID, or vaccine',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _load();
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
            Expanded(
              child: _loading
                  ? const AppLoadingView(
                      title: 'Loading referral history',
                      message: 'Retrieving saved referral records.',
                    )
                  : _groups.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                        itemCount: _groups.length,
                        itemBuilder: (_, index) => _groupCard(_groups[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, ReferralGroupStatus? value) => ChoiceChip(
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) {
      setState(() {
        _filter = value;
        _overdueOnly = false;
      });
      _load();
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
      _load();
    },
  );

  Widget _summary() {
    final pending = _summaryGroups
        .where((group) => group.status == ReferralGroupStatus.pending)
        .length;
    final partial = _summaryGroups
        .where(
          (group) => group.status == ReferralGroupStatus.partiallyCompleted,
        )
        .length;
    final completed = _summaryGroups
        .where((group) => group.status == ReferralGroupStatus.completed)
        .length;
    final overdue = _summaryGroups
        .where((group) => group.isOverdueOn(DateTime.now()))
        .length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _summaryCard('Pending', pending, Colors.blue),
          _summaryCard('Partial', partial, Colors.orange),
          _summaryCard('Completed', completed, Colors.green),
          _summaryCard('Overdue', overdue, Colors.red),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, int count, Color color) => Container(
    width: 105,
    margin: const EdgeInsets.only(right: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.15)),
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
