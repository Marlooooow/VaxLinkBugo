import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';

abstract class AppointmentRepository {
  Future<List<VaccinationAppointment>> getGuardianAppointments(
    String guardianId,
  );

  Future<AppointmentPage> getGuardianAppointmentsPage(
    String guardianId, {
    String? initialAppointmentId,
    int limit = 20,
    int offset = 0,
  });

  Future<List<VaccinationAppointment>> getGuardianUpcomingAppointments(
    String guardianId, {
    int limit = 2,
  });

  Future<List<VaccinationAppointment>> getChildAppointments(String childId);

  Future<List<VaccinationAppointment>> getFacilityAppointments();

  Future<List<VaccinationAppointment>> getFacilityUpcomingAppointments({
    int limit = 2,
  });

  Future<AppointmentPage> getFacilityAppointmentsPage({
    String? initialAppointmentId,
    String? waitlistVaccineId,
    bool waitlistOnly = false,
    int limit = 20,
    int offset = 0,
  });

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

  Future<AppointmentOfferPage> getGuardianSlotOffersPage(
    String guardianId, {
    AppointmentSlotOfferStatus? status,
    String? initialOfferId,
    int limit = 20,
    int offset = 0,
  });

  Future<List<AppointmentSlotOffer>> getFacilitySlotOffers();

  Future<AppointmentOfferPage> getFacilitySlotOffersPage({
    AppointmentSlotOfferStatus? status,
    String? initialOfferId,
    int limit = 20,
    int offset = 0,
  });

  Future<VaccinationAppointment?> respondToSlotOffer(
    String offerId,
    bool accept,
    String respondedByUserId, {
    String responseChannel = 'guardian_online',
  });
}
