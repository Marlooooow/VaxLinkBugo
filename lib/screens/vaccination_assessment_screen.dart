import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_assessment.dart';
import '../models/vaccination_record.dart';
import '../models/first_visit_review.dart';
import '../repositories/vaccination_repository.dart';
import '../services/mock_identifier_generator.dart';
import '../services/session_context.dart';
import '../theme/status_colors.dart';
import 'inventory_check_screen.dart';
import 'previous_vaccination_screen.dart';

class VaccinationAssessmentScreen extends StatefulWidget {
  final ChildProfile child;

  const VaccinationAssessmentScreen({
    super.key,
    required this.child,
  });

  @override
  State<VaccinationAssessmentScreen> createState() =>
      _VaccinationAssessmentScreenState();
}

class _VaccinationAssessmentScreenState
    extends State<VaccinationAssessmentScreen> {
  final VaccinationRepository _repository =
      RepositoryRegistry.instance.vaccinationRepository;

  late Future<VaccinationAssessment> _assessmentFuture;

  FirstVisitReview? _firstVisitReview;

  bool _reviewLoading = true;

  @override
  void initState() {
    super.initState();

    _loadAssessment();
    _loadFirstVisitReview();
  }

  // ---------------------------------------------------------------------------
  // LOAD ASSESSMENT
  // ---------------------------------------------------------------------------

  void _loadAssessment() {
    _assessmentFuture = _repository.assessChild(widget.child);
  }

  // ---------------------------------------------------------------------------
  // LOAD FIRST VISIT REVIEW
  // ---------------------------------------------------------------------------

  Future<void> _loadFirstVisitReview() async {
    try {
      final review = await _repository.getFirstVisitReview(
        widget.child.id,
      );

      if (!mounted) return;

      setState(() {
        _firstVisitReview = review;
        _reviewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _reviewLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'First-visit review could not be loaded: $error',
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RECORD FIRST VISIT DECISION
  // ---------------------------------------------------------------------------

  Future<void> _recordFirstVisitDecision(
    bool hasDocuments,
  ) async {
    if (_reviewLoading) return;

    setState(() {
      _reviewLoading = true;
    });

    final live = RepositoryRegistry.instance.environment.isLive;
    final pendingReview = live
        ? FirstVisitReview.pending(
            childId: widget.child.id,
            hasDocumentedPreviousVaccinations: hasDocuments,
          )
        : (() {
            final identity = MockIdentifierGenerator.next(prefix: 'FVR');
            return FirstVisitReview(
              id: identity.id,
              reviewCode: identity.code,
              childId: widget.child.id,
              hasDocumentedPreviousVaccinations: hasDocuments,
              reviewedAt: DateTime.now(),
              reviewedByUserId: SessionContext.userId,
            );
          })();

    try {
      final review = await _repository.recordFirstVisitReview(pendingReview);

      if (!mounted) return;

      setState(() {
        _firstVisitReview = review;
        _reviewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _reviewLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'First-visit review could not be saved: $error',
          ),
        ),
      );

      return;
    }

    // If the guardian has documents, open the screen
    // where the previous vaccination records can be encoded.
    if (!hasDocuments) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviousVaccinationScreen(
          child: widget.child,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _loadAssessment();
    });
  }

  // ---------------------------------------------------------------------------
  // DATE FORMATTER
  // ---------------------------------------------------------------------------

  String _formatDate(DateTime date) {
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

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  // ---------------------------------------------------------------------------
  // STATUS TITLE
  // ---------------------------------------------------------------------------

  String _statusTitle(
    VaccinationAssessmentStatus status,
  ) {
    switch (status) {
      case VaccinationAssessmentStatus.firstVaccination:
        return 'First Vaccination';

      case VaccinationAssessmentStatus.vaccinationDue:
        return 'Vaccination Due';

      case VaccinationAssessmentStatus.notDue:
        return 'No Vaccination Due';
    }
  }

  // ---------------------------------------------------------------------------
  // STATUS ICON
  // ---------------------------------------------------------------------------

  IconData _statusIcon(
    VaccinationAssessmentStatus status,
  ) {
    switch (status) {
      case VaccinationAssessmentStatus.firstVaccination:
        return Icons.child_friendly_rounded;

      case VaccinationAssessmentStatus.vaccinationDue:
        return Icons.vaccines_rounded;

      case VaccinationAssessmentStatus.notDue:
        return Icons.event_available_rounded;
    }
  }

  // ---------------------------------------------------------------------------
  // STATUS COLOR
  // ---------------------------------------------------------------------------

  Color _statusColor(
    BuildContext context,
    VaccinationAssessmentStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;

    switch (status) {
      case VaccinationAssessmentStatus.firstVaccination:
        return scheme.primary;

      case VaccinationAssessmentStatus.vaccinationDue:
        return scheme.secondary;

      case VaccinationAssessmentStatus.notDue:
        return Colors.blueGrey;
    }
  }

  // ---------------------------------------------------------------------------
  // CONTINUE LOGIC
  // ---------------------------------------------------------------------------

  bool _canContinue(
    VaccinationAssessment assessment,
  ) {
    // No recommended doses = cannot continue.
    if (assessment.recommendedDoses.isEmpty) {
      return false;
    }

    // For first vaccination, the user must first complete
    // the First Visit Review.
    if (assessment.status ==
        VaccinationAssessmentStatus.firstVaccination) {
      if (_reviewLoading) {
        return false;
      }

      if (_firstVisitReview == null) {
        return false;
      }
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // CONTINUE TO INVENTORY
  // ---------------------------------------------------------------------------

  Future<void> _continueToInventory(
    VaccinationAssessment assessment,
  ) async {
    if (!_canContinue(assessment)) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryCheckScreen(
          child: widget.child,
          vaccineIds: assessment.recommendedVaccineIds,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _loadAssessment();
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vaccination Assessment',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: FutureBuilder<VaccinationAssessment>(
        future: _assessmentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Checking vaccination history...',
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorState();
          }

          if (!snapshot.hasData) {
            return _buildErrorState();
          }

          return _buildAssessment(
            context,
            snapshot.data!,
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR STATE
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to assess vaccination information.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loadAssessment();
                });
              },
              child: const Text(
                'Try again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ASSESSMENT CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildAssessment(
    BuildContext context,
    VaccinationAssessment assessment,
  ) {
    final color = _statusColor(
      context,
      assessment.status,
    );

    final canContinue = _canContinue(assessment);

    final isFirstVaccination =
        assessment.status ==
            VaccinationAssessmentStatus.firstVaccination;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          20,
          10,
          20,
          30,
        ),
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // CHILD INFORMATION
            // -----------------------------------------------------------------

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.09),
                    child: Icon(
                      Icons.child_care_rounded,
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          assessment.child.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Child ID: ${assessment.child.id}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // -----------------------------------------------------------------
            // ASSESSMENT STATUS
            // -----------------------------------------------------------------

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _statusIcon(assessment.status),
                      color: color,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusTitle(assessment.status),
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    assessment.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // -----------------------------------------------------------------
            // VACCINATION HISTORY
            // -----------------------------------------------------------------

            _SectionCard(
              title: 'Vaccination History',
              icon: Icons.history_rounded,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
              child: assessment.history.isEmpty
                  ? const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No previous vaccination records found.',
                      ),
                    )
                  : Column(
                      children: assessment.history
                          .map(
                            (record) =>
                                _VaccinationHistoryItem(
                              record: record,
                              formatDate: _formatDate,
                            ),
                          )
                          .toList(),
                    ),
            ),

            const SizedBox(height: 14),

            // -----------------------------------------------------------------
            // PNIP SCHEDULE
            // -----------------------------------------------------------------

            _SectionCard(
              title: 'PNIP Schedule',
              icon: Icons.event_note_rounded,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
              child: Column(
                children: assessment.schedule
                    .where(
                      (entry) =>
                          entry.status !=
                          PnipDoseStatus.notEligible,
                    )
                    .map(
                      (entry) => _ScheduleItem(
                        entry: entry,
                        formatDate: _formatDate,
                      ),
                    )
                    .toList(),
              ),
            ),

            const SizedBox(height: 14),

            // -----------------------------------------------------------------
            // RECOMMENDED VACCINES
            // -----------------------------------------------------------------

            if (assessment
                .recommendedVaccines
                .isNotEmpty)
              _SectionCard(
                title: 'Recommended for Assessment',
                icon: Icons.vaccines_outlined,
                color: Theme.of(context)
                    .colorScheme
                    .secondary,
                child: Column(
                  children: assessment
                      .recommendedVaccines
                      .map(
                        (vaccine) => Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(
                            bottom: 8,
                          ),
                          padding:
                              const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            borderRadius:
                                BorderRadius.circular(13),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.vaccines_rounded,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  vaccine,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

            const SizedBox(height: 18),

            // -----------------------------------------------------------------
            // FIRST VISIT REVIEW
            // -----------------------------------------------------------------

            if (isFirstVaccination) ...[
              _SectionCard(
                title: 'First Visit Review',
                icon: Icons.fact_check_outlined,
                color: Theme.of(context)
                    .colorScheme
                    .primary,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Does the guardian have documented previous vaccination records for this child?',
                      style: TextStyle(
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Existing review result
                    if (_firstVisitReview != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(
                          bottom: 10,
                        ),
                        padding:
                            const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.06),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Text(
                          _firstVisitReview!
                                  .hasDocumentedPreviousVaccinations
                              ? 'Documents available — encode each verified dose.'
                              : 'No documented previous vaccinations confirmed.',
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                      ),

                    // Loading indicator
                    if (_reviewLoading)
                      const Padding(
                        padding:
                            EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Saving review...',
                            ),
                          ],
                        ),
                      ),

                    // Review buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reviewLoading
                                ? null
                                : () =>
                                    _recordFirstVisitDecision(
                                      true,
                                    ),
                            style:
                                OutlinedButton.styleFrom(
                              backgroundColor:
                                  _firstVisitReview
                                              ?.hasDocumentedPreviousVaccinations ==
                                          true
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(
                                            alpha: 0.10,
                                          )
                                      : null,
                            ),
                            child: const Text(
                              'Yes, Review Records',
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: OutlinedButton(
                            onPressed: _reviewLoading
                                ? null
                                : () =>
                                    _recordFirstVisitDecision(
                                      false,
                                    ),
                            style:
                                OutlinedButton.styleFrom(
                              backgroundColor:
                                  _firstVisitReview
                                              ?.hasDocumentedPreviousVaccinations ==
                                          false
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(
                                            alpha: 0.10,
                                          )
                                      : null,
                            ),
                            child: const Text(
                              'No Documents',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
            ],

            // -----------------------------------------------------------------
            // CONTINUE BUTTON
            // -----------------------------------------------------------------

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canContinue
                    ? () =>
                        _continueToInventory(
                          assessment,
                        )
                    : null,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                ),
                label: const Text(
                  'Continue',
                ),
              ),
            ),

            // -----------------------------------------------------------------
            // CONTINUE MESSAGE
            // -----------------------------------------------------------------

            if (isFirstVaccination &&
                assessment
                    .recommendedDoses
                    .isNotEmpty &&
                _firstVisitReview == null &&
                !_reviewLoading)
              Padding(
                padding:
                    const EdgeInsets.only(top: 8),
                child: Text(
                  'Choose one First Visit Review option to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // -----------------------------------------------------------------
            // ENVIRONMENT MESSAGE
            // -----------------------------------------------------------------

            Text(
              RepositoryRegistry
                      .instance
                      .environment
                      .isLive
                  ? 'Assessment uses this child’s saved records and PNIP schedule.'
                  : 'Assessment is simulated for this prototype.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SECTION CARD
// =============================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          child,
        ],
      ),
    );
  }
}

// =============================================================================
// PNIP SCHEDULE ITEM
// =============================================================================

class _ScheduleItem extends StatelessWidget {
  final PnipScheduleEntry entry;
  final String Function(DateTime) formatDate;

  const _ScheduleItem({
    required this.entry,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.status) {
      PnipDoseStatus.completed => (
          'Completed',
          StatusColors.completed,
        ),
      PnipDoseStatus.due => (
          'Due today',
          StatusColors.due,
        ),
      PnipDoseStatus.overdue => (
          'Overdue',
          StatusColors.overdue,
        ),
      PnipDoseStatus.upcoming => (
          'Upcoming',
          StatusColors.upcoming,
        ),
      PnipDoseStatus.notEligible => (
          'Not eligible',
          Colors.grey,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.vaccineName} Dose ${entry.doseNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  formatDate(
                    entry.scheduledDate,
                  ),
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color:
                  color.withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// VACCINATION HISTORY ITEM
// =============================================================================

class _VaccinationHistoryItem
    extends StatelessWidget {
  final VaccinationRecord record;
  final String Function(DateTime) formatDate;

  const _VaccinationHistoryItem({
    required this.record,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
            size: 21,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  record.vaccine,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '${record.dose} • '
                  '${formatDate(record.dateGiven)}',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  record.healthCenter,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
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
}
