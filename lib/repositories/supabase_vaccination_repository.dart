import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/child_profile.dart';
import '../models/first_visit_review.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/pnip_schedule_rule.dart';
import '../models/vaccination_assessment.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../services/pnip_schedule_service.dart';
import 'live_data_access.dart';
import 'vaccination_repository.dart';

class SupabaseVaccinationRepository implements VaccinationRepository {
  final SupabaseClient _client;
  SupabaseVaccinationRepository(this._client);
  static const _select =
      '*, vaccine_definitions(name), facilities(name), '
      'profiles!vaccination_records_administered_by_fkey(full_name)';

  @override
  Future<List<VaccinationRecord>> getVaccinationHistory(String childId) async {
    LiveDataAccess(_client).userId;
    final rows = await _client
        .from('vaccination_records')
        .select(_select)
        .eq('child_id', childId)
        .neq('status', 'voided')
        .order('administered_on', ascending: false);
    return rows.map(recordFromRow).toList(growable: false);
  }

  @override
  Future<List<PnipScheduleEntry>> getVaccinationSchedule(
    ChildProfile child,
  ) async {
    final results = await Future.wait([
      getVaccinationHistory(child.id),
      _getActiveScheduleRules(),
    ]);
    return const PnipScheduleService().calculateFromRules(
      child: child,
      history: results[0] as List<VaccinationRecord>,
      rules: results[1] as List<PnipScheduleRule>,
    );
  }

  @override
  Future<VaccinationAssessment> assessChild(ChildProfile child) async {
    final results = await Future.wait([
      getVaccinationHistory(child.id),
      _getActiveScheduleRules(),
    ]);
    final history = results[0] as List<VaccinationRecord>;
    final schedule = const PnipScheduleService().calculateFromRules(
      child: child,
      history: history,
      rules: results[1] as List<PnipScheduleRule>,
    );
    final due = schedule.where((dose) => dose.requiresAction).toList();
    return VaccinationAssessment(
      child: child,
      history: history,
      schedule: schedule,
      recommendedDoses: due,
      status: history.isEmpty
          ? VaccinationAssessmentStatus.firstVaccination
          : due.isEmpty
          ? VaccinationAssessmentStatus.notDue
          : VaccinationAssessmentStatus.vaccinationDue,
      message:
          'Schedule calculated from the saved birth date and vaccination history. '
          'Health-worker assessment is required before administration.',
    );
  }

  Future<List<PnipScheduleRule>> _getActiveScheduleRules() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final rows = await _client
        .from('pnip_schedule_rules')
        .select(
          'vaccine_id, dose_number, recommended_age_days, '
          'minimum_interval_days, effective_from, vaccine_definitions(name)',
        )
        .eq('active', true)
        .lte('effective_from', today)
        .or('effective_to.is.null,effective_to.gte.$today')
        .order('effective_from', ascending: false);

