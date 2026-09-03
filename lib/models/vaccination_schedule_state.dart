import 'pnip_schedule_entry.dart';

enum VaccinationScheduleState { completed, dueNow, upcoming, overdue }

extension VaccinationScheduleStateDetails on VaccinationScheduleState {
  String get label => switch (this) {
    VaccinationScheduleState.completed => 'Completed',
    VaccinationScheduleState.dueNow => 'Due now',
    VaccinationScheduleState.upcoming => 'Upcoming',
    VaccinationScheduleState.overdue => 'Overdue',
  };
}

VaccinationScheduleState summarizeSchedule(List<PnipScheduleEntry> schedule) {
  if (schedule.every((entry) => entry.status == PnipDoseStatus.completed)) {
    return VaccinationScheduleState.completed;
  }
  if (schedule.any((entry) => entry.status == PnipDoseStatus.overdue)) {
    return VaccinationScheduleState.overdue;
  }
  if (schedule.any((entry) => entry.status == PnipDoseStatus.due)) {
    return VaccinationScheduleState.dueNow;
  }
  return VaccinationScheduleState.upcoming;
}
