import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/advisory_insight.dart';
import 'advisory_insight_repository.dart';

class SupabaseAdvisoryInsightRepository implements AdvisoryInsightRepository {
  final SupabaseClient _client;

  SupabaseAdvisoryInsightRepository(this._client);

  static const _select = '*, children(full_name), vaccine_definitions(name)';

  @override
  Future<List<AdvisoryInsight>> getFacilityInsights() async {
    await _syncChildAdvisories();
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

  Future<void> _syncChildAdvisories() async {
    try {
      await _client.rpc('sync_child_advisory_insights');
    } on PostgrestException {
      // Keep existing advisory rows usable if synchronization is unavailable
      // or temporarily fails. Once the RPC is available, the next load will
      // retry it before reading the facility list.
      return;
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