    final current = <String, PnipScheduleRule>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final rule = PnipScheduleRule.fromRow(row);
      current.putIfAbsent('${rule.vaccineId}:${rule.doseNumber}', () => rule);
    }
    if (current.isEmpty) {
      throw StateError(
        'No active PNIP schedule rules are available. Apply the PNIP schedule migration.',
      );
    }
    final rules = current.values.toList()
      ..sort((a, b) {
        final age = a.recommendedAgeDays.compareTo(b.recommendedAgeDays);
        if (age != 0) return age;
        const order = {
          'bcg': 0,
          'hepatitis_b': 1,
          'pentavalent': 2,
          'opv': 3,
          'pcv': 4,
          'ipv': 5,
          'mmr': 6,
        };
        final vaccine = (order[a.vaccineId] ?? 99).compareTo(
          order[b.vaccineId] ?? 99,
        );
        return vaccine != 0 ? vaccine : a.doseNumber.compareTo(b.doseNumber);
      });
    return rules;
  }

  @override
  Future<FirstVisitReview?> getFirstVisitReview(String childId) async {
    final row = await _client
        .from('first_visit_reviews')
        .select()
        .eq('child_id', childId)
        .maybeSingle();
    if (row == null) return null;
    return FirstVisitReview(
      id: row['id'] as String,
      reviewCode: row['review_code'] as String,
      childId: row['child_id'] as String,
      hasDocumentedPreviousVaccinations:
          row['has_documented_previous_vaccinations'] as bool,
      reviewedAt: DateTime.parse(row['reviewed_at'] as String),
      reviewedByUserId: row['reviewed_by'] as String,
    );
  }

  // The prototype saves history and consumes stock separately. That is unsafe
  // for live data: both must commit in one idempotent server transaction.
  @override
  Future<List<VaccinationRecord>> recordVaccinations(
    List<VaccinationRecord> records,
  ) async {
    if (records.isEmpty) return const [];
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Please sign in again.');
    final rows = await _client.rpc(
      'record_vaccinations',
      params: {
        'records': records
            .map(
              (record) => {
                'child_id': record.childId,
                'vaccine_id': record.vaccineId,
                'dose_number': record.doseNumber,
                'administered_on': record.dateAdministered
                    .toIso8601String()
                    .split('T')
                    .first,
                'external_facility_name': record.administeringFacility,
                'external_health_worker_name': record.healthWorkerName,
                'screening_id': record.screeningId,
                'evidence_type': record.evidenceType,
                'notes': record.notes,
                'source': _source(record.source),
              },
            )
            .toList(growable: false),
      },
    );
    return (rows as List)
        .map((row) => recordFromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  @override
  Future<VaccinationRecord> updateVaccinationRecord(
    VaccinationRecord record,
  ) async {
    final id =
        await _client.rpc(
              'correct_live_vaccination_record',
              params: {
                'target_record_id': record.id,
                'target_administered_on': record.dateAdministered
                    .toIso8601String()
                    .split('T')
                    .first,
                'target_facility': record.administeringFacility,
                'target_worker': record.healthWorkerName,
                'target_notes': record.notes,
              },
            )
            as String;
    final row = await _client
        .from('vaccination_records')
        .select(_select)
        .eq('id', id)
        .single();
    return recordFromRow(row);
  }

  @override
  Future<VaccinationScreening> recordScreening(
    VaccinationScreening screening,
  ) async {
    final row = Map<String, dynamic>.from(
      await _client.rpc(
        'record_vaccination_screening',
        params: {
          'target_child_id': screening.childId,
          'history_reviewed': screening.historyReviewed,
          'current_condition_assessed': screening.currentConditionAssessed,
          'contraindications_reviewed': screening.contraindicationsReviewed,
          'guardian_consent_confirmed': screening.guardianConsentConfirmed,
          'outcome': _screeningOutcome(screening.outcome),
          'notes': screening.notes,
        },
      ),
    );
    return VaccinationScreening(
      id: row['id'] as String,
      screeningCode: row['screening_code'] as String,
      childId: row['child_id'] as String,
      historyReviewed: row['history_reviewed'] as bool,
      currentConditionAssessed: row['current_condition_assessed'] as bool,
      contraindicationsReviewed: row['contraindications_reviewed'] as bool,
      guardianConsentConfirmed: row['guardian_consent_confirmed'] as bool,
      outcome: VaccinationScreeningOutcome.values.byName(
        row['outcome'] as String,
      ),
      notes: row['notes'] as String? ?? '',
      screenedAt: DateTime.parse(row['screened_at'] as String),
      screenedByUserId: row['screened_by'] as String,
    );
  }

  @override
  Future<FirstVisitReview> recordFirstVisitReview(
    FirstVisitReview review,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Please sign in again.');
    }
    if (review.id.isEmpty || review.reviewCode.isEmpty) {
      final row = Map<String, dynamic>.from(
        await _client.rpc(
          'record_first_visit_review',
          params: {
            'target_child_id': review.childId,
            'has_documents': review.hasDocumentedPreviousVaccinations,
          },
        ),
      );
      return _firstVisitReviewFromRow(row);
    }
    final row = await _client
        .from('first_visit_reviews')
        .upsert({
          'id': review.id,
          'review_code': review.reviewCode,
          'child_id': review.childId,
          'has_documented_previous_vaccinations':
              review.hasDocumentedPreviousVaccinations,
          'reviewed_by': userId,
          'reviewed_at': review.reviewedAt.toIso8601String(),
        }, onConflict: 'child_id')
        .select()
        .single();
    return _firstVisitReviewFromRow(row);
  }

  @override
  Future<void> completeAdministration({
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
    required Map<String, int> dosesByVaccineId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Please sign in again.');
    await _client.rpc(
      'complete_vaccination_administration',
      params: {
        'screening': {
          'child_id': screening.childId,
          'history_reviewed': screening.historyReviewed,
          'current_condition_assessed': screening.currentConditionAssessed,
          'contraindications_reviewed': screening.contraindicationsReviewed,
          'guardian_consent_confirmed': screening.guardianConsentConfirmed,
          'outcome': _screeningOutcome(screening.outcome),
          'notes': screening.notes,
        },
        'records': records
            .map(
              (record) => {
                'child_id': record.childId,
                'vaccine_id': record.vaccineId,
                'dose_number': record.doseNumber,
                'administered_on': record.dateAdministered
                    .toIso8601String()
                    .split('T')
                    .first,
                'external_facility_name': record.administeringFacility,
                'external_health_worker_name': record.healthWorkerName,
                'evidence_type': record.evidenceType,
                'notes': record.notes,
                'source': _source(record.source),
              },
            )
            .toList(growable: false),
        'doses': dosesByVaccineId,
      },
    );
  }

  static FirstVisitReview _firstVisitReviewFromRow(Map<String, dynamic> row) =>
      FirstVisitReview(
        id: row['id'] as String,
        reviewCode: row['review_code'] as String,
        childId: row['child_id'] as String,
        hasDocumentedPreviousVaccinations:
            row['has_documented_previous_vaccinations'] as bool,
        reviewedAt: DateTime.parse(row['reviewed_at'] as String),
        reviewedByUserId: row['reviewed_by'] as String,
      );

  static String _source(VaccinationSource source) => switch (source) {
    VaccinationSource.bugo => 'local',
    VaccinationSource.externalReferral => 'external_referral',
    VaccinationSource.previousRecord => 'previous_record',
  };

  static String _screeningOutcome(VaccinationScreeningOutcome outcome) =>
      outcome.name;

  static VaccinationRecord recordFromRow(Map<String, dynamic> row) =>
      VaccinationRecord(
        id: row['id'] as String,
        recordCode: row['vaccination_code'] as String,
        childId: row['child_id'] as String,
        vaccineId: row['vaccine_id'] as String,
        vaccineName:
            (row['vaccine_definitions'] as Map?)?['name'] as String? ??
            row['vaccine_id'] as String,
        doseNumber: row['dose_number'] as int,
        dateAdministered: DateTime.parse(row['administered_on'] as String),
        administeringFacility:
            row['external_facility_name'] as String? ??
            (row['facilities'] as Map?)?['name'] as String? ??
            'Facility not recorded',
        healthWorkerName:
            row['external_health_worker_name'] as String? ??
            (row['profiles'] as Map?)?['full_name'] as String? ??
            'Not recorded',
        healthWorkerId: row['administered_by'] as String?,
        source: switch (row['source']) {
          'local' => VaccinationSource.bugo,
          'external_referral' => VaccinationSource.externalReferral,
          'previous_record' => VaccinationSource.previousRecord,
          _ => throw const FormatException('Unknown vaccination source.'),
        },
        notes: row['notes'] as String? ?? '',
        recordedAt: DateTime.parse(row['recorded_at'] as String),
        recordedByUserId: row['recorded_by'] as String?,
        screeningId: row['screening_id'] as String?,
        referralId: row['referral_item_id'] as String?,
        externalVisitId: row['external_visit_id'] as String?,
        evidenceType: row['evidence_type'] as String?,
      );
}
