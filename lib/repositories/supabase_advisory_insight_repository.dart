import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:qr_code_based_pediatric_vaccination/models/advisory_insight.dart';

import 'advisory_insight_repository.dart';

class SupabaseAdvisoryInsightRepository
    implements AdvisoryInsightRepository, AdvisoryInsightGenerator {
  final SupabaseClient _client;

  SupabaseAdvisoryInsightRepository(this._client);

  static const _select = '*, children(full_name), vaccine_definitions(name)';

  @override
  Future<List<AdvisoryInsight>> getFacilityInsights() async {
    final profile = await _client
        .from('profiles')
        .select('facility_id')
        .eq('id', _client.auth.currentUser!.id)
        .single();
    final rows = await _client
        .from('advisory_insights')
        .select(_select)
        .eq('facility_id', profile['facility_id'])
        .order('generated_at', ascending: false);
    return rows.map<AdvisoryInsight>(_fromRow).toList(growable: false);
  }

  @override
  Future<AdvisoryInsightPage> getFacilityInsightsPage({
    AdvisoryInsightSeverity? severity,
    AdvisoryInsightStatus? status,
    String? insightId,
    int limit = 20,
    int offset = 0,
  }) async {
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'get_advisory_insight_page',
            params: {
              'p_severity': severity?.name,
              'p_status': status == null ? null : _snake(status.name),
              'p_insight_id': insightId,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final summary = Map<String, dynamic>.from(result['summary'] as Map? ?? {});
    return AdvisoryInsightPage(
      items: (result['items'] as List? ?? const [])
          .map((row) => _fromRow(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false),
      summary: AdvisoryInsightSummary(
        high: (summary['high'] as num?)?.toInt() ?? 0,
        medium: (summary['medium'] as num?)?.toInt() ?? 0,
        newCount: (summary['new'] as num?)?.toInt() ?? 0,
      ),
      totalCount: (result['total_count'] as num?)?.toInt() ?? 0,
      hasMore: result['has_more'] == true,
      nextOffset: (result['next_offset'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> generateFacilityInsights() async {
    try {
      final result = await _client.functions.invoke(
        'generate-advisory-insights',
        body: const <String, dynamic>{},
      );
      if (result.status < 200 || result.status >= 300 || result.data is! Map) {
        throw StateError('The advisory service returned an invalid response.');
      }
      final generated = (result.data as Map)['generated'];
      if (generated is! num) {
        throw StateError('The advisory service did not confirm its results.');
      }
      return generated.toInt();
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw StateError(details['error'] as String);
      }
      rethrow;
    }
  }

  @override
  Future<AdvisoryInsight> updateStatus({
    required String insightId,
    required AdvisoryInsightStatus status,
    required String reviewedByUserId,
  }) async {
    final row = await _client
        .from('advisory_insights')
        .update({
          'status': _snake(status.name),
          'reviewed_by': _client.auth.currentUser!.id,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', insightId)
        .select(_select)
        .single();
    return _fromRow(row);
  }

  AdvisoryInsight _fromRow(Map<String, dynamic> row) {
    final child = row['children'] as Map<String, dynamic>?;
    final vaccine = row['vaccine_definitions'] as Map<String, dynamic>?;
    return AdvisoryInsight(
      id: row['id'] as String,
      insightCode: row['insight_code'] as String,
      type: AdvisoryInsightType.values.byName(_camel(row['type'] as String)),
      severity: AdvisoryInsightSeverity.values.byName(
        row['severity'] as String,
      ),
      status: AdvisoryInsightStatus.values.byName(
        _camel(row['status'] as String),
      ),
      title: row['title'] as String,
      summary: row['summary'] as String,
      rationale: row['rationale'] as String,
      recommendedAction: row['recommended_action'] as String,
      childId: row['child_id'] as String?,
      childName: child?['full_name'] as String?,
      vaccineId: row['vaccine_id'] as String?,
      vaccineName: vaccine?['name'] as String?,
      sourceEntityIds: (row['source_entity_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      sourceSnapshot: Map<String, Object?>.from(
        row['source_snapshot'] as Map? ?? const {},
      ),
      analysisProvider: row['analysis_provider'] as String,
      analysisVersion: row['analysis_version'] as String,
      generatedAt: DateTime.parse(row['generated_at'] as String),
      reviewedAt: row['reviewed_at'] == null
          ? null
          : DateTime.parse(row['reviewed_at'] as String),
      reviewedByUserId: row['reviewed_by'] as String?,
    );
  }

  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
  static String _camel(String value) => value.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}
