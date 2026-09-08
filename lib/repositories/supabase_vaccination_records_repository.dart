import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vaccination_record_summary.dart';
import 'live_data_access.dart';
import 'vaccination_records_repository.dart';

class SupabaseVaccinationRecordsRepository
    implements VaccinationRecordsRepository {
  final SupabaseClient _client;

  const SupabaseVaccinationRecordsRepository(this._client);

  @override
  Future<VaccinationRecordSummaryPage> getSummaries({
    String search = '',
    VaccinationRecordSummaryFilter filter =
        VaccinationRecordSummaryFilter.all,
    int pageSize = 20,
    VaccinationRecordSummaryCursor? cursor,
  }) async {
    LiveDataAccess(_client).userId;
    final safePageSize = pageSize.clamp(10, 50).toInt();
    final response = await _client.rpc(
      'get_vaccination_record_summaries',
      params: {
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_filter': filter.databaseValue,
        'p_page_size': safePageSize,
        'p_cursor_sort_at': cursor?.sortAt.toUtc().toIso8601String(),
        'p_cursor_child_id': cursor?.childId,
      },
    );
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final hasMore = rows.length > safePageSize;
    final pageRows = hasMore ? rows.take(safePageSize).toList() : rows;
    final items = pageRows
        .map(VaccinationRecordSummary.fromRow)
        .toList(growable: false);
    return VaccinationRecordSummaryPage(
      items: items,
      totalCount: rows.isEmpty
          ? 0
          : (rows.first['total_count'] as num?)?.toInt() ?? items.length,
      hasMore: hasMore,
      nextCursor: items.isEmpty ? null : items.last.cursor,
    );
  }
}
