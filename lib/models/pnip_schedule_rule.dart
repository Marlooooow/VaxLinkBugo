class PnipScheduleRule {
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final int recommendedAgeDays;
  final int? minimumIntervalDays;

  const PnipScheduleRule({
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.recommendedAgeDays,
    this.minimumIntervalDays,
  });

  factory PnipScheduleRule.fromRow(Map<String, dynamic> row) {
    final vaccine = row['vaccine_definitions'];
    return PnipScheduleRule(
      vaccineId: row['vaccine_id'] as String,
      vaccineName: vaccine is Map && vaccine['name'] is String
          ? vaccine['name'] as String
          : row['vaccine_id'] as String,
      doseNumber: row['dose_number'] as int,
      recommendedAgeDays: row['recommended_age_days'] as int,
      minimumIntervalDays: row['minimum_interval_days'] as int?,
    );
  }
}
