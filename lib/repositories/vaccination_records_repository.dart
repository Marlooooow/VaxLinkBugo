import '../models/vaccination_record_summary.dart';

abstract class VaccinationRecordsRepository {
  Future<VaccinationRecordSummaryPage> getSummaries({
    String search = '',
    VaccinationRecordSummaryFilter filter = VaccinationRecordSummaryFilter.all,
    int pageSize = 20,
    VaccinationRecordSummaryCursor? cursor,
  });
}
