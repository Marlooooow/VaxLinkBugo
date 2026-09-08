import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_record.dart';
import 'package:qr_code_based_pediatric_vaccination/models/first_visit_review.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_vaccination_repository.dart';

void main() {
  test(
    'saved vaccination appears in the same child assessment history',
    () async {
      final repository = MockVaccinationRepository();
      final child = ChildProfile(
        id: 'CH-TEST-HISTORY',
        fullName: 'History Test Child',
        birthDate: DateTime(2026, 8, 1),
        sex: 'Male',
        qrIdentifier: 'QR-TEST-HISTORY',
        relationship: 'Father',
      );
      final record = VaccinationRecord(
        id: '00000000-0000-4000-9000-888888888888',
        recordCode: 'VAX-2026-888888',
        childId: child.id,
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        doseNumber: 1,
        dateAdministered: child.birthDate,
        administeringFacility: 'Barangay Bugo Health Center',
        healthWorkerName: 'Test Worker',
        source: VaccinationSource.bugo,
        notes: '',
        recordedAt: child.birthDate,
      );

      await repository.recordVaccinations([record]);
      final assessment = await repository.assessChild(child);

      expect(assessment.history.any((item) => item.id == record.id), isTrue);
      expect(
        assessment.schedule
            .firstWhere((entry) => entry.vaccineId == 'bcg')
            .vaccinationRecordId,
        record.id,
      );
    },
  );

  test('stores the documented-record decision for a first visit', () async {
    final repository = MockVaccinationRepository();
    final review = FirstVisitReview(
      id: '00000000-0000-4000-8000-777777777777',
      reviewCode: 'FVR-2026-777777',
      childId: 'CH-FIRST-VISIT-TEST',
      hasDocumentedPreviousVaccinations: false,
      reviewedAt: DateTime(2026, 8, 28),
      reviewedByUserId: 'USR-H-001',
    );

    await repository.recordFirstVisitReview(review);
    final stored = await repository.getFirstVisitReview(review.childId);

    expect(stored?.reviewCode, review.reviewCode);
    expect(stored?.hasDocumentedPreviousVaccinations, isFalse);
  });
}
