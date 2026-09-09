import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_report.dart';
import 'operational_report_repository.dart';

class SupabaseOperationalReportRepository
    implements OperationalReportRepository {
  final SupabaseClient _client;

  const SupabaseOperationalReportRepository(this._client);

  @override
  Future<OperationalReport> generate({
    required OperationalReportType type,
    required DateTime fromDate,
    required DateTime toDate,
    String? childId,
  }) async {
    if (type == OperationalReportType.childVaccinationRecord &&
        childId == null) {
      throw ArgumentError('Select a child before generating this report.');
    }
    final raw = switch (type) {
      OperationalReportType.childVaccinationRecord => await _client.rpc(
        'get_child_vaccination_report',
        params: {
          'p_child_id': childId,
          'p_from_date': _date(fromDate),
          'p_to_date': _date(toDate),
        },
      ),
      OperationalReportType.inventoryTransactions => await _client.rpc(
        'get_inventory_transaction_report',
        params: {'p_from_date': _date(fromDate), 'p_to_date': _date(toDate)},
      ),
      _ => await _client.rpc(
        'get_operational_report',
        params: {
          'p_report_type': _snake(type.name),
          'p_from_date': _date(fromDate),
          'p_to_date': _date(toDate),
        },
      ),
    };
    final result = Map<String, dynamic>.from(raw as Map);
    return OperationalReport(
      type: type,
      title: result['title'] as String,
      facilityName: result['facility_name'] as String,
      fromDate: DateTime.parse(result['from_date'] as String),
      toDate: DateTime.parse(result['to_date'] as String),
      generatedAt: DateTime.parse(result['generated_at'] as String),
      columns: (result['columns'] as List? ?? const [])
          .map((column) {
            final value = Map<String, dynamic>.from(column as Map);
            return OperationalReportColumn(
              key: value['key'] as String,
              label: value['label'] as String,
            );
          })
          .toList(growable: false),
      rows: (result['rows'] as List? ?? const [])
          .map(
            (row) => Map<String, Object?>.from(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}
