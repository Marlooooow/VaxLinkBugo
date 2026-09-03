import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';
import '../services/mock_identifier_generator.dart';
import '../services/mock_scenario_clock.dart';
import 'appointment_repository.dart';
import 'mock_inventory_repository.dart';
import '../models/earlier_offer_policy.dart';

class MockAppointmentRepository implements AppointmentRepository {
  static DateTime Function() nowProvider = DateTime.now;
  static EarlierOfferPolicy offerPolicy = const EarlierOfferPolicy();
  static final Set<String> _respondingOffers = {};
  MockAppointmentRepository() {
    MockIdentifierGenerator.reserve('APT', 5);
    MockIdentifierGenerator.reserve('OFR', 1);
    for (final seed in _seededAppointments) {
      if (!_appointments.any((item) => item.id == seed.id)) {
        _appointments.add(seed);
      }
    }
    for (final seed in _seededOffers) {
      if (!_slotOffers.any((item) => item.id == seed.id)) {
        _slotOffers.add(seed);
      }
    }
  }

  static const _facilityId = '00000000-0000-4000-8100-000000000001';
  static const _facilityName = 'Barangay Bugo Health Center';
  static const _guardianUserAliases = {
    'USR-G-001': '00000000-0000-4000-8000-000000001100',
    'USR-G-002': '00000000-0000-4000-8000-000000001102',
    'USR-G-003': '00000000-0000-4000-8000-000000001103',
  };
  static final List<VaccinationAppointment> _appointments = [];
  static final List<AppointmentSlotOffer> _slotOffers = [];
  static final List<VaccinationAppointment> _seededAppointments = [
    _seedAppointment(
      sequence: 1,
      guardianId: '00000000-0000-4000-8000-000000001100',
      childId: 'CH-001',
      childName: 'Sofia Santos',
      vaccineId: 'mmr',
      vaccineName: 'MMR',
      doseNumber: 1,
      pnipDueDate: DateTime(2026, 6, 14),
      appointmentDate: MockScenarioClock.today.add(const Duration(days: 4)),
      status: VaccinationAppointmentStatus.scheduled,
      source: VaccinationAppointmentSource.stockDeferral,
      reason: 'Rescheduled after vaccine stock became available.',
      reminderId: 'REM-00000000-0000-4000-8000-000000001100-CH-001-MMR-1',
    ),
    _seedAppointment(
      sequence: 2,
      guardianId: '00000000-0000-4000-8000-000000001100',
      childId: 'CH-005',
      childName: 'Ana Cruz',
      vaccineId: 'opv',
      vaccineName: 'OPV',
      doseNumber: 3,
      pnipDueDate: DateTime(2026, 7, 2),
      appointmentDate: MockScenarioClock.today.add(const Duration(days: 2)),
      status: VaccinationAppointmentStatus.waitlisted,
      source: VaccinationAppointmentSource.stockDeferral,
      reason: 'Priority waitlist because usable OPV stock is unavailable.',
      reminderId: 'REM-00000000-0000-4000-8000-000000001100-CH-005-OPV-3',
    ),
    _seedAppointment(
      sequence: 3,
      guardianId: '00000000-0000-4000-8000-000000001102',
      childId: 'CH-2026-000102',
      childName: 'Lia Mendoza',
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 1,
      pnipDueDate: MockScenarioClock.today,
      appointmentDate: MockScenarioClock.today.add(const Duration(days: 1)),
      status: VaccinationAppointmentStatus.confirmed,
      source: VaccinationAppointmentSource.pnipReminder,
      reason: 'Guardian confirmed the next available immunization session.',
      reminderId:
          'REM-00000000-0000-4000-8000-000000001102-CH-2026-000102-PENTAVALENT-1',
    ),
    _seedAppointment(
      sequence: 4,
      guardianId: '00000000-0000-4000-8000-000000001105',
      childId: 'CH-2026-000105',
      childName: 'Isabella Navarro',
      vaccineId: 'mmr',
      vaccineName: 'MMR',
      doseNumber: 1,
      pnipDueDate: DateTime(2026, 8, 18),
      appointmentDate: MockScenarioClock.today.add(const Duration(days: 1)),
      status: VaccinationAppointmentStatus.rescheduled,
      source: VaccinationAppointmentSource.healthWorker,
      reason: 'Original session moved because of facility capacity.',
      reminderId: null,
    ),
    _seedAppointment(
      sequence: 5,
      guardianId: '00000000-0000-4000-8000-000000001105',
      childId: 'CH-2026-000105',
      childName: 'Isabella Navarro',
      vaccineId: 'mmr',
      vaccineName: 'MMR',
      doseNumber: 1,
      pnipDueDate: DateTime(2026, 8, 18),
      appointmentDate: MockScenarioClock.today.add(const Duration(days: 5)),
      status: VaccinationAppointmentStatus.scheduled,
      source: VaccinationAppointmentSource.healthWorker,
      reason: 'Replacement appointment after facility capacity change.',
      reminderId: null,
      previousAppointmentId: '00000000-0000-4000-8500-000000000004',
    ),
  ];
  static final List<AppointmentSlotOffer> _seededOffers = [
    AppointmentSlotOffer(
      id: '00000000-0000-4000-8600-000000000001',
      offerCode: 'OFR-2026-000001',
      appointmentId: '00000000-0000-4000-8500-000000000001',
      guardianId: '00000000-0000-4000-8000-000000001100',
      childId: 'CH-001',
      childName: 'Sofia Santos',
      vaccineId: 'mmr',
      vaccineName: 'MMR',
      doseNumber: 1,
      currentAppointmentDate: MockScenarioClock.today.add(
        const Duration(days: 4),
      ),
      offeredAppointmentDate: offerPolicy
          .slots(MockScenarioClock.today.add(const Duration(days: 1)))
          .first,
      status: AppointmentSlotOfferStatus.pending,
      createdAt: DateTime(2026, 8, 29, 8),
      expiresAt: MockScenarioClock.today.add(const Duration(days: 1)),
      respondedAt: null,
    ),
  ];

