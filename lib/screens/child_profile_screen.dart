import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_assessment.dart';
import '../repositories/vaccination_repository.dart';
import 'child_qr_screen.dart';
import '../widgets/vaccination_progress_bar.dart';
import '../widgets/app_loading.dart';

enum ChildProfileSection { history, upcoming }

class ChildProfileScreen extends StatefulWidget {
  final ChildProfile child;
  final String? highlightedVaccineId;
  final int? highlightedDoseNumber;
  final ChildProfileSection? initialSection;
  final VaccinationRepository? repository;

  const ChildProfileScreen({
    super.key,
    required this.child,
    this.highlightedVaccineId,
    this.highlightedDoseNumber,
    this.initialSection,
    this.repository,
  });

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  late final VaccinationRepository _repository;
  late Future<VaccinationAssessment> _assessment;
  final _historyAnchor = GlobalKey();
  final _scheduleAnchor = GlobalKey();
  bool _sectionRevealed = false;
  late bool _upcomingOnly;

  ChildProfile get child => widget.child;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? RepositoryRegistry.instance.vaccinationRepository;
    _upcomingOnly = widget.initialSection == ChildProfileSection.upcoming;
    _assessment = _repository.assessChild(child);
  }

  void _revealInitialSection() {
    if (_sectionRevealed || widget.initialSection == null) return;
    _sectionRevealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.initialSection == ChildProfileSection.history
          ? _historyAnchor.currentContext
          : _scheduleAnchor.currentContext;
      if (target != null) Scrollable.ensureVisible(target);
    });
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final green = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Child Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE7EDF4)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.09),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.child_care_rounded,
                        size: 43,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      child.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Child ID: ${child.id}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _InformationCard(
                title: 'Basic Information',
                icon: Icons.badge_outlined,
                color: primary,
                children: [
                  _InfoRow(
                    label: 'Date of birth',
                    value: _formatDate(child.birthDate),
                  ),
                  _InfoRow(label: 'Sex', value: child.sex),
                  _InfoRow(
                    label: 'Guardian relationship',
                    value: child.relationship,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InformationCard(
                title: 'Child QR Identifier',
                icon: Icons.qr_code_2_rounded,
                color: green,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, color: green, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Identifier',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                child.qrIdentifier,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The QR is an identifier for retrieving the child record. It does not determine the vaccination schedule.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChildQrScreen(child: child),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('View / Print Child QR'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InformationCard(
                title: 'Vaccination',
                icon: Icons.vaccines_outlined,
                color: primary,
                children: [
                  FutureBuilder<VaccinationAssessment>(
                    future: _assessment,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const AppLoadingView(
                          title: 'Loading child record',
                          message:
                              'Preparing vaccination history and schedule.',
                        );
                      }
                      if (!snapshot.hasData) {
                        return TextButton.icon(
                          onPressed: () => setState(() {
                            _assessment = _repository.assessChild(child);
                          }),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'Try loading vaccination records again',
                          ),
                        );
                      }
                      return _vaccinationSummary(snapshot.data!, primary);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vaccinationSummary(VaccinationAssessment assessment, Color primary) {
    _revealInitialSection();
    final schedule = _upcomingOnly
        ? assessment.schedule
              .where((entry) => entry.status == PnipDoseStatus.upcoming)
              .toList()
        : assessment.schedule;
    final actionable = assessment.schedule
        .where(
          (entry) =>
              entry.requiresAction || entry.status == PnipDoseStatus.upcoming,
        )
        .toList();
    final next = actionable.isEmpty ? null : actionable.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VaccinationProgressBar(schedule: assessment.schedule),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assessment.recommendedDoses.isEmpty
                    ? 'Vaccination schedule up to date'
                    : '${assessment.recommendedDoses.length} dose(s) require assessment',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (next != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Next: ${next.vaccineName} Dose ${next.doseNumber} • ${_formatDate(next.scheduledDate)}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded:
              widget.highlightedVaccineId != null ||
              widget.initialSection == ChildProfileSection.history,
          title: Text(
            'Vaccination History (${assessment.history.length})',
            key: _historyAnchor,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          children: assessment.history.isEmpty
              ? const [Text('No vaccination records found.')]
              : assessment.history
                    .map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${record.vaccineName} Dose ${record.doseNumber}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${_formatDate(record.dateAdministered)} • ${record.administeringFacility}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
        ),
        const Divider(height: 1),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded:
              widget.initialSection == ChildProfileSection.upcoming,
          title: Text(
            _upcomingOnly
                ? 'Upcoming Schedule (${schedule.length})'
                : 'PNIP Schedule',
            key: _scheduleAnchor,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          children: [
            if (widget.initialSection == ChildProfileSection.upcoming)
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Upcoming only'),
                  selected: _upcomingOnly,
                  onSelected: (value) => setState(() => _upcomingOnly = value),
                ),
              ),
            if (_upcomingOnly && schedule.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No upcoming doses scheduled.'),
              ),
            ...schedule.map(_profileScheduleRow),
          ],
        ),
      ],
    );
  }

  Widget _profileScheduleRow(PnipScheduleEntry entry) {
    final highlighted =
        entry.vaccineId == widget.highlightedVaccineId &&
        entry.doseNumber == widget.highlightedDoseNumber;
    final (label, color) = switch (entry.status) {
      PnipDoseStatus.completed => ('Completed', Colors.green),
      PnipDoseStatus.due => ('Due', Colors.blue),
      PnipDoseStatus.overdue => ('Overdue', Colors.red),
      PnipDoseStatus.upcoming => ('Upcoming', Colors.blueGrey),
      PnipDoseStatus.notEligible => ('Awaiting prior dose', Colors.grey),
    };
    final isActionable =
        entry.status == PnipDoseStatus.due ||
        entry.status == PnipDoseStatus.overdue;
    final rowColor = isActionable
        ? color.withValues(alpha: highlighted ? 0.12 : 0.055)
        : Theme.of(context).colorScheme.surface;
    final borderColor = highlighted
        ? color.withValues(alpha: 0.42)
        : isActionable
        ? color.withValues(alpha: 0.18)
        : Theme.of(context).dividerColor.withValues(alpha: 0.45);
    final statusIcon = switch (entry.status) {
      PnipDoseStatus.completed => Icons.check_circle_rounded,
      PnipDoseStatus.due => Icons.event_available_rounded,
      PnipDoseStatus.overdue => Icons.notification_important_rounded,
      PnipDoseStatus.upcoming => Icons.event_rounded,
      PnipDoseStatus.notEligible => Icons.lock_clock_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: highlighted ? 1.5 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(statusIcon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.vaccineName} Dose ${entry.doseNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isActionable ? color : null,
                  ),
                ),
                Text(
                  _formatDate(entry.scheduledDate),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _InformationCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
