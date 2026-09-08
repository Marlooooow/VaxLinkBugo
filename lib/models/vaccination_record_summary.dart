import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';

enum VaccinationRecordSummaryFilter {
  all('all'),
  recorded('recorded'),
  dueNow('due_now'),
  overdue('overdue'),
  upcoming('upcoming'),
  completed('completed');

  final String databaseValue;
  const VaccinationRecordSummaryFilter(this.databaseValue);
}

class VaccinationRecordSummaryCursor {
  final DateTime sortAt;
  final String childId;

  const VaccinationRecordSummaryCursor({
    required this.sortAt,
    required this.childId,
  });
}

class VaccinationRecordSummary {
  final ChildProfile child;
  final String guardianId;
  final String guardianCode;
  final String guardianName;
  final int recordedCount;
  final int completedCount;
  final int dueCount;
  final int overdueCount;
  final int upcomingCount;
  final int scheduleCount;
  final String? latestVaccineName;
  final int? latestDoseNumber;
  final DateTime? latestAdministeredOn;
  final DateTime sortAt;

  const VaccinationRecordSummary({
    required this.child,
    required this.guardianId,
    required this.guardianCode,
    required this.guardianName,
    required this.recordedCount,
    required this.completedCount,
    required this.dueCount,
    required this.overdueCount,
    required this.upcomingCount,
    required this.scheduleCount,
    required this.latestVaccineName,
    required this.latestDoseNumber,
    required this.latestAdministeredOn,
    required this.sortAt,
  });

  bool get isCompleted => scheduleCount > 0 && completedCount == scheduleCount;

  VaccinationRecordSummaryCursor get cursor =>
      VaccinationRecordSummaryCursor(sortAt: sortAt, childId: child.id);

  factory VaccinationRecordSummary.fromRow(Map<String, dynamic> row) {
    DateTime? optionalDate(Object? value) =>
        value == null ? null : DateTime.parse(value as String);

    int count(String key) => (row[key] as num?)?.toInt() ?? 0;

    return VaccinationRecordSummary(
      child: ChildProfile(
        id: row['child_id'] as String,
        fullName: row['child_name'] as String,
        birthDate: DateTime.parse(row['child_birth_date'] as String),
        sex: row['child_sex'] as String,
        qrIdentifier: row['child_code'] as String,
        relationship: row['relationship'] as String,
      ),
      guardianId: row['guardian_id'] as String,
      guardianCode: row['guardian_code'] as String,
      guardianName: row['guardian_name'] as String,
      recordedCount: count('recorded_count'),
      completedCount: count('completed_count'),
      dueCount: count('due_count'),
      overdueCount: count('overdue_count'),
      upcomingCount: count('upcoming_count'),
      scheduleCount: count('schedule_count'),
      latestVaccineName: row['latest_vaccine_name'] as String?,
      latestDoseNumber: (row['latest_dose_number'] as num?)?.toInt(),
      latestAdministeredOn: optionalDate(row['latest_administered_on']),
      sortAt: DateTime.parse(row['sort_at'] as String),
    );
  }
}

class VaccinationRecordSummaryPage {
  final List<VaccinationRecordSummary> items;
  final int totalCount;
  final bool hasMore;
  final VaccinationRecordSummaryCursor? nextCursor;

  const VaccinationRecordSummaryPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextCursor,
  });
}
