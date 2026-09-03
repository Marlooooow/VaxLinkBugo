import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/models/reminder_follow_up.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/supabase_reminder_repository.dart';

void main() {
  test(
    'live SMS action uses the server function and maps provider acceptance',
    () async {
      late http.Request sent;
      final client = SupabaseClient(
        'https://unit-test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'requested': 1,
              'accepted': 1,
              'failed': 0,
              'follow_ups': [
                {
                  'id': 'follow-up-id',
                  'follow_up_code': 'FUP-SMS-1',
                  'reminder_id': '10000000-0000-4000-8000-000000000001',
                  'child_id': '10000000-0000-4000-8000-000000000002',
                  'action': 'sms',
                  'outcome': 'provider_accepted',
                  'assigned_to': null,
                  'notes': 'Accepted by provider.',
                  'performed_at': '2026-09-02T00:00:00Z',
                  'performed_by': '10000000-0000-4000-8000-000000000003',
                },
              ],
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);

      final rows = await SupabaseReminderRepository(client).performBatchAction(
        const ReminderBatchActionRequest(
          reminderIds: ['10000000-0000-4000-8000-000000000001'],
          action: ReminderFollowUpAction.sms,
          outcome: ReminderFollowUpOutcome.providerAccepted,
          assignedToUserId: null,
          notes: '',
          performedByUserId: 'ignored-client-actor',
        ),
      );

      expect(sent.url.path, '/functions/v1/send-reminder-sms');
      expect(sent.body, contains('10000000-0000-4000-8000-000000000001'));
      expect(sent.body, isNot(contains('ignored-client-actor')));
      expect(rows.single.action, ReminderFollowUpAction.sms);
      expect(rows.single.outcome, ReminderFollowUpOutcome.providerAccepted);
    },
  );
}
