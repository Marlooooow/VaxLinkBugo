import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/staff_member.dart';
import 'staff_repository.dart';

class SupabaseStaffRepository implements StaffRepository {
  final SupabaseClient _client;

  const SupabaseStaffRepository(this._client);

  @override
  Future<List<StaffMember>> getStaffMembers() async {
    final rows = await _client
        .from('staff_members')
        .select()
        .order('full_name');
    return rows.map<StaffMember>(_fromRow).toList(growable: false);
  }

  @override
  Future<StaffPage> getStaffMembersPage({
    String query = '',
    int limit = 20,
    int offset = 0,
  }) async {
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'get_staff_member_page',
            params: {
              'p_search': query.trim().isEmpty ? null : query.trim(),
              'p_page_size': limit,
              'p_page_offset': offset,
            },
          )
          as Map,
    );
    return StaffPage(
      items: (result['items'] as List? ?? const [])
          .map((row) => _fromRow(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false),
      totalCount: (result['total_count'] as num?)?.toInt() ?? 0,
      hasMore: result['has_more'] == true,
      nextOffset: (result['next_offset'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<StaffInvitationResult> registerStaff(
    StaffRegistrationRequest request,
  ) async {
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'register_staff_member',
            params: {
              'staff_details': {
                ...request.name.toJson(),
                'staff_type': _snake(request.staffType.name),
                'license_number': request.licenseNumber,
                'phone': request.phone,
                'email': request.email,
              },
            },
          )
          as Map,
    );
    final invitation = result['invitation'] as Map<String, dynamic>;
    return StaffInvitationResult(
      staff: _fromRow(result['staff'] as Map<String, dynamic>),
      activationCode: invitation['activation_code'] as String,
      expiresAt: DateTime.parse(invitation['expires_at'] as String),
    );
  }

  @override
  Future<StaffMember> setStaffStatus(
    String staffId,
    StaffAccessStatus status,
  ) async {
    if (status == StaffAccessStatus.invitationPending) {
      throw ArgumentError(
        'Invitation pending is not an account status action.',
      );
    }
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'set_staff_member_status',
            params: {
              'target_staff_id': staffId,
              'requested_status': status.name,
            },
          )
          as Map,
    );
    return _fromRow(row);
  }

  static StaffMember _fromRow(Map<String, dynamic> row) => StaffMember(
    id: row['id'] as String,
    staffCode: row['staff_code'] as String,
    profileId: row['profile_id'] as String?,
    fullName: row['full_name'] as String,
    staffType: StaffType.values.byName(_camel(row['staff_type'] as String)),
    licenseNumber: row['license_number'] as String?,
    phone: row['phone'] as String?,
    email: row['email'] as String?,
    status: StaffAccessStatus.values.byName(_camel(row['status'] as String)),
    createdAt: DateTime.parse(row['created_at'] as String),
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
