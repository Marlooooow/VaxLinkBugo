import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reminder_follow_up.dart';
import '../models/vaccination_reminder.dart';
import 'reminder_repository.dart';
import 'live_data_access.dart';

class SupabaseReminderRepository implements ReminderRepository {
  final SupabaseClient _client;

  SupabaseReminderRepository(this._client);

  static const _select =
      'id, reminder_code, guardian_id, child_id, vaccine_id, dose_number, '
      'due_on, status, delivery_channel, is_read, created_at, updated_at, '
      'children!inner(full_name), vaccine_definitions!inner(name)';

  @override
  Future<void> syncGuardianReminders(String guardianId) async {
    final resolvedId = await _resolveGuardianId(guardianId);
    try {
      await _client.rpc(
        'sync_guardian_reminders',
        params: {'guardian_id': resolvedId},
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('does not exist') ||
          error.message.contains('Could not find the function')) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<List<VaccinationReminder>> getGuardianReminders(
    String guardianId,
  ) async {
    final resolvedId = await _resolveGuardianId(guardianId);
    await syncGuardianReminders(resolvedId);
    return _loadReminders(guardianId: resolvedId);
  }

  // Screens pass the authenticated profile ID; reminders reference guardians.id.
  // Resolve only the signed-in guardian, never another family's supplied ID.
  Future<String> _resolveGuardianId(String identifier) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    final guardian = await _client
        .from('guardians')
        .select('id')
        .eq('profile_id', user.id)
        .maybeSingle();
    if (guardian == null ||
        (identifier != user.id && identifier != guardian['id'])) {
      throw StateError('The guardian account is not linked to this family.');
    }
    return guardian['id'] as String;
  }

  @override
  Future<List<VaccinationReminder>> getFacilityFollowUps() => _loadReminders();

  @override
  Future<ReminderPage> getFacilityFollowUpsPage({
    int limit = 10,
    int offset = 0,
  }) async {
    final safeLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    final safeOffset = offset < 0 ? 0 : offset;
    final payload = Map<String, dynamic>.from(
      await _client.rpc(
        'get_facility_follow_up_child_page',
        params: {'page_size': safeLimit, 'page_offset': safeOffset},
      ),
    );
    final rows = payload['items'] as List? ?? const [];
    final items = rows
        .map((row) => _fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return ReminderPage(
      items: items,
      hasMore: payload['has_more'] as bool? ?? false,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? safeOffset,
    );
  }

  @override
  Future<ReminderSummary> getFacilityFollowUpSummary() async {
    final row = Map<String, dynamic>.from(
      await _client.rpc('get_facility_reminder_summary'),
    );
    return ReminderSummary(
      dueToday: (row['due_today'] as num?)?.toInt() ?? 0,
      overdue: (row['overdue'] as num?)?.toInt() ?? 0,
      upcoming: (row['upcoming'] as num?)?.toInt() ?? 0,
      guardianIds: (row['guardian_ids'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      vaccineCounts: (row['vaccine_counts'] as List? ?? const [])
          .map((value) {
            final item = Map<String, dynamic>.from(value as Map);
            return ReminderVaccineCount(
              vaccineId: item['vaccine_id'] as String,
              vaccineName: item['vaccine_name'] as String,
              dueToday: (item['due_today'] as num?)?.toInt() ?? 0,
              overdue: (item['overdue'] as num?)?.toInt() ?? 0,
            );
          })
          .toList(growable: false),
    );
  }

  Future<List<VaccinationReminder>> _loadReminders({String? guardianId}) async {
    dynamic query = _client.from('reminders').select(_select);
    if (guardianId != null) query = query.eq('guardian_id', guardianId);
    final rows = await query.order('due_on');
    return (rows as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<VaccinationReminder> markAsRead(String reminderId) async {
    final row = await _client
        .from('reminders')
        .update({'is_read': true})
        .eq('id', reminderId)
        .select(_select)
        .single();
    return _fromRow(row);
  }

  @override
  Future<VaccinationReminder> dismiss(String reminderId) async {
    final row = await _client
        .from('reminders')
        .update({'status': 'dismissed', 'is_read': true})
        .eq('id', reminderId)
        .select(_select)
        .single();
    return _fromRow(row);
  }

  @override
  Future<ReminderPreference> getPreference(String guardianId) async {
    final resolvedId = await _resolveGuardianId(guardianId);
    final row = await _client
        .from('reminder_preferences')
        .select()
        .eq('guardian_id', resolvedId)
        .maybeSingle();
    if (row == null) {
      return ReminderPreference(
        guardianId: resolvedId,
        inAppEnabled: true,
        smsEnabled: false,
        emailEnabled: false,
        advanceNoticeDays: 3,
        updatedAt: DateTime.now(),
      );
    }
    return _preferenceFromRow(row);
  }

  @override
  Future<ReminderPreference> savePreference(
    ReminderPreference preference,
  ) async {
    final resolvedId = await _resolveGuardianId(preference.guardianId);
    final row = await _client
        .from('reminder_preferences')
        .upsert({
          'guardian_id': resolvedId,
          'in_app_enabled': preference.inAppEnabled,
          'sms_enabled': preference.smsEnabled,
          'email_enabled': preference.emailEnabled,
          'advance_notice_days': preference.advanceNoticeDays,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    return _preferenceFromRow(row);
  }

  @override
  Future<List<ReminderFollowUpRecord>> performBatchAction(
    ReminderBatchActionRequest request,
  ) async {
    if (request.reminderIds.isEmpty) return const [];
    if (request.action == ReminderFollowUpAction.mockSms) {
      throw const LiveOperationUnavailable('SMS reminder delivery');
    }
    if (request.action == ReminderFollowUpAction.sms) {
      try {
        final response = await _client.functions.invoke(
          'send-reminder-sms',
          body: {'reminder_ids': request.reminderIds.toSet().toList()},
        );
        if (response.data is! Map) {
          throw StateError('The SMS provider returned an invalid response.');
        }
        final data = Map<String, dynamic>.from(response.data as Map);
        final rows = (data['follow_ups'] as List? ?? const [])
            .map(
              (row) => _followUpFromRow(Map<String, dynamic>.from(row as Map)),
            )
            .toList(growable: false);
        final accepted = data['accepted'] as int? ?? 0;
        final failed = data['failed'] as int? ?? 0;
        if (failed > 0 || accepted != request.reminderIds.toSet().length) {
          throw StateError(
            '$accepted SMS request${accepted == 1 ? '' : 's'} accepted; '
            '$failed failed or uncertain. Check follow-up history before retrying.',
          );
        }
        return rows;
      } on FunctionException catch (error) {
        final details = error.details;
        if (details is Map && details['error'] is String) {
          throw StateError(details['error'] as String);
        }
        rethrow;
      }
    }
    // A printed list is a local output, but its preparation must still be
    // recorded in the live follow-up history for accountability.
    final reminderRows = await _client
        .from('reminders')
        .select('id, child_id')
        .inFilter('id', request.reminderIds);
    if (reminderRows.length != request.reminderIds.toSet().length) {
      throw StateError(
        'Some selected reminders are no longer available. Refresh the list before continuing.',
      );
    }
    final now = DateTime.now().toUtc();
    final rows = <Map<String, dynamic>>[];
    for (final item in reminderRows) {
      final reminder = item;
      rows.add({
        'follow_up_code':
            'FUP-${now.microsecondsSinceEpoch}-${rows.length + 1}',
        'reminder_id': reminder['id'],
        'child_id': reminder['child_id'],
        'action': _snake(request.action.name),
        'outcome': _snake(request.outcome.name),
        'assigned_to': request.assignedToUserId,
        'notes': request.notes,
        'performed_by': _client.auth.currentUser!.id,
        'performed_at': now.toIso8601String(),
      });
    }
    final inserted = await _client
        .from('reminder_follow_ups')
        .insert(rows)
        .select();
    return inserted
        .map<ReminderFollowUpRecord>(_followUpFromRow)
        .toList(growable: false);
  }

  @override
  Future<List<ReminderFollowUpRecord>> getFollowUpHistory(
    String reminderId,
  ) async {
    final rows = await _client
        .from('reminder_follow_ups')
        .select()
        .eq('reminder_id', reminderId)
        .order('performed_at', ascending: false);
    return rows
        .map<ReminderFollowUpRecord>(_followUpFromRow)
        .toList(growable: false);
  }

  VaccinationReminder _fromRow(Map<String, dynamic> row) {
    final child = row['children'] as Map<String, dynamic>;
    final vaccine = row['vaccine_definitions'] as Map<String, dynamic>;
    return VaccinationReminder(
      id: row['id'] as String,
      reminderCode: row['reminder_code'] as String,
      guardianId: row['guardian_id'] as String,
      childId: row['child_id'] as String,
      childName: child['full_name'] as String,
      vaccineId: row['vaccine_id'] as String,
      vaccineName: vaccine['name'] as String,
      doseNumber: row['dose_number'] as int,
      dueDate: DateTime.parse(row['due_on'] as String),
      status: VaccinationReminderStatus.values.byName(
        _camel(row['status'] as String),
      ),
      channel: VaccinationReminderChannel.values.byName(
        _camel(row['delivery_channel'] as String),
      ),
      isRead: row['is_read'] as bool,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  ReminderPreference _preferenceFromRow(Map<String, dynamic> row) =>
      ReminderPreference(
        guardianId: row['guardian_id'] as String,
        inAppEnabled: row['in_app_enabled'] as bool,
        smsEnabled: row['sms_enabled'] as bool,
        emailEnabled: row['email_enabled'] as bool,
        advanceNoticeDays: row['advance_notice_days'] as int,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  ReminderFollowUpRecord _followUpFromRow(Map<String, dynamic> row) =>
      ReminderFollowUpRecord(
        id: row['id'] as String,
        followUpCode: row['follow_up_code'] as String,
        reminderId: row['reminder_id'] as String,
        childId: row['child_id'] as String,
        action: ReminderFollowUpAction.values.byName(
          _camel(row['action'] as String),
        ),
        outcome: ReminderFollowUpOutcome.values.byName(
          _camel(row['outcome'] as String),
        ),
        assignedToUserId: row['assigned_to'] as String?,
        notes: row['notes'] as String? ?? '',
        performedAt: DateTime.parse(row['performed_at'] as String),
        performedByUserId: row['performed_by'] as String,
      );

  static String _snake(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
  static String _camel(String value) => value.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}
