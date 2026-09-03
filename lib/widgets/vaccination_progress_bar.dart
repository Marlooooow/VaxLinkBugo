import 'package:flutter/material.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_progress.dart';

class VaccinationProgressBar extends StatelessWidget {
  final List<PnipScheduleEntry> schedule;
  const VaccinationProgressBar({super.key, required this.schedule});

  @override
  Widget build(BuildContext context) {
    final progress = VaccinationProgress.fromSchedule(schedule);
    final label = schedule.isEmpty
        ? 'Schedule not available'
        : '${progress.completed} of ${progress.totalDoses} doses in the full infant schedule completed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vaccination progress',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, height: 1.4)),
        if (progress.totalDoses > 0) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            semanticsLabel: 'Vaccination progress. $label',
            semanticsValue: '${(progress.fraction * 100).round()}%',
          ),
          const SizedBox(height: 5),
          Text(
            '${(progress.fraction * 100).round()}% overall completion',
            style: const TextStyle(fontSize: 12),
          ),
        ],
        if (schedule.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Overdue: ${progress.overdue} · Upcoming: ${progress.upcoming}',
            style: const TextStyle(fontSize: 12),
          ),
          const Text(
            'Includes future doses through 12 months; these are not missed doses.',
            style: TextStyle(fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }
}
