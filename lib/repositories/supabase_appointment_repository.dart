import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';
import 'appointment_repository.dart';
import 'live_data_access.dart';

class SupabaseAppointmentRepository implements AppointmentRepository {
  final SupabaseClient _client;
  late final _access = LiveDataAccess(_client);
  SupabaseAppointmentRepository(this._client);
  static const _select =
      '*, children!inner(full_name), vaccine_definitions!inner(name), facilities!inner(name)';

  @override
  Future<List<VaccinationAppointment>> getGuardianAppointments(
    String guardianId,
  ) async {
    final id = await _access.guardianId(guardianId);
    final rows = await _client
        .from('appointments')
        .select(_select)
        .eq('guardian_id', id)
        .order('scheduled_for');
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<List<VaccinationAppointment>> getChildAppointments(
    String childId,
  ) async {
    _access.userId;
    final rows = await _client
        .from('appointments')
        .select(_select)
        .eq('child_id', childId)
        .order('scheduled_for');
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<List<VaccinationAppointment>> getFacilityAppointments() async {
    final facility = await _access.staffFacilityId();
    final rows = await _client
        .from('appointments')
        .select(_select)
        .eq('facility_id', facility)
        .order('scheduled_for');
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<List<VaccinationAppointment>> getFacilityUpcomingAppointments({
    int limit = 2,
  }) async {
    final facility = await _access.staffFacilityId();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rows = await _client
        .from('appointments')
        .select(_select)
        .eq('facility_id', facility)
        .gte('scheduled_for', today.toIso8601String())
        .inFilter('status', const ['scheduled', 'confirmed', 'checked_in'])
        .order('scheduled_for')
        .limit(limit.clamp(1, 10).toInt());
    return rows.map(fromRow).toList(growable: false);
  }

  @override
  Future<AppointmentPage> getFacilityAppointmentsPage({
    String? initialAppointmentId,
    String? waitlistVaccineId,
    bool waitlistOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_facility_appointment_page',
            params: {
              'p_appointment_id': initialAppointmentId,
              'p_waitlist_vaccine_id': waitlistVaccineId,
              'p_waitlist_only': waitlistOnly,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final items = (payload['items'] as List? ?? const [])
        .map((row) => fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return AppointmentPage(
      items: items,
      totalCount: (payload['total_count'] as num?)?.toInt() ?? items.length,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
    );
  }

  @override
  Future<List<AppointmentSlotOffer>> getGuardianSlotOffers(
    String guardianId,
  ) async => _offers(guardianId: await _access.guardianId(guardianId));
  @override
  Future<List<AppointmentSlotOffer>> getFacilitySlotOffers() async =>
      _offers(facilityId: await _access.staffFacilityId());

  @override
  Future<AppointmentOfferPage> getFacilitySlotOffersPage({
    AppointmentSlotOfferStatus? status,
    String? initialOfferId,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_facility_appointment_offer_page',
            params: {
              'p_status': status?.name,
              'p_offer_id': initialOfferId,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final items = (payload['items'] as List? ?? const [])
        .map(
          (row) => AppointmentSlotOffer.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    return AppointmentOfferPage(
      items: items,
      totalCount: (payload['total_count'] as num?)?.toInt() ?? items.length,
      pendingCount: (payload['pending_count'] as num?)?.toInt() ?? 0,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
    );
  }

  Future<List<AppointmentSlotOffer>> _offers({
    String? guardianId,
    String? facilityId,
  }) async {
    var query = _client
        .from('appointment_offers')
        .select('*, appointments!inner($_select)');
    if (guardianId != null) {
      query = query.eq('appointments.guardian_id', guardianId);
    }
    if (facilityId != null) {
      query = query.eq('appointments.facility_id', facilityId);
    }
    // Withdrawn offers are no longer actionable and have no matching prototype enum.
    final rows = await query.neq('status', 'withdrawn').order('offered_for');
    return rows.map(offerFromRow).toList(growable: false);
  }

  @override
  Future<VaccinationAppointment> schedule(AppointmentRequest request) async {
    final id =
        await _client.rpc(
              'create_live_appointment',
              params: {
                'target_guardian_id': request.guardianId,
                'target_child_id': request.childId,
                'target_vaccine_id': request.vaccineId,
                'target_dose_number': request.doseNumber,
                'target_due_date': LiveDataAccess.date(request.pnipDueDate),
                'target_scheduled_for': request.appointmentDate
                    .toUtc()
                    .toIso8601String(),
                'target_source': _snake(request.source.name),
                'target_reason': request.reason,
                'target_reminder_id': request.reminderId,
                'target_status': 'scheduled',
              },
            )
            as String;
    return _appointment(id);
  }

  @override
  Future<VaccinationAppointment> reschedule(
    RescheduleAppointmentRequest request,
  ) async {
    final id =
        await _client.rpc(
              'reschedule_live_appointment',
              params: {
                'target_appointment_id': request.appointmentId,
                'target_scheduled_for': request.newAppointmentDate
                    .toUtc()
                    .toIso8601String(),
                'target_reason': request.reason,
              },
            )
            as String;
    return _appointment(id);
  }

  @override
  Future<VaccinationAppointment> addToWaitlist(
    AppointmentRequest request,
  ) async {
    final id =
        await _client.rpc(
              'create_live_appointment',
              params: {
                'target_guardian_id': request.guardianId,
                'target_child_id': request.childId,
                'target_vaccine_id': request.vaccineId,
                'target_dose_number': request.doseNumber,
                'target_due_date': LiveDataAccess.date(request.pnipDueDate),
                'target_scheduled_for': request.appointmentDate
                    .toUtc()
                    .toIso8601String(),
                'target_source': _snake(request.source.name),
                'target_reason': request.reason,
                'target_reminder_id': request.reminderId,
                'target_status': 'waitlisted',
              },
            )
            as String;
    return _appointment(id);
  }

  @override
  Future<VaccinationAppointment> updateStatus(
    String appointmentId,
    VaccinationAppointmentStatus status,
    String updatedByUserId,
  ) async {
    final id =
        await _client.rpc(
              'update_live_appointment_status',
              params: {
                'target_appointment_id': appointmentId,
                'target_status': _snake(status.name),
              },
            )
            as String;
    return _appointment(id);
  }

  @override
  Future<VaccinationAppointment?> respondToSlotOffer(
    String offerId,
    bool accept,
    String respondedByUserId, {
    String responseChannel = 'guardian_online',
  }) async {
    final id =
        await _client.rpc(
              'respond_to_live_appointment_offer',
              params: {'target_offer_id': offerId, 'accept_offer': accept},
            )
            as String?;
    return id == null ? null : _appointment(id);
  }

  Future<VaccinationAppointment> _appointment(String id) async => fromRow(
    await _client.from('appointments').select(_select).eq('id', id).single(),
  );

  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );

  static VaccinationAppointment fromRow(Map<String, dynamic> row) =>
      VaccinationAppointment(
        id: row['id'] as String,
        appointmentCode: row['appointment_code'] as String,
        guardianId: row['guardian_id'] as String,
        reminderId: row['reminder_id'] as String?,
        childId: row['child_id'] as String,
        childName: (row['children'] as Map)['full_name'] as String,
        vaccineId: row['vaccine_id'] as String,
        vaccineName: (row['vaccine_definitions'] as Map)['name'] as String,
        doseNumber: row['dose_number'] as int,
        pnipDueDate: DateTime.parse(row['pnip_due_date'] as String),
        appointmentDate: DateTime.parse(
          row['scheduled_for'] as String,
        ).toLocal(),
        facilityId: row['facility_id'] as String,
        facilityName: (row['facilities'] as Map)['name'] as String,
        status: VaccinationAppointmentStatus.values.byName(
          LiveDataAccess.camel(row['status'] as String),
        ),
        source: VaccinationAppointmentSource.values.byName(
          LiveDataAccess.camel(row['source'] as String),
        ),
        reason: row['reason'] as String? ?? '',
        previousAppointmentId: row['previous_appointment_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        createdByUserId: row['created_by'] as String? ?? '',
        clinicalPriority: row['priority'] == 'clinical_priority' ? 1 : 0,
      );

  static AppointmentSlotOffer offerFromRow(Map<String, dynamic> row) {
    final appointment = fromRow(row['appointments'] as Map<String, dynamic>);
    final expiry = DateTime.parse(row['expires_at'] as String);
    final status = row['status'] == 'pending' && !expiry.isAfter(DateTime.now())
        ? AppointmentSlotOfferStatus.expired
        : AppointmentSlotOfferStatus.values.byName(row['status'] as String);
    return AppointmentSlotOffer(
      id: row['id'] as String,
      offerCode: row['offer_code'] as String,
      appointmentId: appointment.id,
      guardianId: appointment.guardianId,
      childId: appointment.childId,
      childName: appointment.childName,
      vaccineId: appointment.vaccineId,
      vaccineName: appointment.vaccineName,
      doseNumber: appointment.doseNumber,
      currentAppointmentDate: appointment.appointmentDate,
      offeredAppointmentDate: DateTime.parse(
        row['offered_for'] as String,
      ).toLocal(),
      status: status,
      createdAt: DateTime.parse(row['created_at'] as String),
      expiresAt: expiry,
      respondedAt: row['responded_at'] == null
          ? null
          : DateTime.parse(row['responded_at'] as String),
      queueReason: 'Offer recorded by the health center',
      responseChannel: 'Not recorded',
    );
  }
}