  @override
  Future<List<VaccinationAppointment>> getGuardianAppointments(
    String guardianId,
  ) async {
    final canonicalId = _guardianUserAliases[guardianId] ?? guardianId;
    return _sorted(
      _appointments.where(
        (item) =>
            item.guardianId == guardianId || item.guardianId == canonicalId,
      ),
    );
  }

  @override
  Future<List<VaccinationAppointment>> getChildAppointments(
    String childId,
  ) async => _sorted(_appointments.where((item) => item.childId == childId));

  @override
  Future<List<VaccinationAppointment>> getFacilityAppointments() async =>
      _sorted(_appointments);

  @override
  Future<List<AppointmentSlotOffer>> getGuardianSlotOffers(
    String guardianId,
  ) async {
    _expireOffers();
    _refreshOffers();
    final canonicalId = _guardianUserAliases[guardianId] ?? guardianId;
    return List.unmodifiable(
      _slotOffers.where(
        (item) =>
            item.guardianId == guardianId || item.guardianId == canonicalId,
      ),
    );
  }

  @override
  Future<List<AppointmentSlotOffer>> getFacilitySlotOffers() async {
    _expireOffers();
    _refreshOffers();
    return List.unmodifiable(_slotOffers);
  }

  @override
  Future<VaccinationAppointment?> respondToSlotOffer(
    String offerId,
    bool accept,
    String respondedByUserId, {
    String responseChannel = 'guardian_online',
  }) async {
    _expireOffers();
    final index = _slotOffers.indexWhere((item) => item.id == offerId);
    if (index < 0) throw StateError('Earlier appointment offer was not found.');
    final offer = _slotOffers[index];
    if (_respondingOffers.contains(offerId)) {
      throw StateError('This offer response is already being processed.');
    }
    if (offer.status != AppointmentSlotOfferStatus.pending) {
      throw StateError('This earlier appointment offer is no longer active.');
    }
    final now = nowProvider();
    if (!accept) {
      _slotOffers[index] = offer.copyWith(
        status: AppointmentSlotOfferStatus.declined,
        respondedAt: now,
        respondedByUserId: respondedByUserId,
        responseChannel: responseChannel,
      );
      _refreshOffers();
      return null;
    }
    final original = _appointments.firstWhere(
      (a) => a.id == offer.appointmentId,
    );
    if (offer.offeredAppointmentDate.isBefore(original.pnipDueDate) ||
        (original.eligibleFrom != null &&
            offer.offeredAppointmentDate.isBefore(original.eligibleFrom!))) {
      throw StateError(
        'The offered date no longer meets the scheduling eligibility date.',
      );
    }
    if (!_isActive(original) || !offer.offeredAppointmentDate.isAfter(now)) {
      throw StateError(
        'The original appointment or offered slot is no longer available.',
      );
    }
    final held = _slotOffers
        .where(
          (o) =>
              o.vaccineId == offer.vaccineId &&
              o.status == AppointmentSlotOfferStatus.pending &&
              o.expiresAt.isAfter(now),
        )
        .length;
    final booked = _slotOffers
        .where(
          (o) =>
              o.vaccineId == offer.vaccineId &&
              o.status == AppointmentSlotOfferStatus.accepted &&
              _appointments.any(
                (a) =>
                    a.previousAppointmentId == o.appointmentId && _isActive(a),
              ),
        )
        .length;
    if (MockInventoryRepository.usableDosesForOffers(offer.vaccineId) <
        held + booked) {
      throw StateError(
        'Stock changed. Please ask the health worker to review this offer.',
      );
    }
    if (_appointments.any(
      (a) =>
          a.id != original.id &&
          _isActive(a) &&
          a.appointmentDate == offer.offeredAppointmentDate,
    )) {
      throw StateError('This appointment time is no longer available.');
    }
    _respondingOffers.add(offerId);
    try {
      final replacement = await reschedule(
        RescheduleAppointmentRequest(
          appointmentId: offer.appointmentId,
          newAppointmentDate: offer.offeredAppointmentDate,
          reason:
              'Guardian accepted an earlier appointment after stock arrival.',
          rescheduledByUserId: respondedByUserId,
        ),
      );
      _slotOffers[index] = offer.copyWith(
        status: AppointmentSlotOfferStatus.accepted,
        respondedAt: now,
        respondedByUserId: respondedByUserId,
        responseChannel: responseChannel,
      );
      return replacement;
    } finally {
      _respondingOffers.remove(offerId);
    }
  }

