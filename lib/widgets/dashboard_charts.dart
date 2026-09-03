import 'package:flutter/material.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_progress.dart';
import '../models/vaccination_reminder.dart';

class ChildCompletionChart extends StatelessWidget {
  final List<PnipScheduleEntry> schedule;
  const ChildCompletionChart({super.key, required this.schedule});

  @override
  Widget build(BuildContext context) {
    final progress = VaccinationProgress.fromSchedule(schedule);
    if (schedule.isEmpty) return const Text('Schedule not available.');
    final percent = (progress.fraction * 100).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF163C50), Color(0xFF125D68)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Infant schedule completion',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 144,
                  height: 144,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress.fraction,
                          strokeWidth: 14,
                          color: const Color(0xFF8CE3CA),
                          backgroundColor: const Color(0xFF436473),
                          semanticsLabel:
                              'Recorded vaccination completion. ${progress.completed} of ${progress.totalDoses} doses',
                          semanticsValue: '$percent%',
                        ),
                      ),
                      ExcludeSemantics(
                        child: Text(
                          '$percent%',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              '${progress.completed} of ${progress.totalDoses} doses recorded',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Due today: ${schedule.where((e) => e.status == PnipDoseStatus.due).length} · Overdue: ${progress.overdue} · Upcoming: ${progress.upcoming}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Mint: recorded · Slate: remaining, including future doses.\nCompletion is not a measure of immunity.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact counts share a common zero-based scale; no interpolated/mock values.
class FollowUpVaccineChart extends StatelessWidget {
  final List<VaccinationReminder> reminders;
  const FollowUpVaccineChart({super.key, required this.reminders});

  @override
  Widget build(BuildContext context) {
    final groups = <String, ({String name, int due, int overdue})>{};
    for (final row in reminders) {
      if (row.status != VaccinationReminderStatus.dueToday &&
          row.status != VaccinationReminderStatus.overdue) {
        continue;
      }
      final old =
          groups[row.vaccineId] ?? (name: row.vaccineName, due: 0, overdue: 0);
      groups[row.vaccineId] = (
        name: old.name,
        due:
            old.due +
            (row.status == VaccinationReminderStatus.dueToday ? 1 : 0),
        overdue:
            old.overdue +
            (row.status == VaccinationReminderStatus.overdue ? 1 : 0),
      );
    }
    final rows = groups.values.toList()
      ..sort((a, b) => (b.due + b.overdue).compareTo(a.due + a.overdue));
    final maximum = rows.isEmpty ? 1 : rows.first.due + rows.first.overdue;
    const dueColor = Color(0xFFAD6500);
    const overdueColor = Color(0xFFC62828);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Follow-up by vaccine',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Vaccine doses, not unique children. Amber: due today · Red: overdue.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Text('No due or overdue doses to display.'),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Semantics(
                  label:
                      '${row.name}: ${row.due} due today, ${row.overdue} overdue',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${row.due} due today · ${row.overdue} overdue',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            height: 14,
                            child: Row(
                              children: [
                                if (row.due > 0)
                                  Expanded(
                                    flex: row.due,
                                    child: const ColoredBox(
                                      color: dueColor,
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                if (row.overdue > 0)
                                  Expanded(
                                    flex: row.overdue,
                                    child: const ColoredBox(
                                      color: overdueColor,
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                if (maximum > row.due + row.overdue)
                                  Expanded(
                                    flex: maximum - row.due - row.overdue,
                                    child: const ColoredBox(
                                      color: Color(0xFFF0F3F3),
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (rows.isNotEmpty)
              Text(
                'Common scale: 0–$maximum doses',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
