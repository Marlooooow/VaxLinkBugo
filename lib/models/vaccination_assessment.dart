import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'pnip_schedule_entry.dart';
import 'vaccination_record.dart';

enum VaccinationAssessmentStatus { firstVaccination, vaccinationDue, notDue }

class VaccinationAssessment {
  final ChildProfile child;
  final List<VaccinationRecord> history;
  final VaccinationAssessmentStatus status;
  final List<PnipScheduleEntry> recommendedDoses;
  final List<PnipScheduleEntry> schedule;
  final String message;

  const VaccinationAssessment({
    required this.child,
    required this.history,
    required this.status,
    required this.recommendedDoses,
    required this.schedule,
    required this.message,
  });

  List<String> get recommendedVaccines => recommendedDoses
      .map((dose) => '${dose.vaccineName} Dose ${dose.doseNumber}')
      .toList(growable: false);

  List<String> get recommendedVaccineIds => recommendedDoses
      .map((dose) => dose.vaccineId)
      .toSet()
      .toList(growable: false);
}