  static bool _isActive(VaccinationAppointment a) =>
      a.status == VaccinationAppointmentStatus.scheduled ||
      a.status == VaccinationAppointmentStatus.confirmed ||
      a.status == VaccinationAppointmentStatus.waitlisted;

  static void _refreshOffers() {
    final vaccines = _appointments
        .where(_isActive)
        .map((a) => a.vaccineId)
        .toSet();
    for (final vaccine in vaccines) {
      createStockAvailabilityOffers(
        vaccineId: vaccine,
        availableSlots: MockInventoryRepository.usableDosesForOffers(vaccine),
      );
    }
  }

  static List<AppointmentSlotOffer> createStockAvailabilityOffers({
    required String vaccineId,
    required int availableSlots,
    DateTime? offeredDate,
  }) {
    MockAppointmentRepository();
    final now = nowProvider();
    final stock = MockInventoryRepository.usableDosesForOffers(vaccineId);
    final held = _slotOffers
        .where(
          (o) =>
              o.vaccineId == vaccineId &&
              o.status == AppointmentSlotOfferStatus.pending &&
              o.expiresAt.isAfter(now),
        )
        .length;
    // Accepted offers retain an allocation while their replacement appointment is active.
    final booked = _slotOffers
        .where(
          (o) =>
              o.vaccineId == vaccineId &&
              o.status == AppointmentSlotOfferStatus.accepted &&
              _appointments.any(
                (a) =>
                    a.previousAppointmentId == o.appointmentId && _isActive(a),
              ),
        )
        .length;
    var budget = stock - held - booked;
    if (budget > availableSlots) budget = availableSlots;
    if (budget <= 0) return const [];
    final candidates =
        _appointments
            .where(
              (a) =>
                  a.vaccineId == vaccineId &&
                  _isActive(a) &&
                  !_slotOffers.any((o) => o.appointmentId == a.id) &&
                  // An accepted replacement must not immediately receive another offer.
                  !_slotOffers.any(
                    (o) =>
                        o.status == AppointmentSlotOfferStatus.accepted &&
                        o.appointmentId == a.previousAppointmentId,
                  ),
            )
            .toList()
          ..sort((a, b) {
            final priority = b.clinicalPriority.compareTo(a.clinicalPriority);
            if (priority != 0) return priority;
            final queued = a.createdAt.compareTo(b.createdAt);
            return queued != 0 ? queued : a.id.compareTo(b.id);
          });
    final created = <AppointmentSlotOffer>[];
    final earliest = offeredDate ?? now.add(const Duration(hours: 2));
    for (final slot in offerPolicy.slots(earliest)) {
      if (budget <= 0 || candidates.isEmpty) break;
      if (slot.isBefore(earliest) ||
          !slot.isAfter(now.add(const Duration(hours: 1)))) {
        continue;
      }
      if (_appointments.any((a) => _isActive(a) && a.appointmentDate == slot) ||
          _slotOffers.any(
            (o) =>
                o.offeredAppointmentDate == slot &&
                o.status == AppointmentSlotOfferStatus.pending &&
                o.expiresAt.isAfter(now),
          )) {
        continue;
      }
      final index = candidates.indexWhere(
        (a) =>
            slot.isBefore(a.appointmentDate) &&
            !slot.isBefore(a.pnipDueDate) &&
            (a.eligibleFrom == null || !slot.isBefore(a.eligibleFrom!)),
      );
      if (index < 0) continue;
      final appointment = candidates.removeAt(index);
      final identity = MockIdentifierGenerator.next(prefix: 'OFR');
      final deadline = now.add(offerPolicy.responseWindow);
      final cutoff = slot.subtract(const Duration(hours: 1));
      final offer = AppointmentSlotOffer(
        id: identity.id,
        offerCode: identity.code,
        appointmentId: appointment.id,
        guardianId: appointment.guardianId,
        childId: appointment.childId,
        childName: appointment.childName,
        vaccineId: appointment.vaccineId,
        vaccineName: appointment.vaccineName,
        doseNumber: appointment.doseNumber,
        currentAppointmentDate: appointment.appointmentDate,
        offeredAppointmentDate: slot,
        status: AppointmentSlotOfferStatus.pending,
        createdAt: now,
        expiresAt: deadline.isBefore(cutoff) ? deadline : cutoff,
        respondedAt: null,
        queueReason: appointment.clinicalPriority > 0
            ? 'Staff-assigned priority, then waiting-list entry time'
            : 'Earliest eligible waiting-list entry',
      );
      _slotOffers.add(offer);
      created.add(offer);
      budget--;
    }
    return List.unmodifiable(created);
  }

