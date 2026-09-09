import '../models/operational_report.dart';

abstract class OperationalReportRepository {
  Future<OperationalReport> generate({
    required OperationalReportType type,
    required DateTime fromDate,
    required DateTime toDate,
  });
}
