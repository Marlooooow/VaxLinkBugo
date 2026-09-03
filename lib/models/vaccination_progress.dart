import 'pnip_schedule_entry.dart';

/// Derived display data, never a persisted percentage or eligibility decision.
class VaccinationProgress {
  final int completed;
  final int totalDoses;
  final int overdue;
  final int upcoming;

  const VaccinationProgress(
    this.completed,
    this.totalDoses,
    this.overdue,
    this.upcoming,
  );

  double get fraction => totalDoses == 0 ? 0 : completed / totalDoses;

  factory VaccinationProgress.fromSchedule(
    List<PnipScheduleEntry> schedule, {
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    // One entry per vaccine/dose prevents duplicate records inflating progress.
    final entries = <String, PnipScheduleEntry>{
      for (final entry in schedule)
        '${entry.vaccineId}:${entry.doseNumber}': entry,
    }.values;
    return VaccinationProgress(
      entries
          .where(
            (e) =>
                e.status == PnipDoseStatus.completed &&
                e.administeredDate != null &&
                !day(e.administeredDate!).isAfter(today),
          )
          .length,
      entries.length,
      entries.where((e) => e.status == PnipDoseStatus.overdue).length,
      entries.where((e) => e.status == PnipDoseStatus.upcoming).length,
    );
  }
}
