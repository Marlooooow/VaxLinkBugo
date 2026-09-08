import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account_profile.dart';
import '../models/app_user.dart';
import 'live_data_access.dart';
import 'profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client;

  const SupabaseProfileRepository(this._client);

  @override
  Future<AccountProfile> getMyProfile(AppUser user) async {
    final profile = await _client
        .from('profiles')
        .select(
          'id, username, full_name, first_name, middle_name, last_name, '
          'suffix, role, active, facilities(name)',
        )
        .eq('id', user.id)
        .single();
    final facility = profile['facilities'] as Map?;

    if (user.role == UserRole.guardian) {
      final guardian = await _client
          .from('guardians')
          .select()
          .eq('profile_id', user.id)
          .single();
      final links = await _client
          .from('guardian_child_links')
          .select('relationship, children!inner(id, child_code, full_name)')
          .eq('guardian_id', guardian['id'])
          .eq('status', 'approved')
          .order('created_at');
      return AccountProfile(
        user: user,
        username: profile['username'] as String,
        accountCode: guardian['guardian_code'] as String,
        facilityName: facility?['name'] as String?,
        firstName: guardian['first_name'] as String?,
        middleName: guardian['middle_name'] as String?,
        lastName: guardian['last_name'] as String?,
        suffix: guardian['suffix'] as String?,
        birthDate: guardian['birth_date'] == null
            ? null
            : DateTime.parse(guardian['birth_date'] as String),
        sex: guardian['sex'] == null
            ? null
            : LiveDataAccess.title(guardian['sex'] as String),
        phone: guardian['phone'] as String?,
        email: guardian['email'] as String?,
        address: guardian['address'] as String?,
        staffType: null,
        licenseNumber: null,
        status: LiveDataAccess.title(guardian['access_status'] as String),
        linkedChildren: links
            .map((row) {
              final child = row['children'] as Map;
              return AccountLinkedChild(
                id: child['id'] as String,
                name: child['full_name'] as String,
                childCode: child['child_code'] as String,
                relationship: LiveDataAccess.relationship(
                  row['relationship'] as String,
                  guardian['sex'] as String,
                ),
              );
            })
            .toList(growable: false),
      );
    }

    final staff = await _client
        .from('staff_members')
        .select()
        .eq('profile_id', user.id)
        .maybeSingle();
    return AccountProfile(
      user: user,
      username: profile['username'] as String,
      accountCode: staff?['staff_code'] as String?,
      facilityName: facility?['name'] as String?,
      firstName: profile['first_name'] as String?,
      middleName: profile['middle_name'] as String?,
      lastName: profile['last_name'] as String?,
      suffix: profile['suffix'] as String?,
      birthDate: null,
      sex: null,
      phone: staff?['phone'] as String?,
      email: staff?['email'] as String?,
      address: null,
      staffType: staff?['staff_type'] == null
          ? (user.isAdministrator ? 'Administrator' : 'Health Worker')
          : LiveDataAccess.title(staff!['staff_type'] as String),
      licenseNumber: staff?['license_number'] as String?,
      status: staff?['status'] == null
          ? (profile['active'] == true ? 'Active' : 'Disabled')
          : LiveDataAccess.title(staff!['status'] as String),
    );
  }

  @override
  Future<AccountProfile> updateMyContact(
    AppUser user,
    ProfileContactUpdate update,
  ) async {
    await _client.rpc(
      'update_my_profile_contact',
      params: {
        'contact': {
          'phone': update.phone?.trim(),
          'email': update.email?.trim(),
          if (user.role == UserRole.guardian) 'address': update.address?.trim(),
        },
      },
    );
    return getMyProfile(user);
  }
}
