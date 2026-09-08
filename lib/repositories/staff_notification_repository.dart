import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/staff_notification.dart';
import '../models/advisory_insight.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';
import '../models/vaccination_reminder.dart';
import '../services/mock_scenario_clock.dart';
import 'repository_registry.dart';
import 'mock_child_repository.dart';
import 'mock_appointment_repository.dart';

abstract class StaffNotificationRepository {
  Listenable get changes;
  Future<List<StaffNotification>> load();
  Future<StaffNotificationPage> loadPage({
    required String userId,
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  });
  Future<int> unreadCount(String userId);
  bool isRead(String userId, String notificationId);
  Future<void> markRead(String userId, Iterable<String> notificationIds);
  Future<String> resetGuardianPassword(String requestId);
  Future<String> resetGuardianPasswordForGuardian(String guardianId);
}

class UnavailableStaffNotificationRepository
    implements StaffNotificationRepository {
  const UnavailableStaffNotificationRepository();
  static final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  @override
  Listenable get changes => _changes;
  @override
  Future<List<StaffNotification>> load() async => const [];
  @override
  Future<StaffNotificationPage> loadPage({
    required String userId,
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async => const StaffNotificationPage(
    items: [],
    overallCount: 0,
    totalCount: 0,
    unreadCount: 0,
    hasMore: false,
    nextOffset: 0,
  );
  @override
  Future<int> unreadCount(String userId) async => 0;
  @override
  bool isRead(String userId, String notificationId) => false;
  @override
  Future<void> markRead(
    String userId,
    Iterable<String> notificationIds,
  ) async {}
  @override
  Future<String> resetGuardianPassword(String requestId) async => 'guardian123';
  @override
  Future<String> resetGuardianPasswordForGuardian(String guardianId) async =>
      'guardian123';
}

/// In-app prototype adapter. Source records remain owned by their repositories.
/// A production adapter must persist recipient receipts and enforce facility access.
class MockStaffNotificationRepository implements StaffNotificationRepository {
  static final Map<String, Set<String>> _receipts = {};
  static final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  @override
  Listenable get changes => _changes;
  final RepositoryRegistry registry;
  MockStaffNotificationRepository(this.registry);

  @override
  bool isRead(String userId, String notificationId) =>
      _receipts[userId]?.contains(notificationId) ?? false;

  @override
  Future<void> markRead(String userId, Iterable<String> notificationIds) async {
    (_receipts[userId] ??= {}).addAll(notificationIds);
    _changes.value++;
  }

  @override
  Future<int> unreadCount(String userId) async =>
      (await load()).where((item) => !isRead(userId, item.id)).length;

  @override
  Future<StaffNotificationPage> loadPage({
    required String userId,
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final all = await load();
    final unread = all.where((item) => !isRead(userId, item.id)).toList();
    final visible = unreadOnly ? unread : all;
    final items = visible.skip(offset).take(limit).toList(growable: false);
    return StaffNotificationPage(
      items: items,
      overallCount: all.length,
      totalCount: visible.length,
      unreadCount: unread.length,
      hasMore: offset + items.length < visible.length,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<String> resetGuardianPassword(String requestId) async => 'guardian123';
  @override
  Future<String> resetGuardianPasswordForGuardian(String guardianId) async =>
      'guardian123';

  @override
  Future<List<StaffNotification>> load() async {
    final now = MockScenarioClock.today;
    final rows = <StaffNotification>[];
    void add(
      String id,
      String title,
      String body,
      StaffNotificationTarget target, {
      String? entityId,
      DateTime? at,
    }) {
      rows.add(
        StaffNotification(
          id: id,
          title: title,
          body: body,
          target: target,
          entityId: entityId,
          createdAt: at ?? now,
        ),
      );
    }

    final appointments = MockAppointmentRepository();
    // Start independent reads together; do not manufacture unrelated demo alerts.
    await Future.wait([
      MockChildRepository().getPendingChildLinkRequests().then((items) {
        for (final item in items) {
          add(
            'request:${item.id}',
            'Child link request',
            '${item.guardianName} requested a link to ${item.childName}.',
            StaffNotificationTarget.requests,
            entityId: item.id,
            at: item.submittedAt,
          );
        }
      }),
      registry.inventoryRepository.getInventoryOverview().then((stock) async {
        for (final item in stock) {
          if (item.isLowStock || item.isUnavailable) {
            add(
              'stock:${item.id}:${item.isUnavailable}',
              item.isUnavailable ? 'Stock unavailable' : 'Low stock',
              '${item.vaccineName}: ${item.availableDoses} usable doses. Review stock.',
              StaffNotificationTarget.inventory,
              entityId: item.vaccineId,
              at: item.updatedAt,
            );
          }
        }
        final visits = await appointments.getFacilityAppointments();
        for (final item in stock.where((s) => s.isAvailable)) {
          final waiting = visits
              .where(
                (a) =>
                    a.vaccineId == item.vaccineId &&
                    a.status == VaccinationAppointmentStatus.waitlisted,
              )
              .length;
          if (waiting > 0) {
            add(
              'waitlist:${item.id}',
              'Stock available for waitlist review',
              '${item.vaccineName}: $waiting waiting appointment(s), ${item.availableDoses} usable doses. Availability does not reserve a dose.',
              StaffNotificationTarget.waitlist,
              entityId: item.vaccineId,
            );
          }
        }
      }),
      registry.inventoryRepository.getAllBatches().then((items) {
        for (final item in items.where((b) => b.availableDoses > 0)) {
          final status = item.statusAsOf(now);
          if (item.safetyStatus == VaccineBatchSafetyStatus.quarantined) {
            add(
              'safety:${item.id}',
              'Batch safety concern',
              '${item.vaccineName} • Lot ${item.lotNumber} is quarantined.',
              StaffNotificationTarget.inventory,
              entityId: item.vaccineId,
              at: item.safetyReviewedAt,
            );
          } else if (status == VaccineBatchStatus.expiringSoon ||
              status == VaccineBatchStatus.expired) {
            add(
              'expiry:${item.id}:${status.name}',
              status == VaccineBatchStatus.expired
                  ? 'Expired stock'
                  : 'Stock nearing expiry',
              '${item.vaccineName} • Lot ${item.lotNumber}. Review batch expiry before use.',
              StaffNotificationTarget.inventory,
              entityId: item.vaccineId,
            );
          }
        }
      }),
      appointments.getFacilityAppointments().then((items) {
        for (final item in items.where(
          (a) =>
              a.status == VaccinationAppointmentStatus.cancelled ||
              a.status == VaccinationAppointmentStatus.rescheduled,
        )) {
          add(
            'appointment:${item.id}:${item.status.name}:${item.updatedAt.toIso8601String()}',
            'Appointment ${item.status.name}',
            '${item.childName} • ${item.vaccineName}. Review appointment details.',
            StaffNotificationTarget.appointments,
            entityId: item.id,
            at: item.updatedAt,
          );
        }
      }),
      appointments.getFacilitySlotOffers().then((items) {
        for (final item in items.where(
          (o) =>
              o.status == AppointmentSlotOfferStatus.accepted ||
              o.status == AppointmentSlotOfferStatus.pending,
        )) {
          add(
            'offer:${item.id}:${item.status.name}',
            item.status == AppointmentSlotOfferStatus.pending
                ? 'Earlier offer awaiting response'
                : 'Earlier appointment accepted',
            '${item.childName} • ${item.vaccineName}. ${item.status == AppointmentSlotOfferStatus.pending ? "Awaiting guardian response before the deadline." : "The guardian accepted the earlier date."}',
            StaffNotificationTarget.offers,
            entityId: item.id,
            at: item.respondedAt,
          );
        }
      }),
      registry.reminderRepository.getFacilityFollowUps().then((items) {
        final due = items
            .where((r) => r.status == VaccinationReminderStatus.dueToday)
            .length;
        final overdue = items
            .where((r) => r.status == VaccinationReminderStatus.overdue)
            .length;
        if (due + overdue > 0) {
          add(
            'follow-ups:${now.year}-${now.month}-${now.day}',
            'Daily follow-up summary',
            '$due vaccine doses due today • $overdue overdue. Open reminders to review children and plan follow-up.',
            StaffNotificationTarget.followUps,
          );
        }
      }),
      registry.advisoryInsightRepository.getFacilityInsights().then((items) {
        final pending = items
            .where((i) => i.status == AdvisoryInsightStatus.newInsight)
            .toList();
        for (final item in pending) {
          add(
            'insight:${item.id}',
            'Advisory: ${item.title}',
            '${item.summary} Recommendations require staff review.',
            StaffNotificationTarget.insights,
            entityId: item.id,
            at: item.generatedAt,
          );
        }
      }),
    ]);
    rows.sort((a, b) {
      final date = b.createdAt.compareTo(a.createdAt);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    return rows;
  }
}

/// Live notification adapter. Notifications are derived from the same
/// facility-scoped repositories used by the destination screens; read state
/// is persisted in Supabase so every staff session sees the same state.
class SupabaseStaffNotificationRepository
    implements StaffNotificationRepository {
  final SupabaseClient _client;
  final RepositoryRegistry registry;
  final Set<String> _readIds = {};
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  SupabaseStaffNotificationRepository(this._client, this.registry);

  @override
  Listenable get changes => _changes;

  @override
  bool isRead(String userId, String notificationId) =>
      _readIds.contains(notificationId);

  @override
  Future<int> unreadCount(String userId) async {
    final value = await _client.rpc('get_staff_notification_unread_count');
    return (value as num?)?.toInt() ?? 0;
  }

  @override
  Future<StaffNotificationPage> loadPage({
    required String userId,
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
            'get_staff_notification_page',
            params: {
              'p_unread_only': unreadOnly,
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    final items = (payload['items'] as List? ?? const [])
        .map(
          (row) =>
              StaffNotification.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
    if (offset == 0) _readIds.clear();
    _readIds.addAll(
      (payload['read_ids'] as List? ?? const []).whereType<String>(),
    );
    return StaffNotificationPage(
      items: items,
      overallCount: (payload['overall_count'] as num?)?.toInt() ?? items.length,
      totalCount: (payload['total_count'] as num?)?.toInt() ?? items.length,
      unreadCount: (payload['unread_count'] as num?)?.toInt() ?? 0,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
    );
  }

  @override
  Future<void> markRead(String userId, Iterable<String> notificationIds) async {
    final ids = notificationIds.toSet();
    if (ids.isEmpty) return;
    final profileId = _client.auth.currentUser?.id;
    if (profileId == null) throw StateError('Please sign in again.');
    await _client.from('staff_notification_receipts').upsert([
      for (final id in ids) {'profile_id': profileId, 'notification_id': id},
    ]);
    _readIds.addAll(ids);
    _changes.value++;
  }

  @override
  Future<String> resetGuardianPassword(String requestId) async {
    final result = await _client.functions.invoke(
      'reset-guardian-password',
      body: {'request_id': requestId},
    );
    if (result.status < 200 || result.status >= 300 || result.data is! Map) {
      final data = result.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'The guardian password could not be reset.';
      throw StateError(message);
    }
    final password = result.data['temporary_password'];
    if (password is! String || password.isEmpty) {
      throw StateError('The reset completed without a temporary password.');
    }
    return password;
  }

  @override
  Future<String> resetGuardianPasswordForGuardian(String guardianId) async {
    final result = await _client.functions.invoke(
      'reset-guardian-password',
      body: {'guardian_id': guardianId},
    );
    if (result.status < 200 || result.status >= 300 || result.data is! Map) {
      final data = result.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'The guardian password could not be reset.';
      throw StateError(message);
    }
    final password = result.data['temporary_password'];
    if (password is! String || password.isEmpty) {
      throw StateError('The reset completed without a temporary password.');
    }
    return password;
  }

  Future<void> _loadPasswordResetNotifications(
    void Function(
      String id,
      String title,
      String body,
      StaffNotificationTarget target, {
      String? entityId,
      DateTime? at,
    })
    add,
  ) async {
    try {
      final items = await _client.rpc('get_pending_guardian_password_resets');
      for (final row in (items as List)) {
        add(
          'password-reset:${row['id']}',
          'Guardian password reset requested',
          '${row['guardian_name'] ?? row['requested_username']} requested a password reset.',
          StaffNotificationTarget.passwordResets,
          // The reset screen needs the request ID so it can finalize the
          // request after changing the guardian's Auth password.
          entityId: row['id'] as String,
          at: DateTime.parse(row['requested_at'] as String),
        );
      }
      return;
    } catch (_) {
      // Older projects may have the table migration but not the helper RPC.
      // Fall back to the facility-scoped table policy without blocking the
      // rest of the notification inbox.
    }

    try {
      final rows = await _client
          .from('guardian_password_reset_requests')
          .select('id, requested_username, requested_at, guardians(full_name)')
          .eq('status', 'pending');
      for (final row in (rows as List)) {
        final guardian = row['guardians'];
        final name = guardian is Map ? guardian['full_name'] : null;
        add(
          'password-reset:${row['id']}',
          'Guardian password reset requested',
          '${name ?? row['requested_username']} requested a password reset.',
          StaffNotificationTarget.passwordResets,
          entityId: row['id'] as String,
          at: DateTime.parse(row['requested_at'] as String),
        );
      }
    } catch (_) {
      // A missing table/migration is reported by the other notification
      // sources only when they fail; do not make the bell unusable.
    }
  }

  @override
  Future<List<StaffNotification>> load() async {
    final profileId = _client.auth.currentUser?.id;
    if (profileId == null) throw StateError('Please sign in again.');
    final receipts = await _client
        .from('staff_notification_receipts')
        .select('notification_id')
        .eq('profile_id', profileId);
    _readIds
      ..clear()
      ..addAll(
        (receipts as List).map((row) => row['notification_id'] as String),
      );

    final rows = <StaffNotification>[];
    void add(
      String id,
      String title,
      String body,
      StaffNotificationTarget target, {
      String? entityId,
      DateTime? at,
    }) => rows.add(
      StaffNotification(
        id: id,
        title: title,
        body: body,
        target: target,
        entityId: entityId,
        createdAt: at ?? DateTime.now(),
      ),
    );

    await Future.wait([
      registry.childRepository.getPendingChildLinkRequests().then((items) {
        for (final item in items) {
          add(
            'request:${item.id}',
            'Child link request',
            '${item.guardianName} requested a link to ${item.childName}.',
            StaffNotificationTarget.requests,
            entityId: item.id,
            at: item.submittedAt,
          );
        }
      }),
      registry.inventoryRepository.getInventoryOverview().then((items) {
        for (final item in items.where(
          (item) => item.isLowStock || item.isUnavailable,
        )) {
          add(
            'stock:${item.id}:${item.isUnavailable}',
            item.isUnavailable ? 'Stock unavailable' : 'Low stock',
            '${item.vaccineName}: ${item.availableDoses} usable doses. Review stock.',
            StaffNotificationTarget.inventory,
            entityId: item.vaccineId,
            at: item.updatedAt,
          );
        }
      }),
      registry.appointmentRepository.getFacilityAppointments().then((items) {
        for (final item in items.where(
          (item) =>
              item.status == VaccinationAppointmentStatus.cancelled ||
              item.status == VaccinationAppointmentStatus.rescheduled,
        )) {
          add(
            'appointment:${item.id}:${item.status.name}',
            'Appointment ${item.status.name}',
            '${item.childName} • ${item.vaccineName}. Review appointment details.',
            StaffNotificationTarget.appointments,
            entityId: item.id,
            at: item.updatedAt,
          );
        }
      }),
      registry.appointmentRepository.getFacilitySlotOffers().then((items) {
        for (final item in items.where(
          (item) =>
              item.status == AppointmentSlotOfferStatus.pending ||
              item.status == AppointmentSlotOfferStatus.accepted,
        )) {
          add(
            'offer:${item.id}:${item.status.name}',
            item.status == AppointmentSlotOfferStatus.pending
                ? 'Earlier offer awaiting response'
                : 'Earlier appointment accepted',
            '${item.childName} • ${item.vaccineName}. Review the earlier appointment offer.',
            StaffNotificationTarget.offers,
            entityId: item.id,
            at: item.createdAt,
          );
        }
      }),
      registry.reminderRepository.getFacilityFollowUps().then((items) {
        final due = items
            .where((r) => r.status == VaccinationReminderStatus.dueToday)
            .length;
        final overdue = items
            .where((r) => r.status == VaccinationReminderStatus.overdue)
            .length;
        if (due + overdue > 0) {
          add(
            'follow-ups:${DateTime.now().toIso8601String().substring(0, 10)}',
            'Daily follow-up summary',
            '$due vaccine doses due today • $overdue overdue. Open reminders to review follow-up work.',
            StaffNotificationTarget.followUps,
          );
        }
      }),
      registry.advisoryInsightRepository.getFacilityInsights().then((items) {
        for (final item in items.where(
          (item) => item.status == AdvisoryInsightStatus.newInsight,
        )) {
          add(
            'insight:${item.id}',
            'Advisory: ${item.title}',
            '${item.summary} Recommendations require staff review.',
            StaffNotificationTarget.insights,
            entityId: item.id,
            at: item.generatedAt,
          );
        }
      }),
      _loadPasswordResetNotifications(add),
    ]);
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }
}
