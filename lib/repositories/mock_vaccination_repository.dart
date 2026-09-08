import '../models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_assessment.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../models/first_visit_review.dart';
import '../services/pnip_schedule_service.dart';
import '../services/mock_identifier_generator.dart';
import '../services/mock_scenario_clock.dart';
import 'vaccination_repository.dart';

class MockVaccinationRepository implements VaccinationRepository {
  MockVaccinationRepository() {
    if (!_identifierSequencesReady || !_prerequisiteRecordsReady) {
      throw StateError('Vaccination identifiers were not initialized.');
    }
  }

  static final bool _identifierSequencesReady = _reserveIdentifiers();
  static const _scheduleService = PnipScheduleService();
  static final Map<String, VaccinationRecord> _records = {
    '00000000-0000-4000-9000-000000000001': VaccinationRecord(
      id: '00000000-0000-4000-9000-000000000001',
      recordCode: 'VAX-2025-000001',
      childId: 'CH-001',
      vaccineId: 'bcg',
      vaccineName: 'BCG',
      doseNumber: 1,
      dateAdministered: DateTime(2025, 9, 14),
      administeringFacility: 'Barangay Bugo Health Center',
      healthWorkerName: 'Bugo Health Worker',
      source: VaccinationSource.bugo,
      notes: 'Birth dose recorded in the mock child history.',
      recordedAt: DateTime(2025, 9, 14),
    ),
    '00000000-0000-4000-9000-000000000002': VaccinationRecord(
      id: '00000000-0000-4000-9000-000000000002',
      recordCode: 'VAX-2025-000002',
      childId: 'CH-001',
      vaccineId: 'hepatitis_b',
      vaccineName: 'Hepatitis B',
      doseNumber: 1,
      dateAdministered: DateTime(2025, 9, 14),
      administeringFacility: 'Barangay Bugo Health Center',
      healthWorkerName: 'Bugo Health Worker',
      source: VaccinationSource.bugo,
      notes: 'Birth dose recorded in the mock child history.',
      recordedAt: DateTime(2025, 9, 14),
    ),
    '00000000-0000-4000-9000-000000000003': VaccinationRecord(
      id: '00000000-0000-4000-9000-000000000003',
      recordCode: 'VAX-2026-000003',
      childId: 'CH-004',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 2,
      dateAdministered: DateTime(2026, 8, 8),
      administeringFacility: 'Barangay Puerto Health Center',
      healthWorkerName: 'Maria Lopez, RM',
      source: VaccinationSource.externalReferral,
      referralId: '00000000-0000-4000-8000-000000000013',
      externalVisitId: '00000000-0000-4000-8000-000000000001',
      notes: 'Verified from the signed printed referral.',
      recordedAt: DateTime(2026, 8, 10, 9, 30),
      recordedByUserId: '00000000-0000-4000-8000-000000000201',
    ),
    '00000000-0000-4000-9000-000000000004': VaccinationRecord(
      id: '00000000-0000-4000-9000-000000000004',
      recordCode: 'VAX-2026-000004',
      childId: 'CH-005',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 3,
      dateAdministered: DateTime(2026, 8, 10),
      administeringFacility: 'Barangay Puerto Health Center',
      healthWorkerName: 'Maria Lopez, RM',
      source: VaccinationSource.externalReferral,
      referralId: '00000000-0000-4000-8000-000000000015',
      externalVisitId: '00000000-0000-4000-8000-000000000002',
      notes: 'Verified from the signed printed referral.',
      recordedAt: DateTime(2026, 8, 12, 14),
      recordedByUserId: '00000000-0000-4000-8000-000000000201',
    ),
    '00000000-0000-4000-9000-000000000005': VaccinationRecord(
      id: '00000000-0000-4000-9000-000000000005',
      recordCode: 'VAX-2026-000005',
      childId: 'CH-005',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      doseNumber: 3,
      dateAdministered: DateTime(2026, 8, 16),
      administeringFacility: 'Barangay Gusa Health Center',
      healthWorkerName: 'Jose Ramos, RN',
      source: VaccinationSource.externalReferral,
      referralId: '00000000-0000-4000-8000-000000000016',
      externalVisitId: '00000000-0000-4000-8000-000000000003',
      notes: 'Verified from the signed printed referral.',
      recordedAt: DateTime(2026, 8, 18, 15),
      recordedByUserId: '00000000-0000-4000-8000-000000000201',
    ),
  };
  static final bool _prerequisiteRecordsReady = _seedPrerequisiteRecords();
  static final Map<String, VaccinationScreening> _screenings = {};
  static final Map<String, FirstVisitReview> _firstVisitReviews = {};

