import '../models/child_profile.dart';
import '../models/external_vaccination_correction.dart';
import '../models/external_vaccination_record.dart';
import '../models/external_vaccination_visit.dart';
import '../models/referral.dart';
import '../models/referral_group.dart';
import '../models/referral_verification_result.dart';
import '../models/vaccine_inventory.dart';
import '../models/vaccination_record.dart' as history;
import '../services/mock_identifier_generator.dart';
import 'mock_vaccination_repository.dart';
import 'referral_repository.dart';

class MockReferralRepository implements ReferralRepository {
  MockReferralRepository() {
    if (!_seededScenariosReady) {
      throw StateError('Mock referral scenarios were not initialized.');
    }
  }

  static final bool _identifierSequencesReady = _reserveIdentifierSequences();
  static final Map<String, Referral> _referrals = {
    'REF-2026-000001': Referral(
      id: '00000000-0000-4000-8000-000000000011',
      referralCode: 'REF-2026-000001',
      referralGroupId: '00000000-0000-4000-8000-000000000001',
      referralGroupCode: 'RGRP-2026-000001',
      childId: 'CH-001',
      childName: 'Sofia Santos',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 1,
      scheduledDueDate: DateTime(2025, 10, 26),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Pending',
      createdAt: DateTime(2026, 8, 1),
    ),
    'REF-2026-000002': Referral(
      id: '00000000-0000-4000-8000-000000000012',
      referralCode: 'REF-2026-000002',
      referralGroupId: '00000000-0000-4000-8000-000000000001',
      referralGroupCode: 'RGRP-2026-000001',
      childId: 'CH-001',
      childName: 'Sofia Santos',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      doseNumber: 1,
      scheduledDueDate: DateTime(2025, 10, 26),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Pending',
      createdAt: DateTime(2026, 8, 1),
    ),
  };
  static final Map<String, ReferralGroup> _groups = {
    '00000000-0000-4000-8000-000000000001': ReferralGroup(
      referralGroupId: '00000000-0000-4000-8000-000000000001',
      referralGroupCode: 'RGRP-2026-000001',
      verificationToken: 'mock-v1-0000000000000001',
      childId: 'CH-001',
      childName: 'Sofia Santos',
      originatingFacility: 'Barangay Bugo Health Center',
      issuedAt: DateTime(2026, 8, 1),
      referrals: [
        _referrals['REF-2026-000001']!,
        _referrals['REF-2026-000002']!,
      ],
    ),
  };
  static final Map<String, ExternalVaccinationRecord> _records = {};
  static final Map<String, ExternalVaccinationVisit> _visits = {};
  static final Map<String, List<ExternalVaccinationCorrection>> _corrections =
      {};
  static final bool _seededScenariosReady = _seedScenarios();
  static String? _lastReferralId = 'REF-2026-000002';

  @override
  Future<Referral> createReferral({
    required ChildProfile child,
    required VaccineInventory vaccine,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!_identifierSequencesReady) throw StateError('IDs not initialized.');
    final groupIdentity = MockIdentifierGenerator.next(prefix: 'RGRP');
    final referralIdentity = MockIdentifierGenerator.next(prefix: 'REF');
    final assessment = await MockVaccinationRepository().assessChild(child);
    final scheduledDose = assessment.recommendedDoses.firstWhere(
      (dose) => dose.vaccineId == vaccine.vaccineId,
    );
    final referral = Referral(
      id: referralIdentity.id,
      referralCode: referralIdentity.code,
      referralGroupId: groupIdentity.id,
      referralGroupCode: groupIdentity.code,
      childId: child.id,
      childName: child.fullName,
      vaccineId: vaccine.vaccineId,
      vaccineName: vaccine.vaccineName,
      doseNumber: scheduledDose.doseNumber,
      scheduledDueDate: scheduledDose.scheduledDate,
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Pending',
      createdAt: DateTime.now(),
      completedAt: null,
    );

    _referrals[referral.referralId] = referral;
    _groups[referral.referralGroupId] = ReferralGroup(
      referralGroupId: referral.referralGroupId,
      referralGroupCode: referral.referralGroupCode,
      verificationToken: MockIdentifierGenerator.verificationTokenFor(
        referral.referralGroupId,
      ),
      childId: referral.childId,
      childName: referral.childName,
      originatingFacility: referral.originatingFacility,
      issuedAt: referral.createdAt,
      referrals: [referral],
    );
    _lastReferralId = referral.referralId;

    return referral;
  }

