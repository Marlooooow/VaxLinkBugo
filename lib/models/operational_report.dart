enum OperationalReportType {
  followUps,
  vaccinationAccomplishment,
  inventory,
  outreachSessions,
  childVaccinationRecord,
  inventoryTransactions,
}

class OperationalReportColumn {
  final String key;
  final String label;

  const OperationalReportColumn({required this.key, required this.label});
}

class OperationalReport {
  final OperationalReportType type;
  final String title;
  final String facilityName;
  final DateTime fromDate;
  final DateTime toDate;
  final DateTime generatedAt;
  final List<OperationalReportColumn> columns;
  final List<Map<String, Object?>> rows;

  const OperationalReport({
    required this.type,
    required this.title,
    required this.facilityName,
    required this.fromDate,
    required this.toDate,
    required this.generatedAt,
    required this.columns,
    required this.rows,
  });
}