  @override
  Future<VaccinationAssessment> assessChild(ChildProfile child) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final history = await getVaccinationHistory(child.id);
    final schedule = _scheduleService.calculate(child: child, history: history);
    final recommended = schedule
        .where((entry) => entry.requiresAction)
        .toList(growable: false);
    final status = history.isEmpty
        ? VaccinationAssessmentStatus.firstVaccination
        : recommended.isNotEmpty
        ? VaccinationAssessmentStatus.vaccinationDue
        : VaccinationAssessmentStatus.notDue;
    return VaccinationAssessment(
      child: child,
      history: history,
      status: status,
      recommendedDoses: recommended,
      schedule: schedule,
      message: history.isEmpty
          ? 'No vaccination records were found for this child.'
          : recommended.isNotEmpty
          ? '${recommended.length} vaccine dose(s) require assessment.'
          : 'No vaccine dose is currently due.',
    );
  }

  @override
  Future<List<VaccinationRecord>> getVaccinationHistory(String childId) async {
    final history =
        _records.values.where((record) => record.childId == childId).toList()
          ..sort((a, b) => b.dateAdministered.compareTo(a.dateAdministered));
    return List.unmodifiable(history);
  }

  @override
  Future<List<PnipScheduleEntry>> getVaccinationSchedule(
    ChildProfile child,
  ) async {
    final history = await getVaccinationHistory(child.id);
    return _scheduleService.calculate(child: child, history: history);
  }

  @override
  Future<List<VaccinationRecord>> recordVaccinations(
    List<VaccinationRecord> records,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    for (final record in records) {
      final duplicate = _records.values.any(
        (existing) =>
            existing.childId == record.childId &&
            existing.vaccineId == record.vaccineId &&
            existing.doseNumber == record.doseNumber,
      );
      if (duplicate) {
        throw StateError(
          '${record.vaccineName} Dose ${record.doseNumber} is already recorded.',
        );
      }
    }
    for (final record in records) {
      _records[record.id] = record;
    }
    return List.unmodifiable(records);
  }

  @override
  Future<VaccinationRecord> updateVaccinationRecord(
    VaccinationRecord record,
  ) async {
    await Future.delayed(const Duration(milliseconds: 350));
    if (!_records.containsKey(record.id)) {
      throw StateError('The vaccination history record was not found.');
    }
    _records[record.id] = record;
    return record;
  }

  @override
  Future<VaccinationScreening> recordScreening(
    VaccinationScreening screening,
  ) async {
    await Future.delayed(const Duration(milliseconds: 250));
    _screenings[screening.id] = screening;
    return screening;
  }

  @override
  Future<FirstVisitReview> recordFirstVisitReview(
    FirstVisitReview review,
  ) async {
    await Future.delayed(const Duration(milliseconds: 250));
    _firstVisitReviews[review.childId] = review;
    return review;
  }

  @override
  Future<FirstVisitReview?> getFirstVisitReview(String childId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _firstVisitReviews[childId];
  }

  @override
  Future<void> completeAdministration({
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
    required Map<String, int> dosesByVaccineId,
  }) async {
    await recordScreening(screening);
    await recordVaccinations(records);
  }

  static VaccinationRecord? linkedExternalRecord(String referralInternalId) {
    for (final record in _records.values) {
      if (record.referralId == referralInternalId) return record;
    }
    return null;
  }

  static void seedLinkedRecord(VaccinationRecord record) {
    final duplicate = _records.values.any(
      (existing) =>
          existing.childId == record.childId &&
          existing.vaccineId == record.vaccineId &&
          existing.doseNumber == record.doseNumber,
    );
    if (!duplicate) _records[record.id] = record;
  }

  static bool _reserveIdentifiers() {
    MockIdentifierGenerator.reserve('VAX', 60);
    return true;
  }

  static bool _seedPrerequisiteRecords() {
    var sequence = 5;
    void add({
      required String childId,
      required String vaccineId,
      required String vaccineName,
      required int dose,
      required DateTime date,
    }) {
      sequence++;
      final id =
          '00000000-0000-4000-9000-${sequence.toString().padLeft(12, '0')}';
      _records[id] = VaccinationRecord(
        id: id,
        recordCode: 'VAX-${date.year}-${sequence.toString().padLeft(6, '0')}',
        childId: childId,
        vaccineId: vaccineId,
        vaccineName: vaccineName,
        doseNumber: dose,
        dateAdministered: date,
        administeringFacility: 'Previous Health Facility',
        healthWorkerName: 'Verified External Health Worker',
        source: VaccinationSource.previousRecord,
        notes: 'Seeded prerequisite vaccination history.',
        recordedAt: date,
      );
    }

    for (final child in [
      ('CH-004', DateTime(2026, 4, 1)),
      ('CH-005', DateTime(2026, 3, 26)),
    ]) {
      add(
        childId: child.$1,
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        dose: 1,
        date: child.$2,
      );
      add(
        childId: child.$1,
        vaccineId: 'hepatitis_b',
        vaccineName: 'Hepatitis B',
        dose: 1,
        date: child.$2,
      );
      add(
        childId: child.$1,
        vaccineId: 'pentavalent',
        vaccineName: 'Pentavalent',
        dose: 1,
        date: child.$2.add(const Duration(days: 42)),
      );
      add(
        childId: child.$1,
        vaccineId: 'opv',
        vaccineName: 'OPV',
        dose: 1,
        date: child.$2.add(const Duration(days: 42)),
      );
    }
    add(
      childId: 'CH-005',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      dose: 2,
      date: DateTime(2026, 6, 4),
    );
    add(
      childId: 'CH-005',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      dose: 2,
      date: DateTime(2026, 6, 4),
    );

    void addCompletedInfantSchedule({
      required String childId,
      required DateTime birthDate,
      required bool includeMmr,
    }) {
      add(
        childId: childId,
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        dose: 1,
        date: birthDate,
      );
      add(
        childId: childId,
        vaccineId: 'hepatitis_b',
        vaccineName: 'Hepatitis B',
        dose: 1,
        date: birthDate,
      );
      for (final dose in const [1, 2, 3]) {
        final date = birthDate.add(Duration(days: [0, 6, 10, 14][dose] * 7));
        for (final vaccine in const [
          ('pentavalent', 'Pentavalent'),
          ('opv', 'OPV'),
          ('pcv', 'PCV'),
        ]) {
          add(
            childId: childId,
            vaccineId: vaccine.$1,
            vaccineName: vaccine.$2,
            dose: dose,
            date: date,
          );
        }
      }
      add(
        childId: childId,
        vaccineId: 'ipv',
        vaccineName: 'IPV',
        dose: 1,
        date: birthDate.add(const Duration(days: 98)),
      );
      if (includeMmr) {
        // Only the explicitly completed mock infant scenarios receive IPV2.
        add(
          childId: childId,
          vaccineId: 'ipv',
          vaccineName: 'IPV',
          dose: 2,
          date: DateTime(birthDate.year, birthDate.month + 9, birthDate.day),
        );
        add(
          childId: childId,
          vaccineId: 'mmr',
          vaccineName: 'MMR',
          dose: 1,
          date: DateTime(birthDate.year, birthDate.month + 9, birthDate.day),
        );
        add(
          childId: childId,
          vaccineId: 'mmr',
          vaccineName: 'MMR',
          dose: 2,
          date: DateTime(birthDate.year, birthDate.month + 12, birthDate.day),
        );
      }
    }

    addCompletedInfantSchedule(
      childId: 'CH-002',
      birthDate: DateTime(2023, 12, 24),
      includeMmr: true,
    );
    addCompletedInfantSchedule(
      childId: 'CH-003',
      birthDate: DateTime(2025, 12, 20),
      includeMmr: false,
    );
    addCompletedInfantSchedule(
      childId: 'CH-2026-000101',
      birthDate: DateTime(2025, 1, 10),
      includeMmr: true,
    );
    for (final child in [
      ('CH-2026-000102', MockScenarioClock.daysAgo(42)),
      ('CH-2026-000103', MockScenarioClock.daysAgo(16)),
      ('CH-2026-000104', MockScenarioClock.daysAgo(100)),
    ]) {
      final birthDate = child.$2;
      add(
        childId: child.$1,
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        dose: 1,
        date: birthDate,
      );
      add(
        childId: child.$1,
        vaccineId: 'hepatitis_b',
        vaccineName: 'Hepatitis B',
        dose: 1,
        date: birthDate,
      );
    }
    return true;
  }
}
