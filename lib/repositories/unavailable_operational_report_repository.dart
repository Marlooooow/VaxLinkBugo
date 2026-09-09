import '../models/operational_report.dart';
import 'operational_report_repository.dart';

class UnavailableOperationalReportRepository
    implements OperationalReportRepository {
  const UnavailableOperationalReportRepository();

  @override
  Future<OperationalReport> generate({
    required OperationalReportType type,
    required DateTime fromDate,
    required DateTime toDate,
  }) => throw StateError(
    'Operational reports require a live database connection.',
  );
}