  @override
  Future<VaccinationAppointment> schedule(AppointmentRequest request) async {
    _validate(request);
    final duplicate = _appointments.any(
      (item) =>
          item.childId == request.childId &&
          item.vaccineId == request.vaccineId &&
          item.doseNumber == request.doseNumber &&
          (item.status == VaccinationAppointmentStatus.scheduled ||
              item.status == VaccinationAppointmentStatus.confirmed ||
              item.status == VaccinationAppointmentStatus.waitlisted),
    );
    if (duplicate) {
      throw StateError(
        'An active appointment or waitlist entry already exists for this dose.',
      );
    }
    return _create(request, status: VaccinationAppointmentStatus.scheduled);
  }

  @override
  Future<VaccinationAppointment> addToWaitlist(
    AppointmentRequest request,
  ) async {
    _validate(request);
    return _create(request, status: VaccinationAppointmentStatus.waitlisted);
  }

  @override
  Future<VaccinationAppointment> reschedule(
    RescheduleAppointmentRequest request,
  ) async {
    final index = _appointments.indexWhere(
      (item) => item.id == request.appointmentId,
    );
    if (index < 0) throw StateError('Appointment record was not found.');
    final current = _appointments[index];
    if (request.reason.trim().isEmpty) {
      throw ArgumentError('A rescheduling reason is required.');
    }
    _validateDate(request.newAppointmentDate, current.pnipDueDate);
    if (request.newAppointmentDate == current.appointmentDate) {
      throw ArgumentError('Select a different appointment date.');
    }
    final now = nowProvider();
    _appointments[index] = current.copyWith(
      status: VaccinationAppointmentStatus.rescheduled,
      updatedAt: now,
    );
    final replacementRequest = AppointmentRequest(
      clinicalPriority: current.clinicalPriority,
      eligibleFrom: current.eligibleFrom,
      guardianId: current.guardianId,
      reminderId: current.reminderId,
      childId: current.childId,
      childName: current.childName,
      vaccineId: current.vaccineId,
      vaccineName: current.vaccineName,
      doseNumber: current.doseNumber,
      pnipDueDate: current.pnipDueDate,
      appointmentDate: request.newAppointmentDate,
      source: VaccinationAppointmentSource.healthWorker,
      reason: request.reason,
      createdByUserId: request.rescheduledByUserId,
    );
    return _create(
      replacementRequest,
      status: VaccinationAppointmentStatus.scheduled,
      previousAppointmentId: current.id,
    );
  }