  @override
  Future<List<Referral>> createReferralGroup({
    required ChildProfile child,
    required List<VaccineInventory> vaccines,
  }) async {
    if (!_identifierSequencesReady) throw StateError('IDs not initialized.');
    final groupIdentity = MockIdentifierGenerator.next(prefix: 'RGRP');
    final createdAt = DateTime.now();
    final assessment = await MockVaccinationRepository().assessChild(child);
    final referrals = <Referral>[];
    for (final vaccine in vaccines) {
      final referralIdentity = MockIdentifierGenerator.next(prefix: 'REF');
      final scheduledDose = assessment.recommendedDoses.firstWhere(
        (dose) => dose.vaccineId == vaccine.vaccineId,
      );
      final referral = Referral(
        id: referralIdentity.id,
        referralCode: referralIdentity.code,
        referralGroupId: groupIdentity.id,
        referralGroupCode: groupIdentity.code,
        childId: child.id,
        childName: child.fullName,
        vaccineId: vaccine.vaccineId,
        vaccineName: vaccine.vaccineName,
        doseNumber: scheduledDose.doseNumber,
        scheduledDueDate: scheduledDose.scheduledDate,
        originatingFacility: 'Barangay Bugo Health Center',
        status: 'Pending',
        createdAt: createdAt,
      );
      _referrals[referral.referralId] = referral;
      referrals.add(referral);
      _lastReferralId = referral.referralId;
    }
    if (referrals.isNotEmpty) {
      _groups[groupIdentity.id] = ReferralGroup(
        referralGroupId: groupIdentity.id,
        referralGroupCode: groupIdentity.code,
        verificationToken: MockIdentifierGenerator.verificationTokenFor(
          groupIdentity.id,
        ),
        childId: child.id,
        childName: child.fullName,
        originatingFacility: 'Barangay Bugo Health Center',
        issuedAt: createdAt,
        referrals: List.unmodifiable(referrals),
      );
    }
    return referrals;
  }

  @override
  Future<Referral?> getReferralById(String referralId) async {
    await Future.delayed(const Duration(milliseconds: 500));

    for (final entry in _referrals.entries) {
      if (entry.key.toUpperCase() == referralId.toUpperCase()) {
        return entry.value;
      }
    }

    return null;
  }

  @override
  Future<Referral?> simulateReferralScan() async {
    await Future.delayed(const Duration(milliseconds: 900));

    if (_lastReferralId == null) return null;
    return _referrals[_lastReferralId];
  }

  @override
  Future<List<Referral>> getReferralGroupByReferralId(String referralId) async {
    final referral = await getReferralById(referralId);
    if (referral == null) return [];
    return _referrals.values
        .where((item) => item.referralGroupId == referral.referralGroupId)
        .toList();
  }

