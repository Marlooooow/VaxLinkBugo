import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/outreach_session.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';
import 'outreach_repository.dart';

class SupabaseOutreachRepository implements OutreachRepository {
  final SupabaseClient _client;
  SupabaseOutreachRepository(this._client);

  static const _allocationSelect =
      '*, vaccine_batches!inner(id, batch_code, lot_number, expiry_date, '
      'vaccine_inventory!inner(facility_id, vaccine_id, '
      'vaccine_definitions!inner(name)))';

  @override
  Future<List<OutreachSession>> getSessions() async =>
      (await getSessionsPage(limit: 50)).items;

  @override
  Future<OutreachPage<OutreachSession>> getSessionsPage({
    String search = '',
    OutreachSessionStatus? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = Map<String, dynamic>.from(
      await _client.rpc(
        'get_outreach_session_page',
        params: {
          'p_search': search.trim().isEmpty ? null : search.trim(),
          'p_status': status?.name,
          'p_page_size': limit,
          'p_page_offset': offset,
        },
      ),
    );
    final rows = (response['items'] as List? ?? const []);
    return OutreachPage(
      items: rows
          .map<OutreachSession>(
            (row) => _session(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      totalCount: (response['total_count'] as num?)?.toInt() ?? 0,
      hasMore: response['has_more'] as bool? ?? false,
      nextOffset: (response['next_offset'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<OutreachSession> getSession(String sessionId) async => _session(
    await _client
        .from('outreach_sessions')
        .select()
        .eq('id', sessionId)
        .single(),
  );

  @override
  Future<OutreachSession> createSession({
    required String title,
    required String location,
    required DateTime scheduledOn,
    String notes = '',
  }) async => _session(
    Map<String, dynamic>.from(
      await _client.rpc(
        'create_outreach_session',
        params: {
          'session_title': title,
          'session_location': location,
          'session_date': _date(scheduledOn),
          'session_notes': notes,
        },
      ),
    ),
  );

  @override
  Future<List<OutreachStockAllocation>> getAllocations(String sessionId) async {
    final rows = await _client
        .from('outreach_stock_allocations')
        .select(_allocationSelect)
        .eq('session_id', sessionId)
        .order('created_at');
    return rows
        .map<OutreachStockAllocation>(
          (row) =>
              OutreachStockAllocation.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Future<List<VaccineBatch>> getEligibleBatches() async =>
      (await getEligibleBatchesPage(limit: 50)).items;

  @override
  Future<OutreachPage<VaccineBatch>> getEligibleBatchesPage({
    String search = '',
    int limit = 20,
    int offset = 0,
  }) async {
    final response = Map<String, dynamic>.from(
      await _client.rpc(
        'get_eligible_outreach_batch_page',
        params: {
          'p_search': search.trim().isEmpty ? null : search.trim(),
          'p_page_size': limit,
          'p_page_offset': offset,
        },
      ),
    );
    final rows = response['items'] as List? ?? const [];
    return OutreachPage(
      items: rows
          .map<VaccineBatch>(
            (row) =>
                VaccineBatch.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      totalCount: (response['total_count'] as num?)?.toInt() ?? 0,
      hasMore: response['has_more'] as bool? ?? false,
      nextOffset: (response['next_offset'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<VaccineInventory>> getSessionInventory(String sessionId) async {
    final allocations = await getAllocations(sessionId);
    final grouped = <String, VaccineInventory>{};
    for (final allocation in allocations) {
      final current = grouped[allocation.vaccineId];
      grouped[allocation.vaccineId] = VaccineInventory(
        id: 'outreach:$sessionId:${allocation.vaccineId}',
        vaccineId: allocation.vaccineId,
        vaccineName: allocation.vaccineName,
        facilityId: sessionId,
        availableDoses: (current?.availableDoses ?? 0) + allocation.remaining,
        updatedAt: DateTime.now(),
      );
    }
    return grouped.values.toList(growable: false);
  }

  @override
  Future<void> releaseStock({
    required String sessionId,
    required String batchId,
    required int quantity,
  }) async {
    await _client.rpc(
      'release_outreach_stock',
      params: {
        'target_session_id': sessionId,
        'target_batch_id': batchId,
        'release_quantity': quantity,
        'request_key': _uuid(),
      },
    );
  }

  @override
  Future<OutreachSession> startSession({
    required String sessionId,
    required bool packagingIntact,
    required bool coldChainVerified,
    required String vvmStatus,
    String notes = '',
  }) async => _session(
    Map<String, dynamic>.from(
      await _client.rpc(
        'start_outreach_session',
        params: {
          'target_session_id': sessionId,
          'package_ok': packagingIntact,
          'cold_chain_ok': coldChainVerified,
          'vvm': vvmStatus,
          'safety_remarks': notes,
        },
      ),
    ),
  );

  @override
  Future<void> recordVaccinations({
    required String sessionId,
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
  }) async {
    await _client.rpc(
      'record_outreach_vaccinations',
      params: {
        'target_session_id': sessionId,
        'screening': {
          'child_id': screening.childId,
          'history_reviewed': screening.historyReviewed,
          'current_condition_assessed': screening.currentConditionAssessed,
          'contraindications_reviewed': screening.contraindicationsReviewed,
          'guardian_consent_confirmed': screening.guardianConsentConfirmed,
          'outcome': screening.outcome.name,
          'notes': screening.notes,
        },
        'records': records
            .map(
              (record) => {
                'child_id': record.childId,
                'vaccine_id': record.vaccineId,
                'dose_number': record.doseNumber,
                'notes': record.notes,
              },
            )
            .toList(growable: false),
        'request_key': _uuid(),
      },
    );
  }

  @override
  Future<void> recordDisposition({
    required String sessionId,
    required String allocationId,
    required OutreachStockDisposition disposition,
    required int quantity,
    required String reason,
  }) async {
    await _client.rpc(
      'record_outreach_stock_disposition',
      params: {
        'target_session_id': sessionId,
        'target_allocation_id': allocationId,
        'disposition': switch (disposition) {
          OutreachStockDisposition.wastage => 'wastage',
          OutreachStockDisposition.returned => 'return',
          OutreachStockDisposition.quarantine => 'quarantine',
        },
        'disposition_quantity': quantity,
        'disposition_reason': reason,
        'request_key': _uuid(),
      },
    );
  }

  @override
  Future<OutreachSession> submitSession(
    String sessionId, {
    String notes = '',
  }) async => _session(
    Map<String, dynamic>.from(
      await _client.rpc(
        'submit_outreach_session',
        params: {'target_session_id': sessionId, 'submission_notes': notes},
      ),
    ),
  );

  @override
  Future<OutreachSession> completeSession(String sessionId) async => _session(
    Map<String, dynamic>.from(
      await _client.rpc(
        'complete_outreach_session',
        params: {'target_session_id': sessionId},
      ),
    ),
  );

  static OutreachSession _session(Map<String, dynamic> row) =>
      OutreachSession.fromJson(row);
  static String _date(DateTime value) =>
      value.toIso8601String().split('T').first;
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
