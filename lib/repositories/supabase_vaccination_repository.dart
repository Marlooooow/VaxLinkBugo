import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/child/child_profile.dart';
import '../models/first_visit_review.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_assessment.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
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
    final rows = await _client.rpc(
      'get_child_pnip_schedule',
      params: {'target_child_id': child.id},
    );
    return (rows as List)
        .map(
          (row) =>
              PnipScheduleEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<Map<String, List<PnipScheduleEntry>>> getVaccinationSchedules(
    List<ChildProfile> children,
  ) async {
    if (children.isEmpty) return const {};
    final grouped = <String, List<PnipScheduleEntry>>{
      for (final child in children) child.id: [],
    };
    for (var start = 0; start < children.length; start += 50) {
      final end = (start + 50).clamp(0, children.length);
      final rows = await _client.rpc(
        'get_children_pnip_schedules',
        params: {
          'target_child_ids': children
              .sublist(start, end)
              .map((child) => child.id)
              .toList(),
        },
      );
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final childId = row.remove('child_id') as String;
        grouped[childId]?.add(PnipScheduleEntry.fromJson(row));
      }
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  @override
  Future<VaccinationAssessment> assessChild(ChildProfile child) async {
    final historyRequest = getVaccinationHistory(child.id);
    final scheduleRequest = getVaccinationSchedule(child);
    final history = await historyRequest;
    final schedule = await scheduleRequest;
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
          'Schedule calculated from the live PNIP rules, saved birth date, and vaccination history. '
          'Health-worker assessment is required before administration.',
    );
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
      historyStatus: _historyStatus(row),
      notes: row['history_notes'] as String? ?? '',
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
    if (_client.auth.currentUser?.id == null) {
      throw StateError('Please sign in again.');
    }
    final row = Map<String, dynamic>.from(
      await _client.rpc(
        'record_first_visit_review',
        params: {
          'target_child_id': review.childId,
          'selected_history_status': _historyStatusValue(review.historyStatus),
          'review_notes': review.notes,
        },
      ),
    );
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
        historyStatus: _historyStatus(row),
        notes: row['history_notes'] as String? ?? '',
        reviewedAt: DateTime.parse(row['reviewed_at'] as String),
        reviewedByUserId: row['reviewed_by'] as String,
      );

  static String _source(VaccinationSource source) => switch (source) {
    VaccinationSource.bugo => 'local',
    VaccinationSource.externalReferral => 'external_referral',
    VaccinationSource.previousRecord => 'previous_record',
    VaccinationSource.outreach => 'outreach',
  };

  static FirstVisitHistoryStatus _historyStatus(Map<String, dynamic> row) =>
      switch (row['history_status']) {
        'verified_records' => FirstVisitHistoryStatus.verifiedRecords,
        'confirmed_none' => FirstVisitHistoryStatus.confirmedNone,
        'unknown_history' => FirstVisitHistoryStatus.unknownHistory,
        _ =>
          row['has_documented_previous_vaccinations'] == true
              ? FirstVisitHistoryStatus.verifiedRecords
              : FirstVisitHistoryStatus.unknownHistory,
      };

  static String _historyStatusValue(FirstVisitHistoryStatus value) =>
      switch (value) {
        FirstVisitHistoryStatus.verifiedRecords => 'verified_records',
        FirstVisitHistoryStatus.unknownHistory => 'unknown_history',
        FirstVisitHistoryStatus.confirmedNone => 'confirmed_none',
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
          'outreach' => VaccinationSource.outreach,
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
