import 'package:supabase_flutter/supabase_flutter.dart';

/// Fail closed: a missing live workflow must never substitute demo records.
class LiveOperationUnavailable implements Exception {
  final String operation;
  const LiveOperationUnavailable(this.operation);

  String get message =>
      '$operation is not connected to the live database yet. No changes were saved.';

  @override
  String toString() => message;
}

class LiveDataAccess {
  final SupabaseClient client;
  const LiveDataAccess(this.client);

  String get userId =>
      client.auth.currentUser?.id ??
      (throw StateError('A signed-in user is required for this action.'));

  Future<String> guardianId(String identifier) async {
    final current = userId;
    final row = await client
        .from('guardians')
        .select('id')
        .eq('profile_id', current)
        .maybeSingle();
    if (row == null || (identifier != current && identifier != row['id'])) {
      throw StateError('The guardian account is not linked to this family.');
    }
    return row['id'] as String;
  }

  Future<String> staffFacilityId() async {
    final row = await client
        .from('profiles')
        .select('facility_id, role, active')
        .eq('id', userId)
        .single();
    if (row['active'] != true ||
        !['health_worker', 'administrator'].contains(row['role']) ||
        row['facility_id'] == null) {
      throw StateError(
        'Not authorized: an active facility staff account is required.',
      );
    }
    return row['facility_id'] as String;
  }

  static String date(DateTime value) =>
      value.toIso8601String().split('T').first;
  static String title(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
  static String relationship(String value, String guardianSex) =>
      value == 'sibling'
      ? (guardianSex == 'male' ? 'Brother' : 'Sister')
      : title(value);
  static String relationshipValue(String value) =>
      ['brother', 'sister'].contains(value.trim().toLowerCase())
      ? 'sibling'
      : value.trim().toLowerCase().replaceAll(' ', '_');
  static String camel(String value) => value.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match[1]!.toUpperCase(),
  );
}