  @override
  Future<VaccinationAppointment> updateStatus(
    String appointmentId,
    VaccinationAppointmentStatus status,
    String updatedByUserId,
  ) async {
    final index = _appointments.indexWhere((item) => item.id == appointmentId);
    if (index < 0) throw StateError('Appointment record was not found.');
    final updated = _appointments[index].copyWith(
      status: status,
      updatedAt: nowProvider(),
    );
    _appointments[index] = updated;
    return updated;
  }

  VaccinationAppointment _create(
    AppointmentRequest request, {
    required VaccinationAppointmentStatus status,
    String? previousAppointmentId,
  }) {
    final identity = MockIdentifierGenerator.next(prefix: 'APT');
    final now = nowProvider();
    final appointment = VaccinationAppointment(
      clinicalPriority: request.clinicalPriority,
      eligibleFrom: request.eligibleFrom,
      id: identity.id,
      appointmentCode: identity.code,
      guardianId: request.guardianId,
      reminderId: request.reminderId,
      childId: request.childId,
      childName: request.childName,
      vaccineId: request.vaccineId,
      vaccineName: request.vaccineName,
      doseNumber: request.doseNumber,
      pnipDueDate: _dateOnly(request.pnipDueDate),
      appointmentDate: request.appointmentDate,
      facilityId: _facilityId,
      facilityName: _facilityName,
      status: status,
      source: request.source,
      reason: request.reason.trim(),
      previousAppointmentId: previousAppointmentId,
      createdAt: now,
      updatedAt: now,
      createdByUserId: request.createdByUserId,
    );
    _appointments.add(appointment);
    return appointment;
  }

  void _validate(AppointmentRequest request) {
    if (request.reason.trim().isEmpty) {
      throw ArgumentError('An appointment reason is required.');
    }
    _validateDate(request.appointmentDate, request.pnipDueDate);
  }

  void _validateDate(DateTime appointmentDate, DateTime pnipDueDate) {
    final date = _dateOnly(appointmentDate);
    if (date.isBefore(MockScenarioClock.today)) {
      throw ArgumentError('An appointment cannot be scheduled in the past.');
    }
    if (date.isBefore(_dateOnly(pnipDueDate))) {
      throw ArgumentError(
        'The appointment cannot be earlier than the PNIP due date.',
      );
    }
  }

  static List<VaccinationAppointment> _sorted(
    Iterable<VaccinationAppointment> items,
  ) {
    final result = items.toList(growable: false)
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    return List.unmodifiable(result);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static void _expireOffers() {
    final now = nowProvider();
    for (var index = 0; index < _slotOffers.length; index++) {
      final offer = _slotOffers[index];
      if (offer.status == AppointmentSlotOfferStatus.pending &&
          !offer.expiresAt.isAfter(now)) {
        _slotOffers[index] = offer.copyWith(
          status: AppointmentSlotOfferStatus.expired,
          respondedAt: now,
        );
      }
    }
  }

  static VaccinationAppointment _seedAppointment({
    required int sequence,
    required String guardianId,
    required String childId,
    required String childName,
    required String vaccineId,
    required String vaccineName,
    required int doseNumber,
    required DateTime pnipDueDate,
    required DateTime appointmentDate,
    required VaccinationAppointmentStatus status,
    required VaccinationAppointmentSource source,
    required String reason,
    required String? reminderId,
    String? previousAppointmentId,
  }) {
    final recordedAt = DateTime(2026, 8, 28, 9, sequence);
    return VaccinationAppointment(
      id: '00000000-0000-4000-8500-${sequence.toString().padLeft(12, '0')}',
      appointmentCode: 'APT-2026-${sequence.toString().padLeft(6, '0')}',
      guardianId: guardianId,
      reminderId: reminderId,
      childId: childId,
      childName: childName,
      vaccineId: vaccineId,
      vaccineName: vaccineName,
      doseNumber: doseNumber,
      pnipDueDate: pnipDueDate,
      appointmentDate: appointmentDate,
      facilityId: _facilityId,
      facilityName: _facilityName,
      status: status,
      source: source,
      reason: reason,
      previousAppointmentId: previousAppointmentId,
      createdAt: recordedAt,
      updatedAt: recordedAt,
      createdByUserId: 'USR-H-001',
    );
  }
}
