import '../models/child_profile.dart';
import '../models/vaccination_assessment.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../models/first_visit_review.dart';

abstract class VaccinationRepository {
  Future<VaccinationAssessment> assessChild(ChildProfile child);

  Future<List<VaccinationRecord>> getVaccinationHistory(String childId);

  Future<List<PnipScheduleEntry>> getVaccinationSchedule(ChildProfile child);

  Future<List<VaccinationRecord>> recordVaccinations(
    List<VaccinationRecord> records,
  );

  Future<VaccinationRecord> updateVaccinationRecord(VaccinationRecord record);

  Future<VaccinationScreening> recordScreening(VaccinationScreening screening);

  Future<FirstVisitReview> recordFirstVisitReview(FirstVisitReview review);

  Future<FirstVisitReview?> getFirstVisitReview(String childId);

  Future<void> completeAdministration({
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
    required Map<String, int> dosesByVaccineId,
  });
}
