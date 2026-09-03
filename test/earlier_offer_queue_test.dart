import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_appointment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/appointment_slot_offer.dart';
import 'package:qr_code_based_pediatric_vaccination/models/earlier_offer_policy.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/services/mock_scenario_clock.dart';

void main() {
  test('Policy emits configured clinic slots only', () {
    const policy = EarlierOfferPolicy();
    final slots = policy.slots(DateTime(2026, 9, 5)).take(12).toList();
    expect(slots.first, DateTime(2026, 9, 7, 9));
    expect(slots.last, DateTime(2026, 9, 7, 11, 45));
  });

  test(
    'Queue holds slots, respects priority/FIFO and advances after decline and expiry',
    () async {
      final repository = MockAppointmentRepository();
      final today = MockScenarioClock.today;
      var now = today.add(const Duration(hours: 7));
      MockAppointmentRepository.nowProvider = () => now;
      addTearDown(() => MockAppointmentRepository.nowProvider = DateTime.now);
      final originals = <VaccinationAppointment>[];
      for (var i = 0; i < 7; i++) {
        now = now.add(const Duration(seconds: 1));
        originals.add(
          await repository.schedule(
            AppointmentRequest(
              guardianId: 'queue-guardian-$i',
              reminderId: null,
              childId: 'queue-child-$i',
              childName: 'Queue Child $i',
              vaccineId: 'bcg',
              vaccineName: 'BCG',
              doseNumber: 1,
              pnipDueDate: today,
              appointmentDate: today.add(const Duration(days: 10)),
              source: VaccinationAppointmentSource.healthWorker,
              reason: 'Queue test',
              clinicalPriority: i == 5 ? 1 : 0,
              eligibleFrom: i == 6
                  ? today.add(const Duration(days: 20))
                  : today,
              createdByUserId: 'worker',
            ),
          ),
        );
      }
      final created = MockAppointmentRepository.createStockAvailabilityOffers(
        vaccineId: 'bcg',
        availableSlots: 20,
        offeredDate: today.add(const Duration(days: 2)),
      );
      expect(
        created.length,
        4,
      ); // Seeded usable BCG stock, not requested capacity.
      expect(created.first.childId, 'queue-child-5');
      expect(created[1].childId, 'queue-child-0');
      expect(created.map((o) => o.offeredAppointmentDate).toSet().length, 4);
      expect(
        created.every((o) => o.expiresAt.isBefore(o.offeredAppointmentDate)),
        isTrue,
      );
      expect(
        MockAppointmentRepository.createStockAvailabilityOffers(
          vaccineId: 'bcg',
          availableSlots: 20,
        ),
        isEmpty,
      );
      await repository.respondToSlotOffer(
        created.first.id,
        false,
        'worker',
        responseChannel: 'staff_recorded',
      );
      final original = (await repository.getChildAppointments(
        'queue-child-5',
      )).single;
      expect(original.appointmentDate, originals[5].appointmentDate);
      final afterDecline = (await repository.getFacilitySlotOffers())
          .where((o) => o.vaccineId == 'bcg')
          .toList();
      expect(
        afterDecline
            .where((o) => o.status == AppointmentSlotOfferStatus.pending)
            .length,
        4,
      );
      expect(
        afterDecline.any(
          (o) =>
              o.childId == 'queue-child-3' &&
              o.status == AppointmentSlotOfferStatus.pending,
        ),
        isTrue,
      );
      expect(
        afterDecline
            .firstWhere((o) => o.id == created.first.id)
            .responseChannel,
        'staff_recorded',
      );
      final accepted = await repository.respondToSlotOffer(
        created[1].id,
        true,
        'queue-guardian-0',
      );
      expect(accepted!.appointmentDate, created[1].offeredAppointmentDate);
      expect(accepted.previousAppointmentId, originals[0].id);
      await expectLater(
        repository.respondToSlotOffer(created[1].id, true, 'queue-guardian-0'),
        throwsStateError,
      );
      now = now.add(const Duration(days: 1, minutes: 1));
      final afterExpiry = (await repository.getFacilitySlotOffers())
          .where((o) => o.vaccineId == 'bcg')
          .toList();
      expect(
        afterExpiry.any((o) => o.status == AppointmentSlotOfferStatus.expired),
        isTrue,
      );
      expect(
        afterExpiry.any(
          (o) =>
              o.childId == 'queue-child-4' &&
              o.status == AppointmentSlotOfferStatus.pending,
        ),
        isTrue,
      );
      expect(afterExpiry.any((o) => o.childId == 'queue-child-6'), isFalse);
    },
  );

  test('No offer when no usable stock exists', () {
    expect(
      MockAppointmentRepository.createStockAvailabilityOffers(
        vaccineId: 'opv',
        availableSlots: 20,
      ),
      isEmpty,
    );
  });
}
