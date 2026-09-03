import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';

abstract class AppointmentRepository {
  Future<List<VaccinationAppointment>> getGuardianAppointments(
    String guardianId,
  );

  Future<List<VaccinationAppointment>> getChildAppointments(String childId);

  Future<List<VaccinationAppointment>> getFacilityAppointments();

  Future<VaccinationAppointment> schedule(AppointmentRequest request);

  Future<VaccinationAppointment> reschedule(
    RescheduleAppointmentRequest request,
  );

  Future<VaccinationAppointment> addToWaitlist(AppointmentRequest request);

  Future<VaccinationAppointment> updateStatus(
    String appointmentId,
    VaccinationAppointmentStatus status,
    String updatedByUserId,
  );

  Future<List<AppointmentSlotOffer>> getGuardianSlotOffers(String guardianId);

  Future<List<AppointmentSlotOffer>> getFacilitySlotOffers();

  Future<VaccinationAppointment?> respondToSlotOffer(
    String offerId,
    bool accept,
    String respondedByUserId, {
    String responseChannel = 'guardian_online',
  });
}
