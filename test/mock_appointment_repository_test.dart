import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_appointment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/appointment_slot_offer.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/services/mock_scenario_clock.dart';

void main() {
  test('Maria Santos can see seeded guardian appointments', () async {
    final repository = MockAppointmentRepository();
    final appointments = await repository.getGuardianAppointments('USR-G-001');

    expect(appointments.map((item) => item.childId), contains('CH-001'));
    expect(appointments.map((item) => item.childId), contains('CH-005'));
  });

  test('rescheduling preserves PNIP due date and links replacement', () async {
    final repository = MockAppointmentRepository();
    final dueDate = MockScenarioClock.today;
    final original = await repository.schedule(
      AppointmentRequest(
        guardianId: '00000000-0000-4000-8000-000000001100',
        reminderId: 'REM-TEST-001',
        childId: 'TEST-APT-CHILD-001',
        childName: 'Appointment Test Child',
        vaccineId: 'pcv',
        vaccineName: 'PCV',
        doseNumber: 2,
        pnipDueDate: dueDate,
        appointmentDate: dueDate.add(const Duration(days: 1)),
        source: VaccinationAppointmentSource.stockDeferral,
        reason: 'Stock unavailable.',
        createdByUserId: 'USR-H-001',
      ),
    );

    final replacement = await repository.reschedule(
      RescheduleAppointmentRequest(
        appointmentId: original.id,
        newAppointmentDate: dueDate.add(const Duration(days: 5)),
        reason: 'New stock delivery date confirmed.',
        rescheduledByUserId: 'USR-H-001',
      ),
    );
    final history = await repository.getChildAppointments('TEST-APT-CHILD-001');

    expect(replacement.pnipDueDate, original.pnipDueDate);
    expect(replacement.previousAppointmentId, original.id);
    expect(history, hasLength(2));
    expect(
      history.firstWhere((item) => item.id == original.id).status,
      VaccinationAppointmentStatus.rescheduled,
    );
    expect(
      VaccinationAppointment.fromJson(replacement.toJson()).appointmentCode,
      replacement.appointmentCode,
    );
  });

  test(
    'guardian user alias can view health-worker-created appointment',
    () async {
      final repository = MockAppointmentRepository();
      final appointments = await repository.getGuardianAppointments(
        'USR-G-001',
      );

      expect(
        appointments.any((item) => item.childId == 'TEST-APT-CHILD-001'),
        isTrue,
      );
    },
  );

  test('new stock creates a priority earlier-slot offer', () async {
    final repository = MockAppointmentRepository();
    final offers = MockAppointmentRepository.createStockAvailabilityOffers(
      vaccineId: 'pcv',
      availableSlots: 1,
      offeredDate: MockScenarioClock.today.add(const Duration(days: 1)),
    );

    expect(offers, hasLength(1));
    expect(offers.single.childId, 'TEST-APT-CHILD-001');
    expect(offers.single.status, AppointmentSlotOfferStatus.pending);
    expect(
      AppointmentSlotOffer.fromJson(offers.single.toJson()).offerCode,
      offers.single.offerCode,
    );

    final replacement = await repository.respondToSlotOffer(
      offers.single.id,
      true,
      'USR-G-001',
    );
    expect(replacement, isNotNull);
    expect(replacement!.appointmentDate, offers.single.offeredAppointmentDate);
    expect(replacement.pnipDueDate, MockScenarioClock.today);
  });
}
