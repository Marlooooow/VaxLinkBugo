import '../models/account_profile.dart';
import '../models/app_user.dart';
import 'profile_repository.dart';

class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository();

  @override
  Future<AccountProfile> getMyProfile(AppUser user) async => AccountProfile(
    user: user,
    username: user.fullName,
    accountCode: null,
    facilityName: null,
    firstName: null,
    middleName: null,
    lastName: null,
    suffix: null,
    birthDate: null,
    sex: null,
    phone: null,
    email: null,
    address: null,
    staffType: null,
    licenseNumber: null,
    status: user.active ? 'Active' : 'Disabled',
  );

  @override
  Future<AccountProfile> updateMyContact(
    AppUser user,
    ProfileContactUpdate update,
  ) => throw StateError('Profile editing requires the live database.');
}
