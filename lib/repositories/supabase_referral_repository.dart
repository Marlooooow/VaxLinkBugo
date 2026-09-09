import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/referral.dart';
import '../models/referral_verification_result.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_record.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_visit.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_correction.dart';
import '../models/referral_group.dart';
import '../models/vaccine_inventory.dart';
import 'referral_repository.dart';

class SupabaseReferralRepository implements ReferralRepository {
  final SupabaseClient _client;

  SupabaseReferralRepository(this._client);

  static const _referralSelect =
      'id, referral_code, referral_group_id, vaccine_id, dose_number, scheduled_due_date, status, completed_at, '
      'referral_groups!inner(id, referral_group_code, child_id, issued_on, created_at, '
      'children!inner(full_name), facilities!inner(name)), '
      'vaccine_definitions!inner(name)';

  @override
  Future<Referral> createReferral({
    required ChildProfile child,
    required VaccineInventory vaccine,
  }) async {
    final referrals = await createReferralGroup(
      child: child,
      vaccines: [vaccine],
    );
    return referrals.single;
  }

  @override
  Future<List<Referral>> createReferralGroup({
    required ChildProfile child,
    required List<VaccineInventory> vaccines,
  }) async {
    if (vaccines.isEmpty) {
      throw ArgumentError('At least one unavailable vaccine is required.');
    }

    final response = await _client.rpc(
      'create_referral_group',
      params: {
        'target_child_id': child.id,
        'target_vaccine_ids': vaccines.map((item) => item.vaccineId).toList(),
      },
    );
    final payload = Map<String, dynamic>.from(response as Map);
    final rows = (payload['referrals'] as List<dynamic>? ?? const []);
    return rows
        .map((row) => Referral.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  @override
  Future<Referral?> getReferralById(String referralId) async {
    final row = await _client
        .from('referral_items')
        .select(_referralSelect)
        .ilike('referral_code', referralId.trim())
        .maybeSingle();
    return row == null ? null : _referralFromRow(row);
  }

  @override
  Future<List<Referral>> getReferralGroupByReferralId(String referralId) async {
    final referral = await getReferralById(referralId);
    return referral == null
        ? const []
        : _referralsForGroup(referral.referralGroupId);
  }

  @override
  Future<ReferralGroup?> getReferralGroup(String referralGroupId) async {
    final referrals = await _referralsForGroup(referralGroupId);
    if (referrals.isEmpty) return null;
    final first = referrals.first;
    return ReferralGroup(
      referralGroupId: first.referralGroupId,
      referralGroupCode: first.referralGroupCode,
      verificationToken: '',
      childId: first.childId,
      childName: first.childName,
      originatingFacility: first.originatingFacility,
      issuedAt: first.createdAt,
      referrals: referrals,
    );
  }

  @override
  Future<List<ReferralGroup>> getReferralGroups({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    return (await getReferralGroupsPage(
      query: query,
      status: status,
      overdueOnly: overdueOnly,
      limit: limit,
      offset: offset,
    )).items;
  }

  @override
  Future<ReferralGroupPage> getReferralGroupsPage({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_referral_group_page',
            params: {
              'p_search': query.trim().isEmpty ? null : query.trim(),
              'p_status': switch (status) {
                ReferralGroupStatus.pending => 'pending',
                ReferralGroupStatus.partiallyCompleted => 'partial',
                ReferralGroupStatus.completed => 'completed',
                null => null,
              },
              'p_overdue_only': overdueOnly,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final groups = (payload['items'] as List? ?? const [])
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final referrals = (row['referrals'] as List? ?? const [])
              .map(
                (item) =>
                    Referral.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList(growable: false);
          return ReferralGroup.fromJson(row, referrals: referrals);
        })
        .toList(growable: false);
    final counts = Map<String, dynamic>.from(
      payload['summary'] as Map? ?? const {},
    );

    return ReferralGroupPage(
      items: groups,
      totalCount: (payload['total_count'] as num?)?.toInt() ?? groups.length,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
      summary: ReferralGroupSummaryCounts(
        pending: (counts['pending'] as num?)?.toInt() ?? 0,
        partiallyCompleted: (counts['partial'] as num?)?.toInt() ?? 0,
        completed: (counts['completed'] as num?)?.toInt() ?? 0,
        overdue: (counts['overdue'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<List<Referral>> _referralsForGroup(String groupId) async {
    final rows = await _client
        .from('referral_items')
        .select(_referralSelect)
        .eq('referral_group_id', groupId)
        .order('referral_code');
    return rows.map(_referralFromRow).toList(growable: false);
  }

  Referral _referralFromRow(Map<String, dynamic> row) {
    final group = Map<String, dynamic>.from(row['referral_groups'] as Map);
    final child = Map<String, dynamic>.from(group['children'] as Map);
    final facility = Map<String, dynamic>.from(group['facilities'] as Map);
    final vaccine = Map<String, dynamic>.from(
      row['vaccine_definitions'] as Map,
    );
    final issued = DateTime.parse(group['issued_on'] as String);
    return Referral(
      id: row['id'] as String,
      referralCode: row['referral_code'] as String,
      referralGroupId: row['referral_group_id'] as String,
      referralGroupCode: group['referral_group_code'] as String,
      childId: group['child_id'] as String,
      childName: child['full_name'] as String,
      vaccineId: row['vaccine_id'] as String,
      vaccineName: vaccine['name'] as String,
      doseNumber: row['dose_number'] as int,
      scheduledDueDate: row['scheduled_due_date'] == null
          ? issued
          : DateTime.parse(row['scheduled_due_date'] as String),
      originatingFacility: facility['name'] as String,
      status: (row['status'] as String) == 'completed'
          ? 'Completed'
          : 'Pending',
      createdAt: DateTime.parse(group['created_at'] as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
    );
  }

  @override
  Future<ReferralVerificationResult> verifyReferralGroup({
    required String referralGroupId,
    String? verificationToken,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_verified_referral_group',
            params: {
              'target_group_id': referralGroupId,
              'supplied_token': verificationToken,
            },
          )
          as Map,
    );
    final result = payload['status'] as String;
    if (result == 'not_found') {
      return const ReferralVerificationResult(
        status: ReferralVerificationStatus.notFound,
        message: 'This referral could not be found.',
      );
    }
    if (result == 'invalid_token') {
      return const ReferralVerificationResult(
        status: ReferralVerificationStatus.invalidToken,
        message: 'The QR verification code is invalid.',
      );
    }
    final rawGroup = payload['group'];
    final group = rawGroup is Map
        ? ReferralGroup.fromJson(
            Map<String, dynamic>.from(rawGroup),
            referrals: (rawGroup['referrals'] as List? ?? const [])
                .map(
                  (item) => Referral.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ).copyWith(verificationToken: verificationToken),
                )
                .toList(growable: false),
          )
        : null;
    if (result == 'completed' || result == 'cancelled') {
      return ReferralVerificationResult(
        status: result == 'completed'
            ? ReferralVerificationStatus.completed
            : ReferralVerificationStatus.cancelled,
        referralGroup: group,
        message: 'This referral is no longer available for recording.',
      );
    }
    return ReferralVerificationResult(
      status: ReferralVerificationStatus.valid,
      referralGroup: group,
      message: 'Referral verified. Confirm the details before continuing.',
    );
  }

  @override
  Future<Referral> recordExternalVaccination({
    required Referral referral,
    required ExternalVaccinationRecord record,
  }) async {
    final completed = await recordExternalVaccinationBatch(
      referrals: [referral],
      records: [record],
    );
    return completed.single;
  }

  @override
  Future<List<Referral>> recordExternalVaccinationBatch({
    required List<Referral> referrals,
    required List<ExternalVaccinationRecord> records,
  }) async {
    if (referrals.isEmpty || referrals.length != records.length) {
      throw ArgumentError('Referral and vaccination record counts must match.');
    }
    final first = records.first;
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'record_external_vaccinations',
            params: {
              'target_group_id': referrals.first.referralGroupId,
              'target_item_ids': referrals.map((item) => item.id).toList(),
              'administered_on_date': first.dateAdministered
                  .toIso8601String()
                  .split('T')
                  .first,
              'receiving_facility': first.administeringFacility,
              'receiving_worker': first.healthWorkerName,
              'visit_notes': first.notes,
              'supplied_token': referrals.first.verificationToken,
            },
          )
          as Map,
    );
    final completedItems = {
      for (final item in result['items'] as List? ?? const [])
        (item as Map)['id'] as String: Map<String, dynamic>.from(item),
    };
    return referrals
        .where((item) => completedItems.containsKey(item.id))
        .map((item) {
          final saved = completedItems[item.id]!;
          return item.copyWith(
            status: saved['status'] as String? ?? 'Completed',
            completedAt: DateTime.parse(saved['completed_at'] as String),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<Referral?> simulateReferralScan() async => null;

  @override
  Future<List<Referral>> simulateReferralGroupScan() async => const [];

  @override
  Future<ExternalVaccinationRecord?> getExternalVaccinationRecord(
    String referralId,
  ) async {
    final item = await _client
        .from('referral_items')
        .select('id')
        .ilike('referral_code', referralId.trim())
        .maybeSingle();
    if (item == null) return null;
    final row = await _client
        .from('vaccination_records')
        .select(
          'id, vaccination_code, child_id, vaccine_id, administered_on, '
          'external_facility_name, external_health_worker_name, notes, recorded_at, '
          'referral_item_id, external_visit_id, vaccine_definitions!inner(name), '
          'external_vaccination_visits(visit_code)',
        )
        .eq('referral_item_id', item['id'])
        .maybeSingle();
    return row == null ? null : _externalRecordFromRow(row, referralId);
  }

  @override
  Future<ExternalVaccinationRecord> updateExternalVaccination({
    required ExternalVaccinationRecord record,
    required String correctionReason,
  }) async {
    final id =
        await _client.rpc(
              'correct_live_external_vaccination_record',
              params: {
                'target_record_id': record.recordId,
                'target_administered_on': record.dateAdministered
                    .toIso8601String()
                    .split('T')
                    .first,
                'target_facility': record.administeringFacility,
                'target_worker': record.healthWorkerName,
                'target_notes': record.notes,
                'correction_reason': correctionReason,
              },
            )
            as String;
    final row = await _client
        .from('vaccination_records')
        .select(
          'id, vaccination_code, child_id, vaccine_id, administered_on, '
          'external_facility_name, external_health_worker_name, notes, recorded_at, '
          'referral_item_id, external_visit_id, vaccine_definitions!inner(name), '
          'external_vaccination_visits(visit_code), referral_items!inner(referral_code)',
        )
        .eq('id', id)
        .single();
    final item = Map<String, dynamic>.from(row['referral_items'] as Map);
    return _externalRecordFromRow(row, item['referral_code'] as String);
  }

  @override
  Future<ExternalVaccinationVisit?> getExternalVaccinationVisitByReferralId(
    String referralId,
  ) async {
    final record = await getExternalVaccinationRecord(referralId);
    if (record == null) return null;
    final visit = await _client
        .from('external_vaccination_visits')
        .select()
        .eq('id', record.externalVisitId)
        .maybeSingle();
    if (visit == null) return null;
    final rows = await _client
        .from('vaccination_records')
        .select(
          'id, vaccination_code, child_id, vaccine_id, administered_on, '
          'external_facility_name, external_health_worker_name, notes, recorded_at, '
          'referral_item_id, external_visit_id, vaccine_definitions!inner(name), '
          'referral_items!inner(referral_code)',
        )
        .eq('external_visit_id', record.externalVisitId);
    final records = rows
        .map((row) {
          final item = Map<String, dynamic>.from(row['referral_items'] as Map);
          return _externalRecordFromRow(row, item['referral_code'] as String);
        })
        .toList(growable: false);
    return ExternalVaccinationVisit(
      externalVisitId: visit['id'] as String,
      visitCode: visit['visit_code'] as String? ?? 'EV-${visit['id']}',
      referralGroupId: visit['referral_group_id'] as String,
      childId: record.childId,
      dateAdministered: DateTime.parse(visit['administered_on'] as String),
      administeringFacility: visit['administering_facility'] as String,
      healthWorkerName: visit['health_worker_name'] as String,
      notes: visit['notes'] as String? ?? '',
      recordedAt: DateTime.parse(visit['verified_at'] as String),
      recordedBy: visit['verified_by'] as String?,
      documentVerified: true,
      verifiedByUserId: visit['verified_by'] as String?,
      verifiedAt: DateTime.parse(visit['verified_at'] as String),
      verificationMethod: visit['verification_method'] as String?,
      records: records,
    );
  }

  @override
  Future<List<ExternalVaccinationCorrection>> getVisitCorrections(
    String externalVisitId,
  ) async {
    final rows = await _client
        .from('vaccination_record_corrections')
        .select(
          'id, correction_code, reason, previous_values, updated_values, corrected_at, corrected_by, '
          'vaccination_records!inner(external_visit_id)',
        )
        .eq('vaccination_records.external_visit_id', externalVisitId)
        .order('corrected_at', ascending: false);
    return rows
        .map(
          (row) => ExternalVaccinationCorrection(
            correctionId: row['id'] as String,
            correctionCode: row['correction_code'] as String,
            externalVisitId: externalVisitId,
            reason: row['reason'] as String? ?? 'Health-worker correction',
            previousValues: Map<String, dynamic>.from(
              row['previous_values'] as Map,
            ),
            updatedValues: Map<String, dynamic>.from(
              row['updated_values'] as Map,
            ),
            correctedAt: DateTime.parse(row['corrected_at'] as String),
            correctedBy: row['corrected_by'] as String?,
          ),
        )
        .toList(growable: false);
  }

  ExternalVaccinationRecord _externalRecordFromRow(
    Map<String, dynamic> row,
    String referralCode,
  ) {
    final vaccine = Map<String, dynamic>.from(
      row['vaccine_definitions'] as Map,
    );
    final visit = row['external_vaccination_visits'];
    final visitMap = visit is Map
        ? Map<String, dynamic>.from(visit)
        : const <String, dynamic>{};
    return ExternalVaccinationRecord(
      recordId: row['id'] as String,
      recordCode: row['vaccination_code'] as String,
      referralId: referralCode,
      externalVisitId: row['external_visit_id'] as String,
      externalVisitCode: visitMap['visit_code'] as String? ?? 'External visit',
      childId: row['child_id'] as String,
      vaccineId: row['vaccine_id'] as String,
      vaccineAdministered: vaccine['name'] as String,
      dateAdministered: DateTime.parse(row['administered_on'] as String),
      administeringFacility: row['external_facility_name'] as String? ?? '',
      healthWorkerName: row['external_health_worker_name'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      recordedAt: DateTime.parse(row['recorded_at'] as String),
    );
  }
}