  @override
  Future<List<Referral>> simulateReferralGroupScan() async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (_lastReferralId == null) return [];
    return getReferralGroupByReferralId(_lastReferralId!);
  }

  @override
  Future<Referral> recordExternalVaccination({
    required Referral referral,
    required ExternalVaccinationRecord record,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final current = _referrals[referral.referralId] ?? referral;
    if (current.isCompleted || _records.containsKey(referral.referralId)) {
      throw StateError('This referral has already been completed.');
    }

    final completed = current.copyWith(
      status: 'Completed',
      completedAt: record.recordedAt,
    );
    _records[referral.referralId] = record;
    _referrals[referral.referralId] = completed;
    _syncGroup(referral.referralGroupId);
    _storeVisit([record]);
    await MockVaccinationRepository().recordVaccinations([
      _historyRecord(current, record),
    ]);
    _lastReferralId = referral.referralId;
    return completed;
  }

  @override
  Future<List<Referral>> recordExternalVaccinationBatch({
    required List<Referral> referrals,
    required List<ExternalVaccinationRecord> records,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (referrals.isEmpty || referrals.length != records.length) {
      throw ArgumentError('Referral and vaccination record counts must match.');
    }
    for (final referral in referrals) {
      final current = _referrals[referral.referralId] ?? referral;
      if (current.isCompleted || _records.containsKey(referral.referralId)) {
        throw StateError('${referral.vaccineName} is already completed.');
      }
    }
    final completed = <Referral>[];
    for (var index = 0; index < referrals.length; index++) {
      final referral = referrals[index];
      final record = records[index];
      final updated = referral.copyWith(
        status: 'Completed',
        completedAt: record.recordedAt,
      );
      _records[referral.referralId] = record;
      _referrals[referral.referralId] = updated;
      completed.add(updated);
    }
    _syncGroup(referrals.first.referralGroupId);
    _storeVisit(records);
    await MockVaccinationRepository().recordVaccinations([
      for (var index = 0; index < referrals.length; index++)
        _historyRecord(referrals[index], records[index]),
    ]);
    return completed;
  }

  @override
  Future<ExternalVaccinationRecord?> getExternalVaccinationRecord(
    String referralId,
  ) async {
    return _records[referralId];
  }

  @override
  Future<ExternalVaccinationRecord> updateExternalVaccination({
    required ExternalVaccinationRecord record,
    required String correctionReason,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final existing = _records[record.referralId];
    if (existing == null) {
      throw StateError('The external vaccination record was not found.');
    }

    final updated = ExternalVaccinationRecord(
      recordId: existing.recordId,
      recordCode: existing.recordCode,
      referralId: record.referralId,
      externalVisitId: existing.externalVisitId,
      externalVisitCode: existing.externalVisitCode,
      childId: record.childId,
      vaccineId: record.vaccineId,
      vaccineAdministered: record.vaccineAdministered,
      dateAdministered: record.dateAdministered,
      administeringFacility: record.administeringFacility,
      healthWorkerName: record.healthWorkerName,
      notes: record.notes,
      recordedAt: existing.recordedAt,
      updatedAt: DateTime.now(),
      correctionReason: correctionReason,
    );
    _records[record.referralId] = updated;
    final linkedHistory = MockVaccinationRepository.linkedExternalRecord(
      _referrals[record.referralId]?.id ?? '',
    );
    if (linkedHistory != null) {
      await MockVaccinationRepository().updateVaccinationRecord(
        linkedHistory.copyWith(
          dateAdministered: updated.dateAdministered,
          administeringFacility: updated.administeringFacility,
          healthWorkerName: updated.healthWorkerName,
          notes: updated.notes,
        ),
      );
    }
    final existingVisit = _visits[existing.externalVisitId];
    if (existingVisit != null) {
      final previousValues = existingVisit.toJson();
      final updatedVisit = existingVisit.copyWith(
        dateAdministered: updated.dateAdministered,
        administeringFacility: updated.administeringFacility,
        healthWorkerName: updated.healthWorkerName,
        notes: updated.notes,
        records: existingVisit.records
            .map(
              (item) => item.referralId == updated.referralId ? updated : item,
            )
            .toList(growable: false),
      );
      _visits[existing.externalVisitId] = updatedVisit;
      final correctionIdentity = MockIdentifierGenerator.next(prefix: 'COR');
      final correction = ExternalVaccinationCorrection(
        correctionId: correctionIdentity.id,
        correctionCode: correctionIdentity.code,
        externalVisitId: existing.externalVisitId,
        reason: correctionReason,
        previousValues: previousValues,
        updatedValues: updatedVisit.toJson(),
        correctedAt: updated.updatedAt!,
      );
      _corrections
          .putIfAbsent(existing.externalVisitId, () => [])
          .add(correction);
    }
    return updated;
  }

  @override
  Future<ReferralGroup?> getReferralGroup(String referralGroupId) async {
    return _groups[referralGroupId];
  }

  @override
  Future<List<ReferralGroup>> getReferralGroups({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final normalizedQuery = query.trim().toLowerCase();
    final groups = _groups.values.where((group) {
      if (status != null && group.status != status) return false;
      if (overdueOnly && !group.isOverdueOn(DateTime.now())) return false;
      if (normalizedQuery.isEmpty) return true;
      return group.childName.toLowerCase().contains(normalizedQuery) ||
          group.childId.toLowerCase().contains(normalizedQuery) ||
          group.referralGroupCode.toLowerCase().contains(normalizedQuery) ||
          group.referrals.any(
            (referral) =>
                referral.referralId.toLowerCase().contains(normalizedQuery) ||
                referral.vaccineName.toLowerCase().contains(normalizedQuery),
          );
    }).toList()..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    if (offset >= groups.length) return [];
    final end = (offset + limit).clamp(0, groups.length);
    return List.unmodifiable(groups.sublist(offset, end));
  }

  @override
  Future<ReferralVerificationResult> verifyReferralGroup({
    required String referralGroupId,
    String? verificationToken,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final group = _groups[referralGroupId];
    if (group == null) {
      return const ReferralVerificationResult(
        status: ReferralVerificationStatus.notFound,
        message: 'This referral could not be found.',
      );
    }
    if (verificationToken != null &&
        verificationToken != group.verificationToken) {
      return const ReferralVerificationResult(
        status: ReferralVerificationStatus.invalidToken,
        message: 'The QR verification code is invalid.',
      );
    }
    if (group.isCompleted) {
      return ReferralVerificationResult(
        status: ReferralVerificationStatus.completed,
        referralGroup: group,
        message: 'All vaccines in this referral have already been recorded.',
      );
    }
    return ReferralVerificationResult(
      status: ReferralVerificationStatus.valid,
      referralGroup: group,
      message: 'Referral verified. Confirm the details before continuing.',
    );
  }

  @override
  Future<ExternalVaccinationVisit?> getExternalVaccinationVisitByReferralId(
    String referralId,
  ) async {
    final record = _records[referralId];
    return record == null ? null : _visits[record.externalVisitId];
  }

  @override
  Future<List<ExternalVaccinationCorrection>> getVisitCorrections(
    String externalVisitId,
  ) async {
    return List.unmodifiable(_corrections[externalVisitId] ?? const []);
  }

  static void _syncGroup(String groupId) {
    final group = _groups[groupId];
    if (group == null) return;
    _groups[groupId] = group.copyWith(
      referrals: group.referrals
          .map((item) => _referrals[item.referralId] ?? item)
          .toList(growable: false),
    );
  }

  static void _storeVisit(List<ExternalVaccinationRecord> records) {
    if (records.isEmpty) return;
    final first = records.first;
    final referral = _referrals[first.referralId];
    if (referral == null) return;
    _visits[first.externalVisitId] = ExternalVaccinationVisit(
      externalVisitId: first.externalVisitId,
      visitCode: first.externalVisitCode,
      referralGroupId: referral.referralGroupId,
      childId: first.childId,
      dateAdministered: first.dateAdministered,
      administeringFacility: first.administeringFacility,
      healthWorkerName: first.healthWorkerName,
      notes: first.notes,
      recordedAt: first.recordedAt,
      documentVerified: true,
      verifiedByUserId: '00000000-0000-4000-8000-000000000201',
      verifiedAt: first.recordedAt,
      verificationMethod: 'signed_printed_referral',
      records: List.unmodifiable(records),
    );
  }

  static bool _reserveIdentifierSequences() {
    MockIdentifierGenerator.reserve('RGRP', 3);
    MockIdentifierGenerator.reserve('REF', 6);
    MockIdentifierGenerator.reserve('EV', 3);
    MockIdentifierGenerator.reserve('VR', 3);
    MockIdentifierGenerator.reserve('VAX', 5);
    return true;
  }

  static bool _seedScenarios() {
    final partialPentavalent = Referral(
      id: '00000000-0000-4000-8000-000000000013',
      referralCode: 'REF-2026-000003',
      referralGroupId: '00000000-0000-4000-8000-000000000002',
      referralGroupCode: 'RGRP-2026-000002',
      childId: 'CH-004',
      childName: 'Miguel Reyes',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 2,
      scheduledDueDate: DateTime(2026, 6, 10),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Completed',
      createdAt: DateTime(2026, 7, 20),
      completedAt: DateTime(2026, 8, 10, 9, 30),
    );
    final partialOpv = Referral(
      id: '00000000-0000-4000-8000-000000000014',
      referralCode: 'REF-2026-000004',
      referralGroupId: '00000000-0000-4000-8000-000000000002',
      referralGroupCode: 'RGRP-2026-000002',
      childId: 'CH-004',
      childName: 'Miguel Reyes',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      doseNumber: 2,
      scheduledDueDate: DateTime(2026, 6, 10),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Pending',
      createdAt: DateTime(2026, 7, 20),
    );
    final completedPentavalent = Referral(
      id: '00000000-0000-4000-8000-000000000015',
      referralCode: 'REF-2026-000005',
      referralGroupId: '00000000-0000-4000-8000-000000000003',
      referralGroupCode: 'RGRP-2026-000003',
      childId: 'CH-005',
      childName: 'Ana Cruz',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 3,
      scheduledDueDate: DateTime(2026, 7, 2),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Completed',
      createdAt: DateTime(2026, 7, 5),
      completedAt: DateTime(2026, 8, 12, 14),
    );
    final completedOpv = Referral(
      id: '00000000-0000-4000-8000-000000000016',
      referralCode: 'REF-2026-000006',
      referralGroupId: '00000000-0000-4000-8000-000000000003',
      referralGroupCode: 'RGRP-2026-000003',
      childId: 'CH-005',
      childName: 'Ana Cruz',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      doseNumber: 3,
      scheduledDueDate: DateTime(2026, 7, 2),
      originatingFacility: 'Barangay Bugo Health Center',
      status: 'Completed',
      createdAt: DateTime(2026, 7, 5),
      completedAt: DateTime(2026, 8, 18, 15),
    );

    _referrals.addAll({
      partialPentavalent.referralId: partialPentavalent,
      partialOpv.referralId: partialOpv,
      completedPentavalent.referralId: completedPentavalent,
      completedOpv.referralId: completedOpv,
    });
    _groups.addAll({
      partialPentavalent.referralGroupId: ReferralGroup(
        referralGroupId: partialPentavalent.referralGroupId,
        referralGroupCode: partialPentavalent.referralGroupCode,
        verificationToken: 'mock-v1-0000000000000002',
        childId: partialPentavalent.childId,
        childName: partialPentavalent.childName,
        originatingFacility: partialPentavalent.originatingFacility,
        issuedAt: partialPentavalent.createdAt,
        referrals: [partialPentavalent, partialOpv],
      ),
      completedPentavalent.referralGroupId: ReferralGroup(
        referralGroupId: completedPentavalent.referralGroupId,
        referralGroupCode: completedPentavalent.referralGroupCode,
        verificationToken: 'mock-v1-0000000000000003',
        childId: completedPentavalent.childId,
        childName: completedPentavalent.childName,
        originatingFacility: completedPentavalent.originatingFacility,
        issuedAt: completedPentavalent.createdAt,
        referrals: [completedPentavalent, completedOpv],
      ),
    });

    _seedCompletedVisit(
      referral: partialPentavalent,
      visitNumber: 1,
      recordNumber: 1,
      administeredAt: DateTime(2026, 8, 8),
      facility: 'Barangay Puerto Health Center',
      worker: 'Maria Lopez, RM',
      recordedAt: DateTime(2026, 8, 10, 9, 30),
    );
    _seedCompletedVisit(
      referral: completedPentavalent,
      visitNumber: 2,
      recordNumber: 2,
      administeredAt: DateTime(2026, 8, 10),
      facility: 'Barangay Puerto Health Center',
      worker: 'Maria Lopez, RM',
      recordedAt: DateTime(2026, 8, 12, 14),
    );
    _seedCompletedVisit(
      referral: completedOpv,
      visitNumber: 3,
      recordNumber: 3,
      administeredAt: DateTime(2026, 8, 16),
      facility: 'Barangay Gusa Health Center',
      worker: 'Jose Ramos, RN',
      recordedAt: DateTime(2026, 8, 18, 15),
    );
    return true;
  }

  static void _seedCompletedVisit({
    required Referral referral,
    required int visitNumber,
    required int recordNumber,
    required DateTime administeredAt,
    required String facility,
    required String worker,
    required DateTime recordedAt,
  }) {
    final visitId =
        '00000000-0000-4000-8000-${visitNumber.toString().padLeft(12, '0')}';
    final visitCode = 'EV-2026-${visitNumber.toString().padLeft(6, '0')}';
    final record = ExternalVaccinationRecord(
      recordId:
          '00000000-0000-4000-8001-${recordNumber.toString().padLeft(12, '0')}',
      recordCode: 'VR-2026-${recordNumber.toString().padLeft(6, '0')}',
      referralId: referral.referralId,
      externalVisitId: visitId,
      externalVisitCode: visitCode,
      childId: referral.childId,
      vaccineId: referral.vaccineId,
      vaccineAdministered: referral.vaccineName,
      dateAdministered: administeredAt,
      administeringFacility: facility,
      healthWorkerName: worker,
      notes: 'Verified from the signed printed referral.',
      recordedAt: recordedAt,
    );
    _records[referral.referralId] = record;
    _storeVisit([record]);
    MockVaccinationRepository.seedLinkedRecord(
      history.VaccinationRecord(
        id: '00000000-0000-4000-9000-${(recordNumber + 2).toString().padLeft(12, '0')}',
        recordCode: 'VAX-2026-${(recordNumber + 2).toString().padLeft(6, '0')}',
        childId: referral.childId,
        vaccineId: referral.vaccineId,
        vaccineName: referral.vaccineName,
        doseNumber: referral.doseNumber,
        dateAdministered: administeredAt,
        administeringFacility: facility,
        healthWorkerName: worker,
        source: history.VaccinationSource.externalReferral,
        referralId: referral.id,
        externalVisitId: visitId,
        notes: record.notes,
        recordedAt: recordedAt,
        recordedByUserId: '00000000-0000-4000-8000-000000000201',
      ),
    );
  }

  static history.VaccinationRecord _historyRecord(
    Referral referral,
    ExternalVaccinationRecord record,
  ) {
    final identity = MockIdentifierGenerator.next(prefix: 'VAX');
    return history.VaccinationRecord(
      id: identity.id,
      recordCode: identity.code,
      childId: referral.childId,
      vaccineId: referral.vaccineId,
      vaccineName: referral.vaccineName,
      doseNumber: referral.doseNumber,
      dateAdministered: record.dateAdministered,
      administeringFacility: record.administeringFacility,
      healthWorkerName: record.healthWorkerName,
      source: history.VaccinationSource.externalReferral,
      referralId: referral.id,
      externalVisitId: record.externalVisitId,
      notes: record.notes,
      recordedAt: record.recordedAt,
      recordedByUserId: '00000000-0000-4000-8000-000000000201',
    );
  }
}
