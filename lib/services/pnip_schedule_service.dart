import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/pnip_schedule_rule.dart';
import '../models/vaccination_record.dart';

class PnipScheduleService {
  const PnipScheduleService();

  List<PnipScheduleEntry> calculate({
    required ChildProfile child,
    required List<VaccinationRecord> history,
    DateTime? asOf,
  }) {
    final todayValue = asOf ?? DateTime.now();
    final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
    final definitions = _definitions(child.birthDate);
    final completedKeys = <String, VaccinationRecord>{
      for (final record in history)
        _key(record.vaccineId, record.doseNumber): record,
    };

    return definitions
        .map((definition) {
          final record =
              completedKeys[_key(definition.vaccineId, definition.dose)];
          final previousRecord = definition.dose > 1
              ? completedKeys[_key(definition.vaccineId, definition.dose - 1)]
              : null;
          // Two-dose IPV routine schedule: at least four months after IPV1.
          // https://hta.dost.gov.ph/wp-content/uploads/2021/09/HTAC-Recommendation-and-ES-on-Two-dose-IPV.pdf
          final minimumIntervalDate = previousRecord == null
              ? null
              : definition.vaccineId == 'ipv'
              ? _addMonths(previousRecord.dateAdministered, 4)
              : previousRecord.dateAdministered.add(const Duration(days: 28));
          final effectiveScheduledDate =
              minimumIntervalDate != null &&
                  minimumIntervalDate.isAfter(definition.date)
              ? minimumIntervalDate
              : definition.date;
          if (record != null) {
            return PnipScheduleEntry(
              vaccineId: definition.vaccineId,
              vaccineName: definition.vaccineName,
              doseNumber: definition.dose,
              scheduledDate: effectiveScheduledDate,
              status: PnipDoseStatus.completed,
              administeredDate: record.dateAdministered,
              vaccinationRecordId: record.id,
            );
          }
          final previousRequired = definition.dose > 1;
          final previousCompleted = !previousRequired || previousRecord != null;
          final status = !previousCompleted
              ? PnipDoseStatus.notEligible
              : effectiveScheduledDate.isAfter(today)
              ? PnipDoseStatus.upcoming
              : effectiveScheduledDate.isBefore(today)
              ? PnipDoseStatus.overdue
              : PnipDoseStatus.due;
          return PnipScheduleEntry(
            vaccineId: definition.vaccineId,
            vaccineName: definition.vaccineName,
            doseNumber: definition.dose,
            scheduledDate: effectiveScheduledDate,
            status: status,
          );
        })
        .toList(growable: false);
  }

  /// Calculates a schedule from the versioned rules loaded from the live
  /// database. Mock mode continues to use [calculate] and its local fixture.
  List<PnipScheduleEntry> calculateFromRules({
    required ChildProfile child,
    required List<VaccinationRecord> history,
    required List<PnipScheduleRule> rules,
    DateTime? asOf,
  }) {
    final todayValue = asOf ?? DateTime.now();
    final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
    final completedKeys = <String, VaccinationRecord>{
      for (final record in history)
        _key(record.vaccineId, record.doseNumber): record,
    };

    return rules
        .map((rule) {
          final record = completedKeys[_key(rule.vaccineId, rule.doseNumber)];
          final previousRecord = rule.doseNumber > 1
              ? completedKeys[_key(rule.vaccineId, rule.doseNumber - 1)]
              : null;
          final ageDate = child.birthDate.add(
            Duration(days: rule.recommendedAgeDays),
          );
          final intervalDate =
              previousRecord == null || rule.minimumIntervalDays == null
              ? null
              : previousRecord.dateAdministered.add(
                  Duration(days: rule.minimumIntervalDays!),
                );
          final scheduledDate =
              intervalDate != null && intervalDate.isAfter(ageDate)
              ? intervalDate
              : ageDate;

          if (record != null) {
            return PnipScheduleEntry(
              vaccineId: rule.vaccineId,
              vaccineName: rule.vaccineName,
              doseNumber: rule.doseNumber,
              scheduledDate: scheduledDate,
              status: PnipDoseStatus.completed,
              administeredDate: record.dateAdministered,
              vaccinationRecordId: record.id,
            );
          }

          final previousCompleted =
              rule.doseNumber == 1 || previousRecord != null;
          final status = !previousCompleted
              ? PnipDoseStatus.notEligible
              : scheduledDate.isAfter(today)
              ? PnipDoseStatus.upcoming
              : scheduledDate.isBefore(today)
              ? PnipDoseStatus.overdue
              : PnipDoseStatus.due;
          return PnipScheduleEntry(
            vaccineId: rule.vaccineId,
            vaccineName: rule.vaccineName,
            doseNumber: rule.doseNumber,
            scheduledDate: scheduledDate,
            status: status,
          );
        })
        .toList(growable: false);
  }

  List<_PnipDefinition> _definitions(DateTime birthDate) => [
    _PnipDefinition('bcg', 'BCG', 1, birthDate),
    _PnipDefinition('hepatitis_b', 'Hepatitis B', 1, birthDate),
    for (final dose in const [1, 2, 3]) ...[
      _PnipDefinition(
        'pentavalent',
        'Pentavalent',
        dose,
        birthDate.add(Duration(days: [0, 6, 10, 14][dose] * 7)),
      ),
      _PnipDefinition(
        'opv',
        'OPV',
        dose,
        birthDate.add(Duration(days: [0, 6, 10, 14][dose] * 7)),
      ),
      _PnipDefinition(
        'pcv',
        'PCV',
        dose,
        birthDate.add(Duration(days: [0, 6, 10, 14][dose] * 7)),
      ),
    ],
    _PnipDefinition('ipv', 'IPV', 1, birthDate.add(const Duration(days: 98))),
    _PnipDefinition('ipv', 'IPV', 2, _addMonths(birthDate, 9)),
    _PnipDefinition('mmr', 'MMR', 1, _addMonths(birthDate, 9)),
    _PnipDefinition('mmr', 'MMR', 2, _addMonths(birthDate, 12)),
  ];

  static DateTime _addMonths(DateTime value, int months) {
    final targetMonth = DateTime(value.year, value.month + months, 1);
    final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
    final day = value.day > lastDay ? lastDay : value.day;
    return DateTime(targetMonth.year, targetMonth.month, day);
  }

  static String _key(String vaccineId, int dose) => '$vaccineId:$dose';
}

class _PnipDefinition {
  final String vaccineId;
  final String vaccineName;
  final int dose;
  final DateTime date;

  const _PnipDefinition(this.vaccineId, this.vaccineName, this.dose, this.date);
}
